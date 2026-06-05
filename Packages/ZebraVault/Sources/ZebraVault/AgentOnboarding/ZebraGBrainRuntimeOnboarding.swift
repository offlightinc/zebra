import Foundation

public struct ZebraGBrainRuntimeOnboardingStore {
    public struct LaunchContext {
        public let launchDirectory: String
        public let startupLine: String
    }

    public struct CompletionResult: Equatable {
        public let isComplete: Bool
        public let reasons: [String]
    }

    private struct State: Codable {
        var schemaVersion: Int
        var receipt: Receipt?
    }

    private struct Receipt: Codable {
        var complete: Bool?
        var runtime: String?
        var executablePath: String?
        var version: String?
        var provider: String?
        var keySource: String?
        var configPaths: [String: String]?
        var verifiedAt: String?
        var checks: [String: Bool]?
        var reasons: [String]?
    }

    private let stateURL: URL
    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private let onboardingLanguage: ZebraOnboardingLanguage

    public init(
        stateURL: URL = ZebraGBrainRuntimeOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        appPreferredLocalizations: [String] = Bundle.main.preferredLocalizations,
        preferredLanguages: [String] = Locale.preferredLanguages,
        currentLocaleIdentifier: String = Locale.current.identifier
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
        self.onboardingLanguage = ZebraOnboardingLanguage.current(
            appPreferredLocalizations: appPreferredLocalizations,
            preferredLanguages: preferredLanguages,
            currentLocaleIdentifier: currentLocaleIdentifier
        )
    }

    public static func defaultStateURL() -> URL {
        ZebraGBrainOnboardingStore.onboardingDirectoryURL()
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
    }

    public func isSetupCompleted() -> Bool {
        cachedCompletionResult().isComplete
    }

    public func cachedCompletionResult() -> CompletionResult {
        guard let state = loadState(),
              let receipt = state.receipt else {
            return CompletionResult(isComplete: false, reasons: ["missing_receipt"])
        }
        guard receipt.complete == true else {
            return CompletionResult(
                isComplete: false,
                reasons: nonEmpty(receipt.reasons) ?? ["receipt_incomplete"]
            )
        }
        guard Self.supportedRuntimeIDs.contains(receipt.runtime ?? "") else {
            return CompletionResult(isComplete: false, reasons: ["runtime_missing"])
        }
        guard let executablePath = nonEmpty(receipt.executablePath),
              fileManager.isExecutableFile(atPath: executablePath) else {
            return CompletionResult(isComplete: false, reasons: ["executable_missing"])
        }
        guard nonEmpty(receipt.keySource) != nil else {
            return CompletionResult(isComplete: false, reasons: ["credential_source_missing"])
        }
        guard receipt.checks?["credentials"] == true else {
            return CompletionResult(isComplete: false, reasons: ["credentials_unverified"])
        }
        guard receipt.checks?["runtimeConfigCommand"] == true else {
            return CompletionResult(isComplete: false, reasons: ["runtime_config_unverified"])
        }
        guard receipt.checks?["llmCall"] == true else {
            return CompletionResult(isComplete: false, reasons: ["llm_call_unverified"])
        }
        return CompletionResult(isComplete: true, reasons: [])
    }

    public func prepareLaunch() -> LaunchContext? {
        guard let helperPath = installHelperScript() else { return nil }
        let launchDirectory = onboardingWorkDirectoryPath()
        let helperDirectory = helperPath.deletingLastPathComponent().path
        let startupLine = [
            "cd \(ZebraAgentLaunchCommand.shellQuote(launchDirectory))",
            "export ZEBRA_GBRAIN_RUNTIME_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_RUNTIME_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export ZEBRA_ONBOARDING_LANGUAGE=\(ZebraAgentLaunchCommand.shellQuote(onboardingLanguage.code))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
            "\(ZebraAgentLaunchCommand.shellQuote(helperPath.path)) run",
        ].joined(separator: " && ") + "\r"
        return LaunchContext(
            launchDirectory: launchDirectory,
            startupLine: startupLine
        )
    }

