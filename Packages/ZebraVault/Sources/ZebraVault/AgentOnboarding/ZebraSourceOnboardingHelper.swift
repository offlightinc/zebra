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
        let languageCode = ZebraOnboardingLanguage.current().code
        persistOnboardingLanguageCode(languageCode)
        var commands = [
            "export ZEBRA_SOURCE_ONBOARDING_STATE=\(ZebraAgentLaunchCommand.shellQuote(stateURL.path))",
            "export ZEBRA_GBRAIN_SETUP_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainOnboardingStateURL.path))",
            "export ZEBRA_GBRAIN_ADAPTER_STATE=\(ZebraAgentLaunchCommand.shellQuote(gbrainAdapterOnboardingStateURL.path))",
            "export ZEBRA_SOURCE_ONBOARDING_HOME=\(ZebraAgentLaunchCommand.shellQuote(homeDirectoryPath))",
            "export ZEBRA_SOURCE_PLAYBOOK_DIR=\(ZebraAgentLaunchCommand.shellQuote(playbookDirectory.path))",
            "export ZEBRA_ONBOARDING_LANGUAGE=\(ZebraAgentLaunchCommand.shellQuote(languageCode))",
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

    private func persistOnboardingLanguageCode(_ languageCode: String) {
        let directory = stateURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let languageURL = directory.appendingPathComponent(
            "source-onboarding-language.json",
            isDirectory: false
        )
        let sidecar = ["onboardingLanguageCode": languageCode]
        if let data = try? JSONSerialization.data(
            withJSONObject: sidecar,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: languageURL, options: .atomic)
        }

        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              var state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        var entry = state["entryContext"] as? [String: Any] ?? [:]
        entry["onboardingLanguageCode"] = languageCode
        state["entryContext"] = entry
        state["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        if let updated = try? JSONSerialization.data(
            withJSONObject: state,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? updated.write(to: stateURL, options: .atomic)
        }
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
        let playbooks: [(resource: String, filename: String, fallback: String)] = [
            (
                "obsidian.direct-markdown.v1",
                "obsidian.direct-markdown.v1.md",
                Self.fallbackObsidianPlaybook
            ),
            (
                "imessage.imsg-cli.v1",
                "imessage.imsg-cli.v1.md",
                Self.fallbackIMessagePlaybook
            ),
            (
                "notion.ntn-cli.v1",
                "notion.ntn-cli.v1.md",
                Self.fallbackNotionPlaybook
            ),
            (
                "apple-notes.memo-cli.v1",
                "apple-notes.memo-cli.v1.md",
                Self.fallbackAppleNotesPlaybook
            ),
            (
                "apple-reminders.remindctl.v1",
                "apple-reminders.remindctl.v1.md",
                Self.fallbackAppleRemindersPlaybook
            ),
        ]
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for playbook in playbooks {
                let destination = directory.appendingPathComponent(
                    playbook.filename,
                    isDirectory: false
                )
                let contents: String
                if let resource = Self.sourcePlaybookResourceURL(named: playbook.resource) {
                    contents = try String(contentsOf: resource, encoding: .utf8)
                } else {
                    contents = playbook.fallback
                }
                try contents.write(to: destination, atomically: true, encoding: .utf8)
            }
        } catch {
            for playbook in playbooks {
                let destination = directory.appendingPathComponent(
                    playbook.filename,
                    isDirectory: false
                )
                try? playbook.fallback.write(
                    to: destination,
                    atomically: true,
                    encoding: .utf8
                )
            }
        }
        return directory
    }

    private static func sourcePlaybookResourceURL(named resource: String) -> URL? {
        Bundle.module.url(
            forResource: resource,
            withExtension: "md",
            subdirectory: "SourcePlaybooks"
        ) ?? Bundle.module.url(
            forResource: resource,
            withExtension: "md"
        )
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

    When the user provides a candidate path, run `zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`.

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

    private static let fallbackIMessagePlaybook = """
    ---
    id: imessage.imsg-cli
    version: v1
    sourceID: imessage
    initialStepID: check_imsg_cli
    steps:
      - check_imsg_cli
      - check_full_disk_access
      - smoke_history
      - choose_ingest_scope
      - confirm_ingest_plan
      - ingest_messages
      - verify_readback
      - complete
    ---

    # iMessage CLI Source Onboarding

    ## Step: check_imsg_cli

    Run `zebra-source-onboarding imessage check-cli`.

    ## Step: check_full_disk_access

    Run `zebra-source-onboarding imessage check-access`.

    ## Step: smoke_history

    Run `zebra-source-onboarding imessage smoke-history`. This is read-only access verification and is not ingest approval.

    ## Step: choose_ingest_scope

    Ask the user to choose updated conversations since a date, selected conversations, all conversations, or skip. For selected conversations, prefer contact/display names when available and otherwise show a formatted phone/email handle.

    ## Step: confirm_ingest_plan

    Summarize the selected iMessage ingest scope and ask for explicit approval.

    ## Step: ingest_messages

    Run `zebra-source-onboarding imessage ingest`.

    ## Step: verify_readback

    Run `zebra-source-onboarding imessage verify-readback`.

    ## Step: complete

    iMessage Source Onboarding is complete.
    """

    private static let fallbackNotionPlaybook = """
    ---
    id: notion.ntn-cli
    version: v1
    sourceID: notion
    initialStepID: check_ntn_cli
    steps:
      - check_ntn_cli
      - choose_scope
      - smoke_read
      - confirm_workspace_ingest
      - ingest_notion
      - verify_readback
      - complete
    ---

    # Notion ntn CLI Source Onboarding

    ## Step: check_ntn_cli

    Work only the Notion `check_ntn_cli` step.

    Run:

    ```bash
    zebra-source-onboarding notion check-cli
    ```

    If `ntn` is missing, report the helper's compact attention reason and tell the user the expected install path is the official `ntn` CLI. The default install command is `curl -fsSL https://ntn.dev | bash`. If that install path fails and `npm` is available, use `npm install --global ntn` as the fallback. After installation, run `ntn --version` and authenticate with `ntn login`. Do not install anything unless the user explicitly asks.

    Continue only from the returned `nextPrompt`.

    ## Step: choose_scope

    Ask the user to choose exactly one Notion scope:

    1. Page URL/ID 기준으로 현재 page만 가져오기
    2. Page URL/ID 기준으로 현재 page와 하위 page까지 가져오기
    3. Data source/database URL/ID 기준으로 pages/rows 전체 가져오기
    4. URL/ID를 모르면 Notion workspace 후보 찾기
    5. Notion workspace 전체 가져오기
    6. Notion 건너뛰기

    Workspace search means authenticated Notion workspace search through `ntn api v1/search page_size:=10`, not web search.

    ## Step: smoke_read

    Run the read-only smoke command automatically after scope selection. Do not ask the user for separate smoke-read approval.

    ## Step: confirm_workspace_ingest

    For whole-workspace ingest, explain expected duration, token/embedding cost possibility, permission gaps, and sensitive/private page risk. Do not ingest until the user explicitly confirms.

    ## Step: ingest_notion

    Convert the selected Notion content into a GBrain markdown artifact with Notion provenance. Do not assume native Notion database ingest.

    ## Step: verify_readback

    Verify the artifact contains Notion provenance and sanitized content.

    ## Step: complete

    Notion Source Onboarding is complete.
    """

    private static let fallbackAppleNotesPlaybook = """
    ---
    id: apple-notes.memo-cli
    version: v1
    sourceID: apple-notes
    initialStepID: check_memo_cli
    steps:
      - check_memo_cli
      - check_notes_automation
      - smoke_list_notes
      - choose_ingest_scope
      - confirm_ingest_plan
      - ingest_notes
      - verify_readback
      - complete
    ---

    # Apple Notes memo CLI Source Onboarding

    ## Step: check_memo_cli

    Work only the Apple Notes `check_memo_cli` step.

    Run:

    ```bash
    zebra-source-onboarding apple-notes check-cli
    ```

    If `memo` is missing, report the helper's compact attention reason and tell the user Apple Notes ingest requires the `memo` CLI. Show this Homebrew install command:

    ```bash
    brew tap antoniorodr/memo && brew install antoniorodr/memo/memo
    ```

    Then ask an explicit yes/no question before installing:

    ```text
    Apple Notes ingest requires the memo CLI. Install it now with Homebrew? (yes/no)
    ```

    Do not install anything unless the user explicitly answers yes.

    Continue only from the returned `nextPrompt`.

    ## Step: check_notes_automation

    Run `zebra-source-onboarding apple-notes check-access`.

    ## Step: smoke_list_notes

    Run `zebra-source-onboarding apple-notes smoke-list`. This is read-only access verification and is not ingest approval.

    ## Step: choose_ingest_scope

    Ask the user to choose a folder, search query, selected note IDs, a small sample, or skip Apple Notes for now.

    ## Step: confirm_ingest_plan

    Summarize the selected Apple Notes ingest plan and ask for explicit approval.

    ## Step: ingest_notes

    Run `zebra-source-onboarding apple-notes ingest`.

    ## Step: verify_readback

    Run `zebra-source-onboarding apple-notes verify-readback`.

    ## Step: complete

    Apple Notes Source Onboarding is complete.
    """

    private static let fallbackAppleRemindersPlaybook = """
    ---
    id: apple-reminders.remindctl
    version: v1
    sourceID: apple-reminders
    initialStepID: check_remindctl_cli
    steps:
      - check_remindctl_cli
      - check_reminders_permission
      - smoke_list_reminders
      - choose_ingest_scope
      - confirm_ingest_plan
      - ingest_reminders
      - verify_readback
      - complete
    ---

    # Apple Reminders remindctl Source Onboarding

    ## Step: check_remindctl_cli

    Run `zebra-source-onboarding apple-reminders check-cli`. If `remindctl` is missing, use the helper's Homebrew/remindctl install consent flow. Do not install anything unless the user explicitly approves that install.

    ## Step: check_reminders_permission

    Run `zebra-source-onboarding apple-reminders check-access`.

    ## Step: smoke_list_reminders

    Run `zebra-source-onboarding apple-reminders smoke-list`. This is read-only verification and not ingest approval.

    ## Step: choose_ingest_scope

    Use the helper-generated localized scope prompt. Ask the user to choose all open reminders, one list, today/week, custom, or skip Apple Reminders for now in the active onboarding language.

    ## Step: confirm_ingest_plan

    Summarize the approved scope, expected count, fields, unsupported fields, artifact path, readback plan, and redaction policy. Ask for explicit yes/no approval before ingest.

    ## Step: ingest_reminders

    Run `zebra-source-onboarding apple-reminders ingest`.

    ## Step: verify_readback

    Run `zebra-source-onboarding apple-reminders verify-readback`.

    If readback succeeds, the helper must move to `complete` and return a completion-report prompt. Do not start the next source from `verify-readback` directly.

    ## Step: complete

    Tell the user a short Apple Reminders result summary, then run:

    ```bash
    zebra-source-onboarding report --status completed --source apple-reminders
    ```

    Only after this report command succeeds may the agent continue to the next source from the report stdout `nextPrompt`.
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
    import contextlib
    import io
    import json
    import os
    import re
    import shutil
    import subprocess
    import sys
    import textwrap
    import unicodedata
    import urllib.error
    import urllib.parse
    import urllib.request
    import uuid
    import hashlib
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
        "apple-notes": {
            "displayName": "Apple Notes",
            "type": "notes",
            "aliases": ["apple notes", "apple note", "애플노트", "애플 노트", "애플 메모", "맥북 메모", "notes", "memo"],
        },
        "apple-reminders": {
            "displayName": "Apple Reminders",
            "type": "tasks",
            "aliases": ["apple reminders", "apple reminder", "reminders", "reminder", "애플 리마인더", "애플리마인더", "리마인더", "미리알림", "미리 알림"],
        },
        "agent-memory": {
            "displayName": "기존 agent memory",
            "type": "agent-memory",
            "aliases": ["agent memory", "agent knowledge", "existing agent memory", "기존 agent memory", "기존 에이전트 memory", "에이전트 메모리", "에이전트 지식", "agent 메모리", "agent 지식"],
        },
    }

    uncataloged_catalog = {}

    def normalize_onboarding_language(raw):
        raw = (raw or "").strip().lower().replace("_", "-")
        if raw == "ko" or raw.startswith("ko-"):
            return "ko"
        if raw == "ja" or raw.startswith("ja-"):
            return "ja"
        return "en"

    def state_onboarding_language():
        state = load_json(state_path)
        entry = state.get("entryContext") if isinstance(state.get("entryContext"), dict) else {}
        raw = entry.get("onboardingLanguageCode") if isinstance(entry, dict) else None
        return raw if isinstance(raw, str) and raw.strip() else ""

    def sidecar_onboarding_language():
        value = load_json(state_path.parent / "source-onboarding-language.json")
        raw = value.get("onboardingLanguageCode") if isinstance(value, dict) else None
        return raw if isinstance(raw, str) and raw.strip() else ""

    def onboarding_language():
        return normalize_onboarding_language(
            os.environ.get("ZEBRA_ONBOARDING_LANGUAGE")
            or state_onboarding_language()
            or sidecar_onboarding_language()
            or "en"
        )

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

    def agent_cli_state_path():
        return state_path.parent / "agent-cli-state.json"

    def agent_cli_events_path():
        return state_path.parent / "agent-cli-events.jsonl"

    def runtime_state_path():
        return state_path.parent / "gbrain-runtime-state.json"

    def installed_by_zebra_agent_ids():
        installed = set()
        events = agent_cli_events_path()
        try:
            for line in events.read_text(encoding="utf-8").splitlines():
                event = json.loads(line)
                if event.get("event") == "install_succeeded":
                    agent = str(event.get("agent") or "").strip()
                    if agent:
                        installed.add(agent)
        except Exception:
            pass
        return installed

    def existing_step1_agent_ids():
        installed_by_zebra = installed_by_zebra_agent_ids()
        state = load_json(agent_cli_state_path())
        candidates = state.get("candidates") if isinstance(state.get("candidates"), list) else []
        result = []
        for item in candidates:
            if not isinstance(item, dict):
                continue
            agent = str(item.get("id") or "").strip()
            if not agent or agent in installed_by_zebra:
                continue
            if item.get("installState") == "installed":
                result.append(agent)
        return result

    def runtime_installed_by_zebra(runtime, state):
        attempts = state.get("attempts") if isinstance(state.get("attempts"), list) else []
        for item in attempts:
            if not isinstance(item, dict):
                continue
            if item.get("kind") == "install-runtime:" + runtime:
                return True
        return False

    def existing_step2_agent_ids():
        state = load_json(runtime_state_path())
        preflight = state.get("preflight") if isinstance(state.get("preflight"), dict) else {}
        facts = preflight.get("facts") if isinstance(preflight.get("facts"), dict) else {}
        result = []
        for runtime in ("openclaw", "hermes"):
            fact = facts.get(runtime) if isinstance(facts.get(runtime), dict) else {}
            if fact.get("ok") and not runtime_installed_by_zebra(runtime, state):
                result.append(runtime)
        return result

    def existing_agent_ids_for_memory_probe():
        seen = set()
        result = []
        for agent in existing_step1_agent_ids() + existing_step2_agent_ids():
            if agent not in seen:
                seen.add(agent)
                result.append(agent)
        return result

    def agent_memory_candidate_paths(agent):
        if agent == "codex":
            return [home / ".codex/AGENTS.md", home / ".codex/rules"]
        if agent == "claude":
            return [home / ".claude/CLAUDE.md", home / ".claude/AGENTS.md"]
        if agent == "antigravity":
            return [
                home / ".config/antigravity/AGENTS.md",
                home / ".local/share/antigravity/AGENTS.md",
            ]
        if agent == "openclaw":
            return [
                home / ".openclaw/workspace/AGENTS.md",
                home / ".openclaw/workspace/USER.md",
                home / ".openclaw/workspace/SOUL.md",
                home / ".openclaw/workspace/TOOLS.md",
                home / ".openclaw/workspace/BOOTSTRAP.md",
                home / ".openclaw/workspace/IDENTITY.md",
            ]
        if agent == "hermes":
            return [
                home / ".hermes/SOUL.md",
                home / ".hermes/memories/MEMORY.md",
                home / ".hermes/memories/USER.md",
            ]
        return []

    def agent_display_name(agent):
        return {
            "claude": "Claude Code",
            "codex": "Codex",
            "antigravity": "Antigravity",
            "openclaw": "OpenClaw",
            "hermes": "Hermes",
        }.get(agent, agent)

    def is_agent_memory_excluded(path):
        name = path.name.lower()
        suffix = path.suffix.lower()
        if name.endswith(".lock") or name in {".ds_store"}:
            return True
        if suffix in {".sqlite", ".db", ".db-shm", ".db-wal", ".lock", ".tmp", ".bak", ".json", ".toml", ".yaml", ".yml"}:
            return True
        lower = str(path).lower()
        sensitive_parts = ("credential", "token", "secret", "auth", "cache", "session", "history", "log", "tmp")
        return any(part in lower for part in sensitive_parts)

    def iter_agent_memory_files(agent):
        roots = agent_memory_candidate_paths(agent)
        for root in roots:
            try:
                resolved_root = root.expanduser().resolve(strict=False)
            except Exception:
                continue
            if resolved_root.is_dir():
                try:
                    children = sorted(resolved_root.rglob("*"))
                except Exception:
                    continue
            else:
                children = [resolved_root]
            for candidate in children:
                try:
                    resolved = candidate.resolve(strict=False)
                except Exception:
                    continue
                if not resolved.is_file() or is_agent_memory_excluded(resolved):
                    continue
                if resolved.suffix.lower() not in {".md", ".markdown", ".txt"}:
                    continue
                try:
                    resolved.relative_to(resolved_root if resolved_root.is_dir() else resolved_root.parent)
                except Exception:
                    continue
                yield resolved

    def meaningful_agent_memory_text(text):
        lines = []
        in_frontmatter = False
        for raw in text.splitlines():
            stripped = raw.strip()
            if stripped == "---" and not lines:
                in_frontmatter = True
                continue
            if in_frontmatter:
                if stripped == "---":
                    in_frontmatter = False
                continue
            if not stripped or stripped.startswith("#") or stripped.startswith("//"):
                continue
            lines.append(stripped)
        combined = " ".join(lines).strip()
        placeholders = {
            "todo",
            "tbd",
            "empty",
            "placeholder",
            "add your memory here",
            "add memories here",
        }
        return bool(combined and combined.lower() not in placeholders)

    def agent_memory_importable_units():
        units = []
        for agent in existing_agent_ids_for_memory_probe():
            for path in iter_agent_memory_files(agent):
                try:
                    if path.stat().st_size <= 0:
                        continue
                    text = path.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    continue
                if not meaningful_agent_memory_text(text):
                    continue
                units.append({
                    "agent": agent,
                    "displayName": agent_display_name(agent),
                    "path": str(path),
                    "bytes": path.stat().st_size,
                })
        return units

    def agent_memory_readiness():
        units = agent_memory_importable_units()
        by_agent = {}
        for unit in units:
            agent = unit["agent"]
            by_agent.setdefault(agent, {
                "agent": agent,
                "displayName": unit["displayName"],
                "importableUnitCount": 0,
            })
            by_agent[agent]["importableUnitCount"] += 1
        reasons = []
        if not existing_agent_ids_for_memory_probe():
            reasons.append("existing_agent_not_found")
        elif not units:
            reasons.append("importable_memory_not_found")
        return {
            "status": "ready" if units else "not_available",
            "importableUnitCount": len(units),
            "agents": list(by_agent.values()),
            "reasons": reasons,
        }

    def agent_memory_available():
        return agent_memory_readiness().get("importableUnitCount", 0) > 0

    def source_readiness():
        return {
            "gmail": gmail_readiness(),
            "agentMemory": agent_memory_readiness(),
        }

    def source_input_prompt(agent_memory=None):
        readiness = agent_memory or agent_memory_readiness()
        if readiness.get("importableUnitCount", 0) > 0:
            return textwrap.dedent('''
            어디에 중요한 기록과 업무 맥락을 쌓아두고 있나요?

            Zebra가 이 Mac에서 기존 agent의 memory/knowledge 파일도 찾았습니다. 가져오고 싶은 항목을 함께 선택할 수 있습니다.

            예: Gmail, Notion, Slack, Obsidian, Apple Notes, 기존 agent memory
            ''').strip()
        return "어디에 중요한 기록과 업무 맥락을 쌓아두고 있나요? 예: Gmail, Notion, Slack, Obsidian, Apple Notes"

    def default_state(timestamp=None):
        timestamp = timestamp or now()
        context = entry_context()
        missing_prerequisite = context.get("gbrainTargetMissingReason") or (None if context.get("adapterReady") else "gbrain_adapter_missing")
        return {
            "schemaVersion": 1,
            "status": "attention" if missing_prerequisite else "ready",
            "entryContext": context,
            "sourceReadiness": source_readiness(),
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
        if isinstance(state.get("entryContext"), dict):
            state["entryContext"].setdefault("onboardingLanguageCode", onboarding_language())
        readiness = state.get("sourceReadiness") if isinstance(state.get("sourceReadiness"), dict) else {}
        readiness["agentMemory"] = agent_memory_readiness()
        readiness.setdefault("gmail", gmail_readiness())
        state["sourceReadiness"] = readiness
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

    imessage_playbook_fallback = {
        "id": "imessage.imsg-cli",
        "version": "v1",
        "sourceID": "imessage",
        "initialStepID": "check_imsg_cli",
        "steps": [
            "check_imsg_cli",
            "check_full_disk_access",
            "smoke_history",
            "choose_ingest_scope",
            "confirm_ingest_plan",
            "ingest_messages",
            "verify_readback",
            "complete",
        ],
        "sections": {},
    }

    notion_playbook_fallback = {
        "id": "notion.ntn-cli",
        "version": "v1",
        "sourceID": "notion",
        "initialStepID": "check_ntn_cli",
        "steps": [
            "check_ntn_cli",
            "choose_scope",
            "smoke_read",
            "confirm_workspace_ingest",
            "ingest_notion",
            "verify_readback",
            "complete",
        ],
        "sections": {},
    }

    apple_notes_playbook_fallback = {
        "id": "apple-notes.memo-cli",
        "version": "v1",
        "sourceID": "apple-notes",
        "initialStepID": "check_memo_cli",
        "steps": [
            "check_memo_cli",
            "check_notes_automation",
            "smoke_list_notes",
            "choose_ingest_scope",
            "confirm_ingest_plan",
            "ingest_notes",
            "verify_readback",
            "complete",
        ],
        "sections": {},
    }

    apple_reminders_playbook_fallback = {
        "id": "apple-reminders.remindctl",
        "version": "v1",
        "sourceID": "apple-reminders",
        "initialStepID": "check_remindctl_cli",
        "steps": [
            "check_remindctl_cli",
            "check_reminders_permission",
            "smoke_list_reminders",
            "choose_ingest_scope",
            "confirm_ingest_plan",
            "ingest_reminders",
            "verify_readback",
            "complete",
        ],
        "sections": {},
    }

    agent_memory_playbook_fallback = {
        "id": "agent-memory.local-files",
        "version": "v1",
        "sourceID": "agent-memory",
        "initialStepID": "review_found_agents",
        "steps": [
            "review_found_agents",
            "choose_ingest_scope",
            "confirm_ingest_plan",
            "ingest_memory",
            "verify_readback",
            "complete",
        ],
        "sections": {},
    }

    fallback_playbook = {
        "id": "uncataloged.agent-fallback",
        "version": "v1",
        "sourceID": "uncataloged",
        "initialStepID": "classify_source",
        "steps": [
            "classify_source",
            "research_access_paths",
            "choose_strategy",
            "smoke_read",
            "propose_ingest_scope",
            "confirm_ingest_plan",
            "ingest",
            "verify_readback",
            "complete",
        ],
        "sections": {},
    }

    def parse_playbook_markdown(path, fallback=None):
        fallback = fallback or obsidian_playbook_fallback
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
            return dict(fallback)
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
        for key in ("id", "version", "sourceID", "initialStepID"):
            if not result.get(key):
                result[key] = fallback[key]
        if not result.get("steps"):
            result["steps"] = list(fallback["steps"])
        return result

    def obsidian_playbook():
        return parse_playbook_markdown(
            playbook_dir / "obsidian.direct-markdown.v1.md",
            obsidian_playbook_fallback,
        )

    def imessage_playbook():
        return parse_playbook_markdown(
            playbook_dir / "imessage.imsg-cli.v1.md",
            imessage_playbook_fallback,
        )

    def notion_playbook():
        return parse_playbook_markdown(
            playbook_dir / "notion.ntn-cli.v1.md",
            notion_playbook_fallback,
        )

    def apple_notes_playbook():
        return parse_playbook_markdown(
            playbook_dir / "apple-notes.memo-cli.v1.md",
            apple_notes_playbook_fallback,
        )

    def apple_reminders_playbook():
        return parse_playbook_markdown(
            playbook_dir / "apple-reminders.remindctl.v1.md",
            apple_reminders_playbook_fallback,
        )

    def agent_memory_playbook():
        return agent_memory_playbook_fallback

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

    def uncataloged_record_for(progress, source_id):
        records = progress.get("uncatalogedSources")
        if not isinstance(records, list):
            return {}
        for item in records:
            if isinstance(item, dict) and item.get("normalizedValue") == source_id:
                return item
        return {}

    def fallback_source_row_for(progress, source_id, timestamp):
        record = uncataloged_record_for(progress, source_id)
        return {
            "id": source_id,
            "displayName": record.get("displayName") or record.get("rawValue") or source_id,
            "type": "uncataloged",
            "phase": "intake",
            "status": "unchecked",
            "selectionState": "confirmed",
            "playbookID": fallback_playbook["id"],
            "playbookVersion": fallback_playbook["version"],
            "updatedAt": timestamp,
        }

    def is_fallback_source_row(row):
        return isinstance(row, dict) and (
            row.get("type") == "uncataloged"
            or row.get("playbookID") == fallback_playbook["id"]
        )

    def set_fallback_row_state(state, source_id, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else fallback_source_row_for(progress, source_id, timestamp)
        row["status"] = row_status
        row["phase"] = phase
        row["selectionState"] = "confirmed"
        row["type"] = "uncataloged"
        row["playbookID"] = fallback_playbook["id"]
        row["playbookVersion"] = fallback_playbook["version"]
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
        rows[source_id] = row
        progress["sourceRows"] = rows
        if source_id not in ensure_execution_order(progress):
            progress["executionOrder"].append(source_id)
        if row_status in {"checked", "skipped"}:
            if progress.get("activeSourceID") == source_id:
                progress["activeSourceID"] = None
        else:
            progress["activeSourceID"] = source_id
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def fallback_phase_for_step(step_id):
        if step_id in {"classify_source", "research_access_paths", "choose_strategy"}:
            return "investigate"
        if step_id in {"smoke_read"}:
            return "preflight"
        if step_id in {"propose_ingest_scope", "confirm_ingest_plan"}:
            return "scope"
        if step_id == "ingest":
            return "ingest"
        if step_id == "verify_readback":
            return "verify"
        if step_id == "complete":
            return "complete"
        return "intake"

    def next_fallback_step_id(step_id):
        steps = fallback_playbook["steps"]
        if step_id not in steps:
            return fallback_playbook["initialStepID"]
        index = steps.index(step_id)
        if index + 1 >= len(steps):
            return "complete"
        return steps[index + 1]

    def redaction_report():
        return {"secret": 0, "privatePath": 0, "rawBody": 0}

    def sanitize_control_plane_text(value, report=None, limit=320):
        if report is None:
            report = redaction_report()
        text = str(value or "")
        secret_patterns = [
            r"(?i)\\bsk-[A-Za-z0-9_-]{6,}\\b",
            r"(?i)\\bcvis_[A-Za-z0-9_-]{6,}\\b",
            r"(?i)\\bxox[a-z]-[A-Za-z0-9_-]{6,}\\b",
            r"(?i)\\b(?:token|cookie|password|secret|oauth(?:_code)?|code)\\s*[:=]\\s*[^\\s,;]+",
        ]
        for pattern in secret_patterns:
            text, count = re.subn(pattern, "<redacted-secret>", text)
            report["secret"] = report.get("secret", 0) + count
        def replace_private_path(match):
            report["privatePath"] = report.get("privatePath", 0) + 1
            basename = Path(match.group(0)).name or "path"
            digest = hashlib.sha256(match.group(0).encode("utf-8")).hexdigest()[:12]
            return "<private-path:" + basename + ":" + digest + ">"
        text = re.sub(r"/Users/[^\\s'\\\"`]+", replace_private_path, text)
        text, body_count = re.subn(
            r"(?is)\\b(raw\\s+body|body|message\\s+body|document\\s+text)\\s*[:=].*",
            r"\\1:<redacted-body>",
            text,
        )
        report["rawBody"] = report.get("rawBody", 0) + body_count
        text = " ".join(text.split())
        if len(text) > limit:
            text = text[: limit - 3].rstrip() + "..."
        return text

    def fallback_run_state(source_id):
        run_state = load_source_run_state(source_id)
        if not run_state.get("fallbackRunID"):
            run_state["fallbackRunID"] = str(uuid.uuid4())
        return run_state

    def fallback_run_directory(source_id, run_state):
        run_id = run_state.get("fallbackRunID") or str(uuid.uuid4())
        directory = state_path.parent / "fallback-runs" / (prompt_file_safe_name(source_id) + "-" + prompt_file_safe_name(run_id))
        directory.mkdir(parents=True, exist_ok=True)
        return directory

    def write_json_file(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\\n")
        os.replace(tmp, path)
        try:
            os.chmod(path, 0o600)
        except Exception:
            pass

    def write_fallback_artifacts(source_id, run_state, event):
        directory = fallback_run_directory(source_id, run_state)
        compact = {
            "schemaVersion": 1,
            "sourceID": source_id,
            "playbookID": fallback_playbook["id"],
            "playbookVersion": fallback_playbook["version"],
            "currentStepID": event.get("stepID"),
            "status": event.get("status"),
            "summary": event.get("sanitizedSummary"),
            "attentionReason": event.get("attentionReason"),
            "strategy": run_state.get("strategy"),
            "ingestScope": run_state.get("ingestScope"),
            "gbrainArtifact": run_state.get("gbrainArtifact"),
            "updatedAt": event.get("updatedAt"),
        }
        write_json_file(directory / "fallback-summary.json", compact)
        write_json_file(directory / "promotion-candidate.json", {
            "schemaVersion": 1,
            "sourceID": source_id,
            "observedSteps": run_state.get("observedSteps", []),
            "implementationNotes": compact_completion_value(event.get("sanitizedSummary"), limit=240),
            "latestStatus": event.get("status"),
            "latestAttentionReason": event.get("attentionReason"),
        })
        playbook_lines = [
            "# Uncataloged Source Fallback Draft",
            "",
            "source: " + source_id,
            "playbook: " + fallback_playbook["id"] + "." + fallback_playbook["version"],
            "latest_step: " + str(event.get("stepID") or ""),
            "latest_status: " + str(event.get("status") or ""),
            "",
            "## Sanitized Notes",
            "",
            str(event.get("sanitizedSummary") or ""),
        ]
        (directory / "playbook-draft.md").write_text("\\n".join(playbook_lines).rstrip() + "\\n", encoding="utf-8")
        try:
            os.chmod(directory / "playbook-draft.md", 0o600)
        except Exception:
            pass
        write_json_file(directory / "redaction-report.json", {
            "schemaVersion": 1,
            "sourceID": source_id,
            "redactions": event.get("redactions", redaction_report()),
            "updatedAt": event.get("updatedAt"),
        })
        return {
            "directoryName": directory.name,
            "summaryFile": "fallback-summary.json",
            "promotionFile": "promotion-candidate.json",
            "playbookDraftFile": "playbook-draft.md",
            "redactionReportFile": "redaction-report.json",
        }

    def gbrain_target_directory(state):
        entry = state.get("entryContext") if isinstance(state.get("entryContext"), dict) else {}
        for key in ["gbrainTargetPath", "gbrainWriteTargetPath"]:
            raw = entry.get(key)
            if isinstance(raw, str) and raw.strip():
                candidate = Path(raw).expanduser()
                candidate.mkdir(parents=True, exist_ok=True)
                return candidate
        return None

    def write_fallback_gbrain_artifact(state, source_id, title, body, provenance):
        target = gbrain_target_directory(state)
        if target is None:
            return None
        safe_title = prompt_file_safe_name(title or source_id)
        path = target / ("source-onboarding-" + prompt_file_safe_name(source_id) + "-" + safe_title + ".md")
        text = "\\n".join([
            "---",
            "source: " + source_id,
            "playbook: " + fallback_playbook["id"] + ".v1",
            "provenance: " + str(provenance or "uncataloged fallback ingest"),
            "---",
            "",
            "# " + str(title or source_id),
            "",
            str(body or "").rstrip(),
            "",
        ]).rstrip() + "\\n"
        path.write_text(text, encoding="utf-8")
        digest = hashlib.sha256(str(path).encode("utf-8")).hexdigest()[:16]
        return {
            "basename": path.name,
            "pathHash": digest,
            "kind": "gbrain-markdown",
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
        if has_attention_row:
            return "attention"
        if all_execution_sources_finished(progress):
            return "completed"
        return "running"

    def pending_completion_source_id(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        ordered = ensure_execution_order(progress)
        for source_id in ordered + [key for key in rows.keys() if key not in ordered]:
            row = rows.get(source_id)
            if (
                isinstance(row, dict)
                and row.get("status") == "running"
                and row.get("phase") == "complete"
                and row.get("playbookStepID") == "complete"
            ):
                return source_id
        return None

    def reject_if_completion_report_pending(command_source_id):
        state = load_json(state_path)
        if not state:
            return None
        migrate_source_state(state)
        pending_source_id = pending_completion_source_id(state)
        if not pending_source_id:
            return None
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, pending_source_id, "complete"))
        payload.update({
            "ok": False,
            "reason": "source_completion_report_required",
            "blockedSourceID": command_source_id,
            "pendingSourceID": pending_source_id,
        })
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1

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

    def obsidian_choose_scope_instruction(language):
        if language == "ko":
            return textwrap.dedent('''
            사용자에게 아래 다섯 가지 선택지만 보여주세요:

            ```text
            Obsidian 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 note 범위를 정해야 합니다.

            어떤 범위로 가져올까요?

            1. 전체 vault
            2. 선택한 폴더
            3. 특정 note 파일
            4. 최근/샘플 일부
            5. 지금은 Obsidian 건너뛰기
            ```

            1번은 `zebra-source-onboarding obsidian choose-scope --scope whole`을 실행하세요.
            2번은 vault 기준 상대 폴더 경로를 확인한 뒤 `zebra-source-onboarding obsidian choose-scope --scope folders --folder "<relative-folder>"`를 실행하세요. 폴더가 여러 개면 `--folder`를 여러 번 넘기세요.
            3번은 vault 기준 상대 Markdown 파일 경로를 확인한 뒤 `zebra-source-onboarding obsidian choose-scope --scope file --file "<relative-note-path.md>"`를 실행하세요.
            4번은 `zebra-source-onboarding obsidian choose-scope --scope sample`을 실행하세요.
            5번은 `zebra-source-onboarding obsidian choose-scope --scope skip`을 실행하세요.

            큰 vault나 폴더에는 private/sensitive note가 포함될 수 있습니다. smoke read 성공은 접근 확인일 뿐 ingest 승인으로 보지 마세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent('''
            ユーザーには次の5つの選択肢だけを表示してください:

            ```text
            Obsidianへのアクセス確認は完了しました。次にbrainへ保存するnoteの範囲を決めます。

            どの範囲を取り込みますか？

            1. vault全体
            2. 選択したフォルダ
            3. 特定のnoteファイル
            4. 最近/サンプルの一部
            5. 今回はObsidianをスキップ
            ```

            1番は`zebra-source-onboarding obsidian choose-scope --scope whole`を実行してください。
            2番はvault基準の相対フォルダパスを確認し、`zebra-source-onboarding obsidian choose-scope --scope folders --folder "<relative-folder>"`を実行してください。複数フォルダの場合は`--folder`を複数回渡してください。
            3番はvault基準の相対Markdownファイルパスを確認し、`zebra-source-onboarding obsidian choose-scope --scope file --file "<relative-note-path.md>"`を実行してください。
            4番は`zebra-source-onboarding obsidian choose-scope --scope sample`を実行してください。
            5番は`zebra-source-onboarding obsidian choose-scope --scope skip`を実行してください。

            大きいvaultやフォルダにはprivate/sensitive noteが含まれる可能性があります。smoke read成功はアクセス確認だけで、ingest承認ではありません。
            ''').strip()
        return textwrap.dedent('''
        Present exactly these five choices to the user:

        ```text
        Obsidian access is verified. Now choose which notes to save into brain.

        Which scope should be ingested?

        1. Whole vault
        2. Selected folders
        3. Specific note file
        4. Recent/sample subset
        5. Skip Obsidian for now
        ```

        If the user chooses option 1, run `zebra-source-onboarding obsidian choose-scope --scope whole`.
        If the user chooses option 2, confirm the vault-relative folder path and run `zebra-source-onboarding obsidian choose-scope --scope folders --folder "<relative-folder>"`. Pass one `--folder` per folder.
        If the user chooses option 3, confirm the vault-relative Markdown file path and run `zebra-source-onboarding obsidian choose-scope --scope file --file "<relative-note-path.md>"`.
        If the user chooses option 4, run `zebra-source-onboarding obsidian choose-scope --scope sample`.
        If the user chooses option 5, run `zebra-source-onboarding obsidian choose-scope --scope skip`.

        Large vaults or folders may contain private/sensitive notes. Smoke read success proves access only; it is not ingest approval.
        ''').strip()

    def obsidian_step_prompt(step_id, state, row):
        playbook = obsidian_playbook()
        run_state = load_source_run_state("obsidian")
        section = playbook.get("sections", {}).get(step_id, "")
        language = onboarding_language()
        path = ""
        if not section:
            section = "Follow the current Obsidian playbook step and continue only through the zebra-source-onboarding helper CLI."
        vault = run_state.get("selectedVaultPath") or run_state.get("candidateVaultPath") or "not selected"
        scope = run_state.get("scope") or "not selected"
        estimated = run_state.get("estimatedFileCount")
        if estimated is None:
            estimated = "unknown"
        artifact = run_state.get("artifactPath") or "not created"
        unreadable_roots = run_state.get("unreadableCandidateRoots") if isinstance(run_state.get("unreadableCandidateRoots"), list) else []
        if step_id == "discover_vault" and unreadable_roots:
            lines = []
            for item in unreadable_roots:
                if not isinstance(item, dict):
                    continue
                root_path = item.get("path") or "unknown"
                reason = item.get("reason") or "unreadable"
                message = item.get("message") or ""
                detail = " - `" + str(root_path) + "` (" + str(reason) + ")"
                if message:
                    detail = detail + ": " + str(message)
                lines.append(detail)
            if lines:
                if language == "ko":
                    section = section + "\\n\\n" + "Zebra가 아래 자동 탐색 위치를 확인하지 못했습니다. 자동 탐색 결과가 불완전할 수 있음을 사용자에게 알리고, 필요하면 정확한 Obsidian vault 경로를 물어보세요:\\n" + "\\n".join(lines)
                elif language == "ja":
                    section = section + "\\n\\n" + "Zebraは次の自動探索場所を確認できませんでした。自動探索結果が不完全な可能性をユーザーに伝え、必要であれば正確なObsidian vaultパスを尋ねてください:\\n" + "\\n".join(lines)
                else:
                    section = section + "\\n\\n" + "Zebra could not inspect these automatic discovery roots. Tell the user that automatic discovery may be incomplete and ask for the exact Obsidian vault path if needed:\\n" + "\\n".join(lines)
        if step_id == "confirm_vault_if_needed":
            candidate = run_state.get("candidateVaultPath")
            candidates = run_state.get("candidateVaultPaths") if isinstance(run_state.get("candidateVaultPaths"), list) else []
            if candidate:
                method = run_state.get("discoveryMethod") or "automatic_discovery"
                if language == "ko":
                    section = section + "\\n\\n" + textwrap.dedent(f'''
                    Zebra가 `{method}`에서 `.obsidian/`을 포함한 Obsidian vault 후보를 찾았습니다:

                    `{candidate}`

                    이 경로를 Obsidian vault로 사용할지 사용자에게 확인하세요. 맞다면 다음 명령을 실행하세요:

                    ```bash
                    zebra-source-onboarding obsidian verify-vault --path "{candidate}"
                    ```

                    아니라면 올바른 vault 경로를 물어보고 `zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`를 실행하세요.
                    ''').strip()
                elif language == "ja":
                    section = section + "\\n\\n" + textwrap.dedent(f'''
                    Zebraは`{method}`から`.obsidian/`を含むObsidian vault候補を見つけました:

                    `{candidate}`

                    このパスをObsidian vaultとして使用するかユーザーに確認してください。正しければ次のコマンドを実行してください:

                    ```bash
                    zebra-source-onboarding obsidian verify-vault --path "{candidate}"
                    ```

                    違う場合は正しいvaultパスを尋ね、`zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`を実行してください。
                    ''').strip()
                else:
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
                candidate_lines = "\\n".join("- `" + str(item) + "`" for item in candidates)
                if language == "ko":
                    section = section + "\\n\\n" + "Zebra가 `" + str(method) + "`에서 여러 `.obsidian/` vault 후보를 찾았습니다. 사용할 vault를 사용자에게 물어본 뒤 `zebra-source-onboarding obsidian verify-vault --path <vault-path>`를 실행하세요. 후보:\\n\\n" + candidate_lines
                elif language == "ja":
                    section = section + "\\n\\n" + "Zebraは`" + str(method) + "`から複数の`.obsidian/` vault候補を見つけました。使用するvaultをユーザーに確認し、`zebra-source-onboarding obsidian verify-vault --path <vault-path>`を実行してください。候補:\\n\\n" + candidate_lines
                else:
                    section = section + "\\n\\n" + "Zebra found multiple `.obsidian/` vault candidates from `" + str(method) + "`. Ask the user which one to use, then run `zebra-source-onboarding obsidian verify-vault --path <vault-path>`. Candidates:\\n\\n" + candidate_lines
        if step_id == "choose_ingest_scope":
            section = obsidian_choose_scope_instruction(language)
        if step_id == "confirm_ingest_plan":
            section = section + "\\n\\n" + obsidian_ingest_plan_summary(run_state)
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

    def imessage_scope_summary(run_state):
        language = onboarding_language()
        scope = run_state.get("scope") or "not selected"
        if scope == "updated-since":
            since = str(run_state.get("since") or "not selected")
            if language == "ko":
                return since + " 이후 업데이트된 대화방"
            if language == "ja":
                return since + "以降に更新された会話"
            return "recently updated conversations since " + since
        if scope == "selected-threads":
            threads = run_state.get("selectedThreadIDs") if isinstance(run_state.get("selectedThreadIDs"), list) else []
            summaries = run_state.get("selectedThreadSummaries") if isinstance(run_state.get("selectedThreadSummaries"), list) else []
            summary_by_id = {}
            for item in summaries:
                if isinstance(item, dict):
                    chat_id = str(item.get("chatID") or "").strip()
                    summary = str(item.get("summary") or item.get("label") or "").strip()
                    if chat_id and summary:
                        summary_by_id[chat_id] = summary
            labels = []
            for item in threads:
                chat_id = str(item)
                labels.append(summary_by_id.get(chat_id) or ("chat_id " + chat_id))
            thread_list = ", ".join(labels) if labels else "none"
            if language == "ko":
                return "선택한 대화방: " + thread_list
            if language == "ja":
                return "選択した会話: " + thread_list
            return "selected conversations: " + thread_list
        if scope == "all-threads":
            if language == "ko":
                return "전체 대화방"
            if language == "ja":
                return "すべての会話"
            return "all conversations"
        if scope == "skip":
            if language == "ko":
                return "이번 Source Onboarding에서 iMessage 건너뛰기"
            if language == "ja":
                return "このSource OnboardingではiMessageをスキップ"
            return "skip iMessage for this Source Onboarding session"
        return str(scope)

    def imessage_ingest_plan_summary(run_state):
        internal_window = run_state.get("internalWindow") if isinstance(run_state.get("internalWindow"), dict) else {}
        message_limit = internal_window.get("messageLimitPerThread") or "bounded"
        thread_limit = internal_window.get("threadListLimit") or "bounded"
        thread_count = run_state.get("estimatedThreadCount")
        if thread_count is None:
            thread_count = "unknown"
        language = onboarding_language()
        if language == "ko":
            return textwrap.dedent(f'''
            선택된 iMessage ingest plan입니다.

            - 선택한 범위: `{imessage_scope_summary(run_state)}`
            - 예상 대화방 수: `{thread_count}`
            - 내부 bounded window: 대화방당 최대 `{message_limit}`개 메시지, 이 helper slice에서 최대 `{thread_limit}`개 대화방
            - 민감정보 안내: 승인된 범위에는 raw message text, phone/email identifier, contact name, OTP/security text, timestamp, thread/message ID, attachment/reaction metadata가 저장될 수 있습니다.
            - Ingest 방식: 승인된 iMessage 범위에 대해 bounded source artifact를 작성합니다.
            - 검증 계획: 생성된 iMessage source artifact를 다시 읽고 `source: imessage`와 `playbook: imessage.imsg-cli.v1`를 확인합니다.

            ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding imessage confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding imessage confirm-plan --answer no`를 실행하세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            選択されたiMessage ingest planです。

            - 選択した範囲: `{imessage_scope_summary(run_state)}`
            - 推定会話数: `{thread_count}`
            - 内部bounded window: 1会話あたり最大`{message_limit}`件のメッセージ、このhelper sliceでは最大`{thread_limit}`件の会話
            - 機微情報の注意: 承認された範囲にはraw message text、phone/email identifier、contact name、OTP/security text、timestamp、thread/message ID、attachment/reaction metadataが保存される可能性があります。
            - Ingest方式: 承認されたiMessage範囲のbounded source artifactを書き込みます。
            - 検証計画: 生成されたiMessage source artifactを読み戻し、`source: imessage`と`playbook: imessage.imsg-cli.v1`を確認します。

            ingestを実行する前にユーザーから明示的な承認を得てください。承認されたら`zebra-source-onboarding imessage confirm-plan --answer yes`を実行し、承認されなければ`zebra-source-onboarding imessage confirm-plan --answer no`を実行してください。
            ''').strip()
        return textwrap.dedent(f'''
        Resolved iMessage ingest plan:

        - Selected scope: `{imessage_scope_summary(run_state)}`
        - Estimated conversation count: `{thread_count}`
        - Internal bounded window: up to `{message_limit}` messages per conversation and up to `{thread_limit}` conversations for this helper slice
        - Sensitive data notice: approved scope may store raw message text, phone/email identifiers, contact names, OTP/security texts, timestamps, thread/message IDs, and attachment/reaction metadata.
        - Ingest mode: write a bounded iMessage source artifact for the approved scope.
        - Verification plan: read back the generated iMessage source artifact and require `source: imessage` plus `playbook: imessage.imsg-cli.v1`.

        Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding imessage confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding imessage confirm-plan --answer no`.
        ''').strip()

    def imessage_step_prompt(step_id, state, row):
        playbook = imessage_playbook()
        run_state = load_source_run_state("imessage")
        section = playbook.get("sections", {}).get(step_id, "")
        language = onboarding_language()
        if not section:
            section = "Follow the current iMessage playbook step and continue only through the zebra-source-onboarding helper CLI."
        if step_id == "choose_ingest_scope":
            if language == "ko":
                scope_instruction = textwrap.dedent('''
                사용자에게 아래 네 가지 선택지만 보여주세요:

                ```text
                iMessage 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 대화방 범위를 정해야 합니다.

                어떤 범위로 가져올까요?

                1. 최근 날짜 이후 업데이트된 대화방
                2. 특정 대화방
                3. 대화방 전체
                4. 지금은 iMessage 건너뛰기
                ```

                사용자가 1번을 고르면 날짜를 물어보고 `zebra-source-onboarding imessage choose-scope --scope updated-since --since YYYY-MM-DD`를 실행하세요.
                사용자가 2번을 고르면 아래 후보 목록에서 선택한 `chat_id`를 확인한 뒤 `zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"`를 실행하세요.
                사용자가 3번을 고르면 `zebra-source-onboarding imessage choose-scope --scope all-threads`를 실행하세요.
                사용자가 4번을 고르면 `zebra-source-onboarding imessage choose-scope --scope skip`을 실행하세요.

                사용자가 2번을 고를 때는 아래 후보 목록을 사용하세요. 표시 label과 `chat_id`를 보여주고, 선택된 row id를 `--chat-id`로 넘기세요.

                메시지 개수 slicing은 사용자 선택지로 노출하지 마세요. helper가 내부 bounded window를 run state와 최종 confirm plan에 기록합니다.
                ''').strip()
            elif language == "ja":
                scope_instruction = textwrap.dedent('''
                ユーザーには次の4つの選択肢だけを表示してください:

                ```text
                iMessageへのアクセス確認は完了しました。次にbrainへ保存する会話の範囲を決めます。

                どの範囲を取り込みますか？

                1. 最近の日付以降に更新された会話
                2. 特定の会話
                3. すべての会話
                4. 今回はiMessageをスキップ
                ```

                ユーザーが1番を選んだら日付を尋ね、`zebra-source-onboarding imessage choose-scope --scope updated-since --since YYYY-MM-DD`を実行してください。
                ユーザーが2番を選んだら下の候補一覧から選択された`chat_id`を確認し、`zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"`を実行してください。
                ユーザーが3番を選んだら`zebra-source-onboarding imessage choose-scope --scope all-threads`を実行してください。
                ユーザーが4番を選んだら`zebra-source-onboarding imessage choose-scope --scope skip`を実行してください。

                ユーザーが2番を選ぶ場合は下の候補一覧を使ってください。表示labelと`chat_id`を示し、選択されたrow idを`--chat-id`に渡してください。

                メッセージ件数によるslicingはユーザー選択肢として表示しないでください。helperが内部bounded windowをrun stateと最終confirm planへ記録します。
                ''').strip()
            else:
                scope_instruction = textwrap.dedent('''
                Present exactly these four choices to the user:

                ```text
                iMessage 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 대화방 범위를 정해야 합니다.

                어떤 범위로 가져올까요?

                1. 최근 날짜 이후 업데이트된 대화방
                2. 특정 대화방
                3. 대화방 전체
                4. 지금은 iMessage 건너뛰기
                ```

                If the user chooses option 1, ask for the date and run `zebra-source-onboarding imessage choose-scope --scope updated-since --since YYYY-MM-DD`.
                If the user chooses option 2, identify the selected conversation ID from the available iMessage data and run `zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"`.
                If the user chooses option 3, run `zebra-source-onboarding imessage choose-scope --scope all-threads`.
                If the user chooses option 4, run `zebra-source-onboarding imessage choose-scope --scope skip`.

                Use the candidate list below when the user chooses option 2. Show the label and chat_id, then run `zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"` with the selected row id.

                Do not expose message-count slicing as a user option. The helper records an internal bounded window in run state and the final confirm plan.
                ''').strip()
            section = section + "\\n\\n" + scope_instruction + "\\n\\n" + imessage_conversation_choices(limit=10)
        if step_id == "confirm_ingest_plan":
            section = section + "\\n\\n" + imessage_ingest_plan_summary(run_state)
        command_path = run_state.get("imsgCommandPath") or "not verified"
        access = run_state.get("accessStatus") or "not verified"
        smoke = run_state.get("smokeHistoryStatus") or "not run"
        artifact = run_state.get("artifactPath") or "not created"
        return textwrap.dedent(f'''
        Zebra Source Onboarding: iMessage is the active source.

        Playbook: {playbook.get("id", "imessage.imsg-cli")} {playbook.get("version", "v1")}
        Current step: `{step_id}`
        imsg command path: `{command_path}`
        Messages access status: `{access}`
        Smoke history status: `{smoke}`
        Current ingest scope: `{imessage_scope_summary(run_state)}`
        Current ingest artifact: `{artifact}`

        Boundary rules:
        - Work only this iMessage step. Do not start Notion, Obsidian, Gmail, or another source unless the helper prints that source as the next active source.
        - Smoke-read is read-only access verification. It is not completion and not ingest approval.
        - Actual ingest/write must stay within the user-approved conversation scope.
        - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
        - Do not store raw message bodies, large chat/history JSON, prompt bodies, or transcripts in Source Onboarding state.
        - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

        Playbook step instructions:

        {section}
        ''').strip()

    def notion_scope_prompt_text():
        language = onboarding_language()
        if language == "ko":
            return textwrap.dedent('''
            Notion에서 GBrain에 가져올 대상을 정해주세요.

            1. Page URL/ID 기준으로 현재 page만 가져오기
            2. Page URL/ID 기준으로 현재 page와 하위 page까지 가져오기
            3. Data source/database URL/ID 기준으로 pages/rows 전체 가져오기
            4. URL/ID를 모르면 Notion workspace 후보 찾기
            5. Notion workspace 전체 가져오기
            6. Notion 건너뛰기
            ''').strip()
        if language == "ja":
            return textwrap.dedent('''
            Notion から GBrain に取り込む対象を選んでください。

            1. Page URL/ID で現在の page だけを取り込む
            2. Page URL/ID で現在の page と下位 page を取り込む
            3. Data source/database URL/ID で pages/rows 全体を取り込む
            4. URL/ID が分からない場合は Notion workspace の候補を探す
            5. Notion workspace 全体を取り込む
            6. Notion をスキップする
            ''').strip()
        return textwrap.dedent('''
        Choose what Zebra should import from Notion into GBrain.

        1. Import only the current page by Page URL/ID
        2. Import the current page and child pages by Page URL/ID
        3. Import all pages/rows from a data source/database URL/ID
        4. Find candidates with Notion workspace search if you do not know the URL/ID
        5. Import the whole Notion workspace
        6. Skip Notion
        ''').strip()

    def notion_workspace_confirmation_text(run_state):
        language = onboarding_language()
        candidate_count = run_state.get("workspaceCandidateCount")
        candidate_text = str(candidate_count) if candidate_count is not None else "unknown"
        if language == "ko":
            return textwrap.dedent(f'''
            Notion workspace 전체 ingest는 범위가 클 수 있으므로 아직 ingest를 시작하지 않습니다.

            확인된 후보 수: `{candidate_text}`

            진행 전 안내:
            - 예상 시간: workspace 크기와 Notion API 응답 속도에 따라 오래 걸릴 수 있습니다.
            - 토큰/임베딩 비용 가능성: GBrain markdown artifact를 import/embedding할 때 비용이 발생할 수 있습니다.
            - 권한 누락 가능성: `ntn`이 접근할 수 없는 private page/data source는 일부 누락될 수 있습니다.
            - 민감 정보 가능성: private/sensitive page, people directory, attachment metadata가 포함될 수 있습니다.

            전체 workspace ingest를 계속하려면 `zebra-source-onboarding notion confirm-workspace --answer yes`를 실행하세요.
            취소하려면 `zebra-source-onboarding notion confirm-workspace --answer no`를 실행하세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            Notion workspace 全体の ingest は範囲が広くなる可能性があるため、まだ ingest は開始しません。

            確認済み候補数: `{candidate_text}`

            続行前の確認:
            - 想定時間: workspace の規模と Notion API の応答速度によって長くかかる場合があります。
            - トークン/embedding コストの可能性: GBrain markdown artifact を import/embedding するときにコストが発生する場合があります。
            - 権限不足の可能性: `ntn` がアクセスできない private page/data source は一部欠落する場合があります。
            - 機密情報の可能性: private/sensitive page, people directory, attachment metadata が含まれる場合があります。

            workspace 全体の ingest を続ける場合は `zebra-source-onboarding notion confirm-workspace --answer yes` を実行してください。
            キャンセルする場合は `zebra-source-onboarding notion confirm-workspace --answer no` を実行してください。
            ''').strip()
        return textwrap.dedent(f'''
        Whole-workspace Notion ingest can be broad, so Zebra has not started ingest yet.

        Confirmed candidate count: `{candidate_text}`

        Before continuing:
        - Expected duration: this can take a long time depending on workspace size and Notion API response speed.
        - Token/embedding cost possibility: importing/embedding the GBrain markdown artifact may incur cost.
        - Permission gaps: private pages/data sources that `ntn` cannot access may be omitted.
        - Sensitive information possibility: private/sensitive pages, people directory data, and attachment metadata may be included.

        To continue whole-workspace ingest, run `zebra-source-onboarding notion confirm-workspace --answer yes`.
        To cancel, run `zebra-source-onboarding notion confirm-workspace --answer no`.
        ''').strip()

    def notion_choose_scope_instruction(run_state):
        language = onboarding_language()
        candidates = run_state.get("searchCandidates") if isinstance(run_state.get("searchCandidates"), list) else []
        candidate_text = ""
        if candidates:
            lines = []
            for index, item in enumerate(candidates, start=1):
                if not isinstance(item, dict):
                    continue
                title = item.get("title") or "Untitled"
                kind = item.get("object") or item.get("kind") or "unknown"
                item_id = item.get("id") or "unknown"
                lines.append(f"{index}. {kind}: {title} ({item_id})")
            if lines:
                heading = "Notion workspace candidates:" if language == "en" else "Notion workspace 候補:" if language == "ja" else "Notion workspace 후보:"
                candidate_text = "\\n\\n" + heading + "\\n" + "\\n".join(lines)
        if language == "ko":
            return notion_scope_prompt_text() + candidate_text + "\\n\\n" + textwrap.dedent('''

            실행 명령:
            - 1번: `zebra-source-onboarding notion choose-scope --scope page --target "<page-url-or-id>"`
            - 2번: `zebra-source-onboarding notion choose-scope --scope page-subtree --target "<page-url-or-id>"`
            - 3번: `zebra-source-onboarding notion choose-scope --scope data-source --target "<data-source-or-database-url-or-id>"`
            - 4번: `zebra-source-onboarding notion choose-scope --scope workspace-search`
            - 5번: `zebra-source-onboarding notion choose-scope --scope workspace-all`
            - 6번: `zebra-source-onboarding notion choose-scope --scope skip`

            `workspace-search`는 웹 검색이 아니라 인증된 Notion workspace 내부 `ntn api v1/search page_size:=10` 후보 조회입니다.
            Smoke read는 target이 정해지면 helper가 자동 실행하므로 별도로 사용자에게 묻지 마세요.
            ''').strip()
        if language == "ja":
            return notion_scope_prompt_text() + candidate_text + "\\n\\n" + textwrap.dedent('''

            実行コマンド:
            - 1番: `zebra-source-onboarding notion choose-scope --scope page --target "<page-url-or-id>"`
            - 2番: `zebra-source-onboarding notion choose-scope --scope page-subtree --target "<page-url-or-id>"`
            - 3番: `zebra-source-onboarding notion choose-scope --scope data-source --target "<data-source-or-database-url-or-id>"`
            - 4番: `zebra-source-onboarding notion choose-scope --scope workspace-search`
            - 5番: `zebra-source-onboarding notion choose-scope --scope workspace-all`
            - 6番: `zebra-source-onboarding notion choose-scope --scope skip`

            `workspace-search` は web search ではなく、認証済み Notion workspace 内で `ntn api v1/search page_size:=10` を使って候補を取得します。
            Smoke read は target が決まると helper が自動実行するため、別途ユーザーに確認しないでください。
            ''').strip()
        return notion_scope_prompt_text() + candidate_text + "\\n\\n" + textwrap.dedent('''

        Commands:
        - Option 1: `zebra-source-onboarding notion choose-scope --scope page --target "<page-url-or-id>"`
        - Option 2: `zebra-source-onboarding notion choose-scope --scope page-subtree --target "<page-url-or-id>"`
        - Option 3: `zebra-source-onboarding notion choose-scope --scope data-source --target "<data-source-or-database-url-or-id>"`
        - Option 4: `zebra-source-onboarding notion choose-scope --scope workspace-search`
        - Option 5: `zebra-source-onboarding notion choose-scope --scope workspace-all`
        - Option 6: `zebra-source-onboarding notion choose-scope --scope skip`

        `workspace-search` is not web search. It searches the authenticated Notion workspace with `ntn api v1/search page_size:=10`.
        Do not ask the user for separate smoke-read approval; the helper runs smoke read automatically after a target is selected.
        ''').strip()

    def notion_step_instruction(step_id, run_state):
        language = onboarding_language()
        if step_id == "check_ntn_cli":
            return textwrap.dedent('''
            Work only the Notion `check_ntn_cli` step.

            Run:

            ```bash
            zebra-source-onboarding notion check-cli
            ```

            If `ntn` is missing, report the helper's compact attention reason `ntn_cli_missing` and tell the user the expected install path is the official `ntn` CLI. The default install command is:

            ```bash
            curl -fsSL https://ntn.dev | bash
            ```

            If that install path fails and `npm` is available, use this fallback:

            ```bash
            npm install --global ntn
            ```

            After installation, run `ntn --version` and authenticate with `ntn login`. Do not install anything unless the user explicitly asks.

            Continue only from the returned `nextPrompt`.
            ''').strip()
        if step_id == "choose_scope":
            return notion_choose_scope_instruction(run_state)
        if step_id == "confirm_workspace_ingest":
            return notion_workspace_confirmation_text(run_state)
        if step_id == "ingest_notion":
            if language == "ko":
                return "이제 `zebra-source-onboarding notion ingest`를 실행하세요. whole-workspace ingest가 아니거나 `workspaceConfirmed`가 true이면 smoke-read나 batch 확인을 다시 묻지 마세요."
            if language == "ja":
                return "`zebra-source-onboarding notion ingest` を実行してください。whole-workspace ingest でない場合、または `workspaceConfirmed` が true の場合は、smoke-read や batch 確認を再度ユーザーに求めないでください。"
            return "Run `zebra-source-onboarding notion ingest`. Do not ask for another smoke-read or batch confirmation unless this is whole-workspace ingest and `workspaceConfirmed` is not true."
        if step_id == "verify_readback":
            if language == "ko":
                return "`zebra-source-onboarding notion verify-readback`을 실행하고, 그 stdout에서 나온 다음 단계만 따르세요."
            if language == "ja":
                return "`zebra-source-onboarding notion verify-readback` を実行し、その stdout に出た次の手順だけに従ってください。"
            return "Run `zebra-source-onboarding notion verify-readback` and continue only from its stdout."
        if language == "ko":
            return "현재 Notion playbook step을 따르고 `zebra-source-onboarding` helper CLI를 통해서만 계속 진행하세요."
        if language == "ja":
            return "現在の Notion playbook step に従い、`zebra-source-onboarding` helper CLI だけで続行してください。"
        return "Follow the current Notion playbook step and continue only through the zebra-source-onboarding helper CLI."

    def notion_step_prompt(step_id, state, row):
        playbook = notion_playbook()
        run_state = load_source_run_state("notion")
        language = onboarding_language()
        section = notion_step_instruction(step_id, run_state)
        target = run_state.get("target") or "not selected"
        scope = run_state.get("scope") or "not selected"
        artifact = run_state.get("artifactPath") or "not created"
        if language == "ko":
            return textwrap.dedent(f'''
            Zebra Source Onboarding: Notion이 활성 source입니다.

            Playbook: {playbook.get("id", "notion.ntn-cli")} {playbook.get("version", "v1")}
            현재 단계: `{step_id}`
            현재 Notion 범위: `{scope}`
            현재 Notion target: `{target}`
            현재 ingest artifact: `{artifact}`

            경계 규칙:
            - 이 Notion 단계만 진행하세요. helper가 다른 source를 다음 active source로 출력하지 않는 한 iMessage, Gmail, Obsidian 또는 다른 source를 시작하지 마세요.
            - 공식 `ntn` CLI 경로를 사용하세요. 기본 인증은 `ntn login`이고, `ntn login --no-browser`는 headless fallback일 때만 사용합니다.
            - `source-onboarding-state.json`을 직접 편집하지 마세요. Source Onboarding state 쓰기는 helper CLI만 담당합니다.
            - prompt body, OAuth code, token, signed URL, credential-like query string을 저장하지 마세요.
            - Notion data source ingest는 GBrain용 markdown/page artifact 변환으로 다루고, native Notion database ingest로 가정하지 마세요.
            - helper stdout의 `nextPrompt`에서만 계속 진행하세요. `nextPromptPath`는 fallback/debug 파일로만 사용하세요.

            Playbook 단계 안내:

            {section}
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            Zebra Source Onboarding: Notion が現在のアクティブな source です。

            Playbook: {playbook.get("id", "notion.ntn-cli")} {playbook.get("version", "v1")}
            現在の step: `{step_id}`
            現在の Notion scope: `{scope}`
            現在の Notion target: `{target}`
            現在の ingest artifact: `{artifact}`

            境界ルール:
            - この Notion step だけを進めてください。helper が別の source を次の active source として出力しない限り、iMessage, Gmail, Obsidian, または他の source を開始しないでください。
            - 公式 `ntn` CLI を使ってください。基本認証は `ntn login` で、`ntn login --no-browser` は headless fallback の場合だけ使います。
            - `source-onboarding-state.json` を直接編集しないでください。Source Onboarding state の書き込みは helper CLI だけが行います。
            - prompt body, OAuth code, token, signed URL, credential-like query string を保存しないでください。
            - Notion data source ingest は GBrain 用の markdown/page artifact 変換として扱い、native Notion database ingest と仮定しないでください。
            - helper stdout の `nextPrompt` からだけ続行してください。`nextPromptPath` は fallback/debug file としてのみ使ってください。

            Playbook step の案内:

            {section}
            ''').strip()
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Notion is the active source.

        Playbook: {playbook.get("id", "notion.ntn-cli")} {playbook.get("version", "v1")}
        Current step: `{step_id}`
        Current Notion scope: `{scope}`
        Current Notion target: `{target}`
        Current ingest artifact: `{artifact}`

        Boundary rules:
        - Work only this Notion step. Do not start iMessage, Gmail, Obsidian, or another source unless the helper prints that source as the next active source.
        - Use the official `ntn` CLI path. Primary auth is `ntn login`; `ntn login --no-browser` is only the headless fallback.
        - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
        - Do not store prompt bodies, OAuth codes, tokens, signed URLs, or credential-like query strings.
        - Treat Notion data source ingest as markdown/page artifact conversion for GBrain, not native Notion database ingest.
        - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

        Playbook step instructions:

        {section}
        ''').strip()

    def apple_reminders_scope_summary(run_state):
        language = onboarding_language()
        scope = run_state.get("scope") or "not selected"
        if scope == "all-open":
            if language == "ko":
                return "모든 list의 open/incomplete reminders"
            if language == "ja":
                return "すべてのlistのopen/incomplete reminders"
            return "all open reminders"
        if scope == "one-list":
            list_name = str(run_state.get("list") or "not selected")
            if language == "ko":
                return "list `" + list_name + "`의 open/incomplete reminders"
            if language == "ja":
                return "list `" + list_name + "` のopen/incomplete reminders"
            return "open reminders from list `" + list_name + "`"
        if scope in {"today", "week", "overdue"}:
            return str(scope)
        if scope == "custom":
            parts = []
            lists = run_state.get("lists") if isinstance(run_state.get("lists"), list) else []
            if lists:
                parts.append("lists: " + ", ".join(str(item) for item in lists))
            status = run_state.get("status")
            if status:
                parts.append("status: " + str(status))
            due = run_state.get("dueWindow")
            if due:
                parts.append("due window: " + str(due))
            parts.append("completed included: " + str(bool(run_state.get("includeCompleted"))).lower())
            cap = run_state.get("itemCap")
            if cap is not None:
                parts.append("item cap: " + str(cap))
            return "custom (" + "; ".join(parts) + ")"
        if scope == "skip":
            if language == "ko":
                return "이번 Source Onboarding에서 Apple Reminders 건너뛰기"
            if language == "ja":
                return "このSource OnboardingではApple Remindersをスキップ"
            return "skip Apple Reminders for this Source Onboarding session"
        return str(scope)

    def apple_reminders_ingest_plan_summary(run_state):
        count = run_state.get("expectedCount")
        count_text = str(count) if count is not None else "unknown"
        fields = run_state.get("observedReminderFields") if isinstance(run_state.get("observedReminderFields"), list) else []
        fields_text = ", ".join(str(item) for item in fields) if fields else "unknown until approved read"
        artifact = run_state.get("plannedArtifactPath") or run_state.get("artifactPath") or "will be created under the selected brain repo sources directory"
        bounded = "bounded" if run_state.get("itemCap") is not None else "full approved scope"
        language = onboarding_language()
        if language == "ko":
            return textwrap.dedent(f'''
            선택된 Apple Reminders ingest plan입니다.

            - 선택한 범위: `{apple_reminders_scope_summary(run_state)}`
            - completed 포함 여부: `{str(bool(run_state.get("includeCompleted"))).lower()}`
            - full vs bounded: `{bounded}`
            - 예상 reminder 수: `{count_text}`
            - 저장할 필드: `{fields_text}`
            - unsupported fields: EventKit/remindctl 경로에서 sections, smart lists, tags, attachments, urgent/private flags는 보장하지 않습니다.
            - artifact path: `{artifact}`
            - readback plan: 생성된 artifact에서 `source: apple-reminders`와 `playbook: apple-reminders.remindctl.v1`를 확인합니다.
            - redaction policy: raw JSON dump는 저장하지 않고, 승인된 scope 안에서 remindctl이 실제 반환한 필드만 markdown으로 씁니다.

            ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding apple-reminders confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding apple-reminders confirm-plan --answer no`를 실행하세요.
            ''').strip()
        return textwrap.dedent(f'''
        Resolved Apple Reminders ingest plan:

        - Selected scope: `{apple_reminders_scope_summary(run_state)}`
        - Completed included: `{str(bool(run_state.get("includeCompleted"))).lower()}`
        - Full vs bounded: `{bounded}`
        - Expected reminder count: `{count_text}`
        - Fields to store: `{fields_text}`
        - Unsupported fields: sections, smart lists, tags, attachments, and urgent/private flags are not guaranteed through EventKit/remindctl.
        - Artifact path: `{artifact}`
        - Readback plan: require `source: apple-reminders` plus `playbook: apple-reminders.remindctl.v1` in the generated artifact.
        - Redaction policy: do not store a raw JSON dump; write only remindctl-returned fields from the approved scope as markdown.

        Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding apple-reminders confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding apple-reminders confirm-plan --answer no`.
        ''').strip()

    def apple_reminders_check_cli_instruction(language):
        if language == "ko":
            return textwrap.dedent('''
            Apple Reminders `check_remindctl_cli` 단계만 진행하세요.

            먼저 실행:

            ```bash
            zebra-source-onboarding apple-reminders check-cli
            ```

            `remindctl`이 없고 Homebrew도 없으면 Homebrew 설치 동의를 별도로 물으세요. 사용자가 yes라고 답하면:

            ```bash
            zebra-source-onboarding apple-reminders check-cli --homebrew-install-answer yes
            ```

            사용자가 no라고 답하면:

            ```bash
            zebra-source-onboarding apple-reminders check-cli --homebrew-install-answer no
            ```

            Homebrew가 있고 `remindctl`이 없으면 remindctl 설치 동의를 별도로 물으세요:

            ```text
            Apple Reminders ingest requires remindctl. Install it with Homebrew now? (yes/no)
            ```

            승인하면 `zebra-source-onboarding apple-reminders check-cli --remindctl-install-answer yes`를 실행하고, 거절하면 `--remindctl-install-answer no`를 실행하세요. Source build는 advanced fallback으로만 언급하세요.

            이후에는 helper stdout의 `nextPrompt`에서만 계속 진행하세요.
            ''').strip()
        return textwrap.dedent('''
        Work only the Apple Reminders `check_remindctl_cli` step.

        First run:

        ```bash
        zebra-source-onboarding apple-reminders check-cli
        ```

        If `remindctl` is missing and Homebrew is also missing, ask for Homebrew install consent as a separate yes/no choice. If the user says yes, run:

        ```bash
        zebra-source-onboarding apple-reminders check-cli --homebrew-install-answer yes
        ```

        If the user says no, run the same command with `--homebrew-install-answer no`.

        If Homebrew exists but `remindctl` is missing, ask this separate yes/no question:

        ```text
        Apple Reminders ingest requires remindctl. Install it with Homebrew now? (yes/no)
        ```

        If approved, run `zebra-source-onboarding apple-reminders check-cli --remindctl-install-answer yes`; if declined, run it with `--remindctl-install-answer no`. Mention source build only as an advanced fallback.

        Continue only from helper stdout `nextPrompt`.
        ''').strip()

    def apple_reminders_scope_choices_instruction(language):
        if language == "ko":
            return textwrap.dedent('''
            사용자에게 아래 다섯 가지 선택지만 보여주세요:

            ```text
            Apple Reminders 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 미리알림 범위를 정해야 합니다.

            어떤 범위로 가져올까요?

            1. 열려 있는 모든 미리알림
            2. 특정 list 하나
            3. 오늘 또는 이번 주
            4. 직접 설정
            5. 지금은 Apple Reminders 건너뛰기
            ```

            1번은 `zebra-source-onboarding apple-reminders choose-scope --scope all-open`를 실행하세요.
            2번은 list 이름을 확인한 뒤 `zebra-source-onboarding apple-reminders choose-scope --scope one-list --list "<list>"`를 실행하세요.
            3번은 사용자가 오늘을 고르면 `--scope today`, 이번 주를 고르면 `--scope week`로 실행하세요.
            4번은 completed 포함, overdue-only, 여러 list, completed 포함 전체, item cap/sample 같은 세부 조건을 확인한 뒤 `--scope custom`과 `--list`, `--include-completed yes`, `--status open|completed|all`, `--due-window overdue|today|week|all`, 필요한 경우 `--item-cap <n>`을 조합해 실행하세요.
            5번은 `zebra-source-onboarding apple-reminders choose-scope --scope skip`을 실행하세요.

            sample cap을 기본값처럼 만들지 마세요. 사용자가 bounded/sample ingest를 명시적으로 원할 때만 `--item-cap`을 사용하세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent('''
            ユーザーには次の5つの選択肢だけを表示してください:

            ```text
            Apple Remindersへのアクセス確認は完了しました。次にbrainへ保存するリマインダーの範囲を決めます。

            どの範囲を取り込みますか？

            1. 未完了のすべてのリマインダー
            2. 特定のlist 1つ
            3. 今日または今週
            4. カスタム
            5. 今回はApple Remindersをスキップ
            ```

            ユーザーが1番を選んだら`zebra-source-onboarding apple-reminders choose-scope --scope all-open`を実行してください。
            ユーザーが2番を選んだらlist名を確認し、`zebra-source-onboarding apple-reminders choose-scope --scope one-list --list "<list>"`を実行してください。
            ユーザーが3番を選んだら、今日なら`--scope today`、今週なら`--scope week`を実行してください。
            ユーザーが4番を選んだら、completedを含めるか、overdue-only、複数list、completedを含む全件、item cap/sampleなどの条件を確認し、`--scope custom`に`--list`、`--include-completed yes`、`--status open|completed|all`、`--due-window overdue|today|week|all`、必要なら`--item-cap <n>`を組み合わせて実行してください。
            ユーザーが5番を選んだら`zebra-source-onboarding apple-reminders choose-scope --scope skip`を実行してください。

            sample capをデフォルト扱いにしないでください。ユーザーがbounded/sample ingestを明示的に望む場合だけ`--item-cap`を使ってください。
            ''').strip()
        return textwrap.dedent('''
        Present exactly these five choices to the user:

        ```text
        Apple Reminders access is verified. Now choose which reminders to save into brain.

        Which scope should be ingested?

        1. All open reminders
        2. One list
        3. Today or this week
        4. Custom
        5. Skip Apple Reminders for now
        ```

        If the user chooses option 1, run `zebra-source-onboarding apple-reminders choose-scope --scope all-open`.
        If the user chooses option 2, confirm the list name and run `zebra-source-onboarding apple-reminders choose-scope --scope one-list --list "<list>"`.
        If the user chooses option 3, run `--scope today` for today or `--scope week` for this week.
        If the user chooses option 4, ask only for the custom details needed for completed reminders, overdue-only, multiple lists, all including completed, or item cap/sample choices. Then run `--scope custom` with flags such as `--list`, `--include-completed yes`, `--status open|completed|all`, `--due-window overdue|today|week|all`, and optional `--item-cap <n>`.
        If the user chooses option 5, run `zebra-source-onboarding apple-reminders choose-scope --scope skip`.

        Do not make a sample cap the default. Use `--item-cap` only when the user explicitly wants a bounded/sample ingest.
        ''').strip()

    def apple_reminders_step_prompt(step_id, state, row):
        playbook = apple_reminders_playbook()
        run_state = load_source_run_state("apple-reminders")
        section = playbook.get("sections", {}).get(step_id, "")
        language = onboarding_language()
        if not section:
            section = "Follow the current Apple Reminders playbook step and continue only through the zebra-source-onboarding helper CLI."
        if step_id == "check_remindctl_cli":
            section = apple_reminders_check_cli_instruction(language)
        if step_id == "check_reminders_permission":
            section = section + "\\n\\n" + textwrap.dedent('''
            Permission flow is status -> doctor --for-agent -> authorize -> final status. The macOS Reminders prompt may belong to the runtime process executing remindctl, such as Terminal, OpenClaw node/agent, or Zebra runtime. If blocked, ask the user to allow that runtime in System Settings > Privacy & Security > Reminders.
            ''').strip()
        if step_id == "choose_ingest_scope":
            section = apple_reminders_scope_choices_instruction(language)
        if step_id == "confirm_ingest_plan":
            section = section + "\\n\\n" + apple_reminders_ingest_plan_summary(run_state)
        command_path = run_state.get("remindctlCommandPath") or "not verified"
        permission = run_state.get("permissionStatus") or "not verified"
        smoke = run_state.get("smokeStatus") or "not run"
        artifact = run_state.get("artifactPath") or "not created"
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Apple Reminders is the active source.

        Playbook: {playbook.get("id", "apple-reminders.remindctl")} {playbook.get("version", "v1")}
        Current step: `{step_id}`
        remindctl command path: `{command_path}`
        Reminders permission status: `{permission}`
        Smoke status: `{smoke}`
        Current ingest scope: `{apple_reminders_scope_summary(run_state)}`
        Current ingest artifact: `{artifact}`

        Boundary rules:
        - Work only this Apple Reminders step. Do not start Notion, Obsidian, iMessage, Gmail, Apple Notes, or another source unless the helper prints that source as the next active source.
        - Use the `remindctl` CLI. Do not read Reminders databases directly and do not invent unsupported fields.
        - Homebrew install consent and remindctl install consent are separate user choices and must be recorded through the helper command flags.
        - Smoke-read is read-only access verification. It is not completion and not ingest approval.
        - Actual ingest/write must stay within the user-approved reminders scope.
        - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
        - Do not store raw reminder JSON, large reminder lists, prompt bodies, or transcripts in Source Onboarding state.
        - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

        Playbook step instructions:

        {section}
        ''').strip()

    def apple_notes_scope_summary(run_state):
        language = onboarding_language()
        scope = run_state.get("scope") or "not selected"
        if scope == "folder":
            folder = str(run_state.get("folder") or "not selected")
            if language == "ko":
                return "폴더: " + folder
            if language == "ja":
                return "フォルダ: " + folder
            return "folder: " + folder
        if scope == "search":
            query = str(run_state.get("query") or "not selected")
            if language == "ko":
                return "검색어: " + query
            if language == "ja":
                return "検索語: " + query
            return "search query: " + query
        if scope == "selected-notes":
            note_ids = run_state.get("selectedNoteIDs") if isinstance(run_state.get("selectedNoteIDs"), list) else []
            return "selected note ids: " + (", ".join(str(item) for item in note_ids) if note_ids else "none")
        if scope == "sample":
            if language == "ko":
                return "작은 샘플: 최대 3개 노트"
            if language == "ja":
                return "小さなサンプル: 最大3件のノート"
            return "small sample: up to 3 notes"
        if scope == "skip":
            if language == "ko":
                return "이번 Source Onboarding에서 Apple Notes 건너뛰기"
            if language == "ja":
                return "このSource OnboardingではApple Notesをスキップ"
            return "skip Apple Notes for this Source Onboarding session"
        return str(scope)

    def apple_notes_ingest_plan_summary(run_state):
        count = run_state.get("estimatedNoteCount")
        count_text = str(count) if count is not None else "unknown"
        language = onboarding_language()
        if language == "ko":
            return textwrap.dedent(f'''
            선택된 Apple Notes ingest plan입니다.

            - 선택한 범위: `{apple_notes_scope_summary(run_state)}`
            - 예상 노트 수: `{count_text}`
            - 민감정보 안내: 승인된 범위에는 개인 메모, 회사 메모, 링크, 사람 이름, 계정 정보처럼 민감할 수 있는 note body가 저장될 수 있습니다.
            - Ingest 방식: `memo` CLI로 승인된 노트만 읽어 선택된 brain repo의 `sources/` 아래 markdown artifact를 작성합니다.
            - 검증 계획: 생성된 Apple Notes source artifact를 다시 읽고 `source: apple-notes`와 `playbook: apple-notes.memo-cli.v1`를 확인합니다.

            ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding apple-notes confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding apple-notes confirm-plan --answer no`를 실행하세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            選択されたApple Notes ingest planです。

            - 選択した範囲: `{apple_notes_scope_summary(run_state)}`
            - 推定ノート数: `{count_text}`
            - 機微情報の注意: 承認された範囲には個人メモ、仕事メモ、リンク、人名、アカウント情報など機微になり得るnote bodyが保存される可能性があります。
            - Ingest方式: `memo` CLIで承認済みノートだけを読み、選択されたbrain repoの`sources/`下にmarkdown artifactを書き込みます。
            - 検証計画: 生成されたApple Notes source artifactを読み戻し、`source: apple-notes`と`playbook: apple-notes.memo-cli.v1`を確認します。

            ingestを実行する前にユーザーから明示的な承認を得てください。承認されたら`zebra-source-onboarding apple-notes confirm-plan --answer yes`を実行し、承認されなければ`zebra-source-onboarding apple-notes confirm-plan --answer no`を実行してください。
            ''').strip()
        return textwrap.dedent(f'''
        Resolved Apple Notes ingest plan:

        - Selected scope: `{apple_notes_scope_summary(run_state)}`
        - Estimated note count: `{count_text}`
        - Sensitive data notice: approved scope may store note bodies containing personal notes, work notes, links, names, or account-like information.
        - Ingest mode: read only approved notes with the `memo` CLI and write a markdown artifact under the selected brain repo's `sources/` directory.
        - Verification plan: read back the generated Apple Notes source artifact and require `source: apple-notes` plus `playbook: apple-notes.memo-cli.v1`.

        Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding apple-notes confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding apple-notes confirm-plan --answer no`.
        ''').strip()

    def apple_notes_check_memo_cli_instruction(language):
        if language == "ko":
            return textwrap.dedent('''
            Apple Notes `check_memo_cli` 단계만 진행하세요.

            먼저 실행:

            ```bash
            zebra-source-onboarding apple-notes check-cli
            ```

            `memo`가 없으면 helper가 반환한 compact attention reason `memo_cli_missing`을 보고하고, Apple Notes ingest에는 `memo` CLI가 필요하다고 설명하세요. Homebrew 설치 명령은 아래입니다:

            ```bash
            brew tap antoniorodr/memo && brew install antoniorodr/memo/memo
            ```

            설치하기 전에 사용자에게 아래 yes/no 질문을 명시적으로 하세요:

            ```text
            Apple Notes ingest에는 memo CLI가 필요합니다. Homebrew로 지금 설치할까요? (yes/no)
            ```

            사용자가 명시적으로 yes라고 답하기 전에는 아무것도 설치하지 마세요.

            이후에는 helper stdout의 `nextPrompt`에서만 계속 진행하세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent('''
            Apple Notes の `check_memo_cli` step だけを進めてください。

            まず実行:

            ```bash
            zebra-source-onboarding apple-notes check-cli
            ```

            `memo` が見つからない場合は、helper が返した compact attention reason `memo_cli_missing` を報告し、Apple Notes ingest には `memo` CLI が必要だと説明してください。Homebrew のインストールコマンドは次のとおりです:

            ```bash
            brew tap antoniorodr/memo && brew install antoniorodr/memo/memo
            ```

            インストール前に、ユーザーへ次の yes/no 質問を明示的にしてください:

            ```text
            Apple Notes ingest には memo CLI が必要です。Homebrew で今インストールしますか？ (yes/no)
            ```

            ユーザーが明示的に yes と答えるまで、何もインストールしないでください。

            以後は helper stdout の `nextPrompt` だけに従って続行してください。
            ''').strip()
        return textwrap.dedent('''
        Work only the Apple Notes `check_memo_cli` step.

        Run:

        ```bash
        zebra-source-onboarding apple-notes check-cli
        ```

        If `memo` is missing, report the helper's compact attention reason `memo_cli_missing` and tell the user Apple Notes ingest requires the `memo` CLI. Show this Homebrew install command:

        ```bash
        brew tap antoniorodr/memo && brew install antoniorodr/memo/memo
        ```

        Then ask an explicit yes/no question before installing:

        ```text
        Apple Notes ingest requires the memo CLI. Install it now with Homebrew? (yes/no)
        ```

        Do not install anything unless the user explicitly answers yes.

        Continue only from the returned `nextPrompt`.
        ''').strip()

    def apple_notes_step_prompt(step_id, state, row):
        playbook = apple_notes_playbook()
        run_state = load_source_run_state("apple-notes")
        section = playbook.get("sections", {}).get(step_id, "")
        language = onboarding_language()
        if not section:
            section = "Follow the current Apple Notes playbook step and continue only through the zebra-source-onboarding helper CLI."
        if step_id == "check_memo_cli":
            section = apple_notes_check_memo_cli_instruction(language)
        if step_id == "choose_ingest_scope":
            if language == "ko":
                section = section + "\\n\\n" + textwrap.dedent('''
                사용자에게 아래 다섯 가지 선택지만 보여주세요:

                ```text
                Apple Notes 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 메모 범위를 정해야 합니다.

                어떤 범위로 가져올까요?

                1. 특정 폴더
                2. 검색어로 찾은 메모
                3. 특정 note 번호
                4. 작은 샘플
                5. 지금은 Apple Notes 건너뛰기
                ```

                1번은 `zebra-source-onboarding apple-notes choose-scope --scope folder --folder "<folder>"`를 실행하세요.
                2번은 `zebra-source-onboarding apple-notes choose-scope --scope search --query "<query>"`를 실행하세요.
                3번은 `zebra-source-onboarding apple-notes choose-scope --scope selected-notes --note-id <memo-list-number>`를 실행하세요. note id는 `memo notes` 목록의 `NNN.` 값을 그대로 사용합니다.
                4번은 `zebra-source-onboarding apple-notes choose-scope --scope sample`을 실행하세요.
                5번은 `zebra-source-onboarding apple-notes choose-scope --scope skip`을 실행하세요.
                ''').strip()
            else:
                section = section + "\\n\\n" + textwrap.dedent('''
                Present exactly these five choices to the user:

                1. A specific folder
                2. Notes matching a search query
                3. Specific note numbers
                4. A small sample
                5. Skip Apple Notes for now

                Commands:
                - Folder: `zebra-source-onboarding apple-notes choose-scope --scope folder --folder "<folder>"`
                - Search: `zebra-source-onboarding apple-notes choose-scope --scope search --query "<query>"`
                - Selected notes: `zebra-source-onboarding apple-notes choose-scope --scope selected-notes --note-id <memo-list-number>`
                - Sample: `zebra-source-onboarding apple-notes choose-scope --scope sample`
                - Skip: `zebra-source-onboarding apple-notes choose-scope --scope skip`

                Note IDs are the global `NNN.` values shown by `memo notes`, not a local row index.
                ''').strip()
        if step_id == "confirm_ingest_plan":
            section = section + "\\n\\n" + apple_notes_ingest_plan_summary(run_state)
        command_path = run_state.get("memoCommandPath") or "not verified"
        access = run_state.get("accessStatus") or "not verified"
        smoke = run_state.get("smokeListStatus") or "not run"
        artifact = run_state.get("artifactPath") or "not created"
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Apple Notes is the active source.

        Playbook: {playbook.get("id", "apple-notes.memo-cli")} {playbook.get("version", "v1")}
        Current step: `{step_id}`
        memo command path: `{command_path}`
        Notes Automation/access status: `{access}`
        Smoke list status: `{smoke}`
        Current ingest scope: `{apple_notes_scope_summary(run_state)}`
        Current ingest artifact: `{artifact}`

        Boundary rules:
        - Work only this Apple Notes step. Do not start Notion, Obsidian, iMessage, Gmail, or another source unless the helper prints that source as the next active source.
        - Use the `memo` CLI. Do not read Apple Notes databases directly and do not implement custom AppleScript in this runner.
        - Smoke-read is read-only access verification. It is not completion and not ingest approval.
        - Actual ingest/write must stay within the user-approved Notes scope.
        - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
        - Do not store note bodies, large note lists, prompt bodies, or transcripts in Source Onboarding state.
        - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

        Playbook step instructions:

        {section}
        ''').strip()

    def source_completion_report_prompt(source_id, row):
        display = row.get("displayName") or source_display_name(source_id)
        summary_text = row.get("resultSummary") or (display + " Source Onboarding is ready to report complete.")
        language = onboarding_language()
        if language == "ko":
            return textwrap.dedent(f'''
            Zebra Source Onboarding: {display} 완료 보고가 필요합니다.

            # Current Source Step
            source: {source_id}
            display: {display}
            step: complete

            # Boundary
            아직 다음 source로 넘어가지 마세요.
            Source Onboarding state는 helper CLI만 변경합니다.

            # User-Facing Output
            아직 사용자에게 {display} 완료 메시지를 보내지 마세요.
            사용자에게 보여줄 완료 결과 block은 report 명령 stdout에서 생성됩니다.
            지금 다음 action은 user-facing message가 아니라 report command입니다.

            # Required Next Action
            아래 명령을 실행하세요:

            ```bash
            zebra-source-onboarding report --status completed --source {source_id}
            ```

            # Continuation
            report 명령이 성공하면 그 stdout의 `nextPrompt`만 따르세요.
            report stdout이 완료 결과와 다음 source prompt를 함께 줄 수 있습니다.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            Zebra Source Onboarding: {display} の完了報告が必要です。

            # Current Source Step
            source: {source_id}
            display: {display}
            step: complete

            # Boundary
            まだ次の source に進まないでください。
            Source Onboarding state は helper CLI だけが変更します。

            # User-Facing Output
            まだ {display} の完了メッセージをユーザーに送らないでください。
            ユーザーに表示する完了結果 block は report command の stdout で生成されます。
            次の action は user-facing message ではなく report command です。

            # Required Next Action
            次のコマンドを実行してください:

            ```bash
            zebra-source-onboarding report --status completed --source {source_id}
            ```

            # Continuation
            report command が成功したら、その stdout の `nextPrompt` だけに従ってください。
            report stdout は完了結果と次の source prompt を一緒に返すことがあります。
            ''').strip()
        return textwrap.dedent(f'''
        Zebra Source Onboarding: {display} completion report is required.

        # Current Source Step
        source: {source_id}
        display: {display}
        step: complete

        # Boundary
        Do not move to the next source yet.
        Source Onboarding state is changed only through the helper CLI.

        # User-Facing Output
        Do not send a user-facing {display} completion message yet.
        The completion result block that should be shown to the user will be produced by the report command stdout.
        Your next action is not a user-facing message. Your next action is the report command.

        # Required Next Action
        Run exactly:

        ```bash
        zebra-source-onboarding report --status completed --source {source_id}
        ```

        # Continuation
        After the report succeeds, continue only from its stdout `nextPrompt`.
        The report stdout may include both the completed source result and the next source prompt.
        ''').strip()

    def compact_completion_value(value, limit=180):
        text = str(value or "").strip()
        text = " ".join(text.split())
        if len(text) > limit:
            return text[: limit - 3].rstrip() + "..."
        return text

    def source_completion_detail_lines(source_id, row, run_state, summary_text):
        lines = []
        summary = compact_completion_value(summary_text or run_state.get("completionSummary") or row.get("resultSummary"))
        if summary:
            lines.append("- Result: " + summary)
        artifact = compact_completion_value(run_state.get("artifactPath"))
        if artifact:
            lines.append("- Artifact: `" + artifact + "`")
        readback = compact_completion_value(run_state.get("readbackStatus"))
        if readback:
            lines.append("- Readback: " + readback)
        verified_at = compact_completion_value(run_state.get("verifiedAt"))
        if verified_at:
            lines.append("- Verified at: " + verified_at)

        if source_id == "notion":
            scope = compact_completion_value(run_state.get("scope"))
            target = compact_completion_value(run_state.get("target"))
            target_id = compact_completion_value(run_state.get("targetID"))
            if scope:
                lines.append("- Scope: " + scope)
            if target:
                lines.append("- Target: `" + target + "`")
            if target_id and target_id != target:
                lines.append("- Target ID: `" + target_id + "`")
            results = run_state.get("ingestResults") if isinstance(run_state.get("ingestResults"), list) else []
            labels = [
                compact_completion_value(item.get("label"), limit=80)
                for item in results
                if isinstance(item, dict) and item.get("ok") and item.get("label")
            ]
            if labels:
                lines.append("- Verified Notion fetches: " + ", ".join(labels[:4]))
        elif source_id == "obsidian":
            vault = compact_completion_value(run_state.get("vaultPath"))
            count = run_state.get("ingestedFileCount")
            if vault:
                lines.append("- Vault: `" + vault + "`")
            if count is not None:
                lines.append("- Markdown files ingested: " + str(count))
        elif source_id == "imessage":
            scope_summary = compact_completion_value(imessage_scope_summary(run_state))
            count = run_state.get("ingestedThreadCount")
            if scope_summary:
                lines.append("- Scope: " + scope_summary)
            if count is not None:
                lines.append("- Conversations ingested: " + str(count))
        elif source_id == "apple-notes":
            scope_summary = compact_completion_value(apple_notes_scope_summary(run_state))
            count = run_state.get("ingestedNoteCount")
            if scope_summary:
                lines.append("- Scope: " + scope_summary)
            if count is not None:
                lines.append("- Notes ingested: " + str(count))
        elif source_id == "apple-reminders":
            scope_summary = compact_completion_value(apple_reminders_scope_summary(run_state))
            count = run_state.get("ingestedReminderCount")
            if scope_summary:
                lines.append("- Scope: " + scope_summary)
            if count is not None:
                lines.append("- Reminders ingested: " + str(count))
        elif source_id == "agent-memory":
            scope_summary = compact_completion_value(run_state.get("scopeSummary"))
            count = run_state.get("ingestedUnitCount")
            if scope_summary:
                lines.append("- Scope: " + scope_summary)
            if count is not None:
                lines.append("- Memory/knowledge files ingested: " + str(count))
        elif source_id == "gmail":
            service = compact_completion_value(run_state.get("service") or run_state.get("completionService"))
            if service:
                lines.append("- Verified service: " + service)

        seen = set()
        unique = []
        for line in lines:
            if line and line not in seen:
                seen.add(line)
                unique.append(line)
        return unique[:8]

    def source_completion_result_block(source_id, summary_text, detail_lines=None):
        display = source_display_name(source_id)
        language = onboarding_language()
        if language == "ko":
            heading = display + " Source Onboarding이 완료됐습니다."
        elif language == "ja":
            heading = display + " Source Onboarding が完了しました。"
        else:
            heading = display + " Source Onboarding is complete."
        lines = [heading, ""]
        details = detail_lines if isinstance(detail_lines, list) and detail_lines else ["- Result: " + str(summary_text)]
        lines.extend(str(item) for item in details)
        return "\\n".join(lines).strip()

    def source_completion_handoff_prompt(source_id, summary_text, detail_lines=None, has_next_source=False, next_prompt=None):
        language = onboarding_language()
        completion_block = source_completion_result_block(source_id, summary_text, detail_lines)
        if has_next_source:
            next_prompt = (next_prompt or "").strip()
            if language == "ko":
                return textwrap.dedent(f'''
                # Completed Source Result
                {completion_block}

                # Continuation Contract
                - 다음 source command를 실행하기 전에 반드시 위 Completed Source Result를 사용자에게 먼저 보여주세요.
                - 짧은 진행상황 업데이트나 commentary는 이 요구사항을 충족하지 않습니다.
                - 사용자에게 계속 진행할지 묻지 마세요.
                - helper stdout `nextPrompt`만 따라 다음 source를 계속 진행하세요.
                - 완료 결과를 보여준 뒤에는 아래 Next Source Prompt를 그대로 진행하세요.

                # Next Source Prompt
                {next_prompt}
                ''').strip()
            if language == "ja":
                return textwrap.dedent(f'''
                # Completed Source Result
                {completion_block}

                # Continuation Contract
                - 次の source command を実行する前に、必ず上の Completed Source Result を先にユーザーへ表示してください。
                - 短い進捗更新や commentary だけでは、この要件を満たしません。
                - ユーザーに続行許可を求めないでください。
                - helper stdout の `nextPrompt` だけに従って次の source を続行してください。
                - 完了結果を表示した後は、下の Next Source Prompt をそのまま進めてください。

                # Next Source Prompt
                {next_prompt}
                ''').strip()
            return textwrap.dedent(f'''
            # Completed Source Result
            {completion_block}

            # Continuation Contract
            - Before running any command from the Next Source Prompt, send a user-facing message that includes the Completed Source Result above.
            - Do not treat a brief progress update or commentary as satisfying this requirement.
            - Do not ask the user for permission to continue.
            - Continue only from helper stdout `nextPrompt`.
            - After sending that completed result to the user, continue with the Next Source Prompt below.

            # Next Source Prompt
            {next_prompt}
            ''').strip()
        if language == "ko":
            return textwrap.dedent(f'''
            사용자에게 아래 완료 결과를 반드시 먼저 그대로 전달하세요.
            완료 결과를 생략하거나, 작업 중 상태 업데이트 한 줄로 대체하지 마세요.
            사용자에게 진행 여부를 묻지 마세요.

            ```text
            {completion_block}
            ```

            위 완료 결과를 사용자에게 전달한 뒤, 선택된 모든 Source Onboarding이 완료됐다고 명확히 말하고 멈추세요.
            다음 source가 없으므로 추가 helper 명령을 실행하지 마세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            まず、次の完了結果を必ずそのままユーザーに伝えてください。
            省略したり、短い進捗更新だけで置き換えたりしないでください。
            ユーザーに進行許可を求めないでください。

            ```text
            {completion_block}
            ```

            その完了結果をユーザーに伝えたあと、選択されたすべての Source Onboarding が完了したことを明確に伝えて停止してください。
            次の source はないため、追加の helper コマンドは実行しないでください。
            ''').strip()
        return textwrap.dedent(f'''
        You must first show the user the exact completion result below.
        Do not omit it or replace it with a brief progress update.
        Do not ask the user for permission to continue.

        ```text
        {completion_block}
        ```

        After showing that completion result, clearly tell the user that all selected Source Onboarding sources are complete, then stop.
        There is no next source, so do not run another helper command.
        ''').strip()

    def agent_memory_unit_summary(units):
        by_agent = {}
        for unit in units:
            by_agent.setdefault(unit["agent"], {
                "displayName": unit["displayName"],
                "count": 0,
            })
            by_agent[unit["agent"]]["count"] += 1
        parts = []
        for _, info in by_agent.items():
            parts.append(info["displayName"] + " " + str(info["count"]) + " file(s)")
        return ", ".join(parts) if parts else "none"

    def agent_memory_step_prompt(step_id, state, row):
        run_state = load_source_run_state("agent-memory")
        units = agent_memory_importable_units()
        found_summary = agent_memory_unit_summary(units)
        scope = run_state.get("scope") or "not selected"
        artifact = run_state.get("artifactPath") or "not created"
        if step_id == "review_found_agents":
            instruction = textwrap.dedent('''
            Show the user the existing agent memory/knowledge candidates that Zebra found and ask which scope to import.

            Present only these choices:

            1. Import all found agent memory/knowledge files
            2. Import a small sample
            3. Skip existing agent memory for now

            If the user chooses 1, run `zebra-source-onboarding agent-memory choose-scope --scope all`.
            If the user chooses 2, run `zebra-source-onboarding agent-memory choose-scope --scope sample`.
            If the user chooses 3, run `zebra-source-onboarding agent-memory choose-scope --scope skip`.
            ''').strip()
        elif step_id == "choose_ingest_scope":
            instruction = "Ask the user to choose all, sample, or skip, then run the matching `zebra-source-onboarding agent-memory choose-scope` command."
        elif step_id == "confirm_ingest_plan":
            instruction = textwrap.dedent(f'''
            Summarize this ingest plan and ask for explicit approval.

            - Selected scope: `{scope}`
            - Found files: `{found_summary}`
            - Artifact path: `{artifact}`

            If approved, run `zebra-source-onboarding agent-memory confirm-plan --answer yes`.
            If not approved, run `zebra-source-onboarding agent-memory confirm-plan --answer no`.
            ''').strip()
        elif step_id == "ingest_memory":
            instruction = "Run `zebra-source-onboarding agent-memory ingest`, then continue only from helper stdout."
        elif step_id == "verify_readback":
            instruction = "Run `zebra-source-onboarding agent-memory verify-readback`, then continue only from helper stdout."
        else:
            instruction = "Existing agent memory Source Onboarding is complete. Run the completion report command when prompted."
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Existing agent memory is the active source.

        Playbook: agent-memory.local-files v1
        Current step: `{step_id}`
        Found importable files: `{found_summary}`
        Current ingest scope: `{scope}`
        Current ingest artifact: `{artifact}`

        Boundary rules:
        - Work only this existing agent memory step. Do not start another source unless the helper prints that source as the next active source.
        - Use the zebra-source-onboarding helper as the only Source Onboarding state write path.
        - Do not edit `source-onboarding-state.json` directly.
        - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

        Step instructions:

        {instruction}
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
        elif source_id == "imessage":
            playbook = imessage_playbook()
            prompt = imessage_step_prompt(step_id, state, row)
        elif source_id == "notion":
            playbook = notion_playbook()
            prompt = notion_step_prompt(step_id, state, row)
        elif source_id == "apple-notes":
            playbook = apple_notes_playbook()
            prompt = apple_notes_step_prompt(step_id, state, row)
        elif source_id == "apple-reminders":
            playbook = apple_reminders_playbook()
            prompt = apple_reminders_step_prompt(step_id, state, row)
        elif source_id == "agent-memory":
            playbook = agent_memory_playbook()
            prompt = agent_memory_step_prompt(step_id, state, row)
        elif is_fallback_source_row(row):
            playbook = fallback_playbook
            prompt = fallback_step_prompt(source_id, step_id, state, row)
        else:
            return {}
        if step_id == "complete":
            prompt = source_completion_report_prompt(source_id, row)
        path = write_source_next_prompt_file(source_id, step_id, prompt)
        return {
            "nextSourceID": source_id,
            "nextPlaybookID": playbook["id"],
            "nextPlaybookVersion": playbook["version"],
            "nextPlaybookStepID": step_id,
            "nextPrompt": prompt,
            "nextPromptPath": path,
        }

    def fallback_attention_prompt_suffix(source_id, step_id, display, row):
        if row.get("status") != "attention":
            return ""
        if row.get("playbookStepID") != step_id:
            return ""
        reason = str(row.get("attentionReason") or "").strip()
        if not reason:
            return ""

        def reason_body(prefix):
            body = reason[len(prefix):].strip() if reason.startswith(prefix) else reason
            return compact_completion_value(body or reason, limit=240)

        language = onboarding_language()
        if reason.startswith("blocked:"):
            blocker = reason_body("blocked:")
            skip_summary = "user chose to skip " + display + " during this Source Onboarding run"
            if language == "ko":
                return textwrap.dedent(f'''

                # Blocked Recovery Prompt
                `{display}`는 여기까지 확인했지만 현재 조건으로는 더 진행할 수 없습니다.

                막힌 이유:
                - {blocker}

                계속하려면 필요한 export file, permission, CLI auth, readable file, 또는 access method를 사용자가 제공해야 합니다.
                사용자에게 필요한 조치를 제공해서 계속할지, 아니면 이번 Source Onboarding run에서 이 source를 건너뛸지 물어보세요.

                사용자가 계속하겠다고 하면 필요한 조치를 기다린 뒤 같은 source/step을 재시도하세요.
                사용자가 건너뛰겠다고 하면 아래 명령으로 이 source를 닫으세요:

                ```bash
                zebra-source-onboarding fallback report --source {source_id} --step {step_id} --status skipped --summary "{skip_summary}"
                ```
                ''').rstrip()
            if language == "ja":
                return textwrap.dedent(f'''

                # Blocked Recovery Prompt
                `{display}` はここまで確認しましたが、現在の条件ではこれ以上進めません。

                ブロック理由:
                - {blocker}

                続行するには、必要な export file、permission、CLI auth、readable file、または access method をユーザーが提供する必要があります。
                必要な対応を提供して続行するか、この Source Onboarding run ではこの source をスキップするかをユーザーに尋ねてください。

                ユーザーが続行を選んだら、必要な対応を待って同じ source/step を再試行してください。
                ユーザーがスキップを選んだら、次のコマンドでこの source を閉じてください:

                ```bash
                zebra-source-onboarding fallback report --source {source_id} --step {step_id} --status skipped --summary "{skip_summary}"
                ```
                ''').rstrip()
            return textwrap.dedent(f'''

            # Blocked Recovery Prompt
            `{display}` has been checked as far as possible, but the current conditions leave no currently viable next step.

            Blocked reason:
            - {blocker}

            Continuing requires the user to provide the missing export file, permission, CLI auth, readable file, or access method.
            Ask the user whether they want to provide the needed action and continue, or skip this source for this Source Onboarding run.

            If the user chooses to continue, wait for the missing prerequisite and retry this same source/step.
            If the user chooses to skip, close this source with:

            ```bash
            zebra-source-onboarding fallback report --source {source_id} --step {step_id} --status skipped --summary "{skip_summary}"
            ```
            ''').rstrip()

        if reason.startswith("waiting:"):
            action = reason_body("waiting:")
            if language == "ko":
                return textwrap.dedent(f'''

                # Waiting Prompt
                `{display}`는 사용자 조치가 필요해서 대기 중입니다.

                필요한 조치:
                - {action}

                사용자에게 위 조치를 안내하고, 조치가 준비되면 같은 source/step을 재시도하세요.
                이 상태를 no viable path 또는 terminal blocked로 설명하지 마세요.
                ''').rstrip()
            if language == "ja":
                return textwrap.dedent(f'''

                # Waiting Prompt
                `{display}` はユーザー対応が必要なため待機中です。

                必要な対応:
                - {action}

                ユーザーに上の対応を案内し、対応が準備できたら同じ source/step を再試行してください。
                この状態を no viable path や terminal blocked として説明しないでください。
                ''').rstrip()
            return textwrap.dedent(f'''

            # Waiting Prompt
            `{display}` is waiting on user action.

            Needed action:
            - {action}

            Tell the user the needed action, then retry this same source/step once it is available.
            Do not describe this as no viable path or terminal blocked.
            ''').rstrip()

        return ""

    def fallback_step_prompt(source_id, step_id, state, row):
        progress = ensure_progress(state)
        record = uncataloged_record_for(progress, source_id)
        display = row.get("displayName") or record.get("displayName") or record.get("rawValue") or source_id
        run_state = load_source_run_state(source_id)
        last_summary = run_state.get("lastSummary") or "not recorded"
        gbrain_artifact = run_state.get("gbrainArtifact") or {}
        artifact_ref = gbrain_artifact.get("basename") if isinstance(gbrain_artifact, dict) else None
        if step_id == "classify_source":
            instruction = textwrap.dedent(f'''
            Classify `{display}` as one or more of: app, web service, file/export, CLI, API, or manual upload.
            Do not ingest yet. Report only a compact classification:
            `zebra-source-onboarding fallback report --source {source_id} --step classify_source --status completed --summary "<category and confidence>"`
            ''').strip()
        elif step_id == "research_access_paths":
            instruction = textwrap.dedent(f'''
            Research viable read paths for `{display}` using local app/CLI/config checks, official docs, or user-provided export information.
            Do not store raw source bodies in Source Onboarding state. Report compact findings:
            `zebra-source-onboarding fallback report --source {source_id} --step research_access_paths --status completed --summary "<access paths and rejected paths>"`
            ''').strip()
        elif step_id == "choose_strategy":
            instruction = textwrap.dedent(f'''
            Choose one strategy for `{display}`: api, export, local_file, manual_upload, or no_viable_path.
            If no path is currently viable, report `--status attention` with a `blocked:` summary.
            Otherwise report the selected compact strategy.
            ''').strip()
        elif step_id == "smoke_read":
            instruction = textwrap.dedent(f'''
            Attempt a read-only smoke read for `{display}` within the selected strategy. Do not perform broad ingest.
            If user action is needed, report `--status waiting` and make the summary start with what the user must do.
            If the path is blocked, report `--status attention` with a blocked reason.
            ''').strip()
        elif step_id == "propose_ingest_scope":
            instruction = textwrap.dedent(f'''
            Propose the ingest scope for `{display}`: source subset, sensitivity, expected size, cost/duration risk, and target artifact shape.
            Do not write source body to GBrain yet.
            Report the compact scope proposal as completed.
            ''').strip()
        elif step_id == "confirm_ingest_plan":
            instruction = textwrap.dedent(f'''
            Ask the user for explicit approval before ingesting `{display}` into the active GBrain target.
            Only after the user approves, run:
            `zebra-source-onboarding fallback report --source {source_id} --step confirm_ingest_plan --status completed --summary "approved scope: <scope>"`
            If the user does not approve, use `--status waiting` or `--status skipped` as appropriate.
            ''').strip()
        elif step_id == "ingest":
            instruction = textwrap.dedent(f'''
            Ingest only the user-approved `{display}` scope into the GBrain target.
            If the helper should write an export-derived markdown artifact, pass only a user-approved file reference to this ingest step:
            `zebra-source-onboarding fallback report --source {source_id} --step ingest --status completed --summary "<compact ingest result>" --ingest-title "<title>" --ingest-file "<approved-export-file>" --ingest-provenance "<provenance>"`
            Do not pass raw source body as a CLI argument. The helper reads the approved file and writes its body to the GBrain target artifact, not to Source Onboarding state or fallback promotion artifacts.
            ''').strip()
        elif step_id == "verify_readback":
            instruction = textwrap.dedent(f'''
            Verify the GBrain ingest artifact for `{display}` can be read back and contains expected provenance/schema.
            Current GBrain artifact reference: `{artifact_ref or "not recorded"}`
            If readback succeeds, report completed; the helper will move to the completion-report boundary.
            ''').strip()
        else:
            instruction = "Fallback Source Onboarding is complete. Run the completion report command when prompted."
        return textwrap.dedent(f'''
        Zebra Source Onboarding: `{display}` is an uncataloged source using the generic agent fallback runner.

        Playbook: {fallback_playbook["id"]} {fallback_playbook["version"]}
        Current step: `{step_id}`
        Last compact summary: `{last_summary}`

        Boundary rules:
        - Work only this source and this fallback step.
        - Use `zebra-source-onboarding fallback report` as the only Source Onboarding state transition path for this fallback source.
        - Do not edit `source-onboarding-state.json` directly.
        - Do not store raw source body, token, cookie, OAuth code, private full path, raw CLI stdout, or transcript content in Source Onboarding state or fallback promotion artifacts.
        - Approved source body may be written only to the GBrain ingest target after `confirm_ingest_plan` is complete.
        - Do not ask the user to skip after a first failed attempt. Before reporting `blocked:`, exhaust reasonable local checks, a small retry when safe, and at least one viable alternative access path or user-provided export/manual-upload path.
        - Use `waiting:` only when a known user action is likely enough to let this source continue. Use `blocked:` only when no currently viable next step remains.
        - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

        Step instructions:

        {instruction}
        {fallback_attention_prompt_suffix(source_id, step_id, display, row)}
        ''').strip()

    def set_gmail_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
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
        if run_state_path:
            row["runStatePath"] = run_state_path
        rows["gmail"] = row
        progress["sourceRows"] = rows
        if "gmail" not in ensure_execution_order(progress):
            progress["executionOrder"].append("gmail")
        if row_status in {"checked", "skipped"}:
            if progress.get("activeSourceID") == "gmail":
                progress["activeSourceID"] = None
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
            if progress.get("activeSourceID") == "obsidian":
                progress["activeSourceID"] = None
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

    def set_notion_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("notion") if isinstance(rows.get("notion"), dict) else source_row_for("notion", timestamp)
        playbook = notion_playbook()
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
        rows["notion"] = row
        progress["sourceRows"] = rows
        if "notion" not in ensure_execution_order(progress):
            progress["executionOrder"].append("notion")
        if row_status in {"checked", "skipped"}:
            if progress.get("activeSourceID") == "notion":
                progress["activeSourceID"] = None
        else:
            progress["activeSourceID"] = "notion"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def should_update_notion_runner(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        if progress.get("activeSourceID") == "notion":
            return True
        if "notion" not in ensure_execution_order(progress):
            return False
        row = rows.get("notion")
        return isinstance(row, dict) and row.get("playbookID") == notion_playbook()["id"]

    def set_imessage_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("imessage") if isinstance(rows.get("imessage"), dict) else source_row_for("imessage", timestamp)
        playbook = imessage_playbook()
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
        rows["imessage"] = row
        progress["sourceRows"] = rows
        if "imessage" not in ensure_execution_order(progress):
            progress["executionOrder"].append("imessage")
        if row_status in {"checked", "skipped"}:
            if progress.get("activeSourceID") == "imessage":
                progress["activeSourceID"] = None
        else:
            progress["activeSourceID"] = "imessage"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def set_apple_notes_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("apple-notes") if isinstance(rows.get("apple-notes"), dict) else source_row_for("apple-notes", timestamp)
        playbook = apple_notes_playbook()
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
        rows["apple-notes"] = row
        progress["sourceRows"] = rows
        if "apple-notes" not in ensure_execution_order(progress):
            progress["executionOrder"].append("apple-notes")
        if row_status in {"checked", "skipped"}:
            if progress.get("activeSourceID") == "apple-notes":
                progress["activeSourceID"] = None
        else:
            progress["activeSourceID"] = "apple-notes"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def should_update_apple_notes_runner(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        if progress.get("activeSourceID") == "apple-notes":
            return True
        if "apple-notes" not in ensure_execution_order(progress):
            return False
        row = rows.get("apple-notes")
        return isinstance(row, dict) and row.get("playbookID") == apple_notes_playbook()["id"]

    def set_apple_reminders_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("apple-reminders") if isinstance(rows.get("apple-reminders"), dict) else source_row_for("apple-reminders", timestamp)
        playbook = apple_reminders_playbook()
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
        rows["apple-reminders"] = row
        progress["sourceRows"] = rows
        if "apple-reminders" not in ensure_execution_order(progress):
            progress["executionOrder"].append("apple-reminders")
        if row_status in {"checked", "skipped"}:
            if progress.get("activeSourceID") == "apple-reminders":
                progress["activeSourceID"] = None
        else:
            progress["activeSourceID"] = "apple-reminders"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def should_update_apple_reminders_runner(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        if progress.get("activeSourceID") == "apple-reminders":
            return True
        if "apple-reminders" not in ensure_execution_order(progress):
            return False
        row = rows.get("apple-reminders")
        return isinstance(row, dict) and row.get("playbookID") == apple_reminders_playbook()["id"]

    def set_agent_memory_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
        timestamp = timestamp or now()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("agent-memory") if isinstance(rows.get("agent-memory"), dict) else source_row_for("agent-memory", timestamp)
        playbook = agent_memory_playbook()
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
        rows["agent-memory"] = row
        progress["sourceRows"] = rows
        if "agent-memory" not in ensure_execution_order(progress):
            progress["executionOrder"].append("agent-memory")
        if row_status in {"checked", "skipped"}:
            if progress.get("activeSourceID") == "agent-memory":
                progress["activeSourceID"] = None
        else:
            progress["activeSourceID"] = "agent-memory"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    required_cli_specs = {
        "imessage": {
            "binary": "imsg",
            "pathKey": "imsgCommandPath",
            "versionKey": "imsgVersion",
            "statusKey": "cliStatus",
            "checkStep": "check_imsg_cli",
            "nextStep": "check_full_disk_access",
            "missingReason": "imsg_cli_missing",
        },
        "notion": {
            "binary": "ntn",
            "pathKey": "ntnCommandPath",
            "versionKey": "ntnVersion",
            "statusKey": "cliStatus",
            "checkStep": "check_ntn_cli",
            "nextStep": "choose_scope",
            "missingReason": "ntn_cli_missing",
        },
        "apple-notes": {
            "binary": "memo",
            "pathKey": "memoCommandPath",
            "versionKey": "memoVersion",
            "statusKey": "cliStatus",
            "checkStep": "check_memo_cli",
            "nextStep": "check_notes_automation",
            "missingReason": "memo_cli_missing",
        },
        "apple-reminders": {
            "binary": "remindctl",
            "pathKey": "remindctlCommandPath",
            "versionKey": "remindctlVersion",
            "statusKey": "cliStatus",
            "checkStep": "check_remindctl_cli",
            "nextStep": "check_reminders_permission",
            "missingReason": "remindctl_cli_missing",
        },
    }

    def set_cli_source_row_state(source_id, state, row_status, phase, step_id, attention_reason=None, result_summary=None, run_state_path=None):
        if source_id == "imessage":
            return set_imessage_row_state(
                state,
                row_status,
                phase,
                step_id,
                attention_reason=attention_reason,
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "notion":
            return set_notion_row_state(
                state,
                row_status,
                phase,
                step_id,
                attention_reason=attention_reason,
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "apple-notes":
            return set_apple_notes_row_state(
                state,
                row_status,
                phase,
                step_id,
                attention_reason=attention_reason,
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "apple-reminders":
            return set_apple_reminders_row_state(
                state,
                row_status,
                phase,
                step_id,
                attention_reason=attention_reason,
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        return state

    def required_cli_command_path(source_id, run_state):
        spec = required_cli_specs[source_id]
        command_path = str(run_state.get(spec["pathKey"]) or "")
        if command_path and not Path(command_path).exists():
            command_path = ""
        if not command_path:
            command_path = shutil.which(spec["binary"]) or ""
        if command_path:
            run_state[spec["pathKey"]] = command_path
        return command_path

    def check_required_cli(source_id):
        spec = required_cli_specs[source_id]
        state = load_or_create_state()
        run_state = load_source_run_state(source_id)
        command_path = required_cli_command_path(source_id, run_state)
        if not command_path:
            run_state.update({
                spec["statusKey"]: "missing",
                "phase": "preflight",
                "step": spec["checkStep"],
                "updatedAt": now(),
            })
            run_path = save_source_run_state(source_id, run_state)
            state = set_cli_source_row_state(
                source_id,
                state,
                "attention",
                "preflight",
                spec["checkStep"],
                attention_reason=spec["missingReason"],
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": spec["missingReason"]}
            payload.update(source_next_prompt_payload(state, source_id, spec["checkStep"]))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        version = ""
        try:
            result = subprocess.run([command_path, "--version"], text=True, capture_output=True, timeout=5)
            version = (result.stdout or result.stderr or "").strip()
        except Exception:
            version = ""
        run_state.update({
            spec["statusKey"]: "passed",
            spec["pathKey"]: command_path,
            spec["versionKey"]: version,
            "phase": "preflight",
            "step": spec["nextStep"],
            "updatedAt": now(),
        })
        run_path = save_source_run_state(source_id, run_state)
        state = set_cli_source_row_state(
            source_id,
            state,
            "running",
            "preflight",
            spec["nextStep"],
            run_state_path=run_path,
            result_summary=spec["binary"] + " CLI found at " + command_path,
        )
        save_json(state)
        payload = {
            "ok": True,
            spec["pathKey"]: command_path,
            spec["versionKey"]: version,
        }
        payload.update(source_next_prompt_payload(state, source_id, spec["nextStep"]))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def required_cli_preflight_passed(source_id):
        spec = required_cli_specs[source_id]
        run_state = load_source_run_state(source_id)
        command_path = required_cli_command_path(source_id, run_state)
        return run_state.get(spec["statusKey"]) == "passed" and bool(command_path)

    def require_cli_preflight_or_attention(source_id):
        spec = required_cli_specs[source_id]
        if required_cli_preflight_passed(source_id):
            return None
        state = load_or_create_state()
        run_state = load_source_run_state(source_id)
        command_path = required_cli_command_path(source_id, run_state)
        if command_path:
            spec = required_cli_specs[source_id]
            version = ""
            try:
                result = subprocess.run([command_path, "--version"], text=True, capture_output=True, timeout=5)
                version = (result.stdout or result.stderr or "").strip()
            except Exception:
                version = ""
            run_state.update({
                spec["statusKey"]: "passed",
                spec["pathKey"]: command_path,
                spec["versionKey"]: version,
                "phase": "preflight",
                "step": spec["nextStep"],
                "updatedAt": now(),
            })
            run_path = save_source_run_state(source_id, run_state)
            state = set_cli_source_row_state(
                source_id,
                state,
                "running",
                "preflight",
                spec["nextStep"],
                run_state_path=run_path,
                result_summary=spec["binary"] + " CLI found at " + command_path,
            )
            save_json(state)
            return None
        run_state.update({
            spec["statusKey"]: "missing",
            "phase": "preflight",
            "step": spec["checkStep"],
            "updatedAt": now(),
        })
        run_path = save_source_run_state(source_id, run_state)
        state = set_cli_source_row_state(
            source_id,
            state,
            "attention",
            "preflight",
            spec["checkStep"],
            attention_reason=spec["missingReason"],
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": spec["missingReason"]}
        payload.update(source_next_prompt_payload(state, source_id, spec["checkStep"]))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1

    def mark_source_completion_pending(state, source_id, disposition, result_summary, run_state=None):
        disposition = "skipped" if disposition == "skipped" else "checked"
        if not isinstance(run_state, dict):
            run_state = load_source_run_state(source_id)
        run_state.update({
            "completionReportPending": True,
            "completionDisposition": disposition,
            "completionSummary": result_summary,
            "phase": "complete",
            "step": "complete",
            "updatedAt": now(),
        })
        run_state_path = save_source_run_state(source_id, run_state)
        if source_id == "gmail":
            return set_gmail_row_state(
                state,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "obsidian":
            return set_obsidian_row_state(
                state,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "notion":
            return set_notion_row_state(
                state,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "imessage":
            return set_imessage_row_state(
                state,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "apple-notes":
            return set_apple_notes_row_state(
                state,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "apple-reminders":
            return set_apple_reminders_row_state(
                state,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        if source_id == "agent-memory":
            return set_agent_memory_row_state(
                state,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else {}
        if is_fallback_source_row(row):
            return set_fallback_row_state(
                state,
                source_id,
                "running",
                "complete",
                "complete",
                result_summary=result_summary,
                run_state_path=run_state_path,
            )
        return state

    def report_source_completion(state, source_id):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else None
        if not row:
            return None, {"ok": False, "reason": "unknown_source", "sourceID": source_id}, 1
        if progress.get("activeSourceID") != source_id:
            return None, {"ok": False, "reason": "source_not_active", "sourceID": source_id}, 1
        if row.get("status") in {"checked", "skipped"}:
            return None, {"ok": False, "reason": "source_already_reported", "sourceID": source_id}, 1
        if row.get("phase") != "complete" or row.get("playbookStepID") != "complete":
            return None, {"ok": False, "reason": "source_completion_not_pending", "sourceID": source_id}, 1
        run_state = load_source_run_state(source_id)
        disposition = run_state.get("completionDisposition") or "checked"
        if disposition not in {"checked", "skipped"}:
            disposition = "checked"
        summary_text = row.get("resultSummary") or run_state.get("completionSummary") or (source_display_name(source_id) + " Source Onboarding completed.")
        timestamp = now()
        if source_id == "gmail":
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_gmail_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text, run_state_path=run_path)
        elif source_id == "obsidian":
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_obsidian_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text, run_state_path=run_path)
        elif source_id == "notion":
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_notion_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text, run_state_path=run_path)
        elif source_id == "imessage":
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_imessage_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text, run_state_path=run_path)
        elif source_id == "apple-notes":
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_apple_notes_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text, run_state_path=run_path)
        elif source_id == "apple-reminders":
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_apple_reminders_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text, run_state_path=run_path)
        elif source_id == "agent-memory":
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_agent_memory_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text, run_state_path=run_path)
        elif is_fallback_source_row(row):
            run_state.update({"completionReportPending": False, "completionReportedAt": timestamp, "updatedAt": timestamp})
            run_path = save_source_run_state(source_id, run_state)
            state = set_fallback_row_state(
                state,
                source_id,
                disposition,
                "complete",
                "complete",
                timestamp=timestamp,
                result_summary=summary_text,
                run_state_path=run_path,
            )
        else:
            return None, {"ok": False, "reason": "unknown_source", "sourceID": source_id}, 1
        save_json(state)
        return state, {"sourceID": source_id, "summary": summary_text, "disposition": disposition}, 0

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

    def obsidian_file_for_vault(vault_path, value):
        if not value:
            return {"ok": False, "reason": "file_path_required"}
        vault = Path(vault_path).expanduser()
        if not vault.is_dir():
            return {"ok": False, "reason": "vault_path_required"}
        raw = str(value).strip()
        if not raw:
            return {"ok": False, "reason": "file_path_required"}
        path = Path(raw).expanduser()
        if path.is_absolute():
            return {"ok": False, "reason": "file_path_must_be_relative"}
        if any((part not in {".", ".."} and part.startswith(".")) or part == "__MACOSX" for part in path.parts):
            return {"ok": False, "reason": "file_path_not_allowed"}
        vault_resolved = vault.resolve(strict=False)

        def candidate_record(candidate):
            resolved = candidate.resolve(strict=False)
            try:
                relative = resolved.relative_to(vault_resolved)
            except Exception:
                return {"ok": False, "reason": "file_path_outside_vault"}
            if not resolved.exists():
                return {"ok": False, "reason": "file_not_found"}
            if not resolved.is_file():
                return {"ok": False, "reason": "file_path_not_file"}
            if resolved.suffix.lower() != ".md":
                return {"ok": False, "reason": "file_path_not_markdown"}
            return {"ok": True, "path": str(resolved), "relative": str(relative)}

        result = candidate_record(vault / path)
        if result.get("ok") or path.suffix or result.get("reason") != "file_not_found":
            return result
        return candidate_record(vault / Path(raw + ".md"))

    def obsidian_markdown_files_for_scope(vault_path, run_state):
        scope = run_state.get("scope")
        folders = run_state.get("folders") if isinstance(run_state.get("folders"), list) else []
        if scope == "file":
            selected = run_state.get("files") if isinstance(run_state.get("files"), list) else []
            files = []
            for item in selected:
                result = obsidian_file_for_vault(vault_path, item)
                if result.get("ok"):
                    files.append(Path(result["path"]))
            return files
        return markdown_files_for_vault(
            vault_path,
            folders=folders if scope == "folders" else None,
            limit=5 if scope == "sample" else None,
        )

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
        files = run_state.get("files") if isinstance(run_state.get("files"), list) else []
        count = run_state.get("estimatedFileCount")
        count_text = str(count) if count is not None else "unknown"
        duration = run_state.get("durationClass") or duration_class(count)
        scope_detail = scope
        if scope == "whole":
            scope_detail = "whole vault"
        if scope == "folders":
            scope_detail = "folders: " + (", ".join(folders) if folders else "none")
        if scope == "file":
            scope_detail = "file: " + (", ".join(files) if files else "none")
        if scope == "sample":
            scope_detail = "recent/sample subset: up to 5 Markdown files"
        language = onboarding_language()
        if language == "ko":
            localized_scope_detail = scope_detail
            if scope == "whole":
                localized_scope_detail = "전체 vault"
            elif scope == "folders":
                localized_scope_detail = "선택한 폴더: " + (", ".join(folders) if folders else "없음")
            elif scope == "file":
                localized_scope_detail = "특정 note 파일: " + (", ".join(files) if files else "없음")
            elif scope == "sample":
                localized_scope_detail = "최근/샘플 일부: 최대 5개 Markdown 파일"
            elif scope == "skip":
                localized_scope_detail = "이번 Source Onboarding에서 Obsidian 건너뛰기"
            return textwrap.dedent(f'''
            선택된 Obsidian ingest plan입니다.
            - Vault 경로: `{vault}`
            - 선택한 범위: `{localized_scope_detail}`
            - 예상 Markdown 파일 수: `{count_text}`
            - 제외 경로/정책: `.obsidian/`, hidden directory, `__MACOSX`, Markdown이 아닌 파일, 선택된 vault 밖의 경로는 제외합니다.
            - 예상 소요 등급: `{duration}`
            - Ingest 방식: Markdown 파일시스템을 직접 읽어 Zebra source artifact를 작성합니다.
            - 검증 계획: 생성된 Obsidian source artifact를 다시 읽고 `source: obsidian`와 `playbook: obsidian.direct-markdown.v1`를 확인합니다.

            ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding obsidian confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding obsidian confirm-plan --answer no`를 실행하세요.
            ''').strip()
        if language == "ja":
            localized_scope_detail = scope_detail
            if scope == "whole":
                localized_scope_detail = "vault全体"
            elif scope == "folders":
                localized_scope_detail = "選択したフォルダ: " + (", ".join(folders) if folders else "なし")
            elif scope == "file":
                localized_scope_detail = "特定のnoteファイル: " + (", ".join(files) if files else "なし")
            elif scope == "sample":
                localized_scope_detail = "最近/サンプルの一部: 最大5件のMarkdownファイル"
            elif scope == "skip":
                localized_scope_detail = "このSource OnboardingではObsidianをスキップ"
            return textwrap.dedent(f'''
            選択されたObsidian ingest planです。
            - Vaultパス: `{vault}`
            - 選択した範囲: `{localized_scope_detail}`
            - 推定Markdownファイル数: `{count_text}`
            - 除外パス/ポリシー: `.obsidian/`、hidden directory、`__MACOSX`、Markdown以外のファイル、選択されたvault外のパスは除外します。
            - 想定所要時間クラス: `{duration}`
            - Ingest方式: Markdownファイルシステムを直接読み、Zebra source artifactを書き込みます。
            - 検証計画: 生成されたObsidian source artifactを読み戻し、`source: obsidian`と`playbook: obsidian.direct-markdown.v1`を確認します。

            ingestを実行する前にユーザーから明示的な承認を得てください。承認されたら`zebra-source-onboarding obsidian confirm-plan --answer yes`を実行し、承認されなければ`zebra-source-onboarding obsidian confirm-plan --answer no`を実行してください。
            ''').strip()
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

    def start_imessage_from_next(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("imessage") if isinstance(rows.get("imessage"), dict) else {}
        playbook = imessage_playbook()
        if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
            step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "imessage", step_id))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        run_state = load_source_run_state("imessage")
        run_state.update({
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "running",
            "preflight",
            playbook["initialStepID"],
            run_state_path=run_path,
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "imessage", playbook["initialStepID"]))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def start_notion_from_next(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("notion") if isinstance(rows.get("notion"), dict) else {}
        playbook = notion_playbook()
        if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
            step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "notion", step_id))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        run_state = load_source_run_state("notion")
        run_state.update({
            "phase": "preflight",
            "step": playbook["initialStepID"],
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "running",
            "preflight",
            playbook["initialStepID"],
            run_state_path=run_path,
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "notion", playbook["initialStepID"]))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def start_apple_notes_from_next(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("apple-notes") if isinstance(rows.get("apple-notes"), dict) else {}
        playbook = apple_notes_playbook()
        if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
            step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "apple-notes", step_id))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        run_state = load_source_run_state("apple-notes")
        run_state.update({
            "phase": "preflight",
            "step": playbook["initialStepID"],
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "running",
            "preflight",
            playbook["initialStepID"],
            run_state_path=run_path,
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "apple-notes", playbook["initialStepID"]))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def start_apple_reminders_from_next(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("apple-reminders") if isinstance(rows.get("apple-reminders"), dict) else {}
        playbook = apple_reminders_playbook()
        if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
            step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "apple-reminders", step_id))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        run_state = load_source_run_state("apple-reminders")
        run_state.update({
            "phase": "preflight",
            "step": playbook["initialStepID"],
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "running",
            "preflight",
            playbook["initialStepID"],
            run_state_path=run_path,
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "apple-reminders", playbook["initialStepID"]))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def agent_memory_artifact_path(state):
        target = gbrain_write_target_path or ((state.get("entryContext") or {}).get("gbrainWriteTargetPath") if isinstance(state.get("entryContext"), dict) else "")
        if target and Path(target).is_dir():
            directory = Path(target) / "sources"
        else:
            directory = state_path.parent / "source-ingest-artifacts"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / "agent-memory-knowledge.md"

    def agent_memory_selected_units(run_state):
        units = agent_memory_importable_units()
        scope = run_state.get("scope")
        if scope == "sample":
            return units[:3]
        if scope == "all":
            return units
        return []

    def start_agent_memory_from_next(state):
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get("agent-memory") if isinstance(rows.get("agent-memory"), dict) else {}
        playbook = agent_memory_playbook()
        if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
            step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "agent-memory", step_id))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        units = agent_memory_importable_units()
        if not units:
            run_state = load_source_run_state("agent-memory")
            run_state.update({"phase": "preflight", "step": "review_found_agents", "updatedAt": now()})
            run_path = save_source_run_state("agent-memory", run_state)
            state = set_agent_memory_row_state(
                state,
                "attention",
                "preflight",
                "review_found_agents",
                attention_reason="agent_memory_importable_content_missing",
                run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "agent_memory_importable_content_missing"
            payload.update(source_next_prompt_payload(state, "agent-memory", "review_found_agents"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state = load_source_run_state("agent-memory")
        artifact = agent_memory_artifact_path(state)
        run_state.update({
            "phase": "review",
            "step": "review_found_agents",
            "foundUnitCount": len(units),
            "foundSummary": agent_memory_unit_summary(units),
            "artifactPath": str(artifact),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("agent-memory", run_state)
        state = set_agent_memory_row_state(
            state,
            "running",
            "review",
            "review_found_agents",
            run_state_path=run_path,
            result_summary=agent_memory_unit_summary(units),
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "agent-memory", "review_found_agents"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def parse_agent_memory_scope_args():
        scope = ""
        index = 0
        while index < len(args):
            token = args[index]
            if token == "--scope" and index + 1 < len(args):
                scope = args[index + 1].strip().lower()
                index += 2
            else:
                print("unknown or incomplete argument: " + token, file=sys.stderr)
                sys.exit(2)
        if scope not in {"all", "sample", "skip"}:
            print("--scope must be all, sample, or skip", file=sys.stderr)
            sys.exit(2)
        return scope

    def agent_memory_choose_scope():
        scope = parse_agent_memory_scope_args()
        state = load_or_create_state()
        run_state = load_source_run_state("agent-memory")
        run_state["scope"] = scope
        run_state["planConfirmed"] = False
        run_state.pop("approvedAt", None)
        if scope == "skip":
            run_state["scopeSummary"] = "skip existing agent memory"
            state = mark_source_completion_pending(
                state,
                "agent-memory",
                "skipped",
                "Skipped existing agent memory for this Source Onboarding session.",
                run_state,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "agent-memory", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        selected = agent_memory_selected_units(run_state)
        run_state.update({
            "scopeSummary": "all found files" if scope == "all" else "small sample",
            "selectedUnitCount": len(selected),
            "phase": "confirm",
            "step": "confirm_ingest_plan",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("agent-memory", run_state)
        state = set_agent_memory_row_state(
            state,
            "running",
            "confirm",
            "confirm_ingest_plan",
            run_state_path=run_path,
            result_summary=run_state["scopeSummary"] + " (" + str(len(selected)) + " file(s))",
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "agent-memory", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def agent_memory_confirm_plan():
        answer = parse_answer()
        state = load_or_create_state()
        run_state = load_source_run_state("agent-memory")
        if answer in {"no", "n"}:
            state = mark_source_completion_pending(
                state,
                "agent-memory",
                "skipped",
                "Skipped existing agent memory after plan review.",
                run_state,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, "agent-memory", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_agent_memory_row_state(state, "attention", "review", "review_found_agents", attention_reason="ingest_scope_required")
            save_json(state)
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "ingest_scope_required"
            payload.update(source_next_prompt_payload(state, "agent-memory", "review_found_agents"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({
            "phase": "ingest",
            "step": "ingest_memory",
            "planConfirmed": True,
            "approvedAt": now(),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("agent-memory", run_state)
        state = set_agent_memory_row_state(state, "running", "ingest", "ingest_memory", run_state_path=run_path)
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "agent-memory", "ingest_memory"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def agent_memory_ingest():
        state = load_or_create_state()
        run_state = load_source_run_state("agent-memory")
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_agent_memory_row_state(state, "attention", "review", "review_found_agents", attention_reason="ingest_scope_required")
            save_json(state)
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "ingest_scope_required"
            payload.update(source_next_prompt_payload(state, "agent-memory", "review_found_agents"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if (
            run_state.get("step") != "ingest_memory"
            or run_state.get("phase") != "ingest"
            or not run_state.get("planConfirmed")
            or not run_state.get("approvedAt")
        ):
            state = set_agent_memory_row_state(state, "attention", "confirm", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
            save_json(state)
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "ingest_plan_unconfirmed"
            payload.update(source_next_prompt_payload(state, "agent-memory", "confirm_ingest_plan"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        units = agent_memory_selected_units(run_state)
        artifact = agent_memory_artifact_path(state)
        lines = [
            "---",
            "source: agent-memory",
            "playbook: agent-memory.local-files.v1",
            "created: " + now(),
            "---",
            "",
            "# Existing Agent Memory",
            "",
        ]
        for unit in units:
            path = Path(unit["path"])
            try:
                text = path.read_text(encoding="utf-8", errors="replace").strip()
            except Exception:
                continue
            if len(text) > 12000:
                text = text[:12000].rstrip() + "\\n\\n[Truncated by Zebra Source Onboarding]"
            lines.extend([
                "## " + unit["displayName"],
                "",
                "[Source: " + unit["displayName"] + " memory/knowledge file `" + str(path) + "`, " + now()[:10] + "]",
                "",
                text,
                "",
            ])
        artifact.write_text("\\n".join(lines).rstrip() + "\\n", encoding="utf-8")
        run_state.update({
            "artifactPath": str(artifact),
            "ingestedUnitCount": len(units),
            "phase": "verify",
            "step": "verify_readback",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("agent-memory", run_state)
        state = set_agent_memory_row_state(
            state,
            "running",
            "verify",
            "verify_readback",
            run_state_path=run_path,
            result_summary="Wrote " + str(len(units)) + " existing agent memory/knowledge file(s).",
        )
        save_json(state)
        payload = summary(state)
        payload["artifactPath"] = str(artifact)
        payload["ingestedUnitCount"] = len(units)
        payload.update(source_next_prompt_payload(state, "agent-memory", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def agent_memory_verify_readback():
        state = load_or_create_state()
        run_state = load_source_run_state("agent-memory")
        artifact = Path(run_state.get("artifactPath") or "")
        if not artifact.is_file():
            state = set_agent_memory_row_state(
                state,
                "attention",
                "verify",
                "verify_readback",
                attention_reason="agent_memory_artifact_missing",
                run_state_path=save_source_run_state("agent-memory", run_state),
            )
            save_json(state)
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "agent_memory_artifact_missing"
            payload.update(source_next_prompt_payload(state, "agent-memory", "verify_readback"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        text = artifact.read_text(encoding="utf-8", errors="replace")
        if "source: agent-memory" not in text:
            payload = summary(state)
            payload["ok"] = False
            payload["reason"] = "agent_memory_readback_failed"
            payload.update(source_next_prompt_payload(state, "agent-memory", "verify_readback"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"readbackStatus": "verified", "verifiedAt": now(), "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "agent-memory",
            "checked",
            "Imported existing agent memory/knowledge files into " + str(artifact) + ".",
            run_state,
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "agent-memory", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def agent_memory_command():
        if not args:
            print("agent-memory requires a subcommand", file=sys.stderr)
            return 2
        pending_code = reject_if_completion_report_pending("agent-memory")
        if pending_code is not None:
            return pending_code
        subcommand = args[0]
        del args[:1]
        if subcommand == "choose-scope":
            return agent_memory_choose_scope()
        if subcommand == "confirm-plan":
            return agent_memory_confirm_plan()
        if subcommand == "ingest":
            return agent_memory_ingest()
        if subcommand == "verify-readback":
            return agent_memory_verify_readback()
        print("unknown agent-memory command: " + subcommand, file=sys.stderr)
        return 2

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
        pending_source_id = pending_completion_source_id(state)
        if pending_source_id:
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, pending_source_id, "complete"))
            payload.update({
                "ok": False,
                "reason": "source_completion_report_required",
                "blockedSourceID": "next",
                "pendingSourceID": pending_source_id,
            })
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
        if source_id == "imessage":
            return start_imessage_from_next(state)
        if source_id == "notion":
            return start_notion_from_next(state)
        if source_id == "apple-notes":
            return start_apple_notes_from_next(state)
        if source_id == "apple-reminders":
            return start_apple_reminders_from_next(state)
        if source_id == "agent-memory":
            return start_agent_memory_from_next(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else {}
        if is_fallback_source_row(row):
            if row.get("playbookID") == fallback_playbook["id"] and row.get("status") in {"running", "attention"}:
                step_id = row.get("playbookStepID") if row.get("playbookStepID") in fallback_playbook["steps"] else fallback_playbook["initialStepID"]
                payload = summary(state)
                payload.update(source_next_prompt_payload(state, source_id, step_id))
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 0
            timestamp = now()
            state = set_fallback_row_state(
                state,
                source_id,
                "running",
                fallback_phase_for_step(fallback_playbook["initialStepID"]),
                fallback_playbook["initialStepID"],
                timestamp=timestamp,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, fallback_playbook["initialStepID"]))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if source_id != "gmail":
            payload = summary(state)
            payload["ok"] = False
            payload["nextSourceID"] = source_id
            payload["reason"] = "source_runner_not_implemented"
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
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

    def run_start_next_captured():
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = start_next()
        stdout = buffer.getvalue().strip()
        payload = {}
        if stdout:
            try:
                payload = json.loads(stdout.splitlines()[-1])
            except Exception:
                payload = {"ok": False, "reason": "next_payload_parse_failed", "rawNextStdout": stdout}
        return code, payload

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

    def adapter_block_exists(root, relative_path):
        try:
            text = (Path(root) / relative_path).read_text(encoding="utf-8")
        except Exception:
            return False
        return "<!-- gbrain-adapter:begin goals-tasks -->" in text and "<!-- gbrain-adapter:end goals-tasks -->" in text

    def adapter_installed_checks(target_path):
        root = Path(target_path)
        return {
            "adapterSkillRouter": (root / ".gbrain-adapter/skills/router/SKILL.md").exists(),
            "adapterSkillDailyTaskManager": (root / ".gbrain-adapter/skills/daily-task-manager/SKILL.md").exists(),
            "adapterSkillDailyTaskPrep": (root / ".gbrain-adapter/skills/daily-task-prep/SKILL.md").exists(),
            "goalsReadme": (root / "goals/README.md").exists(),
            "tasksReadme": (root / "tasks/README.md").exists(),
            "resolverBlock": adapter_block_exists(root, "RESOLVER.md"),
            "schemaBlock": adapter_block_exists(root, "schema.md"),
            "agentsBlock": adapter_block_exists(root, "AGENTS.md"),
        }

    def adapter_completion_result(target_key, target_path, target):
        adapter = load_json(adapter_state_path)
        adapter_receipt = adapter.get("receipt") if isinstance(adapter.get("receipt"), dict) else {}
        if not adapter_receipt:
            return False, ["missing_receipt"]
        if adapter_receipt.get("complete") is not True:
            reasons = adapter_receipt.get("reasons") if isinstance(adapter_receipt.get("reasons"), list) else []
            return False, reasons or ["receipt_incomplete"]

        gbrain = load_json(gbrain_state_path)
        gbrain_receipt = gbrain.get("receipt") if isinstance(gbrain.get("receipt"), dict) else {}
        if not gbrain_receipt:
            return False, ["gbrain_receipt_missing"]
        readiness = gbrain_receipt.get("globalReadiness") if isinstance(gbrain_receipt.get("globalReadiness"), dict) else {}
        if readiness.get("complete") is not True:
            return False, ["gbrain_receipt_incomplete"]
        if not target_key or not target_path or not isinstance(target, dict) or target.get("complete") is not True:
            return False, ["gbrain_target_missing"]
        if adapter_receipt.get("targetKey") != target_key:
            return False, ["target_key_mismatch"]

        receipt_target_path = existing_directory(adapter_receipt.get("targetVaultPath") or "")
        resolved_target_path = existing_directory(target.get("vaultPath") or "")
        if not receipt_target_path or not resolved_target_path or receipt_target_path != resolved_target_path or receipt_target_path != target_path:
            return False, ["target_path_mismatch"]

        binding = gbrain.get("activeGBrainBinding") if isinstance(gbrain.get("activeGBrainBinding"), dict) else {}
        source_repo = existing_directory(binding.get("sourceRepoPath") or "")
        if not source_repo:
            return False, ["gbrain_source_binding_missing"]
        adapter_repo = existing_directory(adapter_receipt.get("adapterRepoPath") or "")
        if not adapter_repo:
            return False, ["adapter_repo_missing"]
        expected_adapter_repo = canonical_path(Path(source_repo).parent / "gbrain-adapter")
        if adapter_repo != expected_adapter_repo:
            return False, ["adapter_repo_path_mismatch"]

        failed = sorted(key for key, value in adapter_installed_checks(target_path).items() if not value)
        if failed:
            return False, ["missing:" + key for key in failed]
        return True, []

    def entry_context():
        target_key, target_path, target = resolve_gbrain_target()
        adapter_ready, adapter_reasons = adapter_completion_result(target_key, target_path, target)
        warnings = target.get("warnings") if isinstance(target.get("warnings"), list) else []
        return {
            "onboardingLanguageCode": onboarding_language(),
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
            "adapterReady": adapter_ready,
            "adapterReadinessReasons": adapter_reasons,
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
            state = mark_source_completion_pending(
                state,
                "gmail",
                "checked",
                "Gmail Clawvisor gateway smoke check passed for service " + service,
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "complete"))
        print(json.dumps(payload, sort_keys=True))
        return 0

    def gmail_command():
        if not args:
            print("gmail requires a subcommand", file=sys.stderr)
            return 2
        pending_code = reject_if_completion_report_pending("gmail")
        if pending_code is not None:
            return pending_code
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
        selected_file = single_flag_value("--file")
        if scope not in {"whole", "folders", "file", "sample", "skip"}:
            print("--scope must be whole, folders, file, sample, or skip", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("obsidian")
        vault = run_state.get("selectedVaultPath")
        if scope == "skip":
            run_state.update({"scope": "skip", "updatedAt": now()})
            state = mark_source_completion_pending(
                state,
                "obsidian",
                "skipped",
                "Obsidian skipped for this Source Onboarding session.",
                run_state=run_state,
            )
            save_json(state)
            payload = {"ok": True, "skipped": True}
            payload.update(source_next_prompt_payload(state, "obsidian", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if scope == "folders" and not folders:
            print("--folder is required when --scope folders", file=sys.stderr)
            return 2
        relative_files = []
        if scope == "file":
            validation = obsidian_file_for_vault(vault, selected_file)
            if not validation.get("ok"):
                print(str(validation.get("reason") or "invalid_file_path"), file=sys.stderr)
                return 2
            relative_files = [validation["relative"]]
        run_state.update({
            "scope": scope,
            "folders": folders if scope == "folders" else [],
            "files": relative_files,
        })
        files = obsidian_markdown_files_for_scope(vault, run_state)
        total = len(markdown_files_for_vault(vault, folders=folders)) if scope == "folders" else len(files)
        run_state.update({
            "scope": scope,
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
        files = obsidian_markdown_files_for_scope(vault, run_state)
        if scope == "file" and not files:
            state = set_obsidian_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="selected_file_unavailable")
            save_json(state)
            payload = {"ok": False, "reason": "selected_file_unavailable"}
            payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
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
        state = mark_source_completion_pending(
            state,
            "obsidian",
            "checked",
            "Obsidian ingest readback verified for " + str(run_state.get("ingestedFileCount") or 0) + " Markdown files.",
            run_state=run_state,
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
        pending_code = reject_if_completion_report_pending("obsidian")
        if pending_code is not None:
            return pending_code
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

    def notion_artifact_path(state=None):
        target = None
        if isinstance(state, dict):
            target = state.get("entryContext", {}).get("gbrainTargetPath")
        if target and Path(target).is_dir():
            directory = Path(target) / "sources"
        else:
            directory = state_path.parent / "source-ingest-artifacts"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / "notion-source-onboarding.md"

    def sanitize_notion_text(value):
        text = str(value or "")
        text = re.sub("secret_[A-Za-z0-9_\\-]+", "REDACTED_SECRET", text)
        text = re.sub("ntn_[A-Za-z0-9_\\-]+", "REDACTED_NTN_TOKEN", text)
        text = re.sub("([\\\"'](?:oauth[_-]?code|access[_-]?token|refresh[_-]?token|id[_-]?token|authorization|cookie)[\\\"']\\s*:\\s*)[\\\"'][^\\\"']+[\\\"']", "\\\\1\\\"REDACTED\\\"", text, flags=re.IGNORECASE)
        text = re.sub("([\\\"']code[\\\"']\\s*:\\s*)[\\\"'][A-Za-z0-9_\\-]{8,}[\\\"']", "\\\\1\\\"REDACTED\\\"", text, flags=re.IGNORECASE)
        text = re.sub("oauth[_-]?code[=:][A-Za-z0-9_\\-]+", "oauth_code=REDACTED", text, flags=re.IGNORECASE)
        text = re.sub("code[=:][A-Za-z0-9_\\-]{8,}", "code=REDACTED", text, flags=re.IGNORECASE)
        text = re.sub("([?&][^\\n\\s)\\\"',}]*(token|signature|x-amz|X-Amz|expires|credential)[^\\n\\s)\\\"',}]*)", "?REDACTED_QUERY", text, flags=re.IGNORECASE)
        return text

    def sanitize_notion_value(value):
        if isinstance(value, dict):
            sanitized = {}
            for key, item in value.items():
                raw_key = str(key)
                lower = raw_key.lower()
                normalized_key = re.sub("[^a-z0-9]", "", lower)
                sensitive_exact = {
                    "code",
                    "oauthcode",
                    "accesstoken",
                    "refreshtoken",
                    "idtoken",
                    "authorization",
                    "cookie",
                }
                if normalized_key in sensitive_exact or any(word in lower for word in ("token", "secret", "oauth", "authorization", "cookie", "credential", "signature")):
                    sanitized[key] = "REDACTED"
                else:
                    sanitized[key] = sanitize_notion_value(item)
            return sanitized
        if isinstance(value, list):
            return [sanitize_notion_value(item) for item in value]
        if isinstance(value, str):
            return sanitize_notion_text(value)
        return value

    def extract_notion_id(value):
        text = str(value or "").strip()
        if not text:
            return ""
        text = text.split("?")[0].rstrip("/")
        tail = text.rsplit("/", 1)[-1]
        if "-" in tail:
            maybe = tail.rsplit("-", 1)[-1]
            if len(maybe) >= 16:
                return maybe
        return tail or text

    def notion_run_state_with_command_path():
        run_state = load_source_run_state("notion")
        command_path = required_cli_command_path("notion", run_state)
        return run_state, command_path

    def run_ntn(ntn_args, timeout=60):
        _, command_path = notion_run_state_with_command_path()
        if not command_path:
            return {"ok": False, "status": 127, "args": list(ntn_args), "stdout": "", "stderr": "ntn_cli_missing", "json": None}
        try:
            completed = subprocess.run(
                [command_path] + list(ntn_args),
                text=True,
                capture_output=True,
                timeout=timeout,
            )
            stdout = sanitize_notion_text(completed.stdout)
            stderr = sanitize_notion_text(completed.stderr)
            payload = None
            try:
                payload = sanitize_notion_value(json.loads(stdout)) if stdout.strip() else None
            except Exception:
                payload = None
            return {
                "ok": completed.returncode == 0,
                "status": completed.returncode,
                "args": list(ntn_args),
                "stdout": stdout,
                "stderr": stderr,
                "json": payload,
            }
        except FileNotFoundError:
            return {"ok": False, "status": 127, "args": list(ntn_args), "stdout": "", "stderr": "ntn_cli_missing", "json": None}
        except subprocess.TimeoutExpired:
            return {"ok": False, "status": 124, "args": list(ntn_args), "stdout": "", "stderr": "ntn_timeout", "json": None}

    def notion_search_candidates(search_result):
        payload = search_result.get("json")
        raw_items = []
        if isinstance(payload, dict):
            if isinstance(payload.get("results"), list):
                raw_items = payload.get("results")
            elif isinstance(payload.get("data"), list):
                raw_items = payload.get("data")
            elif isinstance(payload.get("object"), str):
                raw_items = [payload]
        elif isinstance(payload, list):
            raw_items = payload
        candidates = []
        for item in raw_items[:10]:
            if not isinstance(item, dict):
                continue
            item_id = str(item.get("id") or item.get("page_id") or item.get("data_source_id") or "")
            title = item.get("title")
            if not title and isinstance(item.get("properties"), dict):
                for prop in item["properties"].values():
                    if isinstance(prop, dict) and isinstance(prop.get("title"), list) and prop["title"]:
                        title = "".join(part.get("plain_text", "") for part in prop["title"] if isinstance(part, dict))
                        break
            if not title and isinstance(item.get("name"), str):
                title = item.get("name")
            kind = str(item.get("object") or item.get("type") or item.get("kind") or "unknown")
            candidates.append({
                "id": sanitize_notion_text(item_id),
                "title": sanitize_notion_text(title or "Untitled"),
                "object": sanitize_notion_text(kind),
            })
        return candidates

    def notion_smoke_for_scope(scope, target):
        target_id = extract_notion_id(target)
        if scope in {"page", "page-subtree"}:
            return run_ntn(["pages", "get", target_id])
        if scope == "data-source":
            return run_ntn(["datasources", "query", target_id, "--limit", "5", "--json"])
        return {"ok": False, "status": 2, "args": [], "stdout": "", "stderr": "unsupported_scope", "json": None}

    def notion_smoke_summary(scope, target, smoke):
        stdout = smoke.get("stdout") or ""
        stderr = smoke.get("stderr") or ""
        body = stdout.strip() or stderr.strip()
        if len(body) > 1200:
            body = body[:1200] + "...(truncated)"
        return {
            "scope": scope,
            "target": sanitize_notion_text(target),
            "targetID": sanitize_notion_text(extract_notion_id(target)),
            "status": smoke.get("status"),
            "command": "ntn " + " ".join(smoke.get("args") or []),
            "sample": body,
        }

    def notion_fetch_result_summary(label, result):
        stdout = result.get("stdout") or ""
        stderr = result.get("stderr") or ""
        body = stdout.strip() or stderr.strip()
        if len(body) > 4000:
            body = body[:4000] + "...(truncated)"
        return {
            "label": sanitize_notion_text(label),
            "status": result.get("status"),
            "ok": bool(result.get("ok")),
            "command": "ntn " + " ".join(result.get("args") or []),
            "sample": body,
        }

    def notion_ingest_fetch_results(run_state):
        scope = run_state.get("scope")
        target_id = run_state.get("targetID") or extract_notion_id(run_state.get("target"))
        results = []
        if scope == "page":
            results.append(notion_fetch_result_summary("page", run_ntn(["pages", "get", target_id])))
        elif scope == "page-subtree":
            results.append(notion_fetch_result_summary("page", run_ntn(["pages", "get", target_id])))
            results.append(notion_fetch_result_summary(
                "page-subtree-children",
                run_ntn(["blocks", "children", "list", target_id, "--recursive", "--json"], timeout=180),
            ))
        elif scope == "data-source":
            results.append(notion_fetch_result_summary(
                "data-source-pages",
                run_ntn(["datasources", "query", target_id, "--json"], timeout=180),
            ))
        elif scope == "workspace-all":
            candidates = run_state.get("searchCandidates") if isinstance(run_state.get("searchCandidates"), list) else []
            for index, item in enumerate(candidates[:50], start=1):
                if not isinstance(item, dict):
                    continue
                item_id = item.get("id")
                if not item_id:
                    continue
                results.append(notion_fetch_result_summary(
                    "workspace-candidate-" + str(index),
                    run_ntn(["pages", "get", item_id], timeout=120),
                ))
        return results

    def notion_ingest_fetch_passed(scope, results):
        if scope == "page-subtree":
            labels = {
                item.get("label"): bool(item.get("ok"))
                for item in results
                if isinstance(item, dict)
            }
            return bool(labels.get("page")) and bool(labels.get("page-subtree-children"))
        return any(isinstance(item, dict) and item.get("ok") for item in results)

    def notion_choose_scope():
        scope = single_flag_value("--scope")
        target = single_flag_value("--target")
        if scope not in {"page", "page-subtree", "data-source", "workspace-search", "workspace-all", "skip"}:
            print("--scope must be page, page-subtree, data-source, workspace-search, workspace-all, or skip", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("notion")
        if scope == "skip":
            run_state.update({"scope": "skip", "phase": "complete", "step": "complete", "updatedAt": now()})
            state = mark_source_completion_pending(
                state,
                "notion",
                "skipped",
                "Notion skipped for this Source Onboarding session.",
                run_state=run_state,
            )
            save_json(state)
            payload = {"ok": True, "skipped": True}
            payload.update(source_next_prompt_payload(state, "notion", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        preflight_code = require_cli_preflight_or_attention("notion")
        if preflight_code is not None:
            return preflight_code
        run_state = load_source_run_state("notion")
        if scope == "workspace-search":
            search = run_ntn(["api", "v1/search", "page_size:=10"])
            candidates = notion_search_candidates(search)
            run_state.update({
                "scope": "workspace-search",
                "phase": "preflight",
                "step": "choose_scope",
                "searchStatus": "passed" if search.get("ok") else "failed",
                "searchCandidates": candidates,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("notion", run_state)
            state = set_notion_row_state(
                state,
                "attention",
                "preflight",
                "choose_scope",
                attention_reason="notion_candidate_selection_required" if search.get("ok") else "notion_workspace_search_failed",
                run_state_path=run_path,
                result_summary="Notion workspace search returned " + str(len(candidates)) + " candidates.",
            )
            save_json(state)
            payload = {"ok": bool(search.get("ok")), "scope": scope, "candidates": candidates}
            if not search.get("ok"):
                payload["reason"] = "notion_workspace_search_failed"
            payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0 if search.get("ok") else 1
        if scope == "workspace-all":
            search = run_ntn(["api", "v1/search", "page_size:=10"])
            if not search.get("ok"):
                candidates = notion_search_candidates(search)
                run_state.update({
                    "scope": "workspace-all",
                    "phase": "preflight",
                    "step": "choose_scope",
                    "searchStatus": "failed",
                    "searchCandidates": candidates,
                    "updatedAt": now(),
                })
                run_path = save_source_run_state("notion", run_state)
                state = set_notion_row_state(
                    state,
                    "attention",
                    "preflight",
                    "choose_scope",
                    attention_reason="notion_workspace_search_failed",
                    run_state_path=run_path,
                    result_summary="Notion workspace search failed before whole-workspace estimate.",
                )
                save_json(state)
                payload = {"ok": False, "scope": scope, "reason": "notion_workspace_search_failed", "candidates": candidates}
                payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            candidates = notion_search_candidates(search)
            representative_smoke = None
            if candidates:
                first_id = candidates[0].get("id")
                if first_id:
                    representative_smoke = run_ntn(["pages", "get", first_id])
            run_state.update({
                "scope": "workspace-all",
                "phase": "estimate",
                "step": "confirm_workspace_ingest",
                "workspaceCandidateCount": len(candidates),
                "searchStatus": "passed",
                "searchCandidates": candidates,
                "representativeSmokeStatus": representative_smoke.get("status") if isinstance(representative_smoke, dict) else None,
                "workspaceConfirmed": False,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("notion", run_state)
            state = set_notion_row_state(
                state,
                "attention",
                "estimate",
                "confirm_workspace_ingest",
                attention_reason="workspace_ingest_confirmation_required",
                run_state_path=run_path,
                result_summary="Notion whole-workspace estimate prepared with " + str(len(candidates)) + " search candidates.",
            )
            save_json(state)
            payload = {"ok": True, "scope": scope, "workspaceCandidateCount": len(candidates), "workspaceConfirmed": False}
            payload.update(source_next_prompt_payload(state, "notion", "confirm_workspace_ingest"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if not target:
            print("--target is required for page, page-subtree, and data-source scopes", file=sys.stderr)
            return 2
        smoke = notion_smoke_for_scope(scope, target)
        smoke_summary = notion_smoke_summary(scope, target, smoke)
        if not smoke.get("ok"):
            run_state.update({
                "scope": scope,
                "target": sanitize_notion_text(target),
                "targetID": sanitize_notion_text(extract_notion_id(target)),
                "phase": "smoke",
                "step": "choose_scope",
                "smokeStatus": "failed",
                "smokeSummary": smoke_summary,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("notion", run_state)
            state = set_notion_row_state(
                state,
                "attention",
                "smoke",
                "choose_scope",
                attention_reason="notion_smoke_read_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "scope": scope, "reason": "notion_smoke_read_failed", "smoke": smoke_summary}
            payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({
            "scope": scope,
            "target": sanitize_notion_text(target),
            "targetID": sanitize_notion_text(extract_notion_id(target)),
            "phase": "ingest",
            "step": "ingest_notion",
            "smokeStatus": "passed",
            "smokeSummary": smoke_summary,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "running",
            "ingest",
            "ingest_notion",
            run_state_path=run_path,
            result_summary="Notion smoke read passed for " + scope + " target.",
        )
        save_json(state)
        payload = {"ok": True, "scope": scope, "targetID": run_state.get("targetID"), "smoke": smoke_summary}
        payload.update(source_next_prompt_payload(state, "notion", "ingest_notion"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def notion_confirm_workspace():
        answer = single_flag_value("--answer").strip().lower()
        if answer not in {"yes", "y", "no", "n"}:
            print("--answer must be yes or no", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("notion")
        if answer in {"no", "n"}:
            run_state.update({
                "workspaceConfirmed": False,
                "phase": "preflight",
                "step": "choose_scope",
                "updatedAt": now(),
            })
            run_path = save_source_run_state("notion", run_state)
            state = set_notion_row_state(
                state,
                "attention",
                "preflight",
                "choose_scope",
                attention_reason="workspace_ingest_confirmation_declined",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "workspace_ingest_confirmation_declined"}
            payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if run_state.get("scope") != "workspace-all":
            print("workspace confirmation is only valid after --scope workspace-all", file=sys.stderr)
            return 2
        run_state.update({
            "workspaceConfirmed": True,
            "confirmedAt": now(),
            "phase": "ingest",
            "step": "ingest_notion",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "running",
            "ingest",
            "ingest_notion",
            run_state_path=run_path,
            result_summary="Notion whole-workspace ingest confirmed.",
        )
        save_json(state)
        payload = {"ok": True, "workspaceConfirmed": True}
        payload.update(source_next_prompt_payload(state, "notion", "ingest_notion"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def notion_artifact_markdown(run_state):
        scope = run_state.get("scope") or "unknown"
        target = run_state.get("target") or "workspace"
        title = "Notion Source Onboarding Ingest"
        smoke = run_state.get("smokeSummary") if isinstance(run_state.get("smokeSummary"), dict) else {}
        candidates = run_state.get("searchCandidates") if isinstance(run_state.get("searchCandidates"), list) else []
        ingest_results = run_state.get("ingestResults") if isinstance(run_state.get("ingestResults"), list) else []
        lines = [
            "---",
            "type: source-ingest",
            "source: notion",
            "source_kind: notion",
            "playbook: notion.ntn-cli.v1",
            "scope: " + sanitize_notion_text(scope),
            "source_uri: " + sanitize_notion_text(target),
            "notion_target_id: " + sanitize_notion_text(run_state.get("targetID") or ""),
            "created: " + now(),
            "---",
            "",
            "# " + title,
            "",
            "This artifact was generated by Zebra Source Onboarding from Notion via `ntn`.",
            "",
            "## Provenance",
            "",
            "- Source: Notion",
            "- Source kind: notion",
            "- Scope: " + sanitize_notion_text(scope),
            "- Source URI: " + sanitize_notion_text(target),
            "- Notion target ID: " + sanitize_notion_text(run_state.get("targetID") or ""),
            "- Ingest mode: markdown/page artifact conversion for GBrain, not native Notion database ingest",
            "",
            "## Smoke read",
            "",
        ]
        if smoke:
            lines.extend([
                "- Command: `" + sanitize_notion_text(smoke.get("command") or "") + "`",
                "- Status: `" + sanitize_notion_text(smoke.get("status")) + "`",
                "",
                "```text",
                sanitize_notion_text(smoke.get("sample") or ""),
                "```",
            ])
        elif candidates:
            lines.extend([
                "- Workspace candidate count: `" + str(len(candidates)) + "`",
                "",
                "## Workspace candidates",
                "",
            ])
            for item in candidates:
                if isinstance(item, dict):
                    lines.append("- " + sanitize_notion_text(item.get("object") or "unknown") + ": " + sanitize_notion_text(item.get("title") or "Untitled") + " (" + sanitize_notion_text(item.get("id") or "") + ")")
        else:
            lines.append("- No smoke sample was persisted.")
        if ingest_results:
            lines.extend([
                "",
                "## Ingest fetch",
                "",
            ])
            for item in ingest_results:
                if not isinstance(item, dict):
                    continue
                lines.extend([
                    "### " + sanitize_notion_text(item.get("label") or "Notion fetch"),
                    "",
                    "- Command: `" + sanitize_notion_text(item.get("command") or "") + "`",
                    "- Status: `" + sanitize_notion_text(item.get("status")) + "`",
                    "",
                    "```text",
                    sanitize_notion_text(item.get("sample") or ""),
                    "```",
                    "",
                ])
        return sanitize_notion_text("\\n".join(lines).rstrip() + "\\n")

    def notion_ingest():
        state = load_or_create_state()
        run_state = load_source_run_state("notion")
        scope = run_state.get("scope")
        if not scope or scope in {"skip", "workspace-search"}:
            state = set_notion_row_state(state, "attention", "preflight", "choose_scope", attention_reason="notion_scope_required")
            save_json(state)
            payload = {"ok": False, "reason": "notion_scope_required"}
            payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if scope == "workspace-all" and not run_state.get("workspaceConfirmed"):
            state = set_notion_row_state(state, "attention", "estimate", "confirm_workspace_ingest", attention_reason="workspace_ingest_confirmation_required")
            save_json(state)
            payload = {"ok": False, "reason": "workspace_ingest_confirmation_required"}
            payload.update(source_next_prompt_payload(state, "notion", "confirm_workspace_ingest"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if scope != "workspace-all" and run_state.get("smokeStatus") != "passed":
            state = set_notion_row_state(state, "attention", "smoke", "choose_scope", attention_reason="notion_smoke_read_required")
            save_json(state)
            payload = {"ok": False, "reason": "notion_smoke_read_required"}
            payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        ingest_results = notion_ingest_fetch_results(run_state)
        if not notion_ingest_fetch_passed(scope, ingest_results):
            run_state.update({
                "ingestResults": ingest_results,
                "phase": "ingest",
                "step": "ingest_notion",
                "updatedAt": now(),
            })
            run_path = save_source_run_state("notion", run_state)
            state = set_notion_row_state(
                state,
                "attention",
                "ingest",
                "ingest_notion",
                attention_reason="notion_ingest_fetch_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "notion_ingest_fetch_failed", "scope": scope, "ingestResults": ingest_results}
            payload.update(source_next_prompt_payload(state, "notion", "ingest_notion"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state["ingestResults"] = ingest_results
        artifact = notion_artifact_path(state)
        artifact.write_text(notion_artifact_markdown(run_state), encoding="utf-8")
        run_state.update({
            "artifactPath": str(artifact),
            "ingestedAt": now(),
            "phase": "verify",
            "step": "verify_readback",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "running",
            "verify",
            "verify_readback",
            run_state_path=run_path,
            result_summary="Notion ingest artifact written for scope " + str(scope) + ".",
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "scope": scope}
        payload.update(source_next_prompt_payload(state, "notion", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def notion_verify_readback():
        state = load_or_create_state()
        run_state = load_source_run_state("notion")
        artifact = Path(run_state.get("artifactPath") or "")
        try:
            text = artifact.read_text(encoding="utf-8")
        except Exception:
            text = ""
        forbidden_patterns = [
            "secret_",
            "ntn_",
            "oauth_code=",
            "X-Amz-Signature",
        ]
        has_forbidden = any(pattern in text for pattern in forbidden_patterns)
        if "source_kind: notion" not in text or "playbook: notion.ntn-cli.v1" not in text or has_forbidden:
            run_state.update({"readbackStatus": "failed", "phase": "verify", "step": "verify_readback", "updatedAt": now()})
            run_path = save_source_run_state("notion", run_state)
            state = set_notion_row_state(
                state,
                "attention",
                "verify",
                "verify_readback",
                attention_reason="readback_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "readback_failed", "hasForbiddenMaterial": has_forbidden}
            payload.update(source_next_prompt_payload(state, "notion", "verify_readback"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "phase": "complete", "step": "complete", "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "notion",
            "checked",
            "Notion ingest readback verified.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "readbackStatus": "passed"}
        payload.update(source_next_prompt_payload(state, "notion", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def notion_command():
        if not args:
            print("notion requires a subcommand", file=sys.stderr)
            return 2
        pending_code = reject_if_completion_report_pending("notion")
        if pending_code is not None:
            return pending_code
        subcommand = args[0]
        if subcommand == "check-cli":
            return check_required_cli("notion")
        if subcommand == "choose-scope":
            return notion_choose_scope()
        if subcommand == "confirm-workspace":
            return notion_confirm_workspace()
        if subcommand == "ingest":
            return notion_ingest()
        if subcommand == "verify-readback":
            return notion_verify_readback()
        print("unknown notion subcommand: " + subcommand, file=sys.stderr)
        return 2

    def imessage_run_state_with_command_path():
        run_state = load_source_run_state("imessage")
        command_path = required_cli_command_path("imessage", run_state)
        return run_state, command_path

    def run_imsg(arguments, timeout=15, failure_reason="history_read_failed"):
        run_state, command_path = imessage_run_state_with_command_path()
        if not command_path:
            return run_state, {
                "ok": False,
                "reason": "imsg_cli_missing",
                "stdout": "",
                "stderr": "",
                "returncode": 127,
            }
        try:
            result = subprocess.run(
                [command_path] + list(arguments),
                text=True,
                capture_output=True,
                timeout=timeout,
            )
            return run_state, {
                "ok": result.returncode == 0,
                "reason": None if result.returncode == 0 else failure_reason,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
            }
        except subprocess.TimeoutExpired as error:
            return run_state, {
                "ok": False,
                "reason": failure_reason,
                "stdout": error.stdout or "",
                "stderr": error.stderr or "imsg command timed out",
                "returncode": 124,
            }
        except Exception as error:
            return run_state, {
                "ok": False,
                "reason": failure_reason,
                "stdout": "",
                "stderr": str(error),
                "returncode": 1,
            }

    def parse_json_output(text):
        raw = text or ""
        try:
            return json.loads(raw)
        except Exception:
            items = []
            for line in raw.splitlines():
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    items.append(json.loads(stripped))
                except Exception:
                    return None
            return items if items else None

    def imessage_items(value):
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
        if isinstance(value, dict):
            for key in ("chats", "items", "data", "results", "messages"):
                nested = value.get(key)
                if isinstance(nested, list):
                    return [item for item in nested if isinstance(item, dict)]
            return [value]
        return []

    def imessage_chat_id(item):
        if not isinstance(item, dict):
            return ""
        for key in ("chat_id", "chatID", "chatId", "id", "guid", "chat_guid", "chatGuid"):
            value = item.get(key)
            if value is not None and str(value):
                return str(value)
        return ""

    def imessage_updated_at(item):
        if not isinstance(item, dict):
            return ""
        for key in ("updated_at", "updatedAt", "last_message_at", "lastMessageAt", "date", "timestamp"):
            value = item.get(key)
            if value is not None and str(value):
                return str(value)
        return ""

    def imessage_first_string(item, keys):
        if not isinstance(item, dict):
            return ""
        for key in keys:
            value = item.get(key)
            if value is not None and str(value).strip():
                return str(value).strip()
        return ""

    def imessage_chat_participants(item):
        if not isinstance(item, dict):
            return []
        participants = item.get("participants")
        if isinstance(participants, list):
            values = []
            for participant in participants:
                if isinstance(participant, dict):
                    value = imessage_first_string(participant, ["contact_name", "display_name", "name", "identifier", "address", "handle"])
                else:
                    value = str(participant).strip() if participant is not None else ""
                if value:
                    values.append(value)
            return values
        return []

    def imessage_format_handle(value):
        raw = str(value or "").strip()
        digits = re.sub(r"\\D", "", raw)
        if raw.startswith("+82"):
            national = digits[2:] if digits.startswith("82") else digits
            if national.startswith("10") and len(national) == 10:
                return "+82 " + national[:2] + "-" + national[2:6] + "-" + national[6:]
            if national.startswith("2") and len(national) >= 8:
                return "+82 " + national[:1] + "-" + national[1:-4] + "-" + national[-4:]
            if len(national) == 8:
                return "+82 " + national[:4] + "-" + national[4:]
        return raw

    def imessage_chat_display_label(item):
        label = imessage_first_string(item, ["contact_name", "display_name", "name"])
        handle = imessage_first_string(item, ["identifier", "address", "handle"])
        if not handle:
            participants = imessage_chat_participants(item)
            handle = participants[0] if participants else ""
        formatted_handle = imessage_format_handle(handle)
        if label and label not in {handle, formatted_handle}:
            return label + (" (" + formatted_handle + ")" if formatted_handle else "")
        return formatted_handle or label or imessage_chat_id(item) or "unknown conversation"

    def imessage_chat_kind(item, language=None):
        is_group = bool(item.get("is_group") or item.get("isGroup") or item.get("group")) if isinstance(item, dict) else False
        language = language or onboarding_language()
        if language == "ko":
            return "그룹 대화" if is_group else "개인 대화"
        if language == "ja":
            return "グループ会話" if is_group else "個別会話"
        return "Group" if is_group else "Direct"

    def imessage_display_time(value, language=None):
        raw = str(value or "").strip()
        if not raw:
            language = language or onboarding_language()
            if language == "ko":
                return "시간 알 수 없음"
            if language == "ja":
                return "時刻不明"
            return "unknown time"
        return raw[:16].replace("T", " ")

    def imessage_chat_plan_summary(item, language=None):
        language = language or onboarding_language()
        chat_id = imessage_chat_id(item) or "unknown"
        label = imessage_chat_display_label(item)
        service = imessage_first_string(item, ["service", "service_name", "serviceName"]) or "unknown service"
        if service == "unknown service":
            if language == "ko":
                service = "서비스 알 수 없음"
            elif language == "ja":
                service = "サービス不明"
        timestamp = imessage_display_time(imessage_updated_at(item), language=language)
        separator = " · " if language in {"ko", "ja"} else " - "
        detail = service + separator + imessage_chat_kind(item, language=language) + separator + timestamp + separator + "chat_id " + chat_id
        if label and label != chat_id:
            return label + " (" + detail + ")"
        return "chat_id " + chat_id

    def imessage_conversation_choices(limit=10):
        language = onboarding_language()
        _, result, chats = imessage_chats(limit=limit, failure_reason="history_read_failed")
        if not result.get("ok"):
            if language == "ko":
                return "최근 iMessage 대화방 후보를 가져오지 못했습니다: " + str(result.get("reason") or "history_read_failed")
            if language == "ja":
                return "最近のiMessage会話候補を取得できませんでした: " + str(result.get("reason") or "history_read_failed")
            return "Recent conversation candidates could not be listed: " + str(result.get("reason") or "history_read_failed")
        if not chats:
            if language == "ko":
                return "`imsg chats`가 최근 iMessage 대화방 후보를 반환하지 않았습니다."
            if language == "ja":
                return "`imsg chats`は最近のiMessage会話候補を返しませんでした。"
            return "No recent conversation candidates were returned by `imsg chats`."
        if language == "ko":
            lines = ["옵션 2에서 사용할 최근 iMessage 대화방 후보:"]
        elif language == "ja":
            lines = ["オプション2で使用する最近のiMessage会話候補:"]
        else:
            lines = ["Recent conversation candidates for option 2:"]
        for index, item in enumerate(chats, start=1):
            chat_id = imessage_chat_id(item) or "unknown"
            service = imessage_first_string(item, ["service", "service_name", "serviceName"]) or "unknown service"
            if service == "unknown service":
                if language == "ko":
                    service = "서비스 알 수 없음"
                elif language == "ja":
                    service = "サービス不明"
            timestamp = imessage_display_time(imessage_updated_at(item), language=language)
            lines.append(str(index) + ". " + imessage_chat_display_label(item))
            separator = " · " if language in {"ko", "ja"} else " - "
            lines.append("   " + service + separator + imessage_chat_kind(item, language=language) + separator + timestamp + separator + "chat_id " + chat_id)
        return "\\n".join(lines)

    def imessage_chats(limit=20, failure_reason="messages_full_disk_access_missing"):
        run_state, result = run_imsg(
            ["chats", "--limit", str(limit), "--json"],
            failure_reason=failure_reason,
        )
        if not result.get("ok"):
            return run_state, result, []
        return run_state, result, imessage_items(parse_json_output(result.get("stdout") or ""))

    def imessage_history(chat_id, limit=200):
        return run_imsg(["history", "--chat-id", str(chat_id), "--limit", str(limit), "--json"], timeout=30)

    def imessage_artifact_path(state=None):
        directory = state_path.parent / "source-artifacts"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / "imessage-imsg-cli.md"

    def imessage_internal_window():
        return {
            "messageLimitPerThread": 200,
            "threadListLimit": 50,
            "checkpoint": "not_started",
        }

    def imessage_resolve_selected_thread_summaries(run_state, thread_ids):
        if not thread_ids:
            run_state["selectedThreadSummaries"] = []
            run_state["selectedThreadSummaryStatus"] = "not_needed"
            return
        internal_window = run_state.get("internalWindow") if isinstance(run_state.get("internalWindow"), dict) else imessage_internal_window()
        thread_limit = max(int(internal_window.get("threadListLimit") or 50), len(thread_ids))
        run_state_for_chats, result, chats = imessage_chats(
            limit=thread_limit,
            failure_reason="history_read_failed",
        )
        for key in ("imsgCommandPath", "imsgVersion", "cliStatus"):
            if run_state_for_chats.get(key):
                run_state[key] = run_state_for_chats[key]
        run_state["selectedThreadSummaryListLimit"] = thread_limit
        if not result.get("ok"):
            run_state["selectedThreadSummaryStatus"] = "failed"
            run_state["selectedThreadSummaryFailureReason"] = result.get("reason") or "history_read_failed"
            run_state["selectedThreadSummaries"] = [
                {"chatID": str(chat_id), "summary": "chat_id " + str(chat_id)}
                for chat_id in thread_ids
            ]
            return
        by_id = {}
        for item in chats:
            chat_id = imessage_chat_id(item)
            if chat_id:
                by_id[str(chat_id)] = item
        summaries = []
        missing = []
        for chat_id in thread_ids:
            normalized = str(chat_id)
            item = by_id.get(normalized)
            if item:
                summaries.append({
                    "chatID": normalized,
                    "label": imessage_chat_display_label(item),
                    "summary": imessage_chat_plan_summary(item),
                })
            else:
                missing.append(normalized)
                summaries.append({"chatID": normalized, "summary": "chat_id " + normalized})
        run_state["selectedThreadSummaries"] = summaries
        run_state["selectedThreadSummaryStatus"] = "partial" if missing else "passed"
        if missing:
            run_state["selectedThreadSummaryMissingIDs"] = missing

    def imessage_scope_thread_ids(run_state):
        scope = run_state.get("scope")
        if scope == "selected-threads":
            values = run_state.get("selectedThreadIDs")
            thread_ids = [str(item) for item in values] if isinstance(values, list) else []
            imessage_resolve_selected_thread_summaries(run_state, thread_ids)
            run_state["resolvedThreadIDs"] = thread_ids
            run_state["estimatedThreadCount"] = len(thread_ids)
            return thread_ids
        internal_window = run_state.get("internalWindow") if isinstance(run_state.get("internalWindow"), dict) else imessage_internal_window()
        thread_limit = int(internal_window.get("threadListLimit") or 50)
        run_state_for_chats, result, chats = imessage_chats(
            limit=thread_limit,
            failure_reason="history_read_failed",
        )
        for key in ("imsgCommandPath", "imsgVersion", "cliStatus"):
            if run_state_for_chats.get(key):
                run_state[key] = run_state_for_chats[key]
        run_state["resolvedThreadListLimit"] = thread_limit
        if not result.get("ok"):
            run_state["threadResolutionStatus"] = "failed"
            run_state["threadResolutionFailureReason"] = result.get("reason") or "history_read_failed"
            return []
        run_state["threadResolutionStatus"] = "passed"
        run_state["threadResolutionCandidateCount"] = len(chats)
        if scope == "updated-since":
            since = run_state.get("since") or ""
            filtered = []
            for item in chats:
                updated_at = imessage_updated_at(item)
                if updated_at and updated_at[:10] >= since:
                    chat_id = imessage_chat_id(item)
                    if chat_id:
                        filtered.append(chat_id)
            run_state["resolvedThreadIDs"] = filtered
            run_state["estimatedThreadCount"] = len(filtered)
            return filtered
        if scope == "all-threads":
            thread_ids = [imessage_chat_id(item) for item in chats if imessage_chat_id(item)]
            run_state["resolvedThreadIDs"] = thread_ids
            run_state["estimatedThreadCount"] = len(thread_ids)
            return thread_ids
        return []

    def valid_date(value):
        return bool(re.match(r"^\\d{4}-\\d{2}-\\d{2}$", value or ""))

    def imessage_check_cli():
        return check_required_cli("imessage")

    def imessage_check_access():
        state = load_or_create_state()
        run_state, result, chats = imessage_chats(
            limit=1,
            failure_reason="messages_full_disk_access_missing",
        )
        if not result.get("ok"):
            reason = result.get("reason") or "messages_full_disk_access_missing"
            run_state.update({
                "accessStatus": "failed",
                "accessFailureReason": reason,
                "accessFailureStderr": (result.get("stderr") or "")[:500],
                "updatedAt": now(),
            })
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "preflight",
                "check_full_disk_access",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "imessage", "check_full_disk_access"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({
            "accessStatus": "passed",
            "estimatedThreadCount": len(chats) if chats else 0,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "running",
            "smoke",
            "smoke_history",
            run_state_path=run_path,
            result_summary="iMessage chat listing succeeded.",
        )
        save_json(state)
        payload = {"ok": True, "estimatedThreadCount": len(chats) if chats else 0}
        payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def imessage_smoke_history():
        state = load_or_create_state()
        run_state, result, chats = imessage_chats(
            limit=5,
            failure_reason="history_read_failed",
        )
        if not result.get("ok") or not chats:
            reason = result.get("reason") or "history_read_failed"
            run_state.update({
                "smokeHistoryStatus": "failed",
                "smokeFailureReason": reason,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "smoke",
                "smoke_history",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        chat_id = imessage_chat_id(chats[0])
        if not chat_id:
            reason = "history_read_failed"
            run_state.update({
                "smokeHistoryStatus": "failed",
                "smokeFailureReason": reason,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "smoke",
                "smoke_history",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        history_state, history_result = imessage_history(chat_id, limit=1)
        if not history_result.get("ok"):
            reason = history_result.get("reason") or "history_read_failed"
            run_state.update(history_state)
            run_state.update({
                "smokeHistoryStatus": "failed",
                "smokeFailureReason": reason,
                "smokeChatID": chat_id,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "smoke",
                "smoke_history",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update(history_state)
        run_state.update({
            "smokeHistoryStatus": "passed",
            "smokeChatID": chat_id,
            "estimatedThreadCount": len(chats),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "running",
            "ingest",
            "choose_ingest_scope",
            run_state_path=run_path,
            result_summary="iMessage read-only smoke history passed.",
        )
        save_json(state)
        payload = {"ok": True, "smokeChatID": chat_id, "estimatedThreadCount": len(chats)}
        payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def imessage_choose_scope():
        scope = single_flag_value("--scope")
        state = load_or_create_state()
        run_state = load_source_run_state("imessage")
        if scope == "skip":
            run_state.update({"scope": "skip", "updatedAt": now()})
            state = mark_source_completion_pending(
                state,
                "imessage",
                "skipped",
                "iMessage skipped for this Source Onboarding session.",
                run_state=run_state,
            )
            save_json(state)
            payload = {"ok": True, "skipped": True}
            payload.update(source_next_prompt_payload(state, "imessage", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if scope == "updated-since":
            since = single_flag_value("--since")
            if not valid_date(since):
                print("--since YYYY-MM-DD is required when --scope updated-since", file=sys.stderr)
                return 2
            run_state.update({
                "scope": scope,
                "since": since,
                "selectedThreadIDs": [],
            })
        elif scope == "selected-threads":
            chat_ids = parse_flag_value("--chat-id")
            if not chat_ids:
                print("--chat-id is required when --scope selected-threads", file=sys.stderr)
                return 2
            run_state.update({
                "scope": scope,
                "selectedThreadIDs": chat_ids,
            })
        elif scope == "all-threads":
            run_state.update({
                "scope": scope,
                "selectedThreadIDs": [],
            })
        else:
            print("--scope must be updated-since, selected-threads, all-threads, or skip", file=sys.stderr)
            return 2
        run_state.update({
            "internalWindow": imessage_internal_window(),
            "planConfirmed": False,
            "sensitiveNoticeConfirmed": False,
            "updatedAt": now(),
        })
        thread_ids = imessage_scope_thread_ids(run_state)
        run_state["estimatedThreadCount"] = len(thread_ids)
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "running",
            "ingest",
            "confirm_ingest_plan",
            run_state_path=run_path,
            result_summary="iMessage ingest scope selected: " + scope,
        )
        save_json(state)
        payload = {"ok": True, "scope": scope, "estimatedThreadCount": run_state.get("estimatedThreadCount")}
        payload.update(source_next_prompt_payload(state, "imessage", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def imessage_confirm_plan():
        answer = single_flag_value("--answer").strip().lower()
        if answer not in {"yes", "y", "no", "n"}:
            print("--answer must be yes or no", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("imessage")
        if answer in {"no", "n"}:
            run_state.update({
                "planConfirmed": False,
                "sensitiveNoticeConfirmed": False,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "ingest",
                "choose_ingest_scope",
                attention_reason="ingest_plan_rejected",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_rejected"}
            payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_imessage_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_scope_required"}
            payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({
            "planConfirmed": True,
            "sensitiveNoticeConfirmed": True,
            "confirmedAt": now(),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "running",
            "ingest",
            "ingest_messages",
            run_state_path=run_path,
            result_summary="iMessage ingest plan confirmed.",
        )
        save_json(state)
        payload = {"ok": True, "scope": run_state.get("scope")}
        payload.update(source_next_prompt_payload(state, "imessage", "ingest_messages"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def imessage_ingest():
        state = load_or_create_state()
        run_state = load_source_run_state("imessage")
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_imessage_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_scope_required"}
            payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not run_state.get("planConfirmed"):
            state = set_imessage_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}
            payload.update(source_next_prompt_payload(state, "imessage", "confirm_ingest_plan"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        thread_ids = imessage_scope_thread_ids(run_state)
        if not thread_ids:
            reason = run_state.get("threadResolutionFailureReason") or "no_threads_in_approved_scope"
            run_state.update({
                "ingestStatus": "failed",
                "ingestFailureReason": reason,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "ingest",
                "ingest_messages",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "imessage", "ingest_messages"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        messages_by_thread = []
        message_limit = int((run_state.get("internalWindow") or {}).get("messageLimitPerThread") or 200)
        for chat_id in thread_ids:
            history_state, result = imessage_history(chat_id, limit=message_limit)
            if not result.get("ok"):
                reason = result.get("reason") or "history_read_failed"
                run_state.update(history_state)
                run_state.update({
                    "ingestStatus": "failed",
                    "ingestFailureReason": reason,
                    "failedThreadID": chat_id,
                    "updatedAt": now(),
                })
                run_path = save_source_run_state("imessage", run_state)
                state = set_imessage_row_state(
                    state,
                    "attention",
                    "ingest",
                    "ingest_messages",
                    attention_reason=reason,
                    run_state_path=run_path,
                )
                save_json(state)
                payload = {"ok": False, "reason": reason, "failedThreadID": chat_id}
                payload.update(source_next_prompt_payload(state, "imessage", "ingest_messages"))
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            parsed = parse_json_output(result.get("stdout") or "")
            messages_by_thread.append({
                "chat_id": chat_id,
                "messages": imessage_items(parsed),
            })
        if not messages_by_thread:
            reason = "history_read_failed"
            run_state.update({
                "ingestStatus": "failed",
                "ingestFailureReason": reason,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "ingest",
                "ingest_messages",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "imessage", "ingest_messages"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        artifact = imessage_artifact_path(state)
        lines = [
            "# iMessage Source Onboarding Ingest",
            "",
            "source: imessage",
            "playbook: imessage.imsg-cli.v1",
            "scope: " + str(run_state.get("scope")),
            "scope_summary: " + imessage_scope_summary(run_state),
            "thread_count: " + str(len(thread_ids)),
            "sensitive_notice_confirmed: " + str(bool(run_state.get("sensitiveNoticeConfirmed"))).lower(),
            "",
            "## Threads",
        ]
        for item in messages_by_thread:
            lines.extend([
                "",
                "### " + str(item.get("chat_id")),
                "",
                "```json",
                json.dumps(item.get("messages") or [], ensure_ascii=False, indent=2),
                "```",
            ])
        artifact.write_text("\\n".join(lines).rstrip() + "\\n", encoding="utf-8")
        run_state.update({
            "artifactPath": str(artifact),
            "ingestedThreadCount": len(thread_ids),
            "ingestedAt": now(),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "running",
            "verify",
            "verify_readback",
            run_state_path=run_path,
            result_summary="iMessage ingest artifact written for " + str(len(thread_ids)) + " conversations.",
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "ingestedThreadCount": len(thread_ids)}
        payload.update(source_next_prompt_payload(state, "imessage", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def imessage_verify_readback():
        state = load_or_create_state()
        run_state = load_source_run_state("imessage")
        artifact = Path(run_state.get("artifactPath") or "")
        try:
            text = artifact.read_text(encoding="utf-8")
        except Exception:
            text = ""
        if "source: imessage" not in text or "playbook: imessage.imsg-cli.v1" not in text:
            run_state.update({"readbackStatus": "failed", "updatedAt": now()})
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "verify",
                "verify_readback",
                attention_reason="readback_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "readback_failed"}
            payload.update(source_next_prompt_payload(state, "imessage", "verify_readback"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "imessage",
            "checked",
            "iMessage ingest readback verified for " + str(run_state.get("ingestedThreadCount") or 0) + " conversations.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "readbackStatus": "passed"}
        payload.update(source_next_prompt_payload(state, "imessage", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def imessage_command():
        if not args:
            print("imessage requires a subcommand", file=sys.stderr)
            return 2
        pending_code = reject_if_completion_report_pending("imessage")
        if pending_code is not None:
            return pending_code
        subcommand = args[0]
        if subcommand == "check-cli":
            return imessage_check_cli()
        if subcommand == "check-access":
            return imessage_check_access()
        if subcommand == "smoke-history":
            return imessage_smoke_history()
        if subcommand == "choose-scope":
            return imessage_choose_scope()
        if subcommand == "confirm-plan":
            return imessage_confirm_plan()
        if subcommand == "ingest":
            return imessage_ingest()
        if subcommand == "verify-readback":
            return imessage_verify_readback()
        print("unknown imessage subcommand: " + subcommand, file=sys.stderr)
        return 2

    def apple_reminders_run_state_with_command_path():
        run_state = load_source_run_state("apple-reminders")
        command_path = required_cli_command_path("apple-reminders", run_state)
        return run_state, command_path

    def apple_reminders_brew_path():
        return shutil.which("brew") or ""

    def apple_reminders_command_result(command, timeout=120):
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
            return {
                "ok": result.returncode == 0,
                "returncode": result.returncode,
                "stdout": (result.stdout or "")[:1000],
                "stderr": (result.stderr or "")[:1000],
            }
        except subprocess.TimeoutExpired as error:
            return {
                "ok": False,
                "returncode": 124,
                "stdout": (error.stdout or "")[:1000],
                "stderr": (error.stderr or "command timed out")[:1000],
            }
        except Exception as error:
            return {
                "ok": False,
                "returncode": 1,
                "stdout": "",
                "stderr": str(error)[:1000],
            }

    def apple_reminders_install_answer(flag):
        answer = single_flag_value(flag).strip().lower()
        if answer in {"yes", "y"}:
            return "yes"
        if answer in {"no", "n"}:
            return "no"
        return ""

    def apple_reminders_record_attention(run_state, state, reason, step="check_remindctl_cli"):
        run_state.update({
            "cliStatus": "missing",
            "phase": "preflight",
            "step": step,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "attention",
            "preflight",
            step,
            attention_reason=reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": reason}
        payload.update(source_next_prompt_payload(state, "apple-reminders", step))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1

    def apple_reminders_check_cli():
        state = load_or_create_state()
        run_state = load_source_run_state("apple-reminders")
        command_path = required_cli_command_path("apple-reminders", run_state)
        if command_path:
            return check_required_cli("apple-reminders")

        brew_path = apple_reminders_brew_path()
        homebrew_answer = apple_reminders_install_answer("--homebrew-install-answer")
        remindctl_answer = apple_reminders_install_answer("--remindctl-install-answer")
        run_state["homebrewPath"] = brew_path or None

        if not brew_path:
            run_state["homebrewInstallAsked"] = True
            if homebrew_answer == "no":
                run_state.update({
                    "homebrewInstallAnswer": "no",
                    "homebrewInstallResult": {"status": "user_declined"},
                    "installCommandRun": False,
                })
                return apple_reminders_record_attention(run_state, state, "homebrew_install_declined")
            if homebrew_answer != "yes":
                run_state.update({
                    "homebrewInstallAnswer": None,
                    "homebrewInstallResult": {"status": "not_run"},
                    "installCommandRun": False,
                })
                return apple_reminders_record_attention(run_state, state, "homebrew_install_consent_required")
            run_state["homebrewInstallAnswer"] = "yes"
            run_state["installCommandRun"] = True
            homebrew_command = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
            result = apple_reminders_command_result(["/bin/bash", "-c", homebrew_command], timeout=1800)
            run_state["homebrewInstallResult"] = {
                "status": "succeeded" if result.get("ok") else "failed",
                "returncode": result.get("returncode"),
                "stderrPreview": result.get("stderr"),
            }
            run_path = save_source_run_state("apple-reminders", run_state)
            brew_path = apple_reminders_brew_path()
            if not brew_path:
                state = set_apple_reminders_row_state(
                    state,
                    "attention",
                    "preflight",
                    "check_remindctl_cli",
                    attention_reason="homebrew_install_failed",
                    run_state_path=run_path,
                )
                save_json(state)
                payload = {"ok": False, "reason": "homebrew_install_failed", "homebrewInstallResult": run_state.get("homebrewInstallResult")}
                payload.update(source_next_prompt_payload(state, "apple-reminders", "check_remindctl_cli"))
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            run_state["homebrewPath"] = brew_path

        run_state["remindctlInstallAsked"] = True
        if remindctl_answer == "no":
            run_state.update({
                "remindctlInstallAnswer": "no",
                "remindctlInstallResult": {"status": "user_declined"},
                "installCommandRun": bool(run_state.get("installCommandRun")),
            })
            return apple_reminders_record_attention(run_state, state, "remindctl_install_declined")
        if remindctl_answer != "yes":
            run_state.update({
                "remindctlInstallAnswer": None,
                "remindctlInstallResult": {"status": "not_run"},
                "installCommandRun": bool(run_state.get("installCommandRun")),
            })
            return apple_reminders_record_attention(run_state, state, "remindctl_install_consent_required")

        run_state["remindctlInstallAnswer"] = "yes"
        run_state["installCommandRun"] = True
        result = apple_reminders_command_result([brew_path, "install", "steipete/tap/remindctl"], timeout=600)
        run_state["remindctlInstallResult"] = {
            "status": "succeeded" if result.get("ok") else "failed",
            "returncode": result.get("returncode"),
            "stderrPreview": result.get("stderr"),
        }
        run_path = save_source_run_state("apple-reminders", run_state)
        command_path = shutil.which("remindctl") or ""
        if not result.get("ok") or not command_path:
            state = set_apple_reminders_row_state(
                state,
                "attention",
                "preflight",
                "check_remindctl_cli",
                attention_reason="remindctl_install_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "remindctl_install_failed", "remindctlInstallResult": run_state.get("remindctlInstallResult")}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "check_remindctl_cli"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        return check_required_cli("apple-reminders")

    def run_remindctl(arguments, timeout=30, failure_reason="remindctl_command_failed"):
        run_state, command_path = apple_reminders_run_state_with_command_path()
        if not command_path:
            return run_state, {
                "ok": False,
                "reason": "remindctl_cli_missing",
                "stdout": "",
                "stderr": "",
                "returncode": 127,
                "json": None,
            }
        try:
            result = subprocess.run(
                [command_path] + list(arguments),
                text=True,
                capture_output=True,
                timeout=timeout,
            )
            parsed = parse_json_output(result.stdout or "")
            reason = None if result.returncode == 0 else apple_reminders_failure_reason(result.stdout, result.stderr, failure_reason)
            return run_state, {
                "ok": result.returncode == 0,
                "reason": reason,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
                "json": parsed,
            }
        except subprocess.TimeoutExpired as error:
            return run_state, {"ok": False, "reason": failure_reason, "stdout": error.stdout or "", "stderr": error.stderr or "remindctl command timed out", "returncode": 124, "json": None}
        except Exception as error:
            return run_state, {"ok": False, "reason": failure_reason, "stdout": "", "stderr": str(error), "returncode": 1, "json": None}

    def apple_reminders_failure_reason(stdout, stderr, default_reason):
        combined = (str(stdout or "") + "\\n" + str(stderr or "")).lower()
        if any(token in combined for token in ("not authorized", "not-determined", "denied", "permission", "privacy", "tcc")):
            return "reminders_permission_attention"
        return default_reason

    def apple_reminders_permission_status(value, text=""):
        candidates = []
        if isinstance(value, dict):
            for key in ("status", "authorizationStatus", "authorization_status", "access", "permission"):
                item = value.get(key)
                if item is not None:
                    candidates.append(str(item))
        if isinstance(value, str):
            candidates.append(value)
        candidates.append(str(text or ""))
        combined = " ".join(candidates).lower()
        if "full-access" in combined or "full_access" in combined or "authorized" in combined or "granted" in combined:
            return "full-access"
        if "denied" in combined:
            return "denied"
        if "not-determined" in combined or "not determined" in combined or "undetermined" in combined:
            return "not-determined"
        if "restricted" in combined:
            return "restricted"
        return "unknown"

    def apple_reminders_check_access():
        preflight_code = require_cli_preflight_or_attention("apple-reminders")
        if preflight_code is not None:
            return preflight_code
        state = load_or_create_state()
        run_state, status_result = run_remindctl(["status", "--json"], timeout=15, failure_reason="reminders_status_failed")
        initial_status = apple_reminders_permission_status(status_result.get("json"), status_result.get("stdout") or status_result.get("stderr"))
        _, doctor_result = run_remindctl(["doctor", "--for-agent"], timeout=20, failure_reason="reminders_doctor_failed")
        authorize_result = {"ok": True, "returncode": 0, "stdout": "", "stderr": ""}
        if initial_status != "full-access":
            _, authorize_result = run_remindctl(["authorize"], timeout=60, failure_reason="reminders_authorize_failed")
        _, final_result = run_remindctl(["status", "--json"], timeout=15, failure_reason="reminders_status_failed")
        final_status = apple_reminders_permission_status(final_result.get("json"), final_result.get("stdout") or final_result.get("stderr"))
        if final_status == "unknown" and initial_status == "full-access":
            final_status = initial_status
        run_state.update({
            "permissionStatus": final_status,
            "permissionInitialStatus": initial_status,
            "doctorStatus": "passed" if doctor_result.get("ok") else "attention",
            "doctorPreview": ((doctor_result.get("stdout") or doctor_result.get("stderr") or "")[:800]),
            "authorizeRun": initial_status != "full-access",
            "authorizeResult": {
                "status": "succeeded" if authorize_result.get("ok") else "failed",
                "returncode": authorize_result.get("returncode"),
            },
            "runtimePermissionOwnerNote": "macOS Reminders permission can attach to the runtime process that executes remindctl.",
            "updatedAt": now(),
        })
        if final_status != "full-access":
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(
                state,
                "attention",
                "preflight",
                "check_reminders_permission",
                attention_reason="reminders_permission_attention",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "reminders_permission_attention", "permissionStatus": final_status}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "check_reminders_permission"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "running",
            "smoke",
            "smoke_list_reminders",
            run_state_path=run_path,
            result_summary="Apple Reminders permission verified through remindctl.",
        )
        save_json(state)
        payload = {"ok": True, "permissionStatus": final_status}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "smoke_list_reminders"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def reminder_items(value):
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
        if isinstance(value, dict):
            for key in ("reminders", "items", "data", "results"):
                nested = value.get(key)
                if isinstance(nested, list):
                    return [item for item in nested if isinstance(item, dict)]
            return [value]
        return []

    def reminder_field_names(items):
        fields = []
        seen = set()
        for item in items:
            if not isinstance(item, dict):
                continue
            for key in item.keys():
                text = str(key)
                if text not in seen:
                    seen.add(text)
                    fields.append(text)
        return fields

    def reminder_list_title(item):
        if not isinstance(item, dict):
            return ""
        for key in ("title", "name", "list", "listName"):
            value = item.get(key)
            if value is not None and str(value).strip():
                return str(value).strip()
        return ""

    def apple_reminders_smoke_list():
        preflight_code = require_cli_preflight_or_attention("apple-reminders")
        if preflight_code is not None:
            return preflight_code
        state = load_or_create_state()
        run_state, list_result = run_remindctl(["list", "--json"], timeout=25, failure_reason="reminders_list_failed")
        if not list_result.get("ok"):
            reason = list_result.get("reason") or "reminders_list_failed"
            run_state.update({"smokeStatus": "failed", "smokeFailureReason": reason, "updatedAt": now()})
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(state, "attention", "smoke", "smoke_list_reminders", attention_reason=reason, run_state_path=run_path)
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "smoke_list_reminders"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        lists = reminder_items(list_result.get("json"))
        list_titles = [reminder_list_title(item) for item in lists if reminder_list_title(item)]
        run_state, open_result = run_remindctl(["open", "--json"], timeout=25, failure_reason="reminders_open_failed")
        open_items = reminder_items(open_result.get("json")) if open_result.get("ok") else []
        optional = {}
        for label in ("today", "overdue", "week"):
            _, result = run_remindctl([label, "--json"], timeout=25, failure_reason="reminders_" + label + "_failed")
            optional[label] = {
                "ok": bool(result.get("ok")),
                "count": len(reminder_items(result.get("json"))) if result.get("ok") else None,
                "returncode": result.get("returncode"),
            }
        list_specific = None
        if list_titles:
            _, list_open_result = run_remindctl(["open", "--list", list_titles[0], "--json"], timeout=25, failure_reason="reminders_list_open_failed")
            list_specific = {
                "command": "remindctl open --list <list> --json",
                "list": list_titles[0],
                "ok": bool(list_open_result.get("ok")),
                "count": len(reminder_items(list_open_result.get("json"))) if list_open_result.get("ok") else None,
            }
        fields = sorted(set(reminder_field_names(lists) + reminder_field_names(open_items)))
        run_state.update({
            "smokeStatus": "passed",
            "listCount": len(lists),
            "openReminderCount": len(open_items),
            "listTitles": list_titles[:20],
            "observedListFields": reminder_field_names(lists),
            "observedReminderFields": reminder_field_names(open_items),
            "optionalSmokeChecks": optional,
            "listSpecificOpenCheck": list_specific,
            "observedFields": fields,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "running",
            "ingest",
            "choose_ingest_scope",
            run_state_path=run_path,
            result_summary="Apple Reminders read-only smoke passed.",
        )
        save_json(state)
        payload = {"ok": True, "listCount": len(lists), "openReminderCount": len(open_items), "listTitles": list_titles[:20]}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_reminders_scope_read_command(run_state):
        scope = run_state.get("scope")
        if scope == "all-open":
            return ["open", "--json"], None
        if scope == "one-list":
            list_name = str(run_state.get("list") or "")
            return ["open", "--list", list_name, "--json"], None
        if scope in {"today", "week", "overdue"}:
            return [scope, "--json"], None
        if scope == "custom":
            lists = run_state.get("lists") if isinstance(run_state.get("lists"), list) else []
            status = str(run_state.get("status") or "open")
            due = str(run_state.get("dueWindow") or "")
            include_completed = bool(run_state.get("includeCompleted"))
            if due in {"today", "week", "overdue"} and not lists and not include_completed:
                return [due, "--json"], None
            if len(lists) == 1:
                if include_completed or status in {"completed", "all"}:
                    return ["list", lists[0], "--json"], "list_specific_completed_scope"
                return ["open", "--list", lists[0], "--json"], None
            if not lists and not include_completed and status in {"", "open"}:
                return ["open", "--json"], None
            return None, "unsupported_custom_scope"
        return None, "ingest_scope_required"

    def apple_reminders_estimate_scope(run_state):
        command, unsupported = apple_reminders_scope_read_command(run_state)
        if unsupported:
            return None, [], unsupported
        _, result = run_remindctl(command, timeout=30, failure_reason="reminders_scope_read_failed")
        if not result.get("ok"):
            return None, [], result.get("reason") or "reminders_scope_read_failed"
        items = reminder_items(result.get("json"))
        cap = run_state.get("itemCap")
        if isinstance(cap, int) and cap >= 0:
            items = items[:cap]
        return len(items), reminder_field_names(items), None

    def apple_reminders_choose_scope():
        scope = single_flag_value("--scope")
        if scope not in {"all-open", "one-list", "today", "week", "custom", "skip"}:
            print("--scope must be all-open, one-list, today, week, custom, or skip", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("apple-reminders")
        if scope == "skip":
            run_state.update({"scope": "skip", "phase": "complete", "step": "complete", "updatedAt": now()})
            state = mark_source_completion_pending(
                state,
                "apple-reminders",
                "skipped",
                "Apple Reminders skipped for this Source Onboarding session.",
                run_state=run_state,
            )
            save_json(state)
            payload = {"ok": True, "skipped": True}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        preflight_code = require_cli_preflight_or_attention("apple-reminders")
        if preflight_code is not None:
            return preflight_code
        run_state = load_source_run_state("apple-reminders")
        update = {"scope": scope}
        if scope == "one-list":
            list_name = single_flag_value("--list")
            if not list_name:
                print("--list is required when --scope one-list", file=sys.stderr)
                return 2
            update["list"] = list_name
            update["includeCompleted"] = False
            update["status"] = "open"
        if scope == "custom":
            lists = parse_flag_value("--list")
            include_completed = apple_reminders_install_answer("--include-completed") == "yes"
            status = single_flag_value("--status") or ("all" if include_completed else "open")
            due_window = single_flag_value("--due-window")
            if status not in {"open", "completed", "all"}:
                print("--status must be open, completed, or all", file=sys.stderr)
                return 2
            update.update({
                "lists": lists,
                "includeCompleted": include_completed,
                "status": status,
                "dueWindow": due_window,
            })
        cap_text = single_flag_value("--item-cap")
        if cap_text:
            try:
                cap_value = int(cap_text)
            except Exception:
                print("--item-cap must be an integer", file=sys.stderr)
                return 2
            if cap_value < 0:
                print("--item-cap must be non-negative", file=sys.stderr)
                return 2
            update["itemCap"] = cap_value
        elif "itemCap" in run_state:
            run_state.pop("itemCap", None)
        run_state.update(update)
        expected_count, fields, reason = apple_reminders_estimate_scope(run_state)
        if reason == "unsupported_custom_scope":
            run_state.update({"expectedCount": None, "observedReminderFields": fields, "planConfirmed": False, "updatedAt": now()})
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(
                state,
                "attention",
                "ingest",
                "choose_ingest_scope",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({
            "expectedCount": expected_count,
            "observedReminderFields": fields,
            "planConfirmed": False,
            "plannedArtifactPath": str(apple_reminders_artifact_path(state)),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "running",
            "ingest",
            "confirm_ingest_plan",
            run_state_path=run_path,
            result_summary="Apple Reminders ingest scope selected: " + scope,
        )
        save_json(state)
        payload = {"ok": True, "scope": scope, "expectedCount": expected_count, "fields": fields}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_reminders_confirm_plan():
        answer = single_flag_value("--answer").strip().lower()
        if answer not in {"yes", "y", "no", "n"}:
            print("--answer must be yes or no", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("apple-reminders")
        if answer in {"no", "n"}:
            run_state.update({"planConfirmed": False, "updatedAt": now()})
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(
                state,
                "attention",
                "ingest",
                "choose_ingest_scope",
                attention_reason="ingest_plan_rejected",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_rejected"}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_apple_reminders_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_scope_required"}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"planConfirmed": True, "confirmedAt": now(), "updatedAt": now()})
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "running",
            "ingest",
            "ingest_reminders",
            run_state_path=run_path,
            result_summary="Apple Reminders ingest plan confirmed.",
        )
        save_json(state)
        payload = {"ok": True, "scope": run_state.get("scope"), "expectedCount": run_state.get("expectedCount")}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "ingest_reminders"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_reminders_artifact_path(state=None):
        target = None
        if isinstance(state, dict):
            target = state.get("entryContext", {}).get("gbrainTargetPath")
        if target and Path(target).is_dir():
            directory = Path(target) / "sources"
        else:
            directory = state_path.parent / "source-ingest-artifacts"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / "apple-reminders-remindctl.md"

    def apple_reminders_item_list_name(item, run_state):
        if not isinstance(item, dict):
            return str(run_state.get("list") or "unknown")
        for key in ("list", "listName", "calendar", "calendarTitle"):
            value = item.get(key)
            if value is not None and str(value).strip():
                return str(value).strip()
        return str(run_state.get("list") or "unknown")

    def apple_reminders_field_value(value):
        if value is None:
            return ""
        if isinstance(value, (str, int, float, bool)):
            return str(value)
        return json.dumps(value, ensure_ascii=False, sort_keys=True)

    def apple_reminders_ingest():
        state = load_or_create_state()
        run_state = load_source_run_state("apple-reminders")
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_apple_reminders_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_scope_required"}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not run_state.get("planConfirmed"):
            state = set_apple_reminders_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "confirm_ingest_plan"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        command, unsupported = apple_reminders_scope_read_command(run_state)
        if unsupported:
            run_state.update({"ingestStatus": "failed", "ingestFailureReason": unsupported, "updatedAt": now()})
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(state, "attention", "ingest", "ingest_reminders", attention_reason=unsupported, run_state_path=run_path)
            save_json(state)
            payload = {"ok": False, "reason": unsupported}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "ingest_reminders"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        _, result = run_remindctl(command, timeout=60, failure_reason="reminders_ingest_read_failed")
        if not result.get("ok"):
            reason = result.get("reason") or "reminders_ingest_read_failed"
            run_state.update({"ingestStatus": "failed", "ingestFailureReason": reason, "updatedAt": now()})
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(state, "attention", "ingest", "ingest_reminders", attention_reason=reason, run_state_path=run_path)
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "ingest_reminders"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        items = reminder_items(result.get("json"))
        cap = run_state.get("itemCap")
        if isinstance(cap, int) and cap >= 0:
            items = items[:cap]
        fields = reminder_field_names(items)
        artifact = apple_reminders_artifact_path(state)
        today = now()[:10]
        lines = [
            "# Apple Reminders Source Onboarding Ingest",
            "",
            "source: apple-reminders",
            "playbook: apple-reminders.remindctl.v1",
            "scope: " + str(run_state.get("scope")),
            "scope_summary: " + apple_reminders_scope_summary(run_state),
            "completed_included: " + str(bool(run_state.get("includeCompleted"))).lower(),
            "item_count: " + str(len(items)),
            "fields_returned: " + (", ".join(fields) if fields else "none"),
            "redaction_policy: approved scope only; raw JSON dump not stored",
            "",
            "## Reminders",
        ]
        for index, item in enumerate(items, start=1):
            list_name = apple_reminders_item_list_name(item, run_state)
            title = str(item.get("title") or item.get("name") or ("Reminder " + str(index))) if isinstance(item, dict) else "Reminder " + str(index)
            lines.extend(["", "### " + title, ""])
            if isinstance(item, dict):
                for key in fields:
                    if key in item:
                        lines.append("- " + str(key) + ": " + apple_reminders_field_value(item.get(key)))
            lines.append("")
            lines.append('[Source: Apple Reminders list "' + list_name + '", ' + today + ']')
        artifact.write_text("\\n".join(lines).rstrip() + "\\n", encoding="utf-8")
        run_state.update({
            "artifactPath": str(artifact),
            "ingestedReminderCount": len(items),
            "observedReminderFields": fields,
            "ingestCommand": "remindctl " + " ".join(command),
            "ingestedAt": now(),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "running",
            "verify",
            "verify_readback",
            run_state_path=run_path,
            result_summary="Apple Reminders ingest artifact written for " + str(len(items)) + " reminders.",
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "ingestedReminderCount": len(items)}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_reminders_verify_readback():
        state = load_or_create_state()
        run_state = load_source_run_state("apple-reminders")
        artifact = Path(run_state.get("artifactPath") or "")
        try:
            text = artifact.read_text(encoding="utf-8")
        except Exception:
            text = ""
        if "source: apple-reminders" not in text or "playbook: apple-reminders.remindctl.v1" not in text:
            run_state.update({"readbackStatus": "failed", "updatedAt": now()})
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(
                state,
                "attention",
                "verify",
                "verify_readback",
                attention_reason="readback_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "readback_failed"}
            payload.update(source_next_prompt_payload(state, "apple-reminders", "verify_readback"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()})
        install_summary = "homebrew asked=" + str(run_state.get("homebrewInstallAsked")) + " answer=" + str(run_state.get("homebrewInstallAnswer")) + "; remindctl asked=" + str(run_state.get("remindctlInstallAsked")) + " answer=" + str(run_state.get("remindctlInstallAnswer")) + "; installCommandRun=" + str(bool(run_state.get("installCommandRun"))).lower()
        state = mark_source_completion_pending(
            state,
            "apple-reminders",
            "checked",
            "Apple Reminders ingest readback verified for " + str(run_state.get("ingestedReminderCount") or 0) + " reminders. " + install_summary,
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "readbackStatus": "passed"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_reminders_command():
        if not args:
            print("apple-reminders requires a subcommand", file=sys.stderr)
            return 2
        pending_code = reject_if_completion_report_pending("apple-reminders")
        if pending_code is not None:
            return pending_code
        subcommand = args[0]
        if subcommand == "check-cli":
            return apple_reminders_check_cli()
        if subcommand == "check-access":
            return apple_reminders_check_access()
        if subcommand == "smoke-list":
            return apple_reminders_smoke_list()
        if subcommand == "choose-scope":
            return apple_reminders_choose_scope()
        if subcommand == "confirm-plan":
            return apple_reminders_confirm_plan()
        if subcommand == "ingest":
            return apple_reminders_ingest()
        if subcommand == "verify-readback":
            return apple_reminders_verify_readback()
        print("unknown apple-reminders subcommand: " + subcommand, file=sys.stderr)
        return 2

    def apple_notes_run_state_with_command_path():
        run_state = load_source_run_state("apple-notes")
        command_path = required_cli_command_path("apple-notes", run_state)
        return run_state, command_path

    def apple_notes_failure_reason(result, default_reason="memo_notes_read_failed"):
        stderr = str(result.get("stderr") or "").lower()
        stdout = str(result.get("stdout") or "").lower()
        combined = stderr + "\\n" + stdout
        if any(token in combined for token in ("not authorized", "automation", "tcc", "operation not permitted", "permission")):
            return "notes_automation_denied"
        if result.get("returncode") == 127:
            return "memo_cli_missing"
        return default_reason

    def run_memo(arguments, timeout=20, failure_reason="memo_notes_read_failed"):
        run_state, command_path = apple_notes_run_state_with_command_path()
        if not command_path:
            return run_state, {
                "ok": False,
                "reason": "memo_cli_missing",
                "stdout": "",
                "stderr": "",
                "returncode": 127,
            }
        try:
            result = subprocess.run(
                [command_path] + list(arguments),
                text=True,
                capture_output=True,
                timeout=timeout,
            )
            payload = {
                "ok": result.returncode == 0,
                "reason": None if result.returncode == 0 else failure_reason,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
            }
            if not payload["ok"]:
                payload["reason"] = apple_notes_failure_reason(payload, failure_reason)
            return run_state, payload
        except subprocess.TimeoutExpired as error:
            return run_state, {
                "ok": False,
                "reason": failure_reason,
                "stdout": error.stdout or "",
                "stderr": error.stderr or "memo command timed out",
                "returncode": 124,
            }
        except Exception as error:
            return run_state, {
                "ok": False,
                "reason": failure_reason,
                "stdout": "",
                "stderr": str(error),
                "returncode": 1,
            }

    def memo_note_ids_from_text(text):
        ids = []
        seen = set()
        for line in str(text or "").splitlines():
            match = re.match(r"^\\s*(\\d+)\\.", line)
            if not match:
                continue
            note_id = match.group(1)
            if note_id not in seen:
                seen.add(note_id)
                ids.append(note_id)
        return ids

    def memo_preview(text, limit=4000):
        value = str(text or "").strip()
        return value[:limit]

    def apple_notes_artifact_path(state=None):
        target = None
        if isinstance(state, dict):
            target = state.get("entryContext", {}).get("gbrainTargetPath")
        if target and Path(target).is_dir():
            directory = Path(target) / "sources"
        else:
            directory = state_path.parent / "source-ingest-artifacts"
        directory.mkdir(parents=True, exist_ok=True)
        return directory / "apple-notes-memo-cli.md"

    def apple_notes_check_cli():
        return check_required_cli("apple-notes")

    def apple_notes_check_access():
        state = load_or_create_state()
        run_state, result = run_memo(["notes", "-fl"], timeout=20, failure_reason="notes_automation_denied")
        if not result.get("ok"):
            reason = result.get("reason") or "notes_automation_denied"
            run_state.update({
                "accessStatus": "failed",
                "accessFailureReason": reason,
                "accessFailureStderr": (result.get("stderr") or "")[:500],
                "updatedAt": now(),
            })
            run_path = save_source_run_state("apple-notes", run_state)
            state = set_apple_notes_row_state(
                state,
                "attention",
                "preflight",
                "check_notes_automation",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "apple-notes", "check_notes_automation"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({
            "accessStatus": "passed",
            "folderListPreview": memo_preview(result.get("stdout")),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "running",
            "smoke",
            "smoke_list_notes",
            run_state_path=run_path,
            result_summary="Apple Notes folder/list command succeeded through memo.",
        )
        save_json(state)
        payload = {"ok": True, "folderListPreview": memo_preview(result.get("stdout"), limit=500)}
        payload.update(source_next_prompt_payload(state, "apple-notes", "smoke_list_notes"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_notes_smoke_list():
        state = load_or_create_state()
        run_state, result = run_memo(["notes", "-fl"], timeout=20, failure_reason="memo_notes_list_failed")
        if not result.get("ok") or not str(result.get("stdout") or "").strip():
            run_state, retry = run_memo(["notes", "-nc", "-fl"], timeout=25, failure_reason="memo_notes_list_failed")
            if retry.get("ok") and str(retry.get("stdout") or "").strip():
                result = retry
        if not result.get("ok") or not str(result.get("stdout") or "").strip():
            reason = result.get("reason") or "memo_notes_list_failed"
            run_state.update({
                "smokeListStatus": "failed",
                "smokeFailureReason": reason,
                "smokeFailureStderr": (result.get("stderr") or "")[:500],
                "updatedAt": now(),
            })
            run_path = save_source_run_state("apple-notes", run_state)
            state = set_apple_notes_row_state(
                state,
                "attention",
                "smoke",
                "smoke_list_notes",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "apple-notes", "smoke_list_notes"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        note_ids = memo_note_ids_from_text(result.get("stdout"))
        run_state.update({
            "smokeListStatus": "passed",
            "folderListPreview": memo_preview(result.get("stdout")),
            "smokeNoteIDs": note_ids[:20],
            "estimatedNoteCount": len(note_ids) if note_ids else None,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "running",
            "ingest",
            "choose_ingest_scope",
            run_state_path=run_path,
            result_summary="Apple Notes read-only smoke list passed.",
        )
        save_json(state)
        payload = {"ok": True, "estimatedNoteCount": len(note_ids) if note_ids else None}
        payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_notes_estimate_scope(run_state):
        scope = run_state.get("scope")
        if scope == "selected-notes":
            return list(run_state.get("selectedNoteIDs") or [])
        if scope == "sample":
            ids = run_state.get("smokeNoteIDs") if isinstance(run_state.get("smokeNoteIDs"), list) else []
            if ids:
                return [str(item) for item in ids[:3]]
            _, result = run_memo(["notes"], timeout=20, failure_reason="memo_notes_list_failed")
            return memo_note_ids_from_text(result.get("stdout"))[:3] if result.get("ok") else []
        if scope == "folder":
            folder = str(run_state.get("folder") or "")
            _, result = run_memo(["notes", "-f", folder], timeout=25, failure_reason="memo_notes_list_failed")
            return memo_note_ids_from_text(result.get("stdout")) if result.get("ok") else []
        if scope == "search":
            query = str(run_state.get("query") or "")
            _, result = run_memo(["notes", "-s", query], timeout=25, failure_reason="memo_notes_list_failed")
            return memo_note_ids_from_text(result.get("stdout")) if result.get("ok") else []
        return []

    def apple_notes_choose_scope():
        scope = single_flag_value("--scope")
        state = load_or_create_state()
        run_state = load_source_run_state("apple-notes")
        if scope == "skip":
            run_state.update({"scope": "skip", "updatedAt": now()})
            state = mark_source_completion_pending(
                state,
                "apple-notes",
                "skipped",
                "Apple Notes skipped for this Source Onboarding session.",
                run_state=run_state,
            )
            save_json(state)
            payload = {"ok": True, "skipped": True}
            payload.update(source_next_prompt_payload(state, "apple-notes", "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if scope == "folder":
            folder = single_flag_value("--folder")
            if not folder:
                print("--folder is required when --scope folder", file=sys.stderr)
                return 2
            run_state.update({"scope": scope, "folder": folder})
        elif scope == "search":
            query = single_flag_value("--query")
            if not query:
                print("--query is required when --scope search", file=sys.stderr)
                return 2
            run_state.update({"scope": scope, "query": query})
        elif scope == "selected-notes":
            note_ids = parse_flag_value("--note-id")
            if not note_ids:
                print("--note-id is required when --scope selected-notes", file=sys.stderr)
                return 2
            run_state.update({"scope": scope, "selectedNoteIDs": [str(item) for item in note_ids]})
        elif scope == "sample":
            run_state.update({"scope": scope})
        else:
            print("--scope must be folder, search, selected-notes, sample, or skip", file=sys.stderr)
            return 2
        note_ids = apple_notes_estimate_scope(run_state)
        run_state.update({
            "resolvedNoteIDs": note_ids,
            "estimatedNoteCount": len(note_ids),
            "planConfirmed": False,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "running",
            "ingest",
            "confirm_ingest_plan",
            run_state_path=run_path,
            result_summary="Apple Notes ingest scope selected: " + scope,
        )
        save_json(state)
        payload = {"ok": True, "scope": scope, "estimatedNoteCount": len(note_ids)}
        payload.update(source_next_prompt_payload(state, "apple-notes", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_notes_confirm_plan():
        answer = single_flag_value("--answer").strip().lower()
        if answer not in {"yes", "y", "no", "n"}:
            print("--answer must be yes or no", file=sys.stderr)
            return 2
        state = load_or_create_state()
        run_state = load_source_run_state("apple-notes")
        if answer in {"no", "n"}:
            run_state.update({"planConfirmed": False, "updatedAt": now()})
            run_path = save_source_run_state("apple-notes", run_state)
            state = set_apple_notes_row_state(
                state,
                "attention",
                "ingest",
                "choose_ingest_scope",
                attention_reason="ingest_plan_rejected",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_rejected"}
            payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_apple_notes_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_scope_required"}
            payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"planConfirmed": True, "confirmedAt": now(), "updatedAt": now()})
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "running",
            "ingest",
            "ingest_notes",
            run_state_path=run_path,
            result_summary="Apple Notes ingest plan confirmed.",
        )
        save_json(state)
        payload = {"ok": True, "scope": run_state.get("scope"), "estimatedNoteCount": run_state.get("estimatedNoteCount")}
        payload.update(source_next_prompt_payload(state, "apple-notes", "ingest_notes"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_notes_read_note(note_id):
        _, result = run_memo(["notes", "-v", str(note_id)], timeout=25, failure_reason="memo_note_read_failed")
        if not result.get("ok"):
            _, retry = run_memo(["notes", "-nc", "-v", str(note_id)], timeout=30, failure_reason="memo_note_read_failed")
            if retry.get("ok"):
                result = retry
        return result

    def apple_notes_ingest():
        state = load_or_create_state()
        run_state = load_source_run_state("apple-notes")
        if not run_state.get("scope") or run_state.get("scope") == "skip":
            state = set_apple_notes_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_scope_required"}
            payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not run_state.get("planConfirmed"):
            state = set_apple_notes_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
            save_json(state)
            payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}
            payload.update(source_next_prompt_payload(state, "apple-notes", "confirm_ingest_plan"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        note_ids = run_state.get("resolvedNoteIDs") if isinstance(run_state.get("resolvedNoteIDs"), list) else []
        if not note_ids:
            note_ids = apple_notes_estimate_scope(run_state)
        if not note_ids:
            reason = "no_notes_in_approved_scope"
            run_state.update({"ingestStatus": "failed", "ingestFailureReason": reason, "updatedAt": now()})
            run_path = save_source_run_state("apple-notes", run_state)
            state = set_apple_notes_row_state(
                state,
                "attention",
                "ingest",
                "ingest_notes",
                attention_reason=reason,
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": reason}
            payload.update(source_next_prompt_payload(state, "apple-notes", "ingest_notes"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        artifact = apple_notes_artifact_path(state)
        lines = [
            "# Apple Notes Source Onboarding Ingest",
            "",
            "source: apple-notes",
            "playbook: apple-notes.memo-cli.v1",
            "scope: " + str(run_state.get("scope")),
            "scope_summary: " + apple_notes_scope_summary(run_state),
            "note_count: " + str(len(note_ids)),
            "",
            "## Notes",
        ]
        ingested = 0
        for note_id in note_ids:
            result = apple_notes_read_note(note_id)
            lines.extend(["", "### Note " + str(note_id), ""])
            if not result.get("ok"):
                lines.append("read_error: " + str(result.get("reason") or "memo_note_read_failed"))
                continue
            lines.extend([
                "```text",
                str(result.get("stdout") or "").rstrip(),
                "```",
            ])
            ingested += 1
        artifact.write_text("\\n".join(lines).rstrip() + "\\n", encoding="utf-8")
        run_state.update({
            "artifactPath": str(artifact),
            "ingestedNoteCount": ingested,
            "ingestedAt": now(),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "running",
            "verify",
            "verify_readback",
            run_state_path=run_path,
            result_summary="Apple Notes ingest artifact written for " + str(ingested) + " notes.",
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "ingestedNoteCount": ingested}
        payload.update(source_next_prompt_payload(state, "apple-notes", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_notes_verify_readback():
        state = load_or_create_state()
        run_state = load_source_run_state("apple-notes")
        artifact = Path(run_state.get("artifactPath") or "")
        try:
            text = artifact.read_text(encoding="utf-8")
        except Exception:
            text = ""
        if "source: apple-notes" not in text or "playbook: apple-notes.memo-cli.v1" not in text:
            run_state.update({"readbackStatus": "failed", "updatedAt": now()})
            run_path = save_source_run_state("apple-notes", run_state)
            state = set_apple_notes_row_state(
                state,
                "attention",
                "verify",
                "verify_readback",
                attention_reason="readback_failed",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "readback_failed"}
            payload.update(source_next_prompt_payload(state, "apple-notes", "verify_readback"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "apple-notes",
            "checked",
            "Apple Notes ingest readback verified for " + str(run_state.get("ingestedNoteCount") or 0) + " notes.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "artifactPath": str(artifact), "readbackStatus": "passed"}
        payload.update(source_next_prompt_payload(state, "apple-notes", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def apple_notes_command():
        if not args:
            print("apple-notes requires a subcommand", file=sys.stderr)
            return 2
        pending_code = reject_if_completion_report_pending("apple-notes")
        if pending_code is not None:
            return pending_code
        subcommand = args[0]
        if subcommand == "check-cli":
            return apple_notes_check_cli()
        if subcommand == "check-access":
            return apple_notes_check_access()
        if subcommand == "smoke-list":
            return apple_notes_smoke_list()
        if subcommand == "choose-scope":
            return apple_notes_choose_scope()
        if subcommand == "confirm-plan":
            return apple_notes_confirm_plan()
        if subcommand == "ingest":
            return apple_notes_ingest()
        if subcommand == "verify-readback":
            return apple_notes_verify_readback()
        print("unknown apple-notes subcommand: " + subcommand, file=sys.stderr)
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

    def normalized_alias_text(value):
        return unicodedata.normalize("NFC", value or "").lower()

    def best_alias_match(raw, aliases):
        lower_raw = raw.lower()
        normalized_raw = normalized_alias_text(raw)
        best = None
        for alias in aliases:
            alias_lower = alias.lower()
            position = lower_raw.find(alias_lower)
            if position >= 0:
                raw_value = raw[position:position + len(alias)]
                match_length = len(alias_lower)
            else:
                normalized_alias = normalized_alias_text(alias)
                position = normalized_raw.find(normalized_alias)
                if position < 0:
                    continue
                raw_value = alias
                match_length = len(normalized_alias)
            candidate = (position, -match_length, raw_value)
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
                if source_id == "apple-notes" and match[1].lower() == "memo" and "agent memory" in raw.lower():
                    continue
                matches.append((match[0], source_id, match[1]))
        for source_id, definition in uncataloged_catalog.items():
            match = best_alias_match(raw, definition["aliases"])
            if match:
                matches.append((match[0], source_id, match[1]))
        return sorted(matches)

    def explicit_source_position(raw, source_id, raw_value, fallback_position):
        aliases = []
        if raw_value:
            aliases.append(raw_value)
        if source_id:
            aliases.append(source_id)
        match = best_alias_match(raw, aliases)
        if match:
            return match[0]
        return fallback_position

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
            if normalized == "agent-memory" and not agent_memory_available():
                return
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
                    source_ids.append(normalized)
                    remember_prompt(normalized, raw_value)

        ordered_inputs = []
        for index, (position, source_id, raw_value) in enumerate(scan_aliases(raw)):
            ordered_inputs.append((position, 0, index, source_id, raw_value))
        fallback_base = len(raw) + 1000
        for index, (source_id, raw_value) in enumerate(candidates):
            position = explicit_source_position(raw, source_id, raw_value, fallback_base + index)
            ordered_inputs.append((position, 1, index, source_id, raw_value))
        for index, (source_id, raw_value) in enumerate(uncataloged_pairs):
            position = explicit_source_position(raw, source_id, raw_value, fallback_base + len(candidates) + index)
            ordered_inputs.append((position, 2, index, source_id, raw_value))
        for _, _, _, source_id, raw_value in sorted(ordered_inputs):
            consider(source_id, raw_value, include_prompt=True)

        timestamp = now()
        rows = {}
        for source_id in source_ids:
            if source_id in supported:
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
            else:
                record = next((item for item in uncataloged_sources if isinstance(item, dict) and item.get("normalizedValue") == source_id), {})
                rows[source_id] = {
                    "id": source_id,
                    "displayName": record.get("displayName") or record.get("rawValue") or source_id,
                    "type": "uncataloged",
                    "phase": "intake",
                    "status": "unchecked",
                    "selectionState": "pending_confirmation",
                    "playbookID": fallback_playbook["id"],
                    "playbookVersion": fallback_playbook["version"],
                    "updatedAt": timestamp,
                }
        prompt = confirmation_prompt(prompt_names)
        state = {
            "schemaVersion": 1,
            "status": "running",
            "entryContext": entry_context(),
            "sourceReadiness": source_readiness(),
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
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        display_names = []
        for source_id in source_ids:
            row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else {}
            display_names.append(row.get("displayName") or source_display_name(source_id))
        for item in uncataloged_sources:
            if isinstance(item, dict) and item.get("normalizedValue") not in source_ids:
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
            state["status"] = "ready"
        else:
            state["status"] = "running"
        state["updatedAt"] = timestamp
        save_json(state)
        print(json.dumps(summary(state), ensure_ascii=False, sort_keys=True))

    def summary(state, prompt=None):
        progress = state.get("progress") if isinstance(state.get("progress"), dict) else {}
        uncataloged = progress.get("uncatalogedSources") if isinstance(progress.get("uncatalogedSources"), list) else progress.get("unsupportedInputs") if isinstance(progress.get("unsupportedInputs"), list) else []
        confirmation = progress.get("sourceConfirmation") if isinstance(progress.get("sourceConfirmation"), dict) else {}
        readiness = state.get("sourceReadiness") if isinstance(state.get("sourceReadiness"), dict) else {}
        agent_memory = readiness.get("agentMemory") if isinstance(readiness.get("agentMemory"), dict) else agent_memory_readiness()
        return {
            "ok": True,
            "statePath": str(state_path),
            "status": state.get("status"),
            "normalizedSourceList": progress.get("normalizedSourceList") or [],
            "uncatalogedSources": [item.get("normalizedValue") for item in uncataloged if isinstance(item, dict)],
            "sourceConfirmationStatus": confirmation.get("status"),
            "confirmationPrompt": prompt or confirmation.get("prompt"),
            "sourceInputPrompt": source_input_prompt(agent_memory),
            "agentMemorySuggestion": {
                "available": agent_memory.get("importableUnitCount", 0) > 0,
                "importableUnitCount": agent_memory.get("importableUnitCount", 0),
                "agents": agent_memory.get("agents", []),
            },
        }

    def status():
        state = load_json(state_path)
        if not state:
            state = default_state()
            save_json(state)
        elif migrate_source_state(state):
            save_json(state)
        state = load_or_create_state()
        save_json(state)
        payload = summary(state)
        payload["state"] = state
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))

    def parse_report_args():
        status_value = ""
        source_id = ""
        index = 0
        while index < len(args):
            token = args[index]
            if token == "--status" and index + 1 < len(args):
                status_value = args[index + 1].strip().lower()
                index += 2
            elif token == "--source" and index + 1 < len(args):
                source_id = args[index + 1].strip().lower()
                index += 2
            else:
                print("unknown or incomplete argument: " + token, file=sys.stderr)
                sys.exit(2)
        if status_value != "completed":
            print("--status must be completed", file=sys.stderr)
            sys.exit(2)
        state = load_or_create_state()
        rows = ensure_progress(state).get("sourceRows") if isinstance(ensure_progress(state).get("sourceRows"), dict) else {}
        if source_id not in supported and source_id not in rows:
            print("--source must be a known source row", file=sys.stderr)
            sys.exit(2)
        return source_id

    def report():
        source_id = parse_report_args()
        state = load_or_create_state()
        state, completion, code = report_source_completion(state, source_id)
        if code != 0:
            payload = summary(load_or_create_state())
            payload.update(completion)
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return code

        summary_text = completion.get("summary") or ""
        progress = ensure_progress(state)
        has_unfinished_source = first_unfinished_source_id(progress) is not None
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else {}
        run_state = load_source_run_state(source_id)
        detail_lines = source_completion_detail_lines(source_id, row, run_state, summary_text)
        next_payload = {}
        if has_unfinished_source:
            _, next_payload = run_start_next_captured()
        combined_prompt = source_completion_handoff_prompt(
            source_id,
            summary_text,
            detail_lines=detail_lines,
            has_next_source=has_unfinished_source,
            next_prompt=next_payload.get("nextPrompt"),
        )
        path = write_source_next_prompt_file("report-" + source_id, "completed", combined_prompt)

        payload_state = load_or_create_state() if has_unfinished_source else state
        payload = summary(payload_state)
        payload["ok"] = True
        payload["completedSourceID"] = source_id
        payload["completedSourceSummary"] = summary_text
        payload["completedSourceDisposition"] = completion.get("disposition")
        payload["completedSourceResultBlock"] = source_completion_result_block(source_id, summary_text, detail_lines)
        if has_unfinished_source:
            for key in [
                "nextSourceID",
                "nextPlaybookID",
                "nextPlaybookVersion",
                "nextPlaybookStepID",
            ]:
                if key in next_payload:
                    payload[key] = next_payload.get(key)
            if "nextPromptPath" in next_payload:
                payload["nextSourcePromptPath"] = next_payload.get("nextPromptPath")
            if "reason" in next_payload and next_payload.get("ok") is False:
                payload["nextSourceReason"] = next_payload.get("reason")
        payload["nextPrompt"] = combined_prompt
        payload["nextPromptPath"] = path
        payload["complete"] = not has_unfinished_source and state.get("status") == "completed"
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    def parse_fallback_report_args():
        parsed = {
            "source": "",
            "step": "",
            "status": "",
            "summary": "",
            "ingestTitle": "",
            "ingestFile": "",
            "ingestProvenance": "",
        }
        index = 0
        while index < len(args):
            token = args[index]
            if token == "--source" and index + 1 < len(args):
                parsed["source"] = args[index + 1].strip().lower()
                index += 2
            elif token == "--step" and index + 1 < len(args):
                parsed["step"] = args[index + 1].strip()
                index += 2
            elif token == "--status" and index + 1 < len(args):
                parsed["status"] = args[index + 1].strip().lower()
                index += 2
            elif token == "--summary" and index + 1 < len(args):
                parsed["summary"] = args[index + 1]
                index += 2
            elif token == "--ingest-title" and index + 1 < len(args):
                parsed["ingestTitle"] = args[index + 1]
                index += 2
            elif token == "--ingest-file" and index + 1 < len(args):
                parsed["ingestFile"] = args[index + 1]
                index += 2
            elif token == "--ingest-provenance" and index + 1 < len(args):
                parsed["ingestProvenance"] = args[index + 1]
                index += 2
            else:
                print("unknown or incomplete fallback report argument: " + token, file=sys.stderr)
                sys.exit(2)
        if not parsed["source"]:
            print("--source is required", file=sys.stderr)
            sys.exit(2)
        if parsed["step"] not in fallback_playbook["steps"]:
            print("--step must be one of: " + ", ".join(fallback_playbook["steps"]), file=sys.stderr)
            sys.exit(2)
        if parsed["status"] not in {"completed", "waiting", "attention", "skipped"}:
            print("--status must be completed, waiting, attention, or skipped", file=sys.stderr)
            sys.exit(2)
        if not parsed["summary"].strip():
            print("--summary is required", file=sys.stderr)
            sys.exit(2)
        return parsed

    def fallback_report():
        if not args or args[0] != "report":
            print("fallback requires the report subcommand", file=sys.stderr)
            return 2
        del args[:1]
        parsed = parse_fallback_report_args()
        source_id = parsed["source"]
        state = load_or_create_state()
        progress = ensure_progress(state)
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else None
        if not row:
            payload = summary(state)
            payload.update({"ok": False, "reason": "unknown_source", "sourceID": source_id})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if not is_fallback_source_row(row):
            payload = summary(state)
            payload.update({"ok": False, "reason": "source_not_fallback", "sourceID": source_id})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if progress.get("activeSourceID") != source_id:
            payload = summary(state)
            payload.update({"ok": False, "reason": "source_not_active", "sourceID": source_id})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        current_step = row.get("playbookStepID") or fallback_playbook["initialStepID"]
        if parsed["step"] != current_step:
            payload = summary(state)
            payload.update({
                "ok": False,
                "reason": "fallback_step_mismatch",
                "sourceID": source_id,
                "expectedStepID": current_step,
                "reportedStepID": parsed["step"],
            })
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1

        redactions = redaction_report()
        sanitized_summary = sanitize_control_plane_text(parsed["summary"], redactions)
        timestamp = now()
        run_state = fallback_run_state(source_id)
        observed = run_state.get("observedSteps") if isinstance(run_state.get("observedSteps"), list) else []
        event = {
            "stepID": parsed["step"],
            "status": parsed["status"],
            "sanitizedSummary": sanitized_summary,
            "redactions": redactions,
            "updatedAt": timestamp,
        }
        observed.append(event)
        run_state["observedSteps"] = observed[-32:]
        run_state["lastSummary"] = sanitized_summary
        run_state["lastStepID"] = parsed["step"]
        run_state["lastStatus"] = parsed["status"]
        run_state["updatedAt"] = timestamp

        if parsed["step"] == "choose_strategy" and parsed["status"] == "completed":
            run_state["strategy"] = sanitized_summary
        if parsed["step"] == "propose_ingest_scope" and parsed["status"] == "completed":
            run_state["ingestScope"] = sanitized_summary
        if parsed["step"] == "confirm_ingest_plan" and parsed["status"] == "completed":
            run_state["ingestPlanConfirmed"] = True
        if parsed["step"] == "ingest" and parsed["status"] == "completed":
            if not run_state.get("ingestPlanConfirmed"):
                state = set_fallback_row_state(
                    state,
                    source_id,
                    "attention",
                    fallback_phase_for_step("confirm_ingest_plan"),
                    "confirm_ingest_plan",
                    timestamp=timestamp,
                    attention_reason="waiting:ingest_plan_unconfirmed",
                    result_summary="Ingest plan confirmation is required before fallback ingest.",
                )
                save_json(state)
                payload = summary(state)
                payload.update(source_next_prompt_payload(state, source_id, "confirm_ingest_plan"))
                payload.update({"ok": False, "reason": "ingest_plan_unconfirmed"})
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            if parsed["ingestFile"]:
                ingest_file = Path(parsed["ingestFile"]).expanduser()
                try:
                    ingest_body = ingest_file.read_text(encoding="utf-8")
                except Exception:
                    run_state["ingestFailureReason"] = "ingest_file_unreadable"
                    run_path = save_source_run_state(source_id, run_state)
                    state = set_fallback_row_state(
                        state,
                        source_id,
                        "attention",
                        fallback_phase_for_step("ingest"),
                        "ingest",
                        timestamp=timestamp,
                        attention_reason="waiting:ingest_file_unreadable",
                        result_summary="The approved ingest file could not be read.",
                        run_state_path=run_path,
                    )
                    save_json(state)
                    payload = summary(state)
                    payload.update(source_next_prompt_payload(state, source_id, "ingest"))
                    payload.update({"ok": False, "reason": "ingest_file_unreadable"})
                    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                    return 1
                artifact = write_fallback_gbrain_artifact(
                    state,
                    source_id,
                    parsed["ingestTitle"] or source_id,
                    ingest_body,
                    parsed["ingestProvenance"] or sanitized_summary,
                )
                if artifact:
                    run_state["gbrainArtifact"] = artifact
                else:
                    run_state["ingestFailureReason"] = "gbrain_target_missing"
                    run_path = save_source_run_state(source_id, run_state)
                    state = set_fallback_row_state(
                        state,
                        source_id,
                        "attention",
                        fallback_phase_for_step("ingest"),
                        "ingest",
                        timestamp=timestamp,
                        attention_reason="waiting:gbrain_target_missing",
                        result_summary="GBrain target is required before fallback ingest can write approved source body.",
                        run_state_path=run_path,
                    )
                    save_json(state)
                    payload = summary(state)
                    payload.update(source_next_prompt_payload(state, source_id, "ingest"))
                    payload.update({"ok": False, "reason": "gbrain_target_missing"})
                    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                    return 1

        attention_reason = None
        if parsed["status"] == "waiting":
            attention_reason = "waiting:" + sanitized_summary
            run_path = save_source_run_state(source_id, run_state)
            event["attentionReason"] = attention_reason
            run_state["fallbackArtifacts"] = write_fallback_artifacts(source_id, run_state, event)
            run_path = save_source_run_state(source_id, run_state)
            state = set_fallback_row_state(
                state,
                source_id,
                "attention",
                fallback_phase_for_step(parsed["step"]),
                parsed["step"],
                timestamp=timestamp,
                attention_reason=attention_reason,
                result_summary=sanitized_summary,
                run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, parsed["step"]))
            payload["reason"] = attention_reason
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if parsed["status"] == "attention":
            if sanitized_summary.startswith("blocked:") or sanitized_summary.startswith("waiting:"):
                attention_reason = sanitized_summary
            else:
                attention_reason = "blocked:" + sanitized_summary
            run_path = save_source_run_state(source_id, run_state)
            event["attentionReason"] = attention_reason
            run_state["fallbackArtifacts"] = write_fallback_artifacts(source_id, run_state, event)
            run_path = save_source_run_state(source_id, run_state)
            state = set_fallback_row_state(
                state,
                source_id,
                "attention",
                fallback_phase_for_step(parsed["step"]),
                parsed["step"],
                timestamp=timestamp,
                attention_reason=attention_reason,
                result_summary=sanitized_summary,
                run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, parsed["step"]))
            payload["reason"] = attention_reason
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        if parsed["status"] == "skipped":
            run_state["completionDisposition"] = "skipped"
            run_state["completionSummary"] = sanitized_summary
            run_path = save_source_run_state(source_id, run_state)
            event["attentionReason"] = None
            run_state["fallbackArtifacts"] = write_fallback_artifacts(source_id, run_state, event)
            state = mark_source_completion_pending(state, source_id, "skipped", sanitized_summary, run_state=run_state)
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0

        next_step = next_fallback_step_id(parsed["step"])
        run_path = save_source_run_state(source_id, run_state)
        event["attentionReason"] = None
        run_state["fallbackArtifacts"] = write_fallback_artifacts(source_id, run_state, event)
        run_path = save_source_run_state(source_id, run_state)
        if parsed["step"] == "verify_readback":
            state = mark_source_completion_pending(state, source_id, "checked", sanitized_summary, run_state=run_state)
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, "complete"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 0
        state = set_fallback_row_state(
            state,
            source_id,
            "running",
            fallback_phase_for_step(next_step),
            next_step,
            timestamp=timestamp,
            result_summary=sanitized_summary,
            run_state_path=run_path,
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, source_id, next_step))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

    if command == "intake":
        intake()
    elif command == "confirm":
        confirm()
    elif command == "next":
        sys.exit(start_next())
    elif command == "report":
        sys.exit(report())
    elif command == "gmail":
        sys.exit(gmail_command())
    elif command == "obsidian":
        sys.exit(obsidian_command())
    elif command == "notion":
        sys.exit(notion_command())
    elif command == "imessage":
        sys.exit(imessage_command())
    elif command == "apple-notes":
        sys.exit(apple_notes_command())
    elif command == "apple-reminders":
        sys.exit(apple_reminders_command())
    elif command == "agent-memory":
        sys.exit(agent_memory_command())
    elif command == "fallback":
        sys.exit(fallback_report())
    elif command == "status":
        status()
    else:
        print("unknown command: " + command, file=sys.stderr)
        sys.exit(2)
    PY
    """
}
