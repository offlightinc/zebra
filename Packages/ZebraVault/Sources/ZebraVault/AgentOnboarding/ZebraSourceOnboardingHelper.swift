import Foundation

struct ZebraSourceOnboardingHelper {
    struct LaunchContext {
        var helperPath: String
        var launchDirectory: String
        var runtimePromptDirectory: String
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
        let playbookDirectory = installSourcePlaybooks()
        let helperDirectory = helperURL.deletingLastPathComponent().path
        var commands = [
            "export ZEBRA_SOURCE_ONBOARDING_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_SETUP_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainOnboardingStateURL.path))",
            "export ZEBRA_GBRAIN_ADAPTER_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainAdapterOnboardingStateURL.path))",
            "export ZEBRA_SOURCE_ONBOARDING_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export ZEBRA_SOURCE_PLAYBOOK_DIR=\(ZebraAgentLaunchCommand.shellQuote(playbookDirectory.path))",
            "export PATH=\(ZebraAgentLaunchCommand.shellQuote(helperDirectory)):\"$PATH\"",
        ]
        if let selectedVaultPath = standardizedExistingDirectoryPath(selectedVaultPath) {
            commands.append("export ZEBRA_GBRAIN_WRITE_TARGET_PATH=\(ZebraAgentLaunchCommand.shellQuote(selectedVaultPath))")
        }
        return LaunchContext(
            helperPath: helperURL.path,
            launchDirectory: onboardingWorkDirectoryPath(),
            runtimePromptDirectory: runtimePromptDirectoryPath(),
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

    private func installSourcePlaybooks() -> URL {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-playbooks", isDirectory: true)
        let destination = directory.appendingPathComponent(
            "obsidian.direct-markdown.v1.md",
            isDirectory: false
        )
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if let resource = Bundle.module.url(
                forResource: "obsidian.direct-markdown.v1",
                withExtension: "md",
                subdirectory: "SourcePlaybooks"
            ) {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: resource, to: destination)
            } else if !fileManager.fileExists(atPath: destination.path) {
                try Self.fallbackObsidianPlaybook.write(
                    to: destination,
                    atomically: true,
                    encoding: .utf8
                )
            }
        } catch {
            try? Self.fallbackObsidianPlaybook.write(
                to: destination,
                atomically: true,
                encoding: .utf8
            )
        }
        return directory
    }