    private func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func installHelperScript() -> URL? {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
        let url = directory.appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.helperScript.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    private func onboardingWorkDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-runtime-work", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.standardizedPath(directory.path)
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static let supportedRuntimeIDs: Set<String> = [
        "openclaw",
        "hermes",
    ]

    private func nonEmpty(_ values: [String]?) -> [String]? {
        guard let values, !values.isEmpty else { return nil }
        return values
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let helperScript = """
    #!/bin/sh
    set -eu

    STATE="${ZEBRA_GBRAIN_RUNTIME_STATE:-$HOME/Library/Application Support/zebra/onboarding/gbrain-runtime-state.json}"
    COMMAND="${1:-run}"
    if [ $# -gt 0 ]; then
      shift
    fi

    PYTHON_BIN="$(command -v python3 || true)"
    if [ -z "$PYTHON_BIN" ]; then
      echo "python3 is required for zebra-gbrain-runtime-onboarding" >&2
      exit 1
    fi

    "$PYTHON_BIN" - "$STATE" "$COMMAND" "$@" <<'PY'
    import contextlib
    import getpass
    import json
    import os
    import shutil
    import subprocess
    import sys
    import time
    from datetime import datetime, timezone
    from pathlib import Path
    try:
        import fcntl
    except Exception:
        fcntl = None

    state_path = Path(sys.argv[1]).expanduser()
    command = sys.argv[2] or "run"
    home = Path(os.environ.get("ZEBRA_GBRAIN_RUNTIME_HOME") or str(Path.home())).expanduser()
    language = (os.environ.get("ZEBRA_ONBOARDING_LANGUAGE") or "en").split("-")[0].lower()
    if language not in {"en", "ja", "ko"}:
        language = "en"

    provider_choices = [
        {"id": "openai-codex", "label": "OpenAI Codex account login", "env": "", "auth_type": "oauth", "openclaw_provider": "openai", "openclaw_auth": "openai", "hermes_provider": "openai-codex", "hermes_model": "gpt-5.4", "hermes_base_url": "https://chatgpt.com/backend-api/codex", "hermes_base_env": "HERMES_CODEX_BASE_URL", "hermes_api_mode": "codex_responses"},
        {"id": "anthropic-claude-code", "label": "Anthropic Claude Code account login", "env": "", "auth_type": "oauth", "openclaw_provider": "claude-cli", "openclaw_auth": "anthropic-cli", "hermes_provider": "anthropic", "hermes_model": "claude-sonnet-4-6", "hermes_base_url": "https://api.anthropic.com", "hermes_base_env": "ANTHROPIC_BASE_URL", "hermes_api_mode": "anthropic_messages"},
        {"id": "openrouter", "label": "OpenRouter", "env": "OPENROUTER_API_KEY", "auth_type": "api_key", "openclaw_provider": "openrouter", "openclaw_auth": "openrouter-api-key", "hermes_provider": "openrouter", "hermes_model": "google/gemini-3.5-flash", "hermes_base_url": "https://openrouter.ai/api/v1", "hermes_base_env": "OPENROUTER_BASE_URL", "hermes_api_mode": "chat_completions"},
        {"id": "anthropic-api", "label": "Anthropic API key", "env": "ANTHROPIC_API_KEY", "auth_type": "api_key", "openclaw_provider": "anthropic", "openclaw_auth": "apiKey", "hermes_provider": "anthropic", "hermes_model": "claude-haiku-4-5-20251001", "hermes_base_url": "https://api.anthropic.com", "hermes_base_env": "ANTHROPIC_BASE_URL", "hermes_api_mode": "anthropic_messages"},
        {"id": "google", "label": "Google Gemini", "env": "GOOGLE_API_KEY", "auth_type": "api_key", "openclaw_provider": "google", "openclaw_auth": "google-api-key", "hermes_provider": "gemini", "hermes_model": "gemini-3.5-flash", "hermes_base_url": "https://generativelanguage.googleapis.com/v1beta", "hermes_base_env": "GEMINI_BASE_URL", "hermes_api_mode": "chat_completions"},
        {"id": "openai-api", "label": "OpenAI API key", "env": "OPENAI_API_KEY", "auth_type": "api_key", "openclaw_provider": "openai", "openclaw_auth": "openai-api-key", "hermes_provider": "openai-api", "hermes_model": "gpt-5-mini", "hermes_base_url": "https://api.openai.com/v1", "hermes_base_env": "OPENAI_BASE_URL", "hermes_api_mode": "codex_responses"},
    ]

    def now():
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    def message(en, ko=None, ja=None):
        if language == "ko" and ko:
            return ko
        if language == "ja" and ja:
            return ja
        return en

    def load_state():
        try:
            with state_path.open("r", encoding="utf-8") as handle:
                return json.load(handle)
        except Exception:
            return {"schemaVersion": 1}

    def save_state(state):
        state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = state_path.with_suffix(state_path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, state_path)

    def run_process(argv, *, env=None, timeout=45, input_text=None):
        try:
            completed = subprocess.run(
                argv,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=timeout,
                input=input_text,
            )
            return {
                "ok": completed.returncode == 0,
                "code": completed.returncode,
                "stdout": completed.stdout.strip(),
                "stderr": completed.stderr.strip(),
            }
        except Exception as exc:
            return {"ok": False, "code": -1, "stdout": "", "stderr": str(exc)}

    def run_interactive_process(argv, *, env=None, timeout=600):
        try:
            with open("/dev/tty", "rb", buffering=0) as tty_in, open("/dev/tty", "wb", buffering=0) as tty_out:
                completed = subprocess.run(
                    argv,
                    stdin=tty_in,
                    stdout=tty_out,
                    stderr=tty_out,
                    env=env,
                    timeout=timeout,
                )
            return {"ok": completed.returncode == 0, "code": completed.returncode, "stdout": "", "stderr": ""}
        except Exception as exc:
            return {"ok": False, "code": -1, "stdout": "", "stderr": str(exc)}

    def interactive_process_done_grace_seconds():
        raw = os.environ.get("ZEBRA_GBRAIN_RUNTIME_INTERACTIVE_GRACE_SECONDS", "15")
        try:
            value = float(raw)
        except Exception:
            return 15.0
        if value < 0:
            return 0.0
        return min(value, 60.0)

    def run_interactive_process_until(argv, is_done, *, env=None, timeout=600):
        try:
            with open("/dev/tty", "rb", buffering=0) as tty_in, open("/dev/tty", "wb", buffering=0) as tty_out:
                process = subprocess.Popen(
                    argv,
                    stdin=tty_in,
                    stdout=tty_out,
                    stderr=tty_out,
                    env=env,
                )
                deadline = time.monotonic() + timeout
                while True:
                    code = process.poll()
                    if is_done():
                        if code is None:
                            grace_deadline = time.monotonic() + interactive_process_done_grace_seconds()
                            while time.monotonic() < grace_deadline:
                                time.sleep(0.25)
                                code = process.poll()
                                if code is not None:
                                    break
                        if code is None:
                            process.terminate()
                            try:
                                process.wait(timeout=5)
                            except subprocess.TimeoutExpired:
                                process.kill()
                                process.wait(timeout=5)
                        return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
                    if code is not None:
                        return {"ok": code == 0, "code": code, "stdout": "", "stderr": ""}
                    if time.monotonic() >= deadline:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=5)
                        return {"ok": False, "code": -1, "stdout": "", "stderr": "interactive_process_timeout"}
                    time.sleep(0.5)
        except Exception as exc:
            return {"ok": False, "code": -1, "stdout": "", "stderr": str(exc)}

    def credential_env(provider, credential):
        env = os.environ.copy()
        env_name = credential.get("envName") or provider.get("env", "")
        if credential.get("value") and env_name:
            env[env_name] = credential["value"]
        if provider.get("hermes_base_env") and provider.get("hermes_base_url"):
            env[provider["hermes_base_env"]] = provider["hermes_base_url"]
        return env

    def redact_output(text, credential):
        value = credential.get("value") if isinstance(credential, dict) else ""
        if value:
            text = text.replace(value, "<redacted>")
        return text

    def print_command_failure(result, credential):
        stdout = redact_output(result.get("stdout", ""), credential)
        stderr = redact_output(result.get("stderr", ""), credential)
        if stdout:
            print(stdout)
        if stderr:
            print(stderr, file=sys.stderr)

    def executable_version(path):
        for argv in ([path, "--version"], [path, "version"]):
            result = run_process(argv, timeout=10)
            if result["ok"] and (result["stdout"] or result["stderr"]):
                return (result["stdout"] or result["stderr"]).splitlines()[0][:160]
        return ""

    def prepend_path_once(directory):
        if not directory:
            return
        current = os.environ.get("PATH", "")
        parts = [part for part in current.split(os.pathsep) if part]
        if directory not in parts:
            os.environ["PATH"] = directory + (os.pathsep + current if current else "")

    def runtime_candidate_paths(name):
        candidates = []
        path_match = shutil.which(name)
        if path_match:
            candidates.append(path_match)
        if name == "hermes":
            install_dir = os.environ.get("HERMES_INSTALL_DIR", "").strip()
            if install_dir:
                candidates.append(str(Path(install_dir).expanduser() / "venv" / "bin" / "hermes"))
            candidates.extend([
                str(home / ".local" / "bin" / "hermes"),
                str(home / ".hermes" / "hermes-agent" / "venv" / "bin" / "hermes"),
                "/usr/local/bin/hermes",
            ])
        elif name == "openclaw":
            candidates.extend([
                str(home / ".local" / "bin" / "openclaw"),
                str(home / ".npm-global" / "bin" / "openclaw"),
                str(home / ".bun" / "bin" / "openclaw"),
                "/usr/local/bin/openclaw",
            ])
        seen = set()
        output = []
        for candidate in candidates:
            expanded = str(Path(candidate).expanduser())
            if expanded not in seen:
                seen.add(expanded)
                output.append(expanded)
        return output

    def detect_runtime(name):
        candidates = runtime_candidate_paths(name)
        path = ""
        for candidate in candidates:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                path = candidate
                prepend_path_once(str(Path(candidate).parent))
                break
        return {
            "installed": bool(path),
            "path": path or "",
            "version": executable_version(path) if path else "",
            "candidates": candidates,
        }

    def detect_all():
        return {
            "openclaw": detect_runtime("openclaw"),
            "hermes": detect_runtime("hermes"),
        }

    def hermes_paths():
        return {
            "env": str(home / ".hermes" / ".env"),
            "config": str(home / ".hermes" / "config.yaml"),
        }

    def openclaw_paths():
        return {
            "config": os.environ.get("OPENCLAW_CONFIG_PATH") or str(home / ".openclaw" / "openclaw.json"),
            "home": os.environ.get("OPENCLAW_HOME") or str(home / ".openclaw"),
        }

    def read_env_file_vars(path):
        output = {}
        try:
            for line in Path(path).read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or "=" not in stripped:
                    continue
                key, value = stripped.split("=", 1)
                output[key.strip()] = value.strip().strip('"').strip("'")
        except Exception:
            pass
        return output

    def hermes_credential_env_names(provider):
        if provider.get("hermes_provider") == "anthropic":
            return ["ANTHROPIC_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY"]
        env_name = provider.get("env", "")
        return [env_name] if env_name else []

    def hermes_prompt_env_name(provider):
        if provider.get("hermes_provider") == "anthropic":
            return "ANTHROPIC_API_KEY"
        return provider.get("env", "")

    def agent_cli_state_path():
        return state_path.parent / "agent-cli-state.json"

    def agent_cli_events_path():
        return state_path.parent / "agent-cli-events.jsonl"

    def agent_readiness_source(agent, method):
        events_path = agent_cli_events_path()
        try:
            lines = events_path.read_text(encoding="utf-8").splitlines()
            for line in reversed(lines[-200:]):
                event = json.loads(line)
                if (
                    event.get("event") == "agent_readiness_probe_succeeded"
                    and event.get("agent") == agent
                    and event.get("method") == method
                ):
                    return f"agent-cli:{agent}-auth-status"
        except Exception:
            pass
        try:
            state = json.loads(agent_cli_state_path().read_text(encoding="utf-8"))
            if state.get("phase") == "complete" and state.get("selectedAgent") == agent:
                return f"agent-cli:{agent}-complete"
        except Exception:
            pass
        return ""

    def codex_agent_readiness_source():
        return agent_readiness_source("codex", "codex login status")

    def claude_agent_readiness_source():
        return agent_readiness_source("claude", "claude auth status --json")

    def codex_cli_auth_path():
        codex_home = os.environ.get("CODEX_HOME", "").strip()
        if not codex_home:
            codex_home = str(home / ".codex")
        return Path(codex_home).expanduser() / "auth.json"

    def hermes_auth_path():
        hermes_home = os.environ.get("HERMES_HOME", "").strip()
        if not hermes_home:
            hermes_home = str(home / ".hermes")
        return Path(hermes_home).expanduser() / "auth.json"

    @contextlib.contextmanager
    def hermes_auth_store_lock():
        lock_path = hermes_auth_path().with_suffix(".lock")
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a+", encoding="utf-8") as lock_file:
            if fcntl is not None:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                if fcntl is not None:
                    try:
                        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                    except OSError:
                        pass

    def claude_code_credential_source():
        if sys.platform == "darwin" and os.environ.get("ZEBRA_GBRAIN_RUNTIME_SKIP_CLAUDE_KEYCHAIN") != "1":
            result = run_process([
                "security",
                "find-generic-password",
                "-s",
                "Claude Code-credentials",
                "-w",
            ], timeout=5)
            if result["ok"] and result["stdout"]:
                try:
                    payload = json.loads(result["stdout"])
                    oauth = payload.get("claudeAiOauth") if isinstance(payload, dict) else None
                    if isinstance(oauth, dict) and oauth.get("accessToken"):
                        return "claude-code-keychain"
                except Exception:
                    pass
        credentials_path = home / ".claude" / ".credentials.json"
        try:
            payload = json.loads(credentials_path.read_text(encoding="utf-8"))
            oauth = payload.get("claudeAiOauth") if isinstance(payload, dict) else None
            if isinstance(oauth, dict) and oauth.get("accessToken"):
                return "claude-code-credentials-file"
        except Exception:
            pass
        return ""

    def read_codex_cli_tokens():
        try:
            payload = json.loads(codex_cli_auth_path().read_text(encoding="utf-8"))
            tokens = payload.get("tokens") if isinstance(payload, dict) else None
            if not isinstance(tokens, dict):
                return {}
            access_token = tokens.get("access_token")
            refresh_token = tokens.get("refresh_token")
            if not isinstance(access_token, str) or not access_token.strip():
                return {}
            if not isinstance(refresh_token, str) or not refresh_token.strip():
                return {}
            return dict(tokens)
        except Exception:
            return {}

    def import_codex_cli_tokens_to_hermes():
        tokens = read_codex_cli_tokens()
        if not tokens:
            return {"ok": False, "code": 1, "stdout": "", "stderr": "codex_cli_credentials_unreadable"}
        auth_path = hermes_auth_path()
        try:
            with hermes_auth_store_lock():
                auth_path.parent.mkdir(parents=True, exist_ok=True)
                try:
                    if auth_path.exists():
                        store = json.loads(auth_path.read_text(encoding="utf-8"))
                        if not isinstance(store, dict):
                            store = {}
                    else:
                        store = {}
                except Exception as exc:
                    return {"ok": False, "code": 1, "stdout": "", "stderr": f"hermes_auth_read_failed: {exc}"}
                timestamp = now()
                providers = store.setdefault("providers", {})
                if not isinstance(providers, dict):
                    providers = {}
                    store["providers"] = providers
                providers["openai-codex"] = {
                    "tokens": tokens,
                    "last_refresh": timestamp,
                    "auth_mode": "chatgpt",
                    "label": "Zebra Codex CLI import",
                }
                pool = store.setdefault("credential_pool", {})
                if not isinstance(pool, dict):
                    pool = {}
                    store["credential_pool"] = pool
                existing_entries = pool.get("openai-codex")
                entries = existing_entries if isinstance(existing_entries, list) else []
                next_entry = {
                    "id": "zebra-codex",
                    "label": "Zebra Codex CLI import",
                    "auth_type": "oauth",
                    "priority": 0,
                    "source": "device_code",
                    "access_token": tokens["access_token"],
                    "refresh_token": tokens.get("refresh_token"),
                    "base_url": "https://chatgpt.com/backend-api/codex",
                    "last_refresh": timestamp,
                    "last_status": None,
                    "last_status_at": None,
                    "last_error_code": None,
                    "last_error_reason": None,
                    "last_error_message": None,
                    "last_error_reset_at": None,
                }
                replaced = False
                for index, entry in enumerate(entries):
                    if isinstance(entry, dict) and entry.get("source") == "device_code":
                        entries[index] = next_entry
                        replaced = True
                        break
                if not replaced:
                    entries.insert(0, next_entry)
                pool["openai-codex"] = entries
                store["active_provider"] = "openai-codex"
                store["version"] = store.get("version") or 1
                store["updated_at"] = timestamp
                tmp = auth_path.with_name(f".{auth_path.name}.zebra-tmp")
                try:
                    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                    with os.fdopen(fd, "w", encoding="utf-8") as handle:
                        json.dump(store, handle, indent=2, sort_keys=True)
                        handle.write("\\n")
                        handle.flush()
                        os.fsync(handle.fileno())
                    os.replace(tmp, auth_path)
                    os.chmod(auth_path, 0o600)
                    return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
                except Exception as exc:
                    try:
                        if tmp.exists():
                            tmp.unlink()
                    except Exception:
                        pass
                    return {"ok": False, "code": 1, "stdout": "", "stderr": f"hermes_auth_write_failed: {exc}"}
        except Exception as exc:
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"hermes_auth_lock_failed: {exc}"}

    def write_env_file_value(path, key, value):
        if not key or not (key[0].isalpha() or key[0] == "_") or not all(ch.isalnum() or ch == "_" for ch in key):
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"invalid_env_key: {key}"}
        sanitized_value = value.replace("\\n", "").replace("\\r", "")
        env_path = Path(path)
        env_path.parent.mkdir(parents=True, exist_ok=True)
        lines = []
        try:
            if env_path.exists():
                lines = env_path.read_text(encoding="utf-8-sig", errors="replace").splitlines(keepends=True)
        except Exception as exc:
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"env_read_failed: {exc}"}
        found = False
        prefix = f"{key}="
        for index, line in enumerate(lines):
            if line.strip().startswith(prefix):
                lines[index] = f"{key}={sanitized_value}\\n"
                found = True
                break
        if not found:
            if lines and not lines[-1].endswith("\\n"):
                lines[-1] += "\\n"
            lines.append(f"{key}={sanitized_value}\\n")
        tmp = env_path.with_name(f".{env_path.name}.zebra-tmp")
        try:
            fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.writelines(lines)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, env_path)
            os.chmod(env_path, 0o600)
            os.environ[key] = sanitized_value
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        except Exception as exc:
            try:
                if tmp.exists():
                    tmp.unlink()
            except Exception:
                pass
            return {"ok": False, "code": 1, "stdout": "", "stderr": f"env_write_failed: {exc}"}

    def provider_id_for_runtime(provider, runtime):
        if runtime == "hermes":
            return provider["hermes_provider"]
        return provider["openclaw_provider"]

    def load_json_object(text):
        try:
            return json.loads(text)
        except Exception:
            pass
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            return json.loads(text[start:end + 1])
        raise ValueError("json_output_missing")

    def runtime_options(detection):
        openclaw = detection["openclaw"]["installed"]
        hermes = detection["hermes"]["installed"]
        if openclaw and not hermes:
            return [
                ("openclaw", message("Use OpenClaw", "OpenClaw 사용", "OpenClawを使用")),
                ("hermes", message("Install Hermes and use it", "Hermes 설치 후 사용", "Hermesをインストールして使用")),
            ]
        if hermes and not openclaw:
            return [
                ("hermes", message("Use Hermes", "Hermes 사용", "Hermesを使用")),
                ("openclaw", message("Install OpenClaw and use it", "OpenClaw 설치 후 사용", "OpenClawをインストールして使用")),
            ]
        if openclaw and hermes:
            return [
                ("openclaw", message("Use OpenClaw", "OpenClaw 사용", "OpenClawを使用")),
                ("hermes", message("Use Hermes", "Hermes 사용", "Hermesを使用")),
            ]
        return [
            ("openclaw", message("Install OpenClaw and use it", "OpenClaw 설치 후 사용", "OpenClawをインストールして使用")),
            ("hermes", message("Install Hermes and use it", "Hermes 설치 후 사용", "Hermesをインストールして使用")),
        ]

    def installed_notice(detection):
        openclaw = detection["openclaw"]["installed"]
        hermes = detection["hermes"]["installed"]
        if openclaw and hermes:
            print(message(
                "OpenClaw and Hermes are both installed. Choose which execution tool gbrain should use.\\nFiles or settings needed to run gbrain may be added or changed on the selected side.",
                "OpenClaw와 Hermes가 모두 설치되어 있으므로 gbrain에 사용할 실행 도구를 선택하세요.\\n선택한 쪽에는 gbrain 실행에 필요한 파일이나 설정이 추가되거나 바뀔 수 있습니다.",
                "OpenClawとHermesはどちらもインストール済みです。gbrainで使用する実行ツールを選んでください。\\n選択した側にgbrain実行に必要なファイルや設定が追加または変更される場合があります。",
            ))
        elif openclaw:
            print(message(
                "OpenClaw is already installed, so gbrain can use it as its execution tool.\\nDuring setup, files or settings needed to run gbrain may be added or changed on the OpenClaw side.\\n\\nIf you want to keep your existing OpenClaw settings unchanged, install Hermes and use that for gbrain instead.",
                "현재 OpenClaw가 설치되어 있어 gbrain 실행 도구로 바로 사용할 수 있습니다.\\n다만 준비 과정에서 gbrain 실행에 필요한 파일이나 설정이 OpenClaw 쪽에 추가되거나 바뀔 수 있으니 참고하세요.\\n\\n기존 OpenClaw 설정을 그대로 두고 싶다면 Hermes를 설치해 gbrain에 사용하세요.",
                "OpenClawはすでにインストールされているため、gbrainの実行ツールとしてそのまま使用できます。\\n準備中に、gbrain実行に必要なファイルや設定がOpenClaw側に追加または変更される場合があります。\\n\\n既存のOpenClaw設定をそのままにしたい場合は、Hermesをインストールしてgbrainに使用してください。",
            ))
        elif hermes:
            print(message(
                "Hermes is already installed, so gbrain can use it as its execution tool.\\nDuring setup, files or settings needed to run gbrain may be added or changed on the Hermes side.\\n\\nIf you want to keep your existing Hermes settings unchanged, install OpenClaw and use that for gbrain instead.",
                "현재 Hermes가 설치되어 있어 gbrain 실행 도구로 바로 사용할 수 있습니다.\\n다만 준비 과정에서 gbrain 실행에 필요한 파일이나 설정이 Hermes 쪽에 추가되거나 바뀔 수 있으니 참고하세요.\\n\\n기존 Hermes 설정을 그대로 두고 싶다면 OpenClaw를 설치해 gbrain에 사용하세요.",
                "Hermesはすでにインストールされているため、gbrainの実行ツールとしてそのまま使用できます。\\n準備中に、gbrain実行に必要なファイルや設定がHermes側に追加または変更される場合があります。\\n\\n既存のHermes設定をそのままにしたい場合は、OpenClawをインストールしてgbrainに使用してください。",
            ))
        else:
            print(message(
                "gbrain runs through OpenClaw or Hermes. Choose which execution tool to use, and Zebra will install only what is needed before continuing gbrain setup.",
                "gbrain은 OpenClaw 또는 Hermes를 통해 동작합니다.\\n사용할 실행 도구를 선택하면 Zebra가 필요한 범위만 설치한 뒤 gbrain 실행 준비를 이어갑니다.",
                "gbrainはOpenClawまたはHermesを通じて動作します。\\n使用する実行ツールを選ぶと、Zebraが必要な範囲だけインストールしてgbrainの実行準備を続けます。",
            ))

    def tty_input(prompt):
        try:
            with open("/dev/tty", "r", encoding="utf-8", errors="replace") as tty_in:
                print(prompt, end="", flush=True)
                value = tty_in.readline()
        except OSError:
            raise RuntimeError("interactive_terminal_required")
        if value == "":
            raise RuntimeError("interactive_terminal_required")
        return value.rstrip("\\n")

    def ask(prompt, default=""):
        suffix = f" [{default}]" if default else ""
        value = tty_input(f"{prompt}{suffix}: ").strip()
        return value or default

    def choose_runtime(detection):
        options = runtime_options(detection)
        print()
        installed_notice(detection)
        print()
        for index, (_, label) in enumerate(options, start=1):
            print(f"{index}. {label}")
        print()
        while True:
            raw = ask(message(
                "Select runtime",
                "실행 도구 선택",
                "実行ツールを選択",
            )).lower()
            for index, (runtime, _) in enumerate(options, start=1):
                aliases = {str(index), runtime}
                if runtime == "openclaw":
                    aliases.add("openclo")
                if raw in aliases:
                    return runtime
            print(message(
                "Enter one of the option numbers above.",
                "위 선택지 번호 중 하나를 입력하세요.",
                "上の選択肢番号を入力してください。",
            ))

    def install_runtime(runtime):
        if runtime == "openclaw":
            print(message(
                "Installing OpenClaw CLI with npm...",
                "npm으로 OpenClaw CLI를 설치합니다...",
                "npmでOpenClaw CLIをインストールします...",
            ))
            return run_process(["npm", "install", "-g", "openclaw"], timeout=900)
        print(message(
            "Installing Hermes CLI with the installer in minimal mode...",
            "installer로 Hermes CLI를 최소 모드로 설치합니다...",
            "installerでHermes CLIを最小モードでインストールします...",
        ))
        script = "set -o pipefail; curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-browser --no-skills --non-interactive"
        env = os.environ.copy()
        env["PATH"] = os.pathsep.join([
            str(home / ".local" / "bin"),
            str(home / ".hermes" / "bin"),
            env.get("PATH", ""),
        ])
        return run_process(["/bin/bash", "-lc", script], env=env, timeout=1200)

    def ensure_runtime_installed(runtime, detection):
        if detection[runtime]["installed"]:
            return detection[runtime]
        name = runtime_display_name(runtime)
        print(message(
            f"{name} is not installed. Starting installation.",
            f"{name}가 설치되어 있지 않아 설치를 시작합니다.",
            f"{name}はインストールされていないため、インストールを開始します。",
        ))
        result = install_runtime(runtime)
        if not result["ok"]:
            print(result["stdout"])
            print(result["stderr"], file=sys.stderr)
            raise RuntimeError(f"{runtime}_install_failed")
        refreshed = detect_runtime("openclaw" if runtime == "openclaw" else "hermes")
        if not refreshed["installed"]:
            tail = "\\n".join((result["stdout"] + "\\n" + result["stderr"]).splitlines()[-12:])
            if tail:
                print(tail)
            print(message(
                f"{runtime} was not found after installation. Checked candidates:",
                f"설치 후 {runtime} 실행 파일을 찾지 못했습니다. 확인한 경로:",
                f"インストール後に{runtime}実行ファイルを検出できませんでした。確認したパス:",
            ), file=sys.stderr)
            for candidate in refreshed.get("candidates", []):
                print(f"- {candidate}", file=sys.stderr)
            raise RuntimeError(f"{runtime}_install_not_detected")
        return refreshed

    def runtime_display_name(runtime):
        return "OpenClaw" if runtime == "openclaw" else "Hermes"

    def print_provider_intro(runtime):
        name = runtime_display_name(runtime)
        print()
        print(message(
            f"{name} is ready.",
            f"{name} 준비가 끝났습니다.",
            f"{name}の準備が完了しました。",
        ))
        print(message(
            "Now choose how gbrain should connect to an LLM.",
            "이제 gbrain이 LLM에 연결할 방식을 선택합니다.",
            "次にgbrainがLLMへ接続する方法を選択します。",
        ))

    def choose_provider():
        print()
        codex_readiness_source = codex_agent_readiness_source()
        claude_readiness_source = claude_agent_readiness_source()
        default_provider_id = "anthropic-claude-code" if claude_readiness_source else "openai-codex"
        if claude_readiness_source:
            print(message(
                "Default: Anthropic Claude Code account login",
                "기본값: Anthropic Claude Code 계정 연동",
                "デフォルト: Anthropic Claude Codeアカウント連携",
            ))
            print()
        elif codex_readiness_source:
            print(message(
                "Codex login was verified in the agent CLI step, so OpenAI account login is selected by default.",
                "agent CLI 단계에서 Codex 로그인이 확인되어 OpenAI 계정 연동을 기본값으로 사용합니다.",
                "agent CLIステップでCodexログインが確認されたため、OpenAIアカウント連携をデフォルトにします。",
            ))
            print()
        for index, provider in enumerate(provider_choices, start=1):
            env = provider.get("env", "")
            if env:
                has_env = bool(os.environ.get(env))
                print(f"{index}. {provider['label']} ({env}{' set' if has_env else ''})")
            else:
                print(f"{index}. {provider['label']}")
        while True:
            default_index = next(
                (str(index) for index, provider in enumerate(provider_choices, start=1) if provider["id"] == default_provider_id),
                "1",
            )
            raw = ask(message("Select LLM connection", "LLM 연결 방식 선택", "LLM接続方法を選択"), default_index).lower()
            for index, provider in enumerate(provider_choices, start=1):
                if raw in {str(index), provider["id"]}:
                    return provider
            print(message("Choose one option number.", "선택지 번호 중 하나를 입력하세요.", "選択肢番号を選んでください。"))

    def credential_for(provider, runtime):
        if provider.get("auth_type") == "oauth":
            source = ""
            if provider.get("id") == "openai-codex":
                source = codex_agent_readiness_source()
            elif provider.get("id") == "anthropic-claude-code":
                source = claude_agent_readiness_source() or claude_code_credential_source()
            return {
                "value": "",
                "source": source or f"{provider['id']}:oauth",
                "envName": "",
                "persistEnvName": "",
            }
        env_name = provider.get("env", "")
        if runtime == "hermes":
            for candidate_env_name in hermes_credential_env_names(provider):
                if os.environ.get(candidate_env_name):
                    return {
                        "value": os.environ[candidate_env_name],
                        "source": f"env:{candidate_env_name}",
                        "envName": candidate_env_name,
                        "persistEnvName": candidate_env_name,
                    }
            hermes_env = read_env_file_vars(hermes_paths()["env"])
            for candidate_env_name in hermes_credential_env_names(provider):
                if hermes_env.get(candidate_env_name):
                    return {
                        "value": hermes_env[candidate_env_name],
                        "source": f"hermes-env:{candidate_env_name}",
                        "envName": candidate_env_name,
                        "persistEnvName": "",
                    }
            if provider.get("hermes_provider") == "anthropic":
                claude_source = claude_code_credential_source()
                if claude_source:
                    return {
                        "value": "",
                        "source": claude_source,
                        "envName": "",
                        "persistEnvName": "",
                    }
            env_name = hermes_prompt_env_name(provider)
        elif os.environ.get(env_name):
            return {
                "value": os.environ[env_name],
                "source": f"env:{env_name}",
                "envName": env_name,
                "persistEnvName": "",
            }
        value = getpass.getpass(message(
            f"Enter {provider['label']} API key (input hidden): ",
            f"{provider['label']} API key 입력 (입력값 숨김): ",
            f"{provider['label']} API keyを入力（非表示）: ",
        )).strip()
        if not value:
            raise RuntimeError("api_key_missing")
        return {
            "value": value,
            "source": f"entered:{env_name}",
            "envName": env_name,
            "persistEnvName": env_name if runtime == "hermes" else "",
        }

    def run_hermes_oauth_setup(exe, provider, credential):
        if provider.get("id") != "openai-codex":
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        env = credential_env(provider, credential)
        def codex_status():
            result = run_process([exe, "auth", "status", "openai-codex"], env=env, timeout=30)
            text = (result.get("stdout", "") + "\\n" + result.get("stderr", "")).lower()
            lines = [line.strip() for line in text.splitlines()]
            return result, "openai-codex: logged in" in lines
        status, logged_in = codex_status()
        if status["ok"] and logged_in:
            return status
        if codex_agent_readiness_source() and codex_cli_auth_path().is_file():
            imported = import_codex_cli_tokens_to_hermes()
            if not imported["ok"]:
                return imported
            verified, logged_in = codex_status()
            if verified["ok"] and logged_in:
                return verified
            return {
                "ok": False,
                "code": verified.get("code", 1),
                "stdout": verified.get("stdout", ""),
                "stderr": verified.get("stderr", "") or "openai_codex_import_not_verified",
            }
        print(message(
            "OpenAI account login is required for Hermes. Continue the Hermes auth flow below.",
            "Hermes에서 OpenAI 계정 연동이 필요합니다. 아래 Hermes 인증 절차를 계속 진행하세요.",
            "HermesでOpenAIアカウント連携が必要です。以下のHermes認証手順を続けてください。",
        ))
        interactive = run_interactive_process([exe, "auth", "add", "openai-codex"], env=env, timeout=900)
        if not interactive["ok"]:
            return interactive
        verified, logged_in = codex_status()
        if verified["ok"] and logged_in:
            return verified
        return {
            "ok": False,
            "code": verified.get("code", 1),
            "stdout": verified.get("stdout", ""),
            "stderr": verified.get("stderr", "") or "openai_codex_auth_not_verified",
        }

    def run_hermes_config(exe, provider, credential):
        env = credential_env(provider, credential)
        if provider.get("auth_type") == "oauth":
            auth_result = run_hermes_oauth_setup(exe, provider, credential)
            if not auth_result["ok"]:
                return auth_result
        persist_env_name = credential.get("persistEnvName") or ""
        if persist_env_name and credential["value"]:
            result = write_env_file_value(hermes_paths()["env"], persist_env_name, credential["value"])
            if not result["ok"]:
                return result
        for key, value in [
            ("model.provider", provider_id_for_runtime(provider, "hermes")),
            ("model.default", provider["hermes_model"]),
            ("model.base_url", provider["hermes_base_url"]),
            ("model.api_mode", provider["hermes_api_mode"]),
        ]:
            result = run_process([exe, "config", "set", key, value], env=env, timeout=60)
            if not result["ok"]:
                return result
        return {"ok": True, "code": 0, "stdout": "", "stderr": ""}

    def openclaw_help_flags(exe):
        result = run_process([exe, "onboard", "--help"], timeout=20)
        text = result["stdout"] + "\\n" + result["stderr"]
        return {flag for flag in [
            "--skip-daemon",
            "--skip-ui",
            "--skip-skills",
            "--skip-health",
            "--skip-bootstrap",
            "--skip-channels",
            "--skip-search",
        ] if flag in text}

    def claude_cli_auth_status(env):
        result = run_process(["claude", "auth", "status", "--json"], env=env, timeout=30)
        if not result["ok"]:
            return result, False
        try:
            payload = load_json_object(result["stdout"] + "\\n" + result["stderr"])
            return result, bool(payload.get("loggedIn"))
        except Exception:
            return result, False

    def openclaw_auth_route_matches(route, provider_id):
        values = {
            str(route.get("provider") or ""),
            str(route.get("runtime") or ""),
            str(route.get("authProvider") or ""),
        }
        if provider_id == "claude-cli":
            return "claude-cli" in values or ("anthropic" in values and str(route.get("runtime") or "") == "claude-cli")
        return provider_id in values

    def openclaw_openai_oauth_env_fallback_keys():
        return ["CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID", "OPENAI_ORGANIZATION"]

    def openclaw_env(provider, credential):
        env = credential_env(provider, credential)
        if provider.get("id") == "openai-codex":
            for key in openclaw_openai_oauth_env_fallback_keys():
                env.pop(key, None)
        return env

    def openclaw_oauth_profile_present(payload, provider_id):
        if provider_id != "openai":
            return True
        auth = payload.get("auth") or {}
        oauth = auth.get("oauth") or {}
        for profile in oauth.get("profiles") or []:
            if profile.get("provider") == "openai" and profile.get("status") not in {"missing", "expired"}:
                return True
        for provider in oauth.get("providers") or []:
            if provider.get("provider") == "openai" and provider.get("status") not in {"missing", "expired"}:
                return True
        for label in auth.get("providersWithOAuth") or []:
            if str(label).startswith("openai "):
                return True
        return False

    def openclaw_auth_profile_usable(exe, provider_id, credential):
        env = credential_env_by_provider_id(provider_id, credential)
        if provider_id == "openai":
            for key in openclaw_openai_oauth_env_fallback_keys():
                env.pop(key, None)
        result = run_process(
            [
                exe,
                "models",
                "status",
                "--json",
                "--probe-provider",
                provider_id,
            ],
            env=env,
            timeout=60,
        )
        if not result["ok"]:
            return False
        try:
            payload = load_json_object(result["stdout"] + "\\n" + result["stderr"])
            if not openclaw_oauth_profile_present(payload, provider_id):
                return False
            routes = ((payload.get("auth") or {}).get("runtimeAuthRoutes") or [])
            for route in routes:
                if openclaw_auth_route_matches(route, provider_id) and route.get("status") == "usable":
                    return True
        except Exception:
            return False
        return False

    def credential_env_by_provider_id(provider_id, credential):
        provider = next(
            (candidate for candidate in provider_choices if candidate["openclaw_provider"] == provider_id),
            None,
        )
        return credential_env(provider, credential) if provider else os.environ.copy()

    def run_openclaw_anthropic_cli_setup(exe, provider, credential):
        env = credential_env(provider, credential)
        provider_id = provider_id_for_runtime(provider, "openclaw")
        if openclaw_auth_profile_usable(exe, provider_id, credential):
            print(message(
                "Existing Claude CLI auth profile is already registered in OpenClaw. Continuing without another registration.",
                "OpenClaw에 기존 Claude CLI auth profile이 확인되어 재등록 없이 계속합니다.",
                "OpenClawに既存のClaude CLI auth profileが確認されたため、再登録せずに続行します。",
            ))
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        status, logged_in = claude_cli_auth_status(env)
        if not logged_in:
            print(message(
                "Claude CLI login is required. Continue the Claude login flow below.",
                "Claude CLI 로그인이 필요합니다. 아래 Claude 로그인 절차를 계속 진행하세요.",
                "Claude CLIログインが必要です。以下のClaudeログイン手順を続けてください。",
            ))
            login = run_interactive_process(["claude", "auth", "login"], env=env, timeout=900)
            if not login["ok"]:
                return login
            status, logged_in = claude_cli_auth_status(env)
            if not logged_in:
                return {
                    "ok": False,
                    "code": status.get("code", 1),
                    "stdout": status.get("stdout", ""),
                    "stderr": status.get("stderr", "") or "claude_cli_auth_not_verified",
                }
        print(message(
            "Registering Claude CLI auth profile in OpenClaw...",
            "OpenClaw에 Claude CLI auth profile을 등록합니다...",
            "OpenClawにClaude CLI auth profileを登録します...",
        ))
        return run_interactive_process_until(
            [exe, "models", "auth", "login", "--provider", "anthropic", "--method", "cli", "--set-default"],
            lambda: openclaw_auth_profile_usable(exe, provider_id, credential),
            env=env,
            timeout=900,
        )

    def run_openclaw_openai_codex_setup(exe, provider, credential):
        env = openclaw_env(provider, credential)
        provider_id = provider_id_for_runtime(provider, "openclaw")
        if openclaw_auth_profile_usable(exe, provider_id, credential):
            print(message(
                "Existing ChatGPT/Codex account login is already registered in OpenClaw. Continuing without another login.",
                "OpenClaw에 기존 ChatGPT/Codex 계정 연동이 확인되어 재로그인 없이 계속합니다.",
                "OpenClawに既存のChatGPT/Codexアカウント連携が確認されたため、再ログインせずに続行します。",
            ))
            return {"ok": True, "code": 0, "stdout": "", "stderr": ""}
        print(message(
            "Registering ChatGPT/Codex account login in OpenClaw...",
            "OpenClaw에 ChatGPT/Codex 계정 연동을 등록합니다...",
            "OpenClawにChatGPT/Codexアカウント連携を登録します...",
        ))
        return run_interactive_process_until(
            [exe, "models", "auth", "login", "--provider", "openai", "--method", "oauth", "--set-default"],
            lambda: openclaw_auth_profile_usable(exe, provider_id, credential),
            env=env,
            timeout=900,
        )

    def run_openclaw_onboard(exe, provider, credential):
        env = credential_env(provider, credential)
        argv = [
            exe,
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--mode",
            "local",
            "--auth-choice",
            provider["openclaw_auth"],
            "--secret-input-mode",
            "ref",
        ]
        help_flags = openclaw_help_flags(exe)
        for flag in [
            "--skip-daemon",
            "--skip-ui",
            "--skip-skills",
            "--skip-health",
            "--skip-bootstrap",
            "--skip-channels",
            "--skip-search",
        ]:
            if flag in help_flags:
                argv.append(flag)
        result = run_process(argv, env=env, timeout=300)
        if result["ok"]:
            return result
        return result

    def run_openclaw_config(exe, provider, credential):
        if provider.get("id") == "anthropic-claude-code":
            return run_openclaw_anthropic_cli_setup(exe, provider, credential)
        if provider.get("id") == "openai-codex":
            return run_openclaw_openai_codex_setup(exe, provider, credential)
        return run_openclaw_onboard(exe, provider, credential)

    def verify_hermes_llm_call(exe, provider, credential):
        provider_id = provider_id_for_runtime(provider, "hermes")
        result = run_process(
            [
                exe,
                "chat",
                "-q",
                "Reply with OK. Do not use tools.",
                "--provider",
                provider_id,
                "--model",
                provider["hermes_model"],
                "--max-turns",
                "1",
                "--quiet",
                "--ignore-rules",
            ],
            env=credential_env(provider, credential),
            timeout=120,
        )
        if not result["ok"]:
            return result
        if not result["stdout"]:
            return {"ok": False, "code": 1, "stdout": result["stdout"], "stderr": "empty_llm_response"}
        if "ok" not in result["stdout"].lower():
            return {"ok": False, "code": 1, "stdout": result["stdout"], "stderr": "unexpected_llm_response"}
        return result

    def verify_openclaw_llm_call(exe, provider, credential):
        provider_id = provider_id_for_runtime(provider, "openclaw")
        result = run_process(
            [
                exe,
                "models",
                "status",
                "--json",
                "--probe",
                "--probe-provider",
                provider_id,
                "--probe-timeout",
                "15000",
                "--probe-concurrency",
                "1",
                "--probe-max-tokens",
                "4",
            ],
            env=openclaw_env(provider, credential),
            timeout=180,
        )
        if not result["ok"]:
            return result
        try:
            payload = load_json_object(result["stdout"])
            probes = (((payload.get("auth") or {}).get("probes") or {}).get("results") or [])
            for probe in probes:
                if probe.get("provider") == provider_id and probe.get("status") == "ok":
                    return result
            statuses = ", ".join(
                f"{probe.get('provider', '?')}:{probe.get('status', '?')}"
                for probe in probes
            )
            return {
                "ok": False,
                "code": 1,
                "stdout": result["stdout"],
                "stderr": f"no_ok_llm_probe_for_{provider_id}" + (f" ({statuses})" if statuses else ""),
            }
        except Exception as exc:
            return {"ok": False, "code": 1, "stdout": result["stdout"], "stderr": f"probe_json_parse_failed: {exc}"}

    def verify_llm_call(runtime, executable, provider, credential):
        print()
        print(message(
            "Checking that the selected tool can call the LLM...",
            "선택한 실행 도구가 LLM을 호출할 수 있는지 확인합니다...",
            "選択した実行ツールがLLMを呼び出せるか確認します...",
        ))
        if runtime == "hermes":
            result = verify_hermes_llm_call(executable["path"], provider, credential)
        else:
            result = verify_openclaw_llm_call(executable["path"], provider, credential)
        if not result["ok"]:
            print_command_failure(result, credential)
            raise RuntimeError("llm_call_verification_failed")
        print(message(
            "LLM call verified.",
            "LLM 호출 가능 상태를 확인했습니다.",
            "LLM呼び出し可能な状態を確認しました。",
        ))
        return result

    def write_receipt(runtime, executable, provider, credential, command_result, verification_result):
        config_paths = hermes_paths() if runtime == "hermes" else openclaw_paths()
        state = load_state()
        state["schemaVersion"] = 1
        state["receipt"] = {
            "complete": True,
            "runtime": runtime,
            "executablePath": executable["path"],
            "version": executable["version"],
            "provider": provider["id"],
            "runtimeProvider": provider_id_for_runtime(provider, runtime),
            "runtimeModel": provider.get("hermes_model") if runtime == "hermes" else "",
            "keySource": credential["source"],
            "keyEnvName": credential.get("envName") or "",
            "keyPersistedEnvName": credential.get("persistEnvName") or "",
            "configPaths": config_paths,
            "verifiedAt": now(),
            "checks": {
                "executable": True,
                "credentials": True,
                "runtimeConfigCommand": bool(command_result.get("ok")),
                "llmCall": bool(verification_result.get("ok")),
            },
            "reasons": [],
        }
        save_state(state)
        print()
        runtime_name = runtime_display_name(runtime)
        print(message(
            "OpenClaw/Hermes execution setup is complete.",
            "OpenClaw/Hermes 실행 준비가 완료되었습니다.",
            "OpenClaw/Hermesの実行準備が完了しました。",
        ))
        print(message(
            f"Selected execution tool: {runtime_name}",
            f"선택한 실행 도구: {runtime_name}",
            f"選択した実行ツール: {runtime_name}",
        ))
        print()
        print(message(
            "Return to Zebra onboarding and continue with gbrain installation.",
            "Zebra 온보딩으로 돌아가 gbrain 설치를 계속하세요.",
            "Zebraオンボーディングに戻ってgbrainのインストールを続けてください。",
        ))

    def print_provider_selection_notice(runtime, provider):
        print()
        if runtime == "hermes":
            if provider.get("id") == "anthropic-claude-code":
                print(message(
                    "Hermes condition: Max + extra credits required.",
                    "Hermes 조건: Max + extra credits 필요.",
                    "Hermes条件: Max + extra credits 必須。",
                ))
            elif provider.get("id") == "openai-codex":
                print(message(
                    "Hermes will use OpenAI Codex account login.",
                    "Hermes에 OpenAI Codex 계정 연동을 설정합니다.",
                    "HermesにOpenAI Codexアカウント連携を設定します。",
                ))
            else:
                print(message(
                    f"Hermes will use {provider['label']}.",
                    f"Hermes에 {provider['label']} 연결 정보를 설정합니다.",
                    f"Hermesに{provider['label']}の接続情報を設定します。",
                ))
            return
        if provider.get("id") == "anthropic-claude-code":
            print(message(
                "OpenClaw condition: Claude CLI login required.",
                "OpenClaw 조건: Claude CLI 로그인 필요.",
                "OpenClaw条件: Claude CLIログイン必須。",
            ))
        elif provider.get("id") == "openai-codex":
            print(message(
                "OpenClaw will register ChatGPT/Codex account login.",
                "OpenClaw에 ChatGPT/Codex 계정 연동을 등록합니다.",
                "OpenClawにChatGPT/Codexアカウント連携を登録します。",
            ))
        else:
            print(message(
                f"OpenClaw will use {provider['label']}.",
                f"OpenClaw에 {provider['label']} 연결 정보를 설정합니다.",
                f"OpenClawに{provider['label']}の接続情報を設定します。",
            ))

    def run_onboarding():
        detection = detect_all()
        runtime = choose_runtime(detection)
        executable = ensure_runtime_installed(runtime, detection)
        print_provider_intro(runtime)
        provider = choose_provider()
        print_provider_selection_notice(runtime, provider)
        credential = credential_for(provider, runtime)
        if runtime == "hermes":
            command_result = run_hermes_config(executable["path"], provider, credential)
        else:
            command_result = run_openclaw_config(executable["path"], provider, credential)
        if not command_result["ok"]:
            print_command_failure(command_result, credential)
            raise RuntimeError(f"{runtime}_config_failed")
        verification_result = verify_llm_call(runtime, executable, provider, credential)
        write_receipt(runtime, executable, provider, credential, command_result, verification_result)

    def print_status():
        state = load_state()
        output = {
            "statePath": str(state_path),
            "detection": detect_all(),
            "receipt": state.get("receipt"),
        }
        print(json.dumps(output, indent=2, sort_keys=True))

    if command in {"run", ""}:
        try:
            run_onboarding()
        except KeyboardInterrupt:
            print("\\nCancelled.")
            sys.exit(130)
        except Exception as exc:
            state = load_state()
            state["schemaVersion"] = 1
            state["receipt"] = {
                "complete": False,
                "verifiedAt": now(),
                "reasons": [str(exc)],
            }
            save_state(state)
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
    elif command in {"status", "detect"}:
        print_status()
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(2)
    PY
    """
}
