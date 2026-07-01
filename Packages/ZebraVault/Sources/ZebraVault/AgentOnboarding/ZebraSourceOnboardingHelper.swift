import Foundation

struct ZebraSourceOnboardingHelper {
    struct LaunchContext {
        var helperPath: String
        var launchDirectory: String
        var shellEnvironmentPrefix: String
    }

    private let stateURL: URL
    private let gbrainOnboardingStateURL: URL
    private let gbrainAdapterOnboardingStateURL: URL
    private let fileManager: FileManager
    private let homeDirectoryPath: String

    init(
        stateURL: URL = ZebraSourceOnboardingState.defaultStateURL(),
        gbrainOnboardingStateURL: URL = ZebraGBrainOnboardingStore.defaultStateURL(),
        gbrainAdapterOnboardingStateURL: URL = ZebraGBrainAdapterOnboardingStore.defaultStateURL(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.stateURL = stateURL
        self.gbrainOnboardingStateURL = gbrainOnboardingStateURL
        self.gbrainAdapterOnboardingStateURL = gbrainAdapterOnboardingStateURL
        self.fileManager = fileManager
        self.homeDirectoryPath = Self.standardizedPath(homeDirectoryPath)
    }

    func prepareLaunch(selectedVaultPath: String?) -> LaunchContext? {
        guard let helperURL = installHelperScript() else { return nil }
        let helperDirectory = helperURL.deletingLastPathComponent().path
        var commands = [
            "export ZEBRA_SOURCE_ONBOARDING_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_SETUP_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainOnboardingStateURL.path))",
            "export ZEBRA_GBRAIN_ADAPTER_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainAdapterOnboardingStateURL.path))",
            "export ZEBRA_SOURCE_ONBOARDING_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
        ]
        if let selectedVaultPath = standardizedExistingDirectoryPath(selectedVaultPath) {
            commands.append("export ZEBRA_SOURCE_SELECTED_VAULT=\(ZebraAgentLaunchCommand.shellQuote(selectedVaultPath))")
        }
        return LaunchContext(
            helperPath: helperURL.path,
            launchDirectory: onboardingWorkDirectoryPath(),
            shellEnvironmentPrefix: commands.joined(separator: " && ") + " && "
        )
    }

    private func installHelperScript() -> URL? {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
        let url = directory.appendingPathComponent("zebra-source-onboarding", isDirectory: false)
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
            .appendingPathComponent("source-onboarding-work", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.standardizedPath(directory.path)
    }

    private func standardizedExistingDirectoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let standardized = Self.standardizedPath((path as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return standardized
    }

    private static func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static let helperScript = """
    #!/bin/sh
    set -eu

    STATE="${ZEBRA_SOURCE_ONBOARDING_STATE:-$HOME/Library/Application Support/zebra/onboarding/source-onboarding-state.json}"
    COMMAND="${1:-status}"
    if [ $# -gt 0 ]; then
      shift
    fi

    PYTHON_BIN="$(command -v python3 || true)"
    if [ -z "$PYTHON_BIN" ]; then
      echo "python3 is required for zebra-source-onboarding" >&2
      exit 1
    fi

    "$PYTHON_BIN" - "$STATE" "$COMMAND" "$@" <<'PY'
    import json
    import os
    import sys
    import urllib.error
    import urllib.parse
    import urllib.request
    import uuid
    from datetime import datetime, timezone
    from pathlib import Path

    state_path = Path(sys.argv[1]).expanduser()
    command = sys.argv[2] or "status"
    args = sys.argv[3:]
    home = Path(os.environ.get("ZEBRA_SOURCE_ONBOARDING_HOME") or str(Path.home())).expanduser()
    gbrain_state_path = Path(
        os.environ.get("ZEBRA_GBRAIN_SETUP_STATE")
        or str(home / "Library/Application Support/zebra/onboarding/gbrain-setup-state.json")
    ).expanduser()
    adapter_state_path = Path(
        os.environ.get("ZEBRA_GBRAIN_ADAPTER_STATE")
        or str(home / "Library/Application Support/zebra/onboarding/gbrain-adapter-state.json")
    ).expanduser()
    selected_vault = os.environ.get("ZEBRA_SOURCE_SELECTED_VAULT") or ""

    supported = {
        "gmail": {
            "displayName": "Gmail",
            "type": "email",
            "aliases": ["gmail", "지메일", "이메일", "email", "메일"],
        },
        "obsidian": {
            "displayName": "Obsidian",
            "type": "vault",
            "aliases": ["obsidian", "옵시디언", "옵시디안", "vault", "볼트"],
        },
        "imessage": {
            "displayName": "iMessage",
            "type": "messages",
            "aliases": ["imessage", "imsg", "아이메세지", "아이메시지", "messages", "message", "문자", "sms"],
        },
        "notion": {
            "displayName": "Notion",
            "type": "workspace",
            "aliases": ["notion", "노션"],
        },
    }

    uncataloged_catalog = {
        "slack": {"displayName": "Slack", "aliases": ["slack", "슬랙"]},
        "apple-notes": {"displayName": "Apple Notes", "aliases": ["apple notes", "apple note", "애플 메모"]},
        "apple-reminders": {"displayName": "Apple Reminders", "aliases": ["apple reminders", "apple reminder", "애플 리마인더", "reminders", "reminder"]},
    }

    def now():
        return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    def load_json(path):
        try:
            with path.open("r", encoding="utf-8") as handle:
                value = json.load(handle)
            return value if isinstance(value, dict) else {}
        except Exception:
            return {}

    def migrate_source_state(value):
        progress = value.get("progress") if isinstance(value.get("progress"), dict) else None
        if progress is None:
            return False
        legacy = progress.get("unsupportedInputs")
        if "uncatalogedSources" not in progress and isinstance(legacy, list):
            progress["uncatalogedSources"] = legacy
        if "unsupportedInputs" in progress:
            progress.pop("unsupportedInputs", None)
            return True
        return False

    def save_json(value):
        state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = state_path.with_suffix(state_path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, state_path)

    def canonical_path(value):
        if not value:
            return ""
        return str(Path(value).expanduser().resolve(strict=False))

    def existing_directory(value):
        if not value:
            return ""
        candidate = Path(value).expanduser()
        if not candidate.is_dir():
            return ""
        return canonical_path(candidate)

    def parse_env_keys(path):
        keys = set()
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except Exception:
            return keys
        for raw in lines:
            text = raw.strip()
            if not text or text.startswith("#"):
                continue
            if text.startswith("export "):
                text = text[len("export "):].strip()
            if "=" not in text:
                continue
            key = text.split("=", 1)[0].strip()
            if key:
                keys.add(key)
        return keys

    def local_email_artifact():
        artifact_path = home / "Library/Application Support/zebra/email.sqlite"
        if not artifact_path.exists():
            return None
        return {
            "kind": "sqlite",
            "path": str(artifact_path),
            "exists": True,
        }

    def gmail_readiness_record(status, env_path, connection_path=None, repair_kind=None, reasons=None):
        return {
            "status": status,
            "connectionPath": connection_path,
            "envPath": str(env_path),
            "localArtifact": local_email_artifact(),
            "repairKind": repair_kind,
            "reasons": reasons or [],
        }

    def gmail_readiness():
        env_path = home / ".gbrain/.env"
        required = {"CLAWVISOR_URL", "CLAWVISOR_AGENT_TOKEN", "CLAWVISOR_TASK_ID"}
        keys = parse_env_keys(env_path)
        has_required = required.issubset(keys)
        if has_required:
            return gmail_readiness_record(
                "unverified",
                env_path,
                connection_path="existing_clawvisor_gmail_connection_path",
                reasons=["email_connection_unverified"],
            )
        return gmail_readiness_record(
            "missing_env",
            env_path,
            reasons=["clawvisor_email_env_missing_or_incomplete"],
        )

    def default_state(timestamp=None):
        timestamp = timestamp or now()
        return {
            "schemaVersion": 1,
            "status": "attention" if entry_context().get("gbrainTargetMissingReason") else "ready",
            "entryContext": entry_context(),
            "sourceReadiness": {"gmail": gmail_readiness()},
            "progress": {
                "rawSourceInput": None,
                "normalizedSourceList": [],
                "uncatalogedSources": [],
                "sourceConfirmation": None,
                "sourceRows": {},
                "pendingQuestion": None,
            },
            "updatedAt": timestamp,
        }

    def load_or_create_state():
        state = load_json(state_path)
        if not state:
            return default_state()
        migrate_source_state(state)
        state.setdefault("schemaVersion", 1)
        state.setdefault("status", "ready")
        state.setdefault("entryContext", entry_context())
        state.setdefault("sourceReadiness", {})
        state.setdefault("progress", {
            "rawSourceInput": None,
            "normalizedSourceList": [],
            "uncatalogedSources": [],
            "sourceConfirmation": None,
            "sourceRows": {},
            "pendingQuestion": None,
        })
        return state

    def update_gmail_readiness(status, env_path, connection_path=None, repair_kind=None, reasons=None):
        state = load_or_create_state()
        source_readiness = state.get("sourceReadiness")
        if not isinstance(source_readiness, dict):
            source_readiness = {}
        source_readiness["gmail"] = gmail_readiness_record(
            status,
            env_path,
            connection_path=connection_path,
            repair_kind=repair_kind,
            reasons=reasons,
        )
        state["sourceReadiness"] = source_readiness
        state["updatedAt"] = now()
        save_json(state)
        return state

    def resolve_gbrain_target():
        gbrain = load_json(gbrain_state_path)
        receipt = gbrain.get("receipt") or {}
        targets = receipt.get("targets") or {}
        selected = existing_directory(selected_vault)
        if selected:
            for key, target in targets.items():
                path = existing_directory((target or {}).get("vaultPath") or "")
                if path == selected:
                    return key, path, target or {}
            return "vault:" + selected, selected, {}
        key = receipt.get("primaryTargetKey") or ""
        target = targets.get(key) or {}
        path = existing_directory(target.get("vaultPath") or "")
        if key and path:
            return key, path, target
        return None, None, {}

    def entry_context():
        target_key, target_path, target = resolve_gbrain_target()
        adapter = load_json(adapter_state_path)
        adapter_receipt = adapter.get("receipt") or {}
        warnings = target.get("warnings") if isinstance(target.get("warnings"), list) else []
        return {
            "selectedVaultPath": existing_directory(selected_vault) or None,
            "gbrainTargetPath": target_path,
            "gbrainTargetKey": target_key,
            "gbrainReceiptPath": str(gbrain_state_path),
            "gbrainTargetStatus": target.get("status") or ("receipt_target_available" if target_path else None),
            "gbrainTargetMissingReason": None if target_path else "gbrain_target_missing",
            "gbrainWarnings": warnings,
            "liveProbe": {
                "ran": False,
                "status": None,
                "reason": "step3_receipt_available" if target_path else "gbrain_target_missing",
            },
            "adapterReady": bool(adapter_receipt.get("complete")),
            "adapterReadinessReasons": adapter_receipt.get("reasons") if isinstance(adapter_receipt.get("reasons"), list) else [],
        }

    def strip_optional_quotes(value):
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            return value[1:-1]
        return value

    def dotenv_values():
        env_path = home / ".gbrain/.env"
        values = {}
        raw = env_path.read_text(encoding="utf-8")
        for line in raw.splitlines():
            text = line.strip()
            if not text or text.startswith("#") or "=" not in text:
                continue
            if text.startswith("export "):
                text = text[len("export "):].lstrip()
            key, value = text.split("=", 1)
            key = key.strip()
            if key:
                values[key] = strip_optional_quotes(value)
        return env_path, values

    def persisted_env():
        try:
            env_path, values = dotenv_values()
        except Exception:
            env_path = home / ".gbrain/.env"
            values = {}
        return env_path, values

    def request_json(method, url, token, body=None):
        try:
            data = None
            headers = {"Authorization": "Bearer " + token}
            if body is not None:
                data = json.dumps(body).encode("utf-8")
                headers["Content-Type"] = "application/json"
            request = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read().decode("utf-8")
                return response.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            raw = error.read().decode("utf-8", errors="replace")
            try:
                payload = json.loads(raw) if raw else {}
            except Exception:
                payload = {"error": raw}
            return error.code, payload
        except Exception as error:
            return 0, {"error": type(error).__name__, "detail": str(error)}

    def is_gmail_service(service):
        service = (service or "").strip()
        return service == "google.gmail" or service.startswith("google.gmail:")

    def gmail_service_from_task(value):
        if isinstance(value, dict):
            service = value.get("service")
            if isinstance(service, str) and is_gmail_service(service):
                return service
            actions = value.get("authorized_actions")
            if isinstance(actions, list):
                for action in actions:
                    service = gmail_service_from_task(action)
                    if service:
                        return service
            for key in ("task", "data", "result"):
                service = gmail_service_from_task(value.get(key))
                if service:
                    return service
        if isinstance(value, list):
            for item in value:
                service = gmail_service_from_task(item)
                if service:
                    return service
        return ""

    def gmail_verify_env():
        env_path, env = persisted_env()
        required = [
            "CLAWVISOR_URL",
            "CLAWVISOR_AGENT_TOKEN",
            "CLAWVISOR_TASK_ID",
        ]
        missing = [key for key in required if not env.get(key, "").strip()]
        if missing:
            update_gmail_readiness(
                "missing_env",
                env_path,
                reasons=["missing:" + ",".join(missing)],
            )
        else:
            update_gmail_readiness(
                "unverified",
                env_path,
                connection_path="clawvisor_env_available",
                reasons=["email_connection_unverified"],
            )
        print(json.dumps({"ok": not missing, "missing": missing, "path": str(env_path)}, sort_keys=True))
        return 0 if not missing else 1

    def gmail_verify_connection():
        env_path, env = persisted_env()
        required = ["CLAWVISOR_URL", "CLAWVISOR_AGENT_TOKEN", "CLAWVISOR_TASK_ID"]
        missing = [key for key in required if not env.get(key, "").strip()]
        if missing:
            update_gmail_readiness(
                "missing_env",
                env_path,
                reasons=["missing:" + ",".join(missing)],
            )
            print(json.dumps({"ok": False, "stage": "env", "missing": missing, "path": str(env_path)}, sort_keys=True))
            return 1
        base_url = env["CLAWVISOR_URL"].strip().rstrip("/")
        token = env["CLAWVISOR_AGENT_TOKEN"].strip()
        task_id = env["CLAWVISOR_TASK_ID"].strip()
        task_url = base_url + "/api/tasks/" + urllib.parse.quote(task_id, safe="")
        status, task = request_json("GET", task_url, token)
        if status == 0:
            reason = "task_request_failed:" + str(task.get("error") if isinstance(task, dict) else "request_failed")
            update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id,
                repair_kind="task_request_failed",
                reasons=[reason],
            )
            print(json.dumps({"ok": False, "stage": "task", "status": status, "response": task}, sort_keys=True))
            return 1
        if status < 200 or status >= 300:
            update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id,
                repair_kind="task_lookup_failed",
                reasons=["task_http_status:" + str(status)],
            )
            print(json.dumps({"ok": False, "stage": "task", "status": status, "response": task}, sort_keys=True))
            return 1
        service = gmail_service_from_task(task)
        if not service:
            update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id,
                repair_kind="gmail_service_missing",
                reasons=["no_authorized_google_gmail_service"],
            )
            print(json.dumps({"ok": False, "stage": "task", "reason": "no authorized google.gmail service"}, sort_keys=True))
            return 1
        gateway_body = {
            "task_id": task_id,
            "session_id": str(uuid.uuid4()),
            "service": service,
            "action": "list_messages",
            "params": {"query": "newer_than:7d", "max_results": 1},
            "reason": "Verify Zebra can read Gmail through the approved Clawvisor task before marking Source Onboarding Gmail integration complete.",
        }
        gateway_url = base_url + "/api/gateway/request?wait=true"
        status, gateway = request_json("POST", gateway_url, token, gateway_body)
        if status == 0:
            reason = "gateway_request_failed:" + str(gateway.get("error") if isinstance(gateway, dict) else "request_failed")
            update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id + "#" + service,
                repair_kind="gateway_request_failed",
                reasons=[reason],
            )
            print(json.dumps({"ok": False, "stage": "gateway", "status": status, "service": service, "response": gateway}, sort_keys=True))
            return 1
        if status < 200 or status >= 300:
            update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id + "#" + service,
                repair_kind="gateway_failed",
                reasons=["gateway_http_status:" + str(status)],
            )
            print(json.dumps({"ok": False, "stage": "gateway", "status": status, "service": service, "response": gateway}, sort_keys=True))
            return 1
        gateway_status = gateway.get("status") if isinstance(gateway, dict) else None
        if gateway_status and gateway_status not in ("executed", "approved", "completed", "success"):
            update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id + "#" + service,
                repair_kind="gateway_pending_or_rejected",
                reasons=["gateway_status:" + str(gateway_status)],
            )
            print(json.dumps({"ok": False, "stage": "gateway", "status": gateway_status, "service": service, "response": gateway}, sort_keys=True))
            return 1
        update_gmail_readiness(
            "ready",
            env_path,
            connection_path="clawvisor_task:" + task_id + "#" + service,
            reasons=[],
        )
        print(json.dumps({"ok": True, "service": service, "taskId": task_id}, sort_keys=True))
        return 0

    def gmail_command():
        if not args:
            print("gmail requires a subcommand", file=sys.stderr)
            return 2
        subcommand = args[0]
        if subcommand == "verify-env":
            return gmail_verify_env()
        if subcommand == "verify-connection":
            return gmail_verify_connection()
        print("unknown gmail subcommand: " + subcommand, file=sys.stderr)
        return 2

    def split_pair(value):
        if "=" in value:
            left, right = value.split("=", 1)
            return left.strip(), right.strip()
        return value.strip(), value.strip()

    def parse_intake_args():
        raw = ""
        candidates = []
        uncataloged = []
        index = 0
        while index < len(args):
            token = args[index]
            if token == "--raw" and index + 1 < len(args):
                raw = args[index + 1]
                index += 2
            elif token == "--candidate" and index + 1 < len(args):
                candidates.append(split_pair(args[index + 1]))
                index += 2
            elif token == "--uncataloged" and index + 1 < len(args):
                uncataloged.append(split_pair(args[index + 1]))
                index += 2
            else:
                print("unknown or incomplete argument: " + token, file=sys.stderr)
                sys.exit(2)
        if not raw.strip():
            print("--raw is required", file=sys.stderr)
            sys.exit(2)
        return raw, candidates, uncataloged

    def best_alias_match(raw, aliases):
        lower_raw = raw.lower()
        best = None
        for alias in aliases:
            position = lower_raw.find(alias.lower())
            if position < 0:
                continue
            raw_value = raw[position:position + len(alias)]
            candidate = (position, -len(alias), raw_value)
            if best is None or candidate < best:
                best = candidate
        if best is None:
            return None
        return best[0], best[2]

    def scan_aliases(raw):
        matches = []
        for source_id, definition in supported.items():
            match = best_alias_match(raw, definition["aliases"])
            if match:
                matches.append((match[0], source_id, match[1]))
        for source_id, definition in uncataloged_catalog.items():
            match = best_alias_match(raw, definition["aliases"])
            if match:
                matches.append((match[0], source_id, match[1]))
        return [(source_id, raw_value) for _, source_id, raw_value in sorted(matches)]

    def add_uncataloged(items, seen, source_id, raw_value, reason="not_in_current_catalog"):
        normalized = source_id.strip().lower()
        if not normalized or normalized in seen:
            return
        seen.add(normalized)
        display = uncataloged_catalog.get(normalized, {}).get("displayName")
        items.append({
            "rawValue": raw_value or normalized,
            "normalizedValue": normalized,
            "displayName": display,
            "reason": reason,
        })

    def source_display_name(source_id, raw_value=None):
        if source_id in supported:
            return supported[source_id]["displayName"]
        return uncataloged_catalog.get(source_id, {}).get("displayName") or raw_value or source_id

    def confirmation_prompt(display_names):
        if not display_names:
            return "아직 Zebra가 처리할 수 있는 source를 확인하지 못했습니다. Zebra가 이해해야 할 source를 자유롭게 적어주세요."
        names = ", ".join(display_names)
        return names + "로 이해했습니다. 맞나요?"

    def intake():
        raw, candidates, uncataloged_pairs = parse_intake_args()
        source_ids = []
        seen_sources = set()
        uncataloged_sources = []
        seen_uncataloged = set()
        prompt_names = []
        seen_prompt = set()

        def remember_prompt(source_id, raw_value=None):
            normalized = source_id.strip().lower()
            if normalized and normalized not in seen_prompt:
                seen_prompt.add(normalized)
                prompt_names.append(source_display_name(normalized, raw_value))

        def consider(source_id, raw_value, include_prompt=True):
            normalized = source_id.strip().lower()
            if normalized in supported:
                if normalized not in seen_sources:
                    seen_sources.add(normalized)
                    source_ids.append(normalized)
                    if include_prompt:
                        remember_prompt(normalized, raw_value)
            else:
                before = len(uncataloged_sources)
                add_uncataloged(uncataloged_sources, seen_uncataloged, normalized, raw_value)
                if include_prompt and len(uncataloged_sources) > before:
                    remember_prompt(normalized, raw_value)

        for source_id, raw_value in scan_aliases(raw):
            consider(source_id, raw_value)
        for source_id, raw_value in candidates:
            consider(source_id, raw_value, include_prompt=True)
        for source_id, raw_value in uncataloged_pairs:
            consider(source_id, raw_value, include_prompt=True)

        timestamp = now()
        rows = {}
        for source_id in source_ids:
            definition = supported[source_id]
            rows[source_id] = {
                "id": source_id,
                "displayName": definition["displayName"],
                "type": definition["type"],
                "phase": "intake",
                "status": "unchecked",
                "selectionState": "pending_confirmation",
                "updatedAt": timestamp,
            }
        prompt = confirmation_prompt(prompt_names)
        state = {
            "schemaVersion": 1,
            "status": "attention" if uncataloged_sources else "running",
            "entryContext": entry_context(),
            "sourceReadiness": {"gmail": gmail_readiness()},
            "progress": {
                "rawSourceInput": raw,
                "normalizedSourceList": source_ids,
                "uncatalogedSources": uncataloged_sources,
                "sourceConfirmation": {
                    "sourceIDs": source_ids,
                    "prompt": prompt,
                    "status": "pending",
                    "confirmedAt": None,
                    "updatedAt": timestamp,
                },
                "sourceRows": rows,
                "pendingQuestion": {
                    "prompt": prompt,
                    "status": "pending_source_confirmation",
                    "askedAt": timestamp,
                },
            },
            "updatedAt": timestamp,
        }
        save_json(state)
        print(json.dumps(summary(state, prompt), ensure_ascii=False, sort_keys=True))

    def parse_answer():
        answer = ""
        index = 0
        while index < len(args):
            token = args[index]
            if token == "--answer" and index + 1 < len(args):
                answer = args[index + 1].strip().lower()
                index += 2
            else:
                print("unknown or incomplete argument: " + token, file=sys.stderr)
                sys.exit(2)
        if answer not in {"yes", "y", "no", "n"}:
            print("--answer must be yes or no", file=sys.stderr)
            sys.exit(2)
        return answer

    def confirm():
        answer = parse_answer()
        state = load_json(state_path)
        migrate_source_state(state)
        progress = state.get("progress") if isinstance(state.get("progress"), dict) else {}
        source_ids = progress.get("normalizedSourceList") if isinstance(progress.get("normalizedSourceList"), list) else []
        timestamp = now()
        previous = progress.get("sourceConfirmation") if isinstance(progress.get("sourceConfirmation"), dict) else {}
        uncataloged_sources = progress.get("uncatalogedSources") if isinstance(progress.get("uncatalogedSources"), list) else progress.get("unsupportedInputs") if isinstance(progress.get("unsupportedInputs"), list) else []
        display_names = [source_display_name(source_id) for source_id in source_ids]
        for item in uncataloged_sources:
            if isinstance(item, dict):
                display_names.append(item.get("displayName") or item.get("rawValue") or item.get("normalizedValue"))
        prompt = previous.get("prompt") or confirmation_prompt([name for name in display_names if name])
        is_yes = answer in {"yes", "y"}
        progress["sourceConfirmation"] = {
            "sourceIDs": source_ids,
            "prompt": prompt,
            "status": "confirmed" if is_yes else "rejected",
            "confirmedAt": timestamp if is_yes else None,
            "updatedAt": timestamp,
        }
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        if is_yes:
            progress["pendingQuestion"] = None
            for source_id in source_ids:
                row = rows.get(source_id)
                if isinstance(row, dict):
                    row["selectionState"] = "confirmed"
                    row["updatedAt"] = timestamp
        else:
            progress["pendingQuestion"] = {
                "prompt": "Please restate the sources Zebra should understand for this source intake.",
                "status": "source_confirmation_rejected",
                "askedAt": timestamp,
            }
        progress["sourceRows"] = rows
        state["progress"] = progress
        uncataloged_sources = progress.get("uncatalogedSources") if isinstance(progress.get("uncatalogedSources"), list) else progress.get("unsupportedInputs") if isinstance(progress.get("unsupportedInputs"), list) else []
        if is_yes:
            state["status"] = "attention" if uncataloged_sources else "ready"
        else:
            state["status"] = "running"
        state["updatedAt"] = timestamp
        save_json(state)
        print(json.dumps(summary(state), ensure_ascii=False, sort_keys=True))

    def summary(state, prompt=None):
        progress = state.get("progress") if isinstance(state.get("progress"), dict) else {}
        uncataloged = progress.get("uncatalogedSources") if isinstance(progress.get("uncatalogedSources"), list) else progress.get("unsupportedInputs") if isinstance(progress.get("unsupportedInputs"), list) else []
        confirmation = progress.get("sourceConfirmation") if isinstance(progress.get("sourceConfirmation"), dict) else {}
        return {
            "ok": True,
            "statePath": str(state_path),
            "status": state.get("status"),
            "normalizedSourceList": progress.get("normalizedSourceList") or [],
            "uncatalogedSources": [item.get("normalizedValue") for item in uncataloged if isinstance(item, dict)],
            "sourceConfirmationStatus": confirmation.get("status"),
            "confirmationPrompt": prompt or confirmation.get("prompt"),
        }

    def status():
        state = load_json(state_path)
        if not state:
            state = default_state()
            save_json(state)
        elif migrate_source_state(state):
            save_json(state)
        payload = summary(state)
        payload["state"] = state
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))

    if command == "intake":
        intake()
    elif command == "confirm":
        confirm()
    elif command == "gmail":
        sys.exit(gmail_command())
    elif command == "status":
        status()
    else:
        print("unknown command: " + command, file=sys.stderr)
        sys.exit(2)
    PY
    """
}
