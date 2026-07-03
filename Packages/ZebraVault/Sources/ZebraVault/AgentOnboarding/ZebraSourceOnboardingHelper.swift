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
        ]
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for playbook in playbooks {
                let destination = directory.appendingPathComponent(
                    playbook.filename,
                    isDirectory: false
                )
                if let resource = Bundle.module.url(
                    forResource: playbook.resource,
                    withExtension: "md",
                    subdirectory: "SourcePlaybooks"
                ) {
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.copyItem(at: resource, to: destination)
                } else if !fileManager.fileExists(atPath: destination.path) {
                    try playbook.fallback.write(
                        to: destination,
                        atomically: true,
                        encoding: .utf8
                    )
                }
            }
        } catch {
            for playbook in playbooks {
                let destination = directory.appendingPathComponent(
                    playbook.filename,
                    isDirectory: false
                )
                if !fileManager.fileExists(atPath: destination.path) {
                    try? playbook.fallback.write(
                        to: destination,
                        atomically: true,
                        encoding: .utf8
                    )
                }
            }
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
    initialStepID: choose_scope
    steps:
      - choose_scope
      - smoke_read
      - confirm_workspace_ingest
      - ingest_notion
      - verify_readback
      - complete
    ---

    # Notion ntn CLI Source Onboarding

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
    import re
    import shutil
    import subprocess
    import sys
    import textwrap
    import io
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

    def default_state(timestamp=None):
        timestamp = timestamp or now()
        context = entry_context()
        missing_prerequisite = context.get("gbrainTargetMissingReason") or (None if context.get("adapterReady") else "gbrain_adapter_missing")
        return {
            "schemaVersion": 1,
            "status": "attention" if missing_prerequisite else "ready",
            "entryContext": context,
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
        if isinstance(state.get("entryContext"), dict):
            state["entryContext"].setdefault("onboardingLanguageCode", onboarding_language())
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
        "initialStepID": "choose_scope",
        "steps": [
            "choose_scope",
            "smoke_read",
            "confirm_workspace_ingest",
            "ingest_notion",
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

    def source_completion_report_prompt(source_id, row):
        display = source_display_name(source_id)
        summary_text = row.get("resultSummary") or (display + " Source Onboarding is ready to report complete.")
        language = onboarding_language()
        if language == "ko":
            return textwrap.dedent(f'''
            Zebra Source Onboarding: {display} 완료 보고가 필요합니다.

            {summary_text}

            아직 다음 source로 넘어가지 마세요. 먼저 사용자에게 {display} 작업이 완료됐다고 짧게 말한 뒤, 아래 명령으로 완료를 Zebra에 보고하세요:

            ```bash
            zebra-source-onboarding report --status completed --source {source_id}
            ```

            보고 명령이 성공하면 그 stdout의 `nextPrompt`만 따라 다음 source 또는 최종 완료 안내를 진행하세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            Zebra Source Onboarding: {display} の完了報告が必要です。

            {summary_text}

            まだ次の source に進まないでください。まず {display} の作業が完了したことをユーザーに短く伝え、次のコマンドで Zebra に完了を報告してください:

            ```bash
            zebra-source-onboarding report --status completed --source {source_id}
            ```

            報告コマンドが成功したら、その stdout の `nextPrompt` だけに従って次の source または最終完了案内を進めてください。
            ''').strip()
        return textwrap.dedent(f'''
        Zebra Source Onboarding: {display} completion report is required.

        {summary_text}

        Do not move to the next source yet. First briefly tell the user that {display} is complete, then report the completion to Zebra:

        ```bash
        zebra-source-onboarding report --status completed --source {source_id}
        ```

        After that report succeeds, continue only from its stdout `nextPrompt`.
        ''').strip()

    def source_completion_handoff_prompt(source_id, summary_text, next_prompt=None):
        display = source_display_name(source_id)
        language = onboarding_language()
        if next_prompt:
            if language == "ko":
                return textwrap.dedent(f'''
                먼저 사용자에게 이 완료 사실을 짧게 알려주세요:
                {display} Source Onboarding이 완료됐습니다. {summary_text}

                그 다음 아래 다음 source 단계만 진행하세요:

                {next_prompt}
                ''').strip()
            if language == "ja":
                return textwrap.dedent(f'''
                まず、この完了内容をユーザーに短く伝えてください:
                {display} Source Onboarding が完了しました。{summary_text}

                その後、次の source step だけを進めてください:

                {next_prompt}
                ''').strip()
            return textwrap.dedent(f'''
            First, briefly tell the user this completed source:
            {display} Source Onboarding is complete. {summary_text}

            Then proceed only with the next source step below:

            {next_prompt}
            ''').strip()
        if language == "ko":
            return textwrap.dedent(f'''
            {display} Source Onboarding이 완료됐습니다. {summary_text}

            선택된 모든 Source Onboarding이 완료됐습니다. 사용자에게 전체 Source Onboarding이 끝났다고 짧게 말한 뒤 멈추세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            {display} Source Onboarding が完了しました。{summary_text}

            選択されたすべての Source Onboarding が完了しました。ユーザーに全体の Source Onboarding が完了したことを短く伝えて、そこで止めてください。
            ''').strip()
        return textwrap.dedent(f'''
        {display} Source Onboarding is complete. {summary_text}

        All selected Source Onboarding sources are complete. Briefly tell the user that Source Onboarding is complete, then stop.
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
            progress["activeSourceID"] = first_unfinished_source_id(progress)
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
            progress["activeSourceID"] = first_unfinished_source_id(progress)
        else:
            progress["activeSourceID"] = "imessage"
        state["status"] = source_completion_status(state)
        state["updatedAt"] = timestamp
        return state

    def mark_source_completion_pending(state, source_id, disposition, result_summary, run_state=None):
        disposition = "skipped" if disposition == "skipped" else "checked"
        run_state_path = None
        if source_id != "gmail":
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
        run_state = load_source_run_state(source_id) if source_id != "gmail" else {}
        disposition = run_state.get("completionDisposition") or "checked"
        if disposition not in {"checked", "skipped"}:
            disposition = "checked"
        summary_text = row.get("resultSummary") or run_state.get("completionSummary") or (source_display_name(source_id) + " Source Onboarding completed.")
        timestamp = now()
        if source_id == "gmail":
            state = set_gmail_row_state(state, disposition, "complete", "complete", timestamp=timestamp, result_summary=summary_text)
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
        language = onboarding_language()
        if language == "ko":
            localized_scope_detail = scope_detail
            if scope == "all":
                localized_scope_detail = "전체 vault"
            elif scope == "folders":
                localized_scope_detail = "선택한 폴더: " + (", ".join(folders) if folders else "없음")
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
            if scope == "all":
                localized_scope_detail = "vault全体"
            elif scope == "folders":
                localized_scope_detail = "選択したフォルダ: " + (", ".join(folders) if folders else "なし")
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
            "step": "choose_scope",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "running",
            "preflight",
            "choose_scope",
            run_state_path=run_path,
            result_summary="Notion scope selection required before smoke read.",
        )
        save_json(state)
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
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
        if source_id == "imessage":
            return start_imessage_from_next(state)
        if source_id == "notion":
            return start_notion_from_next(state)
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
        if scope not in {"whole", "folders", "sample", "skip"}:
            print("--scope must be whole, folders, sample, or skip", file=sys.stderr)
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

    def run_ntn(ntn_args, timeout=60):
        try:
            completed = subprocess.run(
                ["ntn"] + list(ntn_args),
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
            return {"ok": False, "status": 127, "args": list(ntn_args), "stdout": "", "stderr": "ntn_not_found", "json": None}
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
        command_path = run_state.get("imsgCommandPath")
        if not command_path:
            command_path = shutil.which("imsg") or ""
        if command_path:
            run_state["imsgCommandPath"] = command_path
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
        state = load_or_create_state()
        run_state, command_path = imessage_run_state_with_command_path()
        if not command_path:
            run_state.update({"cliStatus": "missing", "updatedAt": now()})
            run_path = save_source_run_state("imessage", run_state)
            state = set_imessage_row_state(
                state,
                "attention",
                "preflight",
                "check_imsg_cli",
                attention_reason="imsg_cli_missing",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {"ok": False, "reason": "imsg_cli_missing"}
            payload.update(source_next_prompt_payload(state, "imessage", "check_imsg_cli"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        version = ""
        try:
            result = subprocess.run([command_path, "--version"], text=True, capture_output=True, timeout=5)
            version = (result.stdout or result.stderr or "").strip()
        except Exception:
            version = ""
        run_state.update({
            "cliStatus": "passed",
            "imsgCommandPath": command_path,
            "imsgVersion": version,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "running",
            "preflight",
            "check_full_disk_access",
            run_state_path=run_path,
            result_summary="imsg CLI found at " + command_path,
        )
        save_json(state)
        payload = {"ok": True, "imsgCommandPath": command_path, "imsgVersion": version}
        payload.update(source_next_prompt_payload(state, "imessage", "check_full_disk_access"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0

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
        if source_id not in supported:
            print("--source must be one of: " + ", ".join(sorted(supported.keys())), file=sys.stderr)
            sys.exit(2)
        return source_id

    def run_start_next_captured():
        buffer = io.StringIO()
        old_stdout = sys.stdout
        try:
            sys.stdout = buffer
            code = start_next()
        finally:
            sys.stdout = old_stdout
        text = buffer.getvalue().strip()
        if not text:
            return {}, code
        try:
            return json.loads(text), code
        except Exception:
            return {"ok": False, "reason": "next_payload_parse_failed", "raw": text}, 1

    def report():
        source_id = parse_report_args()
        state = load_or_create_state()
        state, completion, code = report_source_completion(state, source_id)
        if code != 0:
            payload = summary(load_or_create_state())
            payload.update(completion)
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return code

        next_payload, next_code = run_start_next_captured()
        summary_text = completion.get("summary") or ""
        next_prompt = next_payload.get("nextPrompt") if isinstance(next_payload.get("nextPrompt"), str) else None
        combined_prompt = source_completion_handoff_prompt(source_id, summary_text, next_prompt=next_prompt)
        path = write_source_next_prompt_file("report-" + source_id, "completed", combined_prompt)

        payload = dict(next_payload)
        payload["ok"] = next_payload.get("ok", True)
        payload["completedSourceID"] = source_id
        payload["completedSourceSummary"] = summary_text
        payload["completedSourceDisposition"] = completion.get("disposition")
        payload["nextPrompt"] = combined_prompt
        payload["nextPromptPath"] = path
        if not next_prompt:
            payload["complete"] = True
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return next_code

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
    elif command == "status":
        status()
    else:
        print("unknown command: " + command, file=sys.stderr)
        sys.exit(2)
    PY
    """
}