    private func onboardingWorkDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-onboarding-work", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self.standardizedPath(directory.path)
    }

    private func runtimePromptDirectoryPath() -> String {
        let directory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-runtime-prompts", isDirectory: true)
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

    private static let fallbackObsidianPlaybook = """
    ---
    id: obsidian.direct-markdown
    version: v1
    sourceID: obsidian
    initialStepID: discover_vault
    steps:
      - discover_vault
      - confirm_vault_if_needed
      - smoke_read
      - choose_ingest_scope
      - confirm_ingest_plan
      - ingest_markdown
      - verify_readback
      - complete
    ---

    # Obsidian Direct Markdown Source Onboarding

    ## Step: discover_vault

    Prefer an Obsidian app registry candidate from `~/Library/Application Support/obsidian/obsidian.json`. If exactly one valid candidate exists, continue to `smoke_read`; ask the user only when there are no candidates or multiple candidates. Do not use the GBrain write target path as the Obsidian vault path.

    ## Step: confirm_vault_if_needed

    Ask the user to choose among multiple candidates or provide a corrected Obsidian vault path, then run `zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`. Do not pass the GBrain write target path to `verify-vault`.

    ## Step: smoke_read

    Run `zebra-source-onboarding obsidian smoke-read`.

    ## Step: choose_ingest_scope

    Ask whether to ingest the whole vault, selected folders, a recent/sample subset, or skip Obsidian for now.

    ## Step: confirm_ingest_plan

    Summarize the ingest plan and run `zebra-source-onboarding obsidian confirm-plan --answer yes` only after approval.

    ## Step: ingest_markdown

    Run `zebra-source-onboarding obsidian ingest`.

    ## Step: verify_readback

    Run `zebra-source-onboarding obsidian verify-readback`.

    ## Step: complete

    Obsidian Source Onboarding is complete.
    """

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
    import textwrap
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
    gbrain_write_target_path = (
        os.environ.get("ZEBRA_GBRAIN_WRITE_TARGET_PATH")
        or os.environ.get("ZEBRA_SOURCE_SELECTED_VAULT")
        or ""
    )
    playbook_dir = Path(
        os.environ.get("ZEBRA_SOURCE_PLAYBOOK_DIR")
        or str(state_path.parent / "source-playbooks")
    ).expanduser()

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
        changed = False
        entry = value.get("entryContext") if isinstance(value.get("entryContext"), dict) else None
        if entry is not None:
            legacy_selected = entry.pop("selectedVaultPath", None)
            if legacy_selected and not entry.get("gbrainWriteTargetPath"):
                entry["gbrainWriteTargetPath"] = legacy_selected
            if legacy_selected is not None:
                changed = True
        progress = value.get("progress") if isinstance(value.get("progress"), dict) else None
        if progress is None:
            return changed
        legacy = progress.get("unsupportedInputs")
        if "uncatalogedSources" not in progress and isinstance(legacy, list):
            progress["uncatalogedSources"] = legacy
            changed = True
        if "unsupportedInputs" in progress:
            progress.pop("unsupportedInputs", None)
            changed = True
        return changed

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
                "executionOrder": None,
                "activeSourceID": None,
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
            "executionOrder": None,
            "activeSourceID": None,
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

    gmail_playbook = {
        "id": "gmail.clawvisor-gbrain",
        "version": "v1",
        "sourceID": "gmail",
        "initialStepID": "connect_clawvisor",
        "steps": ["connect_clawvisor", "verify_env", "verify_connection", "complete"],
    }

    obsidian_playbook_fallback = {
        "id": "obsidian.direct-markdown",
        "version": "v1",
        "sourceID": "obsidian",
        "initialStepID": "discover_vault",
        "steps": [
            "discover_vault",
            "confirm_vault_if_needed",
            "smoke_read",
            "choose_ingest_scope",
            "confirm_ingest_plan",
            "ingest_markdown",
            "verify_readback",
            "complete",
        ],
        "sections": {},
    }

    def parse_playbook_markdown(path):
        result = {
            "id": "",
            "version": "",
            "sourceID": "",
            "initialStepID": "",
            "steps": [],
            "sections": {},
        }
        try:
            text = path.read_text(encoding="utf-8")
        except Exception:
            return dict(obsidian_playbook_fallback)
        body = text
        if text.startswith("---"):
            marker = text.find("\\n---", 3)
            if marker >= 0:
                frontmatter = text[3:marker].strip().splitlines()
                body = text[marker + 4:]
                current_list = None
                for raw in frontmatter:
                    if not raw.strip():
                        continue
                    if raw.startswith("  - ") and current_list == "steps":
                        result["steps"].append(raw[4:].strip())
                        continue
                    current_list = None
                    if ":" not in raw:
                        continue
                    key, value = raw.split(":", 1)
                    key = key.strip()
                    value = value.strip()
                    if key == "steps":
                        current_list = "steps"
                    elif key in result and isinstance(result[key], str):
                        result[key] = value
        current_step = None
        buffer = []
        for line in body.splitlines():
            if line.startswith("## Step: "):
                if current_step:
                    result["sections"][current_step] = "\\n".join(buffer).strip()
                current_step = line[len("## Step: "):].strip()
                buffer = []
            elif current_step:
                buffer.append(line)
        if current_step:
            result["sections"][current_step] = "\\n".join(buffer).strip()
        fallback = obsidian_playbook_fallback
        for key in ("id", "version", "sourceID", "initialStepID"):
            if not result.get(key):
                result[key] = fallback[key]
        if not result.get("steps"):
            result["steps"] = list(fallback["steps"])
        return result

    def obsidian_playbook():
        return parse_playbook_markdown(playbook_dir / "obsidian.direct-markdown.v1.md")

    def source_run_state_path(source_id):
        directory = state_path.parent / "source-run-state"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / (prompt_file_safe_name(source_id) + ".json")

    def load_source_run_state(source_id):
        path = source_run_state_path(source_id)
        value = load_json(path)
        return value if isinstance(value, dict) else {}

    def save_source_run_state(source_id, value):
        path = source_run_state_path(source_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, path)
        return str(path)

    def prompt_file_safe_name(value):
        safe = "".join(
            character if character.isalnum() or character in "-_" else "-"
            for character in str(value or "source")
        ).strip("-_")
        return safe[:96] or "source"

    def write_source_next_prompt_file(source_id, step_id, prompt):
        directory = state_path.parent / "source-step-prompts" / prompt_file_safe_name(source_id)
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / (prompt_file_safe_name(step_id) + ".md")
        path.write_text(prompt.rstrip() + "\\n", encoding="utf-8")
        try:
            os.chmod(path, 0o600)
        except Exception:
            pass
        return str(path)

    def source_row_for(source_id, timestamp):
        definition = supported.get(source_id) or {}
        return {
            "id": source_id,
            "displayName": definition.get("displayName") or source_id,
            "type": definition.get("type"),
            "phase": "intake",
            "status": "unchecked",
            "selectionState": "confirmed",
            "updatedAt": timestamp,
        }

    def ensure_progress(state):
        progress = state.get("progress")
        if not isinstance(progress, dict):
            progress = {}
        progress.setdefault("rawSourceInput", None)
        progress.setdefault("normalizedSourceList", [])
        progress.setdefault("uncatalogedSources", [])
        progress.setdefault("sourceConfirmation", None)
        progress.setdefault("executionOrder", None)
        progress.setdefault("activeSourceID", None)
        progress.setdefault("sourceRows", {})
        progress.setdefault("pendingQuestion", None)
        state["progress"] = progress
        return progress

    def ensure_execution_order(progress):
        order = progress.get("executionOrder")
        if not isinstance(order, list) or not order:
            normalized = progress.get("normalizedSourceList")
            order = [item for item in normalized if isinstance(item, str)] if isinstance(normalized, list) else []
            progress["executionOrder"] = order
        return order

    def is_terminal_source_row(row):
        return isinstance(row, dict) and row.get("status") in {"checked", "skipped"}

    def first_unfinished_source_id(progress):
        order = ensure_execution_order(progress)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        active = progress.get("activeSourceID")
        if isinstance(active, str) and active:
            row = rows.get(active)
            if not is_terminal_source_row(row):
                return active
        for source_id in order:
            row = rows.get(source_id)
            if not is_terminal_source_row(row):
                return source_id
        return None

    def all_execution_sources_finished(progress):
        order = ensure_execution_order(progress)
        if not order:
            return False
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        return all(is_terminal_source_row(rows.get(source_id)) for source_id in order)

    def source_completion_status(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        has_attention_row = any(
            isinstance(row, dict) and row.get("status") == "attention"
            for row in rows.values()
        )
        uncataloged = progress.get("uncatalogedSources") if isinstance(progress.get("uncatalogedSources"), list) else []
        if has_attention_row or uncataloged:
            return "attention"
        if all_execution_sources_finished(progress):
            return "completed"
        return "running"

    def gmail_step_prompt(step_id, state, row):
        env_path = str(home / ".gbrain/.env")
        if step_id == "connect_clawvisor":
            return textwrap.dedent('''
            Zebra Source Onboarding: Gmail is the active source.

            Work only the Gmail/Clawvisor step `connect_clawvisor`. Do not start Notion, Obsidian, iMessage, or any other source runner in this session.

            Your first response must use the existing Zebra Gmail onboarding structure. Start by giving the user this Clawvisor connection instruction, with the numbered steps preserved:

            Zebra는 Clawvisor를 통해 Gmail, Calendar, Contacts 접근 권한을 안전하게 연결합니다.
            아래 순서대로 진행하세요.

            1. https://app.clawvisor.com/register 을 열고 Google로 sign up 또는 sign in 하세요.
            2. Clawvisor에서 왼쪽 sidebar의 Agents를 열고 GBrain을 선택한 뒤 Create GBrain agent를 클릭하세요.
            3. Google service authorization과 task approval을 이어서 진행하세요.
            4. 마지막 Env vars step에 도달하면 세 줄의 export env lines를 이 터미널에 그대로 붙여넣으세요.

            Those three canonical env vars are:

                export CLAWVISOR_URL="https://app.clawvisor.com"
                export CLAWVISOR_AGENT_TOKEN="cvis_..."
                export CLAWVISOR_TASK_ID="..."

            When the user pastes the env lines:
              1. Parse exactly `CLAWVISOR_URL`, `CLAWVISOR_AGENT_TOKEN`, and `CLAWVISOR_TASK_ID`. Ignore old Zebra-only keys if they appear.
              2. Upsert only those three canonical keys into Zebra's env file while preserving unrelated lines, then restrict the file permissions.
              3. Run `zebra-source-onboarding gmail verify-env`.
              4. Continue from the `nextPrompt` printed by that command.

            Do not ask for a Gmail account. Do not ask for a separate Gmail task id. Do not show the user any local file path, chmod instruction, or file-editing procedure. Persisting the env values is your job, not the user's. Do not search the web for Clawvisor API docs. The helper CLI is the only state write path for Gmail source progress.
            ''').strip()
        if step_id == "verify_env":
            return textwrap.dedent(f'''
            Zebra Source Onboarding: Gmail env verification needs attention.

            Work only the Gmail/Clawvisor step `verify_env`. Do not start other source runners.

            Zebra could not verify the required Clawvisor env keys in `{env_path}`.

            Ask the user to revisit Clawvisor's Connect an Agent -> GBrain flow and paste the three env lines again. Then upsert only `CLAWVISOR_URL`, `CLAWVISOR_AGENT_TOKEN`, and `CLAWVISOR_TASK_ID`, rerun `zebra-source-onboarding gmail verify-env`, and continue from the returned `nextPrompt`.
            ''').strip()
        if step_id == "verify_connection":
            return textwrap.dedent('''
            Zebra Source Onboarding: Gmail env is present. Verify the Clawvisor Gmail connection now.

            Work only the Gmail/Clawvisor step `verify_connection`. Do not start other source runners.

            Run `zebra-source-onboarding gmail verify-connection`.

            That helper performs the Clawvisor task lookup and Gmail gateway smoke check. Do not hand-write curl calls and do not search for alternate Clawvisor API docs. If it succeeds, continue from its `nextPrompt`. If it fails, report the exact failing stage from stdout and ask the user to revisit the matching Clawvisor step.
            ''').strip()
        if step_id == "complete":
            return textwrap.dedent('''
            Zebra Source Onboarding: Gmail is complete.

            Do not run more Gmail verification commands. Briefly tell the user that Gmail is connected for Zebra Source Onboarding, then stop unless Zebra has printed a next source prompt.
            ''').strip()
        return textwrap.dedent('''
        Zebra Source Onboarding: Gmail needs attention.

        Work only the current Gmail/Clawvisor repair step. Do not start other source runners. Use the helper stdout to identify the failing stage, repair that stage, and rerun the matching `zebra-source-onboarding gmail ...` command.
        ''').strip()

    def obsidian_step_prompt(step_id, state, row):
        playbook = obsidian_playbook()
        run_state = load_source_run_state("obsidian")
        section = playbook.get("sections", {}).get(step_id, "")
        if not section:
            section = "Follow the current Obsidian playbook step and continue only through the zebra-source-onboarding helper CLI."
        unreadable_roots = run_state.get("unreadableCandidateRoots") if isinstance(run_state.get("unreadableCandidateRoots"), list) else []
        if step_id == "discover_vault" and unreadable_roots:
            lines = []
            for item in unreadable_roots:
                if not isinstance(item, dict):
                    continue
                path = item.get("path") or "unknown"
                reason = item.get("reason") or "unreadable"
                message = item.get("message") or ""
                detail = " - `" + str(path) + "` (" + str(reason) + ")"
                if message:
                    detail = detail + ": " + str(message)
                lines.append(detail)
            if lines:
                section = section + "\\n\\n" + "Zebra could not inspect these automatic discovery roots. Tell the user that automatic discovery may be incomplete and ask for the exact Obsidian vault path if needed:\\n" + "\\n".join(lines)
        if step_id == "confirm_vault_if_needed":
            candidate = run_state.get("candidateVaultPath")
            candidates = run_state.get("candidateVaultPaths") if isinstance(run_state.get("candidateVaultPaths"), list) else []
            if candidate:
                method = run_state.get("discoveryMethod") or "automatic_discovery"
                section = section + "\\n\\n" + textwrap.dedent(f'''
                Zebra found this Obsidian-like vault candidate from `{method}` because it contains `.obsidian/`:

                `{candidate}`

                Ask the user to confirm whether this is the Obsidian vault to use. If yes, run:

                ```bash
                zebra-source-onboarding obsidian verify-vault --path "{candidate}"
                ```

                If no, ask for the correct vault path and run `zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`.
                ''').strip()
            elif candidates:
                method = run_state.get("discoveryMethod") or "automatic_discovery"
                section = section + "\\n\\n" + "Zebra found multiple `.obsidian/` vault candidates from `" + str(method) + "`. Ask the user which one to use, then run `zebra-source-onboarding obsidian verify-vault --path \"<vault-path>\"`. Candidates:\\n\\n" + "\\n".join("- `" + str(item) + "`" for item in candidates)
        if step_id == "confirm_ingest_plan":
            section = section + "\\n\\n" + obsidian_ingest_plan_summary(run_state)
        vault = run_state.get("selectedVaultPath") or run_state.get("candidateVaultPath") or "not selected"
        scope = run_state.get("scope") or "not selected"
        estimated = run_state.get("estimatedFileCount")
        if estimated is None:
            estimated = "unknown"
        artifact = run_state.get("artifactPath") or "not created"
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Obsidian is the active source.

        Playbook: {playbook.get("id", "obsidian.direct-markdown")} {playbook.get("version", "v1")}
        Current step: `{step_id}`
        Current vault path: `{vault}`
        Current ingest scope: `{scope}`
        Approximate file count: `{estimated}`
        Current ingest artifact: `{artifact}`

        Boundary rules:
        - Work only this Obsidian step. Do not start Notion, iMessage, Gmail, or another source unless the helper prints that source as the next active source.
        - Use direct Markdown filesystem access. Do not require Obsidian CLI or Clawvisor for Obsidian.
        - Do not use the GBrain write target path or `gbrainTargetPath` as the Obsidian source vault. If the user wants Obsidian, use an automatic `.obsidian/` candidate from this prompt or ask for the actual Obsidian vault path.
        - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
        - Do not store Markdown bodies, large file lists, or prompt bodies in Source Onboarding state.
        - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

        Playbook step instructions:

        {section}
        ''').strip()

    def source_next_prompt_payload(state, source_id, step_id):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else {}
        if source_id == "gmail":
            playbook = gmail_playbook
            prompt = gmail_step_prompt(step_id, state, row)
        elif source_id == "obsidian":
            playbook = obsidian_playbook()
            prompt = obsidian_step_prompt(step_id, state, row)
        else:
            return {}
        path = write_source_next_prompt_file(source_id, step_id, prompt)
        return {
            "nextSourceID": source_id,
            "nextPlaybookID": playbook["id"],
            "nextPlaybookVersion": playbook["version"],
            "nextPlaybookStepID": step_id,
            "nextPrompt": prompt,
            "nextPromptPath": path,
        }

    def set_gmail_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("gmail") if isinstance(rows.get("gmail"), dict) else source_row_for("gmail", timestamp)
        row["status"] = row_status
        row["phase"] = phase
        row["selectionState"] = "confirmed"
        row["playbookID"] = gmail_playbook["id"]
        row["playbookVersion"] = gmail_playbook["version"]
        row["playbookStepID"] = step_id
        row["updatedAt"] = timestamp
        if attention_reason:
            row["attentionReason"] = attention_reason
        else:
            row.pop("attentionReason", None)
        if result_summary:
            row["resultSummary"] = result_summary
        rows["gmail"] = row
        progress["sourceRows"] = rows
        if "gmail" not in ensure_execution_order(progress):
            progress["executionOrder"].append("gmail")
        if row_status in {"checked", "skipped"}:
            progress["activeSourceID"] = first_unfinished_source_id(progress)
        else:
            progress["activeSourceID"] = "gmail"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def should_update_gmail_runner(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        if progress.get("activeSourceID") == "gmail":
            return True
        if "gmail" not in ensure_execution_order(progress):
            return False
        return isinstance(rows.get("gmail"), dict) and rows["gmail"].get("playbookID") == gmail_playbook["id"]

    def set_obsidian_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("obsidian") if isinstance(rows.get("obsidian"), dict) else source_row_for("obsidian", timestamp)
        playbook = obsidian_playbook()
        row["status"] = row_status
        row["phase"] = phase
        row["selectionState"] = "confirmed"
        row["playbookID"] = playbook["id"]
        row["playbookVersion"] = playbook["version"]
        row["playbookStepID"] = step_id
        row["updatedAt"] = timestamp
        if attention_reason:
            row["attentionReason"] = attention_reason
        else:
            row.pop("attentionReason", None)
        if result_summary:
            row["resultSummary"] = result_summary
        if run_state_path:
            row["runStatePath"] = run_state_path
        rows["obsidian"] = row
        progress["sourceRows"] = rows
        if "obsidian" not in ensure_execution_order(progress):
            progress["executionOrder"].append("obsidian")
        if row_status in {"checked", "skipped"}:
            progress["activeSourceID"] = first_unfinished_source_id(progress)
        else:
            progress["activeSourceID"] = "obsidian"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def should_update_obsidian_runner(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        if progress.get("activeSourceID") == "obsidian":
            return True
        if "obsidian" not in ensure_execution_order(progress):
            return False
        row = rows.get("obsidian")
        return isinstance(row, dict) and row.get("playbookID") == obsidian_playbook()["id"]

    def markdown_files_for_vault(vault_path, folders=None, limit=None):
        vault = Path(vault_path).expanduser()
        if not vault.is_dir():
            return []
        roots = []
        if folders:
            for folder in folders:
                candidate = (vault / folder).resolve(strict=False)
                try:
                    candidate.relative_to(vault.resolve(strict=False))
                    if candidate.exists():
                        roots.append(candidate)
                except Exception:
                    continue
        if not roots:
            roots = [vault]
        files = []
        for root in roots:
            for current, dirnames, filenames in os.walk(root):
                dirnames[:] = [
                    name for name in dirnames
                    if not name.startswith(".") and name not in {".obsidian", "__MACOSX"}
                ]
                for filename in filenames:
                    if not filename.lower().endswith(".md"):
                        continue
                    path = Path(current) / filename
                    try:
                        path.relative_to(vault)
                    except Exception:
                        continue
                    files.append(path)
                    if limit and len(files) >= limit:
                        return files
        return files

    def vault_validation(value):
        if not value:
            return {"ok": False, "reason": "vault_path_required", "path": ""}
        path = Path(value).expanduser()
        if not path.exists():
            return {"ok": False, "reason": "invalid_vault_path", "path": canonical_path(path)}
        if not path.is_dir():
            return {"ok": False, "reason": "vault_path_not_directory", "path": canonical_path(path)}
        canonical = canonical_path(path)
        broad_roots = {canonical_path(home), canonical_path(home / "Desktop"), canonical_path(home / "Documents")}
        if canonical in broad_roots:
            return {"ok": False, "reason": "vault_path_too_broad", "path": canonical}
        markdown_files = markdown_files_for_vault(canonical, limit=1)
        marker = (Path(canonical) / ".obsidian").is_dir()
        if not marker and not markdown_files:
            return {"ok": False, "reason": "no_markdown_files", "path": canonical}
        count = len(markdown_files_for_vault(canonical))
        return {
            "ok": True,
            "path": canonical,
            "hasObsidianMarker": marker,
            "estimatedFileCount": count,
        }

    def discovery_error_record(path, error):
        reason = "permission_denied" if isinstance(error, PermissionError) else "unreadable"
        return {
            "path": str(path),
            "reason": reason,
            "message": str(error),
        }

    def deduped_paths(paths):
        deduped = []
        seen = set()
        for path in paths:
            canonical = canonical_path(path)
            if canonical in seen:
                continue
            seen.add(canonical)
            deduped.append(path)
        return deduped

    def obsidian_registry_candidate_paths():
        paths = []
        diagnostics = []
        registry = home / "Library/Application Support/obsidian/obsidian.json"
        try:
            data = json.loads(registry.read_text(encoding="utf-8"))
            vaults = data.get("vaults") if isinstance(data, dict) else {}
            if isinstance(vaults, dict):
                for item in vaults.values():
                    if not isinstance(item, dict):
                        continue
                    raw_path = item.get("path")
                    if isinstance(raw_path, str) and raw_path:
                        paths.append(Path(raw_path).expanduser())
        except FileNotFoundError:
            pass
        except Exception as error:
            diagnostics.append(discovery_error_record(registry, error))
        return deduped_paths(paths), diagnostics

    def fallback_obsidian_candidate_paths():
        paths = []
        diagnostics = []
        icloud_root = home / "Library/Mobile Documents/iCloud~md~obsidian/Documents"
        try:
            if icloud_root.exists() and icloud_root.is_dir():
                paths.extend(sorted(child for child in icloud_root.iterdir() if child.is_dir()))
        except Exception as error:
            diagnostics.append(discovery_error_record(icloud_root, error))
        cloud_storage = home / "Library/CloudStorage"
        try:
            if cloud_storage.exists() and cloud_storage.is_dir():
                for pattern in ("OneDrive*", "GoogleDrive*"):
                    paths.extend(sorted(child for child in cloud_storage.glob(pattern) if child.is_dir()))
        except Exception as error:
            diagnostics.append(discovery_error_record(cloud_storage, error))
        paths.extend([
            home / "Dropbox",
            home / "Documents/Obsidian",
            home / "Obsidian",
        ])
        return deduped_paths(paths), diagnostics

    def discover_obsidian_marker_candidates():
        candidates = {}
        diagnostics = []
        broad_roots = {
            canonical_path(home),
            canonical_path(home / "Desktop"),
            canonical_path(home / "Documents"),
            canonical_path(home / "Library/Mobile Documents"),
            canonical_path(home / "Library/Mobile Documents/iCloud~md~obsidian/Documents"),
        }
        registry_paths, registry_diagnostics = obsidian_registry_candidate_paths()
        diagnostics.extend(registry_diagnostics)
        for discovery_method, paths in [("obsidian_registry", registry_paths)]:
            for path in paths:
                try:
                    if not path.is_dir() or not (path / ".obsidian").is_dir():
                        continue
                except Exception as error:
                    diagnostics.append(discovery_error_record(path, error))
                    continue
                vault = canonical_path(path)
                if vault in broad_roots:
                    continue
                validation = vault_validation(vault)
                if validation.get("ok") and validation.get("hasObsidianMarker"):
                    validation["discoveryMethod"] = discovery_method
                    candidates[vault] = validation
        if not candidates:
            fallback_paths, fallback_diagnostics = fallback_obsidian_candidate_paths()
            diagnostics.extend(fallback_diagnostics)
            for path in fallback_paths:
                try:
                    if not path.is_dir() or not (path / ".obsidian").is_dir():
                        continue
                except Exception as error:
                    diagnostics.append(discovery_error_record(path, error))
                    continue
                vault = canonical_path(path)
                if vault in broad_roots:
                    continue
                validation = vault_validation(vault)
                if validation.get("ok") and validation.get("hasObsidianMarker"):
                    validation["discoveryMethod"] = "bounded_fallback_path"
                    candidates[vault] = validation
        return list(candidates.values()), diagnostics

    def duration_class(count):
        try:
            count = int(count)
        except Exception:
            return "unknown"
        if count <= 25:
            return "short"
        if count <= 250:
            return "medium"
        return "long"

    def obsidian_ingest_plan_summary(run_state):
        vault = run_state.get("selectedVaultPath") or "not selected"
        scope = run_state.get("scope") or "not selected"
        folders = run_state.get("folders") if isinstance(run_state.get("folders"), list) else []
        count = run_state.get("estimatedFileCount")
        count_text = str(count) if count is not None else "unknown"
        duration = run_state.get("durationClass") or duration_class(count)
        scope_detail = scope
        if scope == "folders":
            scope_detail = "folders: " + (", ".join(folders) if folders else "none")
        if scope == "sample":
            scope_detail = "recent/sample subset: up to 5 Markdown files"
        return textwrap.dedent(f'''
        Resolved Obsidian ingest plan:
        - Vault path: `{vault}`
        - Selected scope: `{scope_detail}`
        - Approximate Markdown file count: `{count_text}`
        - Excluded paths/policies: `.obsidian/`, hidden directories, `__MACOSX`, non-Markdown files, and paths outside the selected vault.
        - Expected duration class: `{duration}`
        - Ingest mode: direct Markdown filesystem ingest into a Zebra source artifact.
        - Verification plan: read back the generated Obsidian source artifact and require `source: obsidian` plus `playbook: obsidian.direct-markdown.v1`.

        Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding obsidian confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding obsidian confirm-plan --answer no`.
        ''').strip()

    def obsidian_artifact_path(state=None):
        target = None
        if isinstance(state, dict):
            target = state.get("entryContext", {}).get("gbrainTargetPath")
        if target and Path(target).is_dir():
            directory = Path(target) / "sources"
        else:
            directory = state_path.parent / "source-ingest-artifacts"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / "obsidian-direct-markdown.md"

    def gbrain_target_paths(state):
        paths = set()
        entry = state.get("entryContext") if isinstance(state.get("entryContext"), dict) else {}
        for key in ("gbrainWriteTargetPath", "gbrainTargetPath", "selectedVaultPath"):
            path = existing_directory(entry.get(key) or "")
            if path:
                paths.add(path)
        env_path = existing_directory(gbrain_write_target_path)
        if env_path:
            paths.add(env_path)
        _, resolved_target_path, _ = resolve_gbrain_target()
        if resolved_target_path:
            paths.add(resolved_target_path)
        return paths

    def is_gbrain_target_path(state, value):
        path = existing_directory(value)
        return bool(path and path in gbrain_target_paths(state))

    def start_obsidian_from_next(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("obsidian") if isinstance(rows.get("obsidian"), dict) else {}
        playbook = obsidian_playbook()
        if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
            step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "obsidian", step_id))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        discovered, discovery_diagnostics = discover_obsidian_marker_candidates()
        if len(discovered) == 1:
            validation = discovered[0]
            run_state = load_source_run_state("obsidian")
            run_state.update({
                "selectedVaultPath": validation["path"],
                "hasObsidianMarker": validation.get("hasObsidianMarker"),
                "estimatedFileCount": validation.get("estimatedFileCount"),
                "discoveryMethod": validation.get("discoveryMethod") or "single_obsidian_marker_candidate",
                "updatedAt": now(),
            })
            if discovery_diagnostics:
                run_state["unreadableCandidateRoots"] = discovery_diagnostics
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "running",
                "smoke",
                "smoke_read",
                run_state_path=run_path,
                result_summary="Single Obsidian vault candidate selected from " + str(validation.get("discoveryMethod") or "automatic_discovery") + " with " + str(validation.get("estimatedFileCount")) + " Markdown files.",
            )
            save_json(state)
            payload = {"ok": True, "path": validation["path"], "estimatedFileCount": validation.get("estimatedFileCount")}
            payload.update(source_next_prompt_payload(state, "obsidian", "smoke_read"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if len(discovered) > 1:
            run_state = load_source_run_state("obsidian")
            run_state.update({
                "candidateVaultPaths": [item.get("path") for item in discovered],
                "discoveryMethod": discovered[0].get("discoveryMethod") or "multiple_obsidian_marker_candidates",
                "updatedAt": now(),
            })
            if discovery_diagnostics:
                run_state["unreadableCandidateRoots"] = discovery_diagnostics
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "attention",
                "preflight",
                "confirm_vault_if_needed",
                attention_reason="multiple_obsidian_vault_candidates",
                run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "multiple_obsidian_vault_candidates"
            payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if discovery_diagnostics:
            run_state = load_source_run_state("obsidian")
            run_state.update({
                "unreadableCandidateRoots": discovery_diagnostics,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "attention",
                "preflight",
                "discover_vault",
                attention_reason="obsidian_candidate_discovery_unreadable",
                run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "obsidian_candidate_discovery_unreadable"
            payload.update(source_next_prompt_payload(state, "obsidian", "discover_vault"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        state = set_obsidian_row_state(state, "running", "preflight", "discover_vault")
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "obsidian", "discover_vault"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def start_next():
        state = load_or_create_state()
        progress = ensure_progress(state)
        confirmation = progress.get("sourceConfirmation") if isinstance(progress.get("sourceConfirmation"), dict) else {}
        if confirmation.get("status") != "confirmed":
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "source_confirmation_required"
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        source_id = first_unfinished_source_id(progress)
        if not source_id:
            state["status"] = source_completion_status(state)
            state["updatedAt"] = now()
            save_json(state)
            payload = summary(state)
            payload["complete"] = state["status"] == "completed"
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if source_id == "obsidian":
            return start_obsidian_from_next(state)
        if source_id != "gmail":
            payload = summary(state)
            payload["ok"] = False
            payload["nextSourceID"] = source_id
            payload["reason"] = "source_runner_not_implemented"
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("gmail") if isinstance(rows.get("gmail"), dict) else {}
        if row.get("playbookID") == gmail_playbook["id"] and row.get("status") in {"running", "attention"}:
            step_id = row.get("playbookStepID") if row.get("playbookStepID") in gmail_playbook["steps"] else gmail_playbook["initialStepID"]
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "gmail", step_id))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        timestamp = now()
        state = set_gmail_row_state(state, "running", "connect", "connect_clawvisor", timestamp=timestamp)
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "gmail", "connect_clawvisor"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def resolve_gbrain_target():
        gbrain = load_json(gbrain_state_path)
        receipt = gbrain.get("receipt") or {}
        targets = receipt.get("targets") or {}
        selected = existing_directory(gbrain_write_target_path)
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
            "gbrainWriteTargetPath": existing_directory(gbrain_write_target_path) or None,
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
            state = update_gmail_readiness(
                "missing_env",
                env_path,
                reasons=["missing:" + ",".join(missing)],
            )
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "connect",
                    "verify_env",
                    attention_reason="missing:" + ",".join(missing),
                )
                save_json(state)
                payload = {"ok": False, "missing": missing, "path": str(env_path)}
                payload.update(source_next_prompt_payload(state, "gmail", "verify_env"))
                print(json.dumps(payload, sort_keys=True))
                return 1
        else:
            state = update_gmail_readiness(
                "unverified",
                env_path,
                connection_path="clawvisor_env_available",
                reasons=["email_connection_unverified"],
            )
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "running",
                    "smoke",
                    "verify_connection",
                )
                save_json(state)
                payload = {"ok": True, "missing": missing, "path": str(env_path)}
                payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
                print(json.dumps(payload, sort_keys=True))
                return 0
        print(json.dumps({"ok": not missing, "missing": missing, "path": str(env_path)}, sort_keys=True))
        return 0 if not missing else 1

    def gmail_verify_connection():
        env_path, env = persisted_env()
        required = ["CLAWVISOR_URL", "CLAWVISOR_AGENT_TOKEN", "CLAWVISOR_TASK_ID"]
        missing = [key for key in required if not env.get(key, "").strip()]
        if missing:
            state = update_gmail_readiness(
                "missing_env",
                env_path,
                reasons=["missing:" + ",".join(missing)],
            )
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "connect",
                    "verify_env",
                    attention_reason="missing:" + ",".join(missing),
                )
                save_json(state)
                payload = {"ok": False, "stage": "env", "missing": missing, "path": str(env_path)}
                payload.update(source_next_prompt_payload(state, "gmail", "verify_env"))
                print(json.dumps(payload, sort_keys=True))
                return 1
            print(json.dumps({"ok": False, "stage": "env", "missing": missing, "path": str(env_path)}, sort_keys=True))
            return 1
        base_url = env["CLAWVISOR_URL"].strip().rstrip("/")
        token = env["CLAWVISOR_AGENT_TOKEN"].strip()
        task_id = env["CLAWVISOR_TASK_ID"].strip()
        task_url = base_url + "/api/tasks/" + urllib.parse.quote(task_id, safe="")
        status, task = request_json("GET", task_url, token)
        if status == 0:
            reason = "task_request_failed:" + str(task.get("error") if isinstance(task, dict) else "request_failed")
            state = update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id,
                repair_kind="task_request_failed",
                reasons=[reason],
            )
            payload = {"ok": False, "stage": "task", "status": status, "response": task}
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "smoke",
                    "verify_connection",
                    attention_reason=reason,
                )
                save_json(state)
                payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
            print(json.dumps(payload, sort_keys=True))
            return 1
        if status < 200 or status >= 300:
            state = update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id,
                repair_kind="task_lookup_failed",
                reasons=["task_http_status:" + str(status)],
            )
            payload = {"ok": False, "stage": "task", "status": status, "response": task}
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "smoke",
                    "verify_connection",
                    attention_reason="task_http_status:" + str(status),
                )
                save_json(state)
                payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
            print(json.dumps(payload, sort_keys=True))
            return 1
        service = gmail_service_from_task(task)
        if not service:
            state = update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id,
                repair_kind="gmail_service_missing",
                reasons=["no_authorized_google_gmail_service"],
            )
            payload = {"ok": False, "stage": "task", "reason": "no authorized google.gmail service"}
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "smoke",
                    "verify_connection",
                    attention_reason="no_authorized_google_gmail_service",
                )
                save_json(state)
                payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
            print(json.dumps(payload, sort_keys=True))
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
            state = update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id + "#" + service,
                repair_kind="gateway_request_failed",
                reasons=[reason],
            )
            payload = {"ok": False, "stage": "gateway", "status": status, "service": service, "response": gateway}
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "smoke",
                    "verify_connection",
                    attention_reason=reason,
                )
                save_json(state)
                payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
            print(json.dumps(payload, sort_keys=True))
            return 1
        if status < 200 or status >= 300:
            state = update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id + "#" + service,
                repair_kind="gateway_failed",
                reasons=["gateway_http_status:" + str(status)],
            )
            payload = {"ok": False, "stage": "gateway", "status": status, "service": service, "response": gateway}
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "smoke",
                    "verify_connection",
                    attention_reason="gateway_http_status:" + str(status),
                )
                save_json(state)
                payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
            print(json.dumps(payload, sort_keys=True))
            return 1
        gateway_status = gateway.get("status") if isinstance(gateway, dict) else None
        if gateway_status and gateway_status not in ("executed", "approved", "completed", "success"):
            state = update_gmail_readiness(
                "attention",
                env_path,
                connection_path="clawvisor_task:" + task_id + "#" + service,
                repair_kind="gateway_pending_or_rejected",
                reasons=["gateway_status:" + str(gateway_status)],
            )
            payload = {"ok": False, "stage": "gateway", "status": gateway_status, "service": service, "response": gateway}
            if should_update_gmail_runner(state):
                state = set_gmail_row_state(
                    state,
                    "attention",
                    "smoke",
                    "verify_connection",
                    attention_reason="gateway_status:" + str(gateway_status),
                )
                save_json(state)
                payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
            print(json.dumps(payload, sort_keys=True))
            return 1
        state = update_gmail_readiness(
            "ready",
            env_path,
            connection_path="clawvisor_task:" + task_id + "#" + service,
            reasons=[],
        )
        payload = {"ok": True, "service": service, "taskId": task_id}
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "checked",
                "complete",
                "complete",
                result_summary="Gmail Clawvisor gateway smoke check passed for service " + service,
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "complete"))
        print(json.dumps(payload, sort_keys=True))
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

    def parse_flag_value(flag):
        values = []
        index = 0
        while index < len(args):
            if args[index] == flag and index + 1 < len(args):
                values.append(args[index + 1])
                index += 2
            else:
                index += 1
        return values

    def single_flag_value(flag):
        values = parse_flag_value(flag)
        return values[-1] if values else ""

    def obsidian_verify_vault():
        path = single_flag_value("--path")
        state = load_or_create_state()
        if is_gbrain_target_path(state, path):
            run_state = load_source_run_state("obsidian")
            run_state.update({
                "rejectedCandidateReason": "gbrain_target_is_not_obsidian_source_vault",
                "updatedAt": now(),
            })
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "attention",
                "preflight",
                "confirm_vault_if_needed",
                attention_reason="gbrain_target_is_not_obsidian_source_vault",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "gbrain_target_is_not_obsidian_source_vault"}
            payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        validation = vault_validation(path)
        if validation.get("ok"):
            run_state = load_source_run_state("obsidian")
            run_state.update({
                "selectedVaultPath": validation["path"],
                "hasObsidianMarker": validation.get("hasObsidianMarker"),
                "estimatedFileCount": validation.get("estimatedFileCount"),
                "updatedAt": now(),
            })
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "running",
                "smoke",
                "smoke_read",
                run_state_path=run_path,
                result_summary="Obsidian vault path validated with " + str(validation.get("estimatedFileCount")) + " Markdown files.",
            )
            save_json(state)
            payload = {"ok": True, "path": validation["path"], "estimatedFileCount": validation.get("estimatedFileCount")}
            payload.update(source_next_prompt_payload(state, "obsidian", "smoke_read"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        run_state = load_source_run_state("obsidian")
        run_state.update({"candidateVaultPath": path, "updatedAt": now()})
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "attention",
            "preflight",
            "confirm_vault_if_needed",
            attention_reason=validation.get("reason") or "invalid_vault_path",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "path": validation.get("path") or path, "reason": validation.get("reason")}
        payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1

    def obsidian_smoke_read():
        state = load_or_create_state()
        run_state = load_source_run_state("obsidian")
        vault = run_state.get("selectedVaultPath")
        validation = vault_validation(vault)
        if not validation.get("ok"):
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "attention",
                "preflight",
                "confirm_vault_if_needed",
                attention_reason=validation.get("reason") or "vault_path_required",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": validation.get("reason") or "vault_path_required"}
            payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        files = markdown_files_for_vault(vault, limit=5)
        readable = None
        for path in files:
            try:
                _ = path.read_text(encoding="utf-8", errors="replace")[:2048]
                readable = path
                break
            except Exception:
                continue
        if not readable:
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "attention",
                "smoke",
                "smoke_read",
                attention_reason="markdown_read_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "markdown_read_failed"}
            payload.update(source_next_prompt_payload(state, "obsidian", "smoke_read"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        relative = str(readable.relative_to(Path(vault)))
        run_state.update({
            "smokeReadStatus": "passed",
            "smokeReadSamplePath": relative,
            "estimatedFileCount": validation.get("estimatedFileCount"),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "running",
            "ingest",
            "choose_ingest_scope",
            run_state_path=run_path,
            result_summary="Obsidian smoke read passed for " + relative,
        )
        save_json(state)
        payload = {"ok": True, "samplePath": relative, "estimatedFileCount": validation.get("estimatedFileCount")}
        payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def obsidian_choose_scope():
        scope = single_flag_value("--scope")
        folders = parse_flag_value("--folder")
        if scope not in {"whole", "folders", "sample", "skip"}:
            print("--scope must be whole, folders, sample, or skip", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("obsidian")
        vault = run_state.get("selectedVaultPath")
        if scope == "skip":
            run_state.update({"scope": "skip", "updatedAt": now()})
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "skipped",
                "complete",
                "complete",
                run_state_path=run_path,
                result_summary="Obsidian skipped for this Source Onboarding session.",
            )
            save_json(state)
            payload = {"ok": True, "skipped": True}
            payload.update(source_next_prompt_payload(state, "obsidian", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if scope == "folders" and not folders:
            print("--folder is required when --scope folders", file=sys.stderr)
            return 2
        files = markdown_files_for_vault(vault, folders=folders if scope == "folders" else None, limit=5 if scope == "sample" else None)
        total = len(markdown_files_for_vault(vault, folders=folders if scope == "folders" else None)) if scope != "sample" else len(files)
        run_state.update({
            "scope": scope,
            "folders": folders,
            "estimatedFileCount": total,
            "durationClass": duration_class(total),
            "planConfirmed": False,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "running",
            "ingest",
            "confirm_ingest_plan",
            run_state_path=run_path,
            result_summary="Obsidian ingest scope selected: " + scope,
        )
        save_json(state)
        payload = {"ok": True, "scope": scope, "folders": folders, "estimatedFileCount": total, "durationClass": duration_class(total)}
        payload.update(source_next_prompt_payload(state, "obsidian", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def obsidian_confirm_plan():
        answer = single_flag_value("--answer").strip().lower()
        if answer not in {"yes", "y", "no", "n"}:
            print("--answer must be yes or no", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("obsidian")
        if answer in {"no", "n"}:
            run_state.update({"planConfirmed": False, "updatedAt": now()})
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "attention",
                "ingest",
                "choose_ingest_scope",
                attention_reason="ingest_plan_rejected",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_rejected"}
            payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            payload = {"ok": False, "reason": "ingest_scope_required"}
            state = set_obsidian_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
            save_json(state)
            payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"planConfirmed": True, "confirmedAt": now(), "updatedAt": now()})
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "running",
            "ingest",
            "ingest_markdown",
            run_state_path=run_path,
            result_summary="Obsidian ingest plan confirmed.",
        )
        save_json(state)
        payload = {"ok": True, "scope": run_state.get("scope"), "estimatedFileCount": run_state.get("estimatedFileCount")}
        payload.update(source_next_prompt_payload(state, "obsidian", "ingest_markdown"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def obsidian_ingest():
        state = load_or_create_state()
        run_state = load_source_run_state("obsidian")
        if not run_state.get("planConfirmed"):
            state = set_obsidian_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}
            payload.update(source_next_prompt_payload(state, "obsidian", "confirm_ingest_plan"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        vault = run_state.get("selectedVaultPath")
        scope = run_state.get("scope")
        folders = run_state.get("folders") if isinstance(run_state.get("folders"), list) else []
        files = markdown_files_for_vault(vault, folders=folders if scope == "folders" else None, limit=5 if scope == "sample" else None)
        artifact = obsidian_artifact_path(state)
        lines = [
            "# Obsidian Source Onboarding Ingest",
            "",
            "source: obsidian",
            "playbook: obsidian.direct-markdown.v1",
            "vault: " + str(vault),
            "scope: " + str(scope),
            "file_count: " + str(len(files)),
            "",
            "## Files",
        ]
        for path in files:
            try:
                relative = str(path.relative_to(Path(vault)))
            except Exception:
                relative = str(path)
            lines.append("- " + relative)
        lines.extend(["", "## Notes"])
        for path in files:
            try:
                relative = str(path.relative_to(Path(vault)))
                body = path.read_text(encoding="utf-8", errors="replace")
            except Exception as error:
                lines.extend([
                    "",
                    "### " + str(path),
                    "",
                    "read_error: " + type(error).__name__,
                ])
                continue
            lines.extend([
                "",
                "### " + relative,
                "",
                "```markdown",
                body.rstrip(),
                "```",
            ])
        artifact.write_text("\\n".join(lines).rstrip() + "\\n", encoding="utf-8")
        run_state.update({
            "artifactPath": str(artifact),
            "ingestedFileCount": len(files),
            "ingestedAt": now(),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "running",
            "verify",
            "verify_readback",
            run_state_path=run_path,
            result_summary="Obsidian ingest artifact written with " + str(len(files)) + " Markdown files.",
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "ingestedFileCount": len(files)}
        payload.update(source_next_prompt_payload(state, "obsidian", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def obsidian_verify_readback():
        state = load_or_create_state()
        run_state = load_source_run_state("obsidian")
        artifact = Path(run_state.get("artifactPath") or "")
        try:
            text = artifact.read_text(encoding="utf-8")
        except Exception:
            text = ""
        if "source: obsidian" not in text or "playbook: obsidian.direct-markdown.v1" not in text:
            run_state.update({"readbackStatus": "failed", "updatedAt": now()})
            run_path = save_source_run_state("obsidian", run_state)
            state = set_obsidian_row_state(
                state,
                "attention",
                "verify",
                "verify_readback",
                attention_reason="readback_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "readback_failed"}
            payload.update(source_next_prompt_payload(state, "obsidian", "verify_readback"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()})
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "checked",
            "complete",
            "complete",
            run_state_path=run_path,
            result_summary="Obsidian ingest readback verified for " + str(run_state.get("ingestedFileCount") or 0) + " Markdown files.",
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "readbackStatus": "passed"}
        payload.update(source_next_prompt_payload(state, "obsidian", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def obsidian_command():
        if not args:
            print("obsidian requires a subcommand", file=sys.stderr)
            return 2
        subcommand = args[0]
        if subcommand == "verify-vault":
            return obsidian_verify_vault()
        if subcommand == "smoke-read":
            return obsidian_smoke_read()
        if subcommand == "choose-scope":
            return obsidian_choose_scope()
        if subcommand == "confirm-plan":
            return obsidian_confirm_plan()
        if subcommand == "ingest":
            return obsidian_ingest()
        if subcommand == "verify-readback":
            return obsidian_verify_readback()
        print("unknown obsidian subcommand: " + subcommand, file=sys.stderr)
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
                "executionOrder": None,
                "activeSourceID": None,
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
    elif command == "next":
        sys.exit(start_next())
    elif command == "gmail":
        sys.exit(gmail_command())
    elif command == "obsidian":
        sys.exit(obsidian_command())
    elif command == "status":
        status()
    else:
        print("unknown command: " + command, file=sys.stderr)
        sys.exit(2)
    PY
    """
}
