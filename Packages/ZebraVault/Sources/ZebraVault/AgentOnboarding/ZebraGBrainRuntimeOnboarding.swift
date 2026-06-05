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
    import getpass
    import json
    import os
    import shutil
    import subprocess
    import sys
    from datetime import datetime, timezone
    from pathlib import Path

    state_path = Path(sys.argv[1]).expanduser()
    command = sys.argv[2] or "run"
    home = Path(os.environ.get("ZEBRA_GBRAIN_RUNTIME_HOME") or str(Path.home())).expanduser()
    language = (os.environ.get("ZEBRA_ONBOARDING_LANGUAGE") or "en").split("-")[0].lower()
    if language not in {"en", "ja", "ko"}:
        language = "en"

    provider_choices = [
        {"id": "openrouter", "label": "OpenRouter", "env": "OPENROUTER_API_KEY", "openclaw_provider": "openrouter", "openclaw_auth": "openrouter-api-key", "hermes_provider": "openrouter", "hermes_model": "google/gemini-3.5-flash", "hermes_base_url": "https://openrouter.ai/api/v1", "hermes_base_env": "OPENROUTER_BASE_URL", "hermes_api_mode": "chat_completions"},
        {"id": "openai", "label": "OpenAI", "env": "OPENAI_API_KEY", "openclaw_provider": "openai", "openclaw_auth": "openai-api-key", "hermes_provider": "openai-api", "hermes_model": "gpt-5-mini", "hermes_base_url": "https://api.openai.com/v1", "hermes_base_env": "OPENAI_BASE_URL", "hermes_api_mode": "codex_responses"},
        {"id": "anthropic", "label": "Anthropic", "env": "ANTHROPIC_API_KEY", "openclaw_provider": "anthropic", "openclaw_auth": "anthropic-api-key", "hermes_provider": "anthropic", "hermes_model": "claude-haiku-4-5-20251001", "hermes_base_url": "https://api.anthropic.com", "hermes_base_env": "ANTHROPIC_BASE_URL", "hermes_api_mode": "anthropic_messages"},
        {"id": "google", "label": "Google Gemini", "env": "GOOGLE_API_KEY", "openclaw_provider": "google", "openclaw_auth": "google-api-key", "hermes_provider": "gemini", "hermes_model": "gemini-3.5-flash", "hermes_base_url": "https://generativelanguage.googleapis.com/v1beta", "hermes_base_env": "GEMINI_BASE_URL", "hermes_api_mode": "chat_completions"},
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

    def run_process(argv, *, env=None, timeout=45):
        try:
            completed = subprocess.run(
                argv,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=timeout,
            )
            return {
                "ok": completed.returncode == 0,
                "code": completed.returncode,
                "stdout": completed.stdout.strip(),
                "stderr": completed.stderr.strip(),
            }
        except Exception as exc:
            return {"ok": False, "code": -1, "stdout": "", "stderr": str(exc)}

    def credential_env(provider, credential):
        env = os.environ.copy()
        if credential.get("value"):
            env[provider["env"]] = credential["value"]
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
            "Now choose the API provider gbrain will use.",
            "이제 gbrain 실행에 사용할 API provider를 선택합니다.",
            "次にgbrain実行に使用するAPI providerを選択します。",
        ))

    def choose_provider():
        print()
        for index, provider in enumerate(provider_choices, start=1):
            env = provider["env"]
            has_env = bool(os.environ.get(env))
            print(f"{index}. {provider['label']} ({env}{' set' if has_env else ''})")
        while True:
            raw = ask(message("Select API provider", "API provider 선택", "API providerを選択"), "1").lower()
            for index, provider in enumerate(provider_choices, start=1):
                if raw in {str(index), provider["id"]}:
                    return provider
            print(message("Choose one provider number.", "provider 번호를 선택하세요.", "provider番号を選んでください。"))

    def credential_for(provider, runtime):
        env_name = provider["env"]
        if os.environ.get(env_name):
            return {"value": os.environ[env_name], "source": f"env:{env_name}"}
        hermes_env = read_env_file_vars(hermes_paths()["env"])
        if runtime == "hermes" and hermes_env.get(env_name):
            return {"value": hermes_env[env_name], "source": f"hermes-env:{env_name}"}
        value = getpass.getpass(message(
            f"Enter {provider['label']} API key (input hidden): ",
            f"{provider['label']} API key 입력 (입력값 숨김): ",
            f"{provider['label']} API keyを入力（非表示）: ",
        )).strip()
        if not value:
            raise RuntimeError("api_key_missing")
        return {"value": value, "source": f"entered:{env_name}"}

    def run_hermes_config(exe, provider, credential):
        env_name = provider["env"]
        env = credential_env(provider, credential)
        if credential["value"]:
            result = write_env_file_value(hermes_paths()["env"], env_name, credential["value"])
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
            env=credential_env(provider, credential),
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

    def run_onboarding():
        detection = detect_all()
        runtime = choose_runtime(detection)
        executable = ensure_runtime_installed(runtime, detection)
        print_provider_intro(runtime)
        provider = choose_provider()
        credential = credential_for(provider, runtime)
        if runtime == "hermes":
            command_result = run_hermes_config(executable["path"], provider, credential)
        else:
            command_result = run_openclaw_onboard(executable["path"], provider, credential)
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
