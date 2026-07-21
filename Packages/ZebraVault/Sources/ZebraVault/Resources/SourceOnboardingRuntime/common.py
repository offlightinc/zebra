import contextlib

import errno

import io

import json

import os

import re

import shutil

import subprocess

import sys

import textwrap

import time

import unicodedata

import urllib.error

import urllib.parse

import urllib.request

import uuid

import hashlib

from datetime import datetime, timezone

from pathlib import Path

from playbooks import parse_playbook_markdown
from domain import deterministic_slug
from gbrain_ingest import submit_connector_ingestion
from state import ingest_projection, load_json_file, load_source_run_state_file, save_json_file, save_source_run_state_file

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

reminders_eventkit_dir = Path(
    os.environ.get("ZEBRA_REMINDERS_EVENTKIT_DIR")
    or str(state_path.parent / "reminders-eventkit")
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
    "id": "apple-reminders.eventkit",
    "version": "v1",
    "sourceID": "apple-reminders",
    "initialStepID": "check_reminders_permission",
    "steps": [
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

def localized_message(en, ko, ja):
    language = onboarding_language()
    if language == "ko":
        return ko
    if language == "ja":
        return ja
    return en

def print_progress(en, ko, ja):
    print(localized_message(en, ko, ja), file=sys.stderr, flush=True)

def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def load_json(path):
    return load_json_file(path)

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
    save_json_file(state_path, value)

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

def agent_display_name(agent):
    return {
        "claude": "Claude Code",
        "codex": "Codex",
        "antigravity": "Antigravity",
        "openclaw": "OpenClaw",
        "hermes": "Hermes",
    }.get(agent, agent)

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
            "actionReview": None,
            "dailyPlan": None,
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
        "actionReview": None,
        "dailyPlan": None,
    })
    return state

def source_run_state_path(source_id):
    from state import source_run_state_path as resolved_path
    return resolved_path(state_path, source_id)

def load_source_run_state(source_id):
    return load_source_run_state_file(state_path, source_id)

def save_source_run_state(source_id, value):
    return save_source_run_state_file(state_path, source_id, value)

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
    path.write_text(prompt.rstrip() + "\n", encoding="utf-8")
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
        r"(?i)\bsk-[A-Za-z0-9_-]{6,}\b",
        r"(?i)\bcvis_[A-Za-z0-9_-]{6,}\b",
        r"(?i)\bxox[a-z]-[A-Za-z0-9_-]{6,}\b",
        r"(?i)\b(?:token|cookie|password|secret|oauth(?:_code)?|code)\s*[:=]\s*[^\s,;]+",
    ]
    for pattern in secret_patterns:
        text, count = re.subn(pattern, "<redacted-secret>", text)
        report["secret"] = report.get("secret", 0) + count
    def replace_private_path(match):
        report["privatePath"] = report.get("privatePath", 0) + 1
        basename = Path(match.group(0)).name or "path"
        digest = hashlib.sha256(match.group(0).encode("utf-8")).hexdigest()[:12]
        return "<private-path:" + basename + ":" + digest + ">"
    text = re.sub(r"/Users/[^\s'\"`]+", replace_private_path, text)
    text, body_count = re.subn(
        r"(?is)\b(raw\s+body|body|message\s+body|document\s+text)\s*[:=].*",
        r"\1:<redacted-body>",
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
        handle.write("\n")
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
        "ingestReceipt": run_state.get("ingestReceipt"),
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
    (directory / "playbook-draft.md").write_text("\n".join(playbook_lines).rstrip() + "\n", encoding="utf-8")
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
    progress.setdefault("actionReview", None)
    progress.setdefault("dailyPlan", None)
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
        action_review = progress.get("actionReview") if isinstance(progress.get("actionReview"), dict) else None
        # States created before source action review shipped remain complete.
        if not action_review or not action_review.get("required"):
            return "completed"
        if action_review.get("status") in {"completed", "skipped"}:
            daily_plan = progress.get("dailyPlan") if isinstance(progress.get("dailyPlan"), dict) else None
            # States completed before daily planning shipped remain complete.
            if not daily_plan or not daily_plan.get("required"):
                return "completed"
            if daily_plan.get("status") in {"completed", "skipped"}:
                return "completed"
            if daily_plan.get("status") == "attention":
                return "attention"
            return "running"
        if action_review.get("status") == "attention":
            return "attention"
        return "running"
    return "running"

def action_review_manifest_path():
    return state_path.parent / "source-action-review-manifest.json"

def action_review_source_records(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    records = []
    for source_id in ensure_execution_order(progress):
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else {}
        if row.get("status") != "checked":
            continue
        run_state = load_source_run_state(source_id)
        ingest_receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else None
        if ingest_receipt and ingest_receipt.get("complete") is True:
            readbacks = ingest_receipt.get("readbacks") if isinstance(ingest_receipt.get("readbacks"), list) else []
            verified_records = [
                {"slug": item.get("slug"), "sourceID": item.get("sourceID"), "identityMatch": True}
                for item in readbacks
                if isinstance(item, dict)
                and item.get("identityMatch") is True
                and isinstance(item.get("slug"), str) and item.get("slug")
                and isinstance(item.get("sourceID"), str) and item.get("sourceID")
            ]
            if verified_records and len(verified_records) == ingest_receipt.get("verifiedRecordCount"):
                records.append({
                    "sourceID": source_id,
                    "displayName": row.get("displayName") or source_display_name(source_id),
                    "gbrainRecords": verified_records,
                    "resultSummary": row.get("resultSummary") or run_state.get("completionSummary"),
                    "runStatePath": row.get("runStatePath"),
                })
                continue
    return records

def prepare_action_review(state):
    progress = ensure_progress(state)
    existing = progress.get("actionReview") if isinstance(progress.get("actionReview"), dict) else None
    if existing and existing.get("required"):
        return state, existing
    timestamp = now()
    records = action_review_source_records(state)
    review_id = str(uuid.uuid4())
    target = gbrain_target_directory(state)
    target_path = str(target.resolve(strict=False)) if target is not None else ""
    existing_task_paths = []
    if target is not None:
        tasks_directory = target / "tasks"
        if tasks_directory.is_dir():
            existing_task_paths = sorted(
                str(path.resolve(strict=False))
                for path in tasks_directory.glob("*.md")
                if path.is_file()
            )
    manifest_path = action_review_manifest_path()
    manifest = {
        "schemaVersion": 1,
        "reviewID": review_id,
        "brainTargetPath": target_path,
        "sourceOnboardingStatePath": str(state_path),
        "createdAt": timestamp,
        "sources": records,
        "existingTaskPaths": existing_task_paths,
    }
    write_json_file(manifest_path, manifest)
    skill_path = target / ".gbrain-adapter/skills/source-to-tasks/SKILL.md" if target is not None else None
    if target is None or not records:
        status_value = "skipped"
        reason = "no_eligible_artifacts"
    elif skill_path is None or not skill_path.is_file():
        status_value = "attention"
        reason = "source_to_tasks_skill_missing"
    else:
        status_value = "ready"
        reason = None
    review = {
        "required": True,
        "status": status_value,
        "reviewID": review_id,
        "manifestPath": str(manifest_path),
        "skillPath": str(skill_path) if skill_path is not None else None,
        "eligibleSourceCount": len(records),
        "candidateCount": None,
        "approvedCount": None,
        "taskPaths": [],
        "reason": reason,
        "updatedAt": timestamp,
    }
    progress["actionReview"] = review
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    save_json(state)
    return state, review

def validated_action_task_path(state, raw_path):
    target = gbrain_target_directory(state)
    if target is None:
        return None, "gbrain_target_missing"
    target = target.resolve(strict=False)
    candidate = Path(raw_path).expanduser()
    if not candidate.is_absolute():
        candidate = target / candidate
    candidate = candidate.resolve(strict=False)
    tasks_root = (target / "tasks").resolve(strict=False)
    try:
        candidate.relative_to(tasks_root)
    except Exception:
        return None, "task_path_outside_tasks"
    if candidate.suffix.lower() != ".md" or not candidate.is_file():
        return None, "task_file_missing"
    try:
        content = candidate.read_text(encoding="utf-8")
    except Exception:
        return None, "task_file_unreadable"
    if not re.search(r"(?m)^type:\s*task\s*$", content[:4096]):
        return None, "task_type_missing"
    review = ensure_progress(state).get("actionReview")
    manifest = load_json(Path(review.get("manifestPath") or "")) if isinstance(review, dict) else {}
    existing_paths = manifest.get("existingTaskPaths") if isinstance(manifest.get("existingTaskPaths"), list) else []
    if str(candidate) in existing_paths:
        return None, "task_preexisted_action_review"
    return str(candidate), None

def parse_action_review_args():
    parsed = {
        "status": "",
        "candidateCount": None,
        "approvedCount": None,
        "taskPaths": [],
        "reason": "",
    }
    index = 0
    while index < len(args):
        token = args[index]
        if token == "--status" and index + 1 < len(args):
            parsed["status"] = args[index + 1].strip().lower()
            index += 2
        elif token == "--candidate-count" and index + 1 < len(args):
            parsed["candidateCount"] = int(args[index + 1])
            index += 2
        elif token == "--approved-count" and index + 1 < len(args):
            parsed["approvedCount"] = int(args[index + 1])
            index += 2
        elif token == "--task-path" and index + 1 < len(args):
            parsed["taskPaths"].append(args[index + 1])
            index += 2
        elif token == "--reason" and index + 1 < len(args):
            parsed["reason"] = args[index + 1].strip()
            index += 2
        else:
            raise ValueError("unknown or incomplete argument: " + token)
    return parsed

def action_review_command():
    subcommand = args.pop(0) if args else "status"
    state = load_or_create_state()
    progress = ensure_progress(state)
    review = progress.get("actionReview") if isinstance(progress.get("actionReview"), dict) else None
    if not review or not review.get("required"):
        payload = summary(state)
        payload.update({"ok": False, "reason": "action_review_not_ready"})
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if subcommand == "status":
        payload = summary(state)
        payload["actionReview"] = review
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    timestamp = now()
    if subcommand == "begin":
        if review.get("status") in {"completed", "skipped"}:
            payload = summary(state)
            payload.update({"ok": False, "reason": "action_review_already_terminal", "actionReview": review})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if review.get("status") == "attention":
            payload = summary(state)
            payload.update({"ok": False, "reason": review.get("reason") or "action_review_attention", "actionReview": review})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        review["status"] = "extracting"
    elif subcommand == "awaiting-approval":
        try:
            parsed = parse_action_review_args()
        except (ValueError, TypeError):
            print("invalid action review arguments", file=sys.stderr)
            return 2
        candidate_count = parsed.get("candidateCount")
        if not isinstance(candidate_count, int) or candidate_count < 1 or candidate_count > 5:
            print("--candidate-count must be between 1 and 5", file=sys.stderr)
            return 2
        review["status"] = "awaiting_approval"
        review["candidateCount"] = candidate_count
    elif subcommand == "report":
        try:
            parsed = parse_action_review_args()
        except (ValueError, TypeError):
            print("invalid action review arguments", file=sys.stderr)
            return 2
        status_value = parsed.get("status")
        if status_value == "skipped":
            reason = parsed.get("reason")
            if reason not in {"no_candidates", "user_skipped", "no_eligible_artifacts"}:
                print("invalid or missing --reason", file=sys.stderr)
                return 2
            if reason == "user_skipped" and review.get("status") != "awaiting_approval":
                payload = summary(state)
                payload.update({"ok": False, "reason": "action_review_approval_required"})
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            review.update({
                "status": "skipped",
                "reason": reason,
                "candidateCount": parsed.get("candidateCount") or review.get("candidateCount") or 0,
                "approvedCount": 0,
                "taskPaths": [],
            })
        elif status_value == "completed":
            candidate_count = parsed.get("candidateCount")
            approved_count = parsed.get("approvedCount")
            raw_paths = parsed.get("taskPaths") or []
            if review.get("status") != "awaiting_approval":
                payload = summary(state)
                payload.update({"ok": False, "reason": "action_review_approval_required"})
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            if not isinstance(candidate_count, int) or candidate_count < 1 or candidate_count > 5:
                print("--candidate-count must be between 1 and 5", file=sys.stderr)
                return 2
            if not isinstance(approved_count, int) or approved_count < 1 or approved_count > candidate_count:
                print("--approved-count must be between 1 and candidate count", file=sys.stderr)
                return 2
            if review.get("candidateCount") != candidate_count:
                payload = summary(state)
                payload.update({"ok": False, "reason": "candidate_count_mismatch"})
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            if len(raw_paths) != approved_count:
                print("--task-path count must equal --approved-count", file=sys.stderr)
                return 2
            validated = []
            for raw_path in raw_paths:
                task_path, reason = validated_action_task_path(state, raw_path)
                if reason:
                    payload = summary(state)
                    payload.update({"ok": False, "reason": reason, "taskPath": raw_path})
                    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                    return 1
                validated.append(task_path)
            review.update({
                "status": "completed",
                "reason": None,
                "candidateCount": candidate_count,
                "approvedCount": approved_count,
                "taskPaths": validated,
            })
        else:
            print("--status must be completed or skipped", file=sys.stderr)
            return 2
    else:
        print("unknown actions command: " + subcommand, file=sys.stderr)
        return 2
    review["updatedAt"] = timestamp
    progress["actionReview"] = review
    daily_plan = None
    if subcommand == "report" and review.get("status") in {"completed", "skipped"}:
        state, daily_plan = prepare_daily_plan(state)
        progress = ensure_progress(state)
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    save_json(state)
    payload = summary(state)
    payload["actionReview"] = review
    if daily_plan:
        payload["dailyPlan"] = daily_plan
        payload["nextPrompt"] = daily_plan_handoff_prompt(daily_plan)
    payload["complete"] = state.get("status") == "completed"
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def prepare_daily_plan(state):
    progress = ensure_progress(state)
    existing = progress.get("dailyPlan") if isinstance(progress.get("dailyPlan"), dict) else None
    if existing and existing.get("required"):
        return state, existing
    timestamp = now()
    target = gbrain_target_directory(state)
    skill_path = target / ".gbrain-adapter/skills/zebra-daily-planner/SKILL.md" if target is not None else None
    adapter = load_json(adapter_state_path)
    adapter_receipt = adapter.get("receipt") if isinstance(adapter.get("receipt"), dict) else {}
    adapter_checks = adapter_receipt.get("checks") if isinstance(adapter_receipt.get("checks"), dict) else {}
    planner_expected = adapter_checks.get("adapterSkillZebraDailyPlanner") is True
    if target is None or not planner_expected:
        required_value = False
        status_value = "skipped"
        reason = "gbrain_target_missing" if target is None else "legacy_adapter_without_daily_planner"
    elif skill_path is None or not skill_path.is_file():
        required_value = True
        status_value = "attention"
        reason = "zebra_daily_planner_skill_missing"
    else:
        required_value = True
        status_value = "ready"
        reason = None
    daily_plan = {
        "required": required_value,
        "status": status_value,
        "skillPath": str(skill_path) if skill_path is not None else None,
        "calendarCoverage": None,
        "freeMinutes": None,
        "scheduledMinutes": None,
        "plannedTaskCount": None,
        "scheduledTaskPaths": [],
        "calendarWriteStatus": None,
        "calendarEventIDs": [],
        "reason": reason,
        "updatedAt": timestamp,
    }
    progress["dailyPlan"] = daily_plan
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    save_json(state)
    return state, daily_plan

def daily_plan_handoff_prompt(daily_plan):
    status_value = daily_plan.get("status")
    reason = daily_plan.get("reason") or "daily_planner_attention"
    skill_path = daily_plan.get("skillPath") or "missing"
    language = onboarding_language()
    if status_value == "attention":
        if language == "ko":
            return f"하루 계획을 시작할 수 없습니다. 원인: `{reason}`. gbrain-adapter 설치를 다시 실행한 뒤 재개하세요."
        if language == "ja":
            return f"一日の計画を開始できません。理由: `{reason}`。gbrain-adapter を再インストールしてから再開してください。"
        return f"Daily planning cannot start. Reason: `{reason}`. Re-run gbrain-adapter installation, then resume."
    if language == "ko":
        return textwrap.dedent(f'''
        이제 오늘 하루를 실제로 계획하세요.

        1. `zebra-source-onboarding planner begin`을 실행하세요.
        2. `{skill_path}` 스킬을 읽고 그대로 따르세요.
        3. 승인된 범위의 오늘 캘린더와 현재 brain의 활성 태스크·목표를 읽으세요.
        4. 스킬의 Quick/Routine/First-run/Rescue 모드를 내부적으로 고르세요. 사용자가 질문 생략을 명시하지 않았다면 최종 시간표 전에 최소 한 번 방향을 맞추고, 질문은 한 번에 하나만 한 뒤 답을 기다리세요.
        5. 명확한 안이 있으면 하나를 추천하고, 실제 우선순위 충돌이 있을 때만 두 안을 제시해 사용자의 선택을 기다리세요.
        6. 선택이 끝나면 가용시간을 계산한 단일 최종 일정안을 보여주세요. 이 단계에서는 캘린더를 쓰지 마세요.
        7. 최종안을 보여준 뒤 `zebra-source-onboarding planner propose --calendar-coverage "<읽은 범위>" --free-minutes <분> --scheduled-minutes <분> --task-count <개>`로 보고하세요.
        8. 사용자가 현재 최종안을 명시적으로 승인하면 adapter-native task마다 `planned_start_at`과 `planned_end_at`을 함께 쓰고 다시 읽어 검증하세요. 그 뒤에만 캘린더 반영 여부를 별도로 물으세요.
        9. `planner report`에는 시간이 기록된 각 task를 `--task-path tasks/<slug>.md`로 반복해서 전달하세요. 캘린더를 쓰지 않으면 `--calendar-write-status not_requested`, 실제 반영이 끝나면 `executed`와 각 `--event-id`를 보고하세요.

        `pending_approval`은 완료가 아닙니다. planner가 completed 또는 skipped가 될 때까지 Source Onboarding 완료라고 말하지 마세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent(f'''
        次に、今日一日を実際に計画してください。

        1. `zebra-source-onboarding planner begin` を実行します。
        2. `{skill_path}` を読み、その契約に従います。
        3. 承認済み範囲の今日のカレンダーと active tasks/goals を読みます。
        4. Quick/Routine/First-run/Rescue mode を内部で選びます。ユーザーが質問の省略を明示しない限り、最終時間割の前に少なくとも一度方向性を確認し、質問は一度に一つだけ行って回答を待ちます。
        5. 明確な案があれば一案を推薦し、実際の優先順位衝突がある場合だけ二案を示して選択を待ちます。
        6. 選択後に read-only の最終案を一つ示し、この段階ではカレンダーを書き換えません。
        7. `planner propose` で coverage/free/scheduled/task count を報告します。
        8. 現在の最終案が明示承認されたら、adapter-native task に `planned_start_at` と `planned_end_at` を一緒に書き、readback で検証します。その後、カレンダー反映を別に確認します。
        9. 時刻を書いた task ごとに `planner report --task-path tasks/<slug>.md` を渡し、カレンダー未反映なら `not_requested`、実行済みなら `executed` と event ID を報告します。

        `pending_approval` は完了ではありません。
        ''').strip()
    return textwrap.dedent(f'''
    Now build today's real plan.

    1. Run `zebra-source-onboarding planner begin`.
    2. Read and follow `{skill_path}`.
    3. Read today's calendars inside the approved scope plus active brain tasks and goals.
    4. Internally choose Quick, Routine, First-run, or Rescue mode. Unless the user explicitly skips questions, require at least one direction-alignment turn before clock times. Ask at most one question per turn and wait for the answer.
    5. Recommend one plan when the winner is clear. Show two alternatives only for a real priority tradeoff, then wait for the user's choice.
    6. After selection, show one capacity-safe final schedule before any calendar write.
    7. Report that final proposal with `planner propose` and its coverage/free/scheduled/task counts.
    8. After explicit approval of the current final schedule, write both `planned_start_at` and `planned_end_at` to each adapter-native task and verify them by readback. Ask about calendar writes separately after task scheduling succeeds.
    9. Pass every scheduled task to `planner report` with repeated `--task-path tasks/<slug>.md`. Use `not_requested` for no calendar write or `executed` plus event IDs after real calendar writes.

    `pending_approval` is not completion. Do not say Source Onboarding is complete until planner is completed or skipped.
    ''').strip()

def parse_daily_plan_args():
    parsed = {
        "status": "",
        "calendarCoverage": "",
        "freeMinutes": None,
        "scheduledMinutes": None,
        "plannedTaskCount": None,
        "taskPaths": [],
        "calendarWriteStatus": "",
        "calendarEventIDs": [],
        "reason": "",
    }
    index = 0
    while index < len(args):
        token = args[index]
        if token == "--status" and index + 1 < len(args):
            parsed["status"] = args[index + 1].strip().lower()
        elif token == "--calendar-coverage" and index + 1 < len(args):
            parsed["calendarCoverage"] = args[index + 1].strip()
        elif token == "--free-minutes" and index + 1 < len(args):
            parsed["freeMinutes"] = int(args[index + 1])
        elif token == "--scheduled-minutes" and index + 1 < len(args):
            parsed["scheduledMinutes"] = int(args[index + 1])
        elif token == "--task-count" and index + 1 < len(args):
            parsed["plannedTaskCount"] = int(args[index + 1])
        elif token == "--task-path" and index + 1 < len(args):
            parsed["taskPaths"].append(args[index + 1].strip())
        elif token == "--calendar-write-status" and index + 1 < len(args):
            parsed["calendarWriteStatus"] = args[index + 1].strip().lower()
        elif token == "--event-id" and index + 1 < len(args):
            parsed["calendarEventIDs"].append(args[index + 1].strip())
        elif token == "--reason" and index + 1 < len(args):
            parsed["reason"] = args[index + 1].strip()
        else:
            raise ValueError("unknown or incomplete argument: " + token)
        index += 2
    return parsed

def planned_task_frontmatter(path):
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return None
    lines = text[:16384].splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    values = {}
    for raw in lines[1:]:
        stripped = raw.strip()
        if stripped == "---":
            return values
        if not stripped or raw[:1].isspace() or ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key.strip()] = value
    return None

def parse_planned_timestamp(raw):
    if not isinstance(raw, str) or not raw.strip():
        return None
    value = raw.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed

def validated_planned_task_path(state, raw_path):
    target = gbrain_target_directory(state)
    if target is None:
        return None, "gbrain_target_missing"
    target = target.resolve(strict=False)
    candidate = Path(raw_path).expanduser()
    if not candidate.is_absolute():
        candidate = target / candidate
    candidate = candidate.resolve(strict=False)
    tasks_root = (target / "tasks").resolve(strict=False)
    try:
        candidate.relative_to(tasks_root)
    except Exception:
        return None, "planned_task_path_outside_tasks"
    if candidate.suffix.lower() != ".md" or not candidate.is_file():
        return None, "planned_task_file_missing"
    values = planned_task_frontmatter(candidate)
    if not isinstance(values, dict) or values.get("type", "").lower() != "task":
        return None, "planned_task_type_missing"
    start_raw = values.get("planned_start_at")
    end_raw = values.get("planned_end_at")
    if not start_raw or not end_raw:
        return None, "planned_task_interval_missing"
    start = parse_planned_timestamp(start_raw)
    end = parse_planned_timestamp(end_raw)
    if start is None or end is None:
        return None, "planned_task_timestamp_invalid"
    if end <= start:
        return None, "planned_task_interval_invalid"
    return str(candidate), None

def validated_planned_task_paths(state, raw_paths):
    validated = []
    seen = set()
    for raw_path in raw_paths:
        task_path, reason = validated_planned_task_path(state, raw_path)
        if reason:
            return None, reason, raw_path
        if task_path in seen:
            return None, "planned_task_path_duplicate", raw_path
        seen.add(task_path)
        validated.append(task_path)
    return validated, None, None

def daily_plan_command():
    subcommand = args.pop(0) if args else "status"
    state = load_or_create_state()
    progress = ensure_progress(state)
    daily_plan = progress.get("dailyPlan") if isinstance(progress.get("dailyPlan"), dict) else None
    if not daily_plan or not daily_plan.get("required"):
        payload = summary(state)
        payload.update({"ok": False, "reason": "daily_plan_not_ready"})
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if subcommand == "status":
        payload = summary(state)
        payload["dailyPlan"] = daily_plan
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    if daily_plan.get("status") == "attention":
        payload = summary(state)
        payload.update({"ok": False, "reason": daily_plan.get("reason") or "daily_plan_attention"})
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    timestamp = now()
    try:
        parsed = parse_daily_plan_args() if subcommand in {"propose", "report"} else {}
    except (ValueError, TypeError):
        print("invalid planner arguments", file=sys.stderr)
        return 2
    if subcommand == "begin":
        if daily_plan.get("status") in {"completed", "skipped"}:
            payload = summary(state)
            payload.update({"ok": False, "reason": "daily_plan_already_terminal"})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        daily_plan["status"] = "planning"
    elif subcommand == "propose":
        free_minutes = parsed.get("freeMinutes")
        scheduled_minutes = parsed.get("scheduledMinutes")
        task_count = parsed.get("plannedTaskCount")
        coverage = parsed.get("calendarCoverage")
        if not coverage or not isinstance(free_minutes, int) or free_minutes < 0:
            print("calendar coverage and non-negative free minutes are required", file=sys.stderr)
            return 2
        if not isinstance(scheduled_minutes, int) or scheduled_minutes < 0 or scheduled_minutes > free_minutes:
            print("scheduled minutes must be between zero and free minutes", file=sys.stderr)
            return 2
        if not isinstance(task_count, int) or task_count < 0 or task_count > 5:
            print("task count must be between zero and five", file=sys.stderr)
            return 2
        daily_plan.update({
            "status": "awaiting_approval",
            "calendarCoverage": coverage,
            "freeMinutes": free_minutes,
            "scheduledMinutes": scheduled_minutes,
            "plannedTaskCount": task_count,
            "calendarWriteStatus": "not_requested",
            "reason": None,
        })
    elif subcommand == "report":
        status_value = parsed.get("status")
        if status_value == "skipped":
            if parsed.get("reason") != "user_skipped":
                print("skipped planner requires --reason user_skipped", file=sys.stderr)
                return 2
            daily_plan.update({"status": "skipped", "reason": "user_skipped"})
        elif status_value == "completed":
            if daily_plan.get("status") not in {"awaiting_approval", "awaiting_calendar_approval"}:
                payload = summary(state)
                payload.update({"ok": False, "reason": "daily_plan_proposal_required"})
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            write_status = parsed.get("calendarWriteStatus")
            raw_task_paths = parsed.get("taskPaths") or daily_plan.get("scheduledTaskPaths") or []
            scheduled_task_paths, path_reason, failed_path = validated_planned_task_paths(state, raw_task_paths)
            if path_reason:
                payload = summary(state)
                payload.update({"ok": False, "reason": path_reason, "taskPath": failed_path})
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            planned_count = daily_plan.get("plannedTaskCount")
            if isinstance(planned_count, int) and len(scheduled_task_paths) > planned_count:
                payload = summary(state)
                payload.update({"ok": False, "reason": "planned_task_path_count_exceeds_plan"})
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
                return 1
            if write_status == "pending_approval":
                daily_plan.update({
                    "status": "awaiting_calendar_approval",
                    "scheduledTaskPaths": scheduled_task_paths,
                    "calendarWriteStatus": "pending_approval",
                    "reason": "calendar_write_pending_approval",
                })
            elif write_status in {"not_requested", "executed"}:
                event_ids = [value for value in parsed.get("calendarEventIDs", []) if value]
                if write_status == "executed" and not event_ids:
                    print("executed calendar writes require at least one --event-id", file=sys.stderr)
                    return 2
                daily_plan.update({
                    "status": "completed",
                    "scheduledTaskPaths": scheduled_task_paths,
                    "calendarWriteStatus": write_status,
                    "calendarEventIDs": event_ids,
                    "reason": None,
                })
            else:
                print("calendar write status must be not_requested, pending_approval, or executed", file=sys.stderr)
                return 2
        else:
            print("planner report status must be completed or skipped", file=sys.stderr)
            return 2
    else:
        print("unknown planner command: " + subcommand, file=sys.stderr)
        return 2
    daily_plan["updatedAt"] = timestamp
    progress["dailyPlan"] = daily_plan
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    save_json(state)
    payload = summary(state)
    payload["dailyPlan"] = daily_plan
    payload["complete"] = state.get("status") == "completed"
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

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
    migrated_ingest_sources = {"obsidian", "agent-memory", "notion", "imessage", "apple-notes", "apple-reminders"}
    if source_id not in migrated_ingest_sources:
        artifact = compact_completion_value(run_state.get("artifactPath"))
        if artifact:
            lines.append("- Artifact: `" + artifact + "`")
    ingest_receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
    if source_id in migrated_ingest_sources and ingest_receipt.get("verifiedRecordCount") is not None:
        lines.append("- GBrain records verified: " + str(ingest_receipt.get("verifiedRecordCount")))
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
        count = run_state.get("successfullyReadFileCount")
        if count is None:
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
    return "\n".join(lines).strip()

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

def source_action_review_handoff_prompt(source_id, summary_text, review, detail_lines=None):
    completion_block = source_completion_result_block(source_id, summary_text, detail_lines)
    language = onboarding_language()
    status_value = review.get("status")
    if status_value == "attention":
        reason = review.get("reason") or "source_action_review_attention"
        if language == "ko":
            return textwrap.dedent(f'''
            ```text
            {completion_block}
            ```

            소스 인제스트는 완료됐지만 태스크 검토를 시작할 수 없습니다.
            원인: `{reason}`
            gbrain-adapter 설치 단계를 다시 실행한 뒤 Source Onboarding을 재개하세요.
            ''').strip()
        if language == "ja":
            return textwrap.dedent(f'''
            ```text
            {completion_block}
            ```

            ソースの取り込みは完了しましたが、タスクレビューを開始できません。
            理由: `{reason}`
            gbrain-adapter のインストール手順を再実行してから Source Onboarding を再開してください。
            ''').strip()
        return textwrap.dedent(f'''
        ```text
        {completion_block}
        ```

        Source ingest completed, but task review cannot start.
        Reason: `{reason}`
        Re-run the gbrain-adapter installation step, then resume Source Onboarding.
        ''').strip()
    manifest_path = review.get("manifestPath") or "missing"
    skill_path = review.get("skillPath") or "missing"
    if language == "ko":
        return textwrap.dedent(f'''
        ```text
        {completion_block}
        ```

        이제 방금 인제스트한 자료에서 실행할 일을 찾으세요.

        1. `zebra-source-onboarding actions begin`을 실행하세요.
        2. `{skill_path}` 스킬을 읽고 그대로 따르세요.
        3. 입력 범위는 `{manifest_path}`에 기록된 GBrain record 또는 legacy artifact로만 제한하세요. GBrain record는 manifest의 sourceID 범위에서 exact slug로 읽으세요.
        4. 후보를 최대 5개 제안하고, 사용자가 번호를 승인하기 전에는 `tasks/*.md`를 만들지 마세요.
        5. 완료 또는 건너뛰기 결과를 반드시 `zebra-source-onboarding actions report`로 보고하세요.

        태스크 검토가 completed 또는 skipped가 될 때까지 Source Onboarding을 완료했다고 말하지 마세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent(f'''
        ```text
        {completion_block}
        ```

        次に、今回取り込んだ資料から実行項目を見つけてください。

        1. `zebra-source-onboarding actions begin` を実行してください。
        2. `{skill_path}` のスキルを読み、その契約に従ってください。
        3. `{manifest_path}` に記載された GBrain record または legacy artifact だけを対象にしてください。GBrain record は manifest の sourceID 範囲で exact slug を指定して読み込んでください。
        4. 候補は最大5件とし、ユーザーが番号を承認するまで `tasks/*.md` を作成しないでください。
        5. 完了またはスキップ結果を `zebra-source-onboarding actions report` で必ず報告してください。

        タスクレビューが completed または skipped になるまで Source Onboarding 完了とは伝えないでください。
        ''').strip()
    return textwrap.dedent(f'''
    ```text
    {completion_block}
    ```

    Now find actionable work in the sources that were just ingested.

    1. Run `zebra-source-onboarding actions begin`.
    2. Read and follow the skill at `{skill_path}`.
    3. Limit input to the GBrain records or legacy artifacts listed in `{manifest_path}`. Read each GBrain record by exact slug within its manifest sourceID scope.
    4. Propose at most five candidates. Do not create `tasks/*.md` until the user approves candidate numbers.
    5. Report completion or skip through `zebra-source-onboarding actions report`.

    Do not say Source Onboarding is complete until task review is completed or skipped.
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
    ingest_receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
    verified_count = ingest_receipt.get("verifiedRecordCount") or 0
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
        Pass only a user-approved file reference to the common GBrain ingestion step:
        `zebra-source-onboarding fallback report --source {source_id} --step ingest --status completed --summary "<compact ingest result>" --ingest-title "<title>" --ingest-file "<approved-export-file>" --ingest-provenance "<provenance>"`
        Do not pass raw source body as a CLI argument. The helper reads the approved file, submits one normalized record to the common GBrain coordinator, and persists only bounded receipts.
        ''').strip()
    elif step_id == "verify_readback":
        instruction = textwrap.dedent(f'''
        Confirm the common GBrain ingestion receipt for `{display}` completed exact source-scoped readback.
        Current verified GBrain record count: `{verified_count}`
        Report completed only after the helper's common receipt is complete; the helper will reject an agent-only success claim.
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
    migrated_ingest_sources = {
        "obsidian", "agent-memory", "notion", "imessage", "apple-notes", "apple-reminders",
    }
    if (source_id in migrated_ingest_sources or is_fallback_source_row(row)) and run_state.get("completionReportPending") is not True:
        return None, {
            "ok": False,
            "reason": "source_completion_not_pending",
            "sourceID": source_id,
        }, 1
    if (source_id in migrated_ingest_sources or is_fallback_source_row(row)) and disposition == "checked":
        ingest_receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
        acquisition_receipt = run_state.get("acquisitionReceipt") if isinstance(run_state.get("acquisitionReceipt"), dict) else {}
        if ingest_receipt.get("complete") is not True or acquisition_receipt.get("complete") is not True:
            return None, {
                "ok": False,
                "reason": ingest_receipt.get("failure") or "acquisitionIncomplete",
                "sourceID": source_id,
            }, 1
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
        apple_reminders_transition(run_state, "completed")
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

def homebrew_candidate_is_verified(candidate):
    candidate = (candidate or "").strip()
    if not candidate:
        return False
    path = Path(candidate)
    if not path.is_absolute() or not path.is_file() or not os.access(str(path), os.X_OK):
        return False
    resolved = str(path.resolve())
    if ".app/Contents/" in resolved:
        return False
    if resolved == "/private/tmp" or resolved.startswith("/private/tmp/"):
        return False
    if resolved == "/var/tmp" or resolved.startswith("/var/tmp/"):
        return False
    try:
        result = subprocess.run(
            [resolved, "--version"], text=True, capture_output=True, timeout=10
        )
    except Exception:
        return False
    output = ((result.stdout or "") + "\n" + (result.stderr or "")).strip()
    return result.returncode == 0 and "Homebrew" in output

def sanitized_shell_environment():
    environment = os.environ.copy()
    inherited_zdotdir = environment.get("CMUX_ZSH_ZDOTDIR", "").strip()
    if inherited_zdotdir and Path(inherited_zdotdir).is_dir():
        environment["ZDOTDIR"] = inherited_zdotdir
    else:
        environment.pop("ZDOTDIR", None)
    return environment

def homebrew_login_shell_candidate():
    shell = os.environ.get("SHELL", "/bin/zsh").strip() or "/bin/zsh"
    if not Path(shell).is_file() or not os.access(shell, os.X_OK):
        return ""
    try:
        result = subprocess.run(
            [shell, "-lc", "command -v brew"],
            text=True,
            capture_output=True,
            timeout=10,
            env=sanitized_shell_environment(),
        )
    except Exception:
        return ""
    lines = [line.strip() for line in (result.stdout or "").splitlines() if line.strip()]
    if result.returncode != 0 or len(lines) != 1:
        return ""
    return lines[0]

def record_homebrew_install_failure(source_id, reason, returncode):
    if source_id != "apple-notes":
        print(json.dumps({"ok": False, "reason": reason, "returncode": returncode}, sort_keys=True))
        return returncode or 1
    state = load_or_create_state()
    run_state = load_source_run_state("apple-notes")
    plan = run_state.get("installPlan") if isinstance(run_state.get("installPlan"), dict) else {
        "homebrewRequired": True,
        "memoRequired": True,
        "resumeSource": "apple-notes",
        "resumeStep": "check_memo_cli",
    }
    plan.update({
        "answer": "yes",
        "status": "failed",
        "failedStage": "homebrew_install",
        "result": {"reason": reason, "returncode": returncode},
        "updatedAt": now(),
    })
    run_state["installPlan"] = plan
    run_path = save_source_run_state("apple-notes", run_state)
    state = set_apple_notes_row_state(
        state, "attention", "preflight", "check_memo_cli",
        attention_reason=reason,
        run_state_path=run_path,
    )
    save_json(state)
    print(json.dumps({
        "ok": False,
        "reason": reason,
        "returncode": returncode,
        "installPlan": plan,
    }, ensure_ascii=False, sort_keys=True))
    return returncode or 1

def install_homebrew_command():
    source_id = single_flag_value("--source").strip()
    if source_id not in {"apple-notes", "apple-reminders"}:
        print(json.dumps({"ok": False, "reason": "homebrew_install_source_invalid"}, sort_keys=True))
        return 2
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print(json.dumps({"ok": False, "reason": "homebrew_install_tty_required"}, sort_keys=True))
        return 2
    existing = apple_reminders_brew_path()
    if existing:
        if source_id == "apple-notes":
            return apple_notes_install_memo(existing, resumed_after_homebrew=True)
        print(json.dumps({"ok": True, "reason": "homebrew_already_installed", "brewPath": existing}, sort_keys=True))
        return 0
    installer = os.environ.get("ZEBRA_SOURCE_ONBOARDING_HOMEBREW_INSTALLER", "").strip()
    if not installer:
        installer = '/bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    try:
        result = subprocess.run(
            ["/bin/bash", "-c", installer],
            timeout=1800,
            env=sanitized_shell_environment(),
        )
    except subprocess.TimeoutExpired:
        return record_homebrew_install_failure(source_id, "homebrew_install_timeout", 124)
    except KeyboardInterrupt:
        return record_homebrew_install_failure(source_id, "homebrew_install_cancelled", 130)
    except Exception:
        return record_homebrew_install_failure(source_id, "homebrew_installer_failed", 1)
    brew_path = apple_reminders_brew_path()
    if not brew_path:
        reason = {
            124: "homebrew_install_timeout",
            130: "homebrew_install_cancelled",
            77: "homebrew_authentication_failed",
        }.get(result.returncode, "homebrew_installer_failed")
        return record_homebrew_install_failure(source_id, reason, result.returncode or 1)
    if source_id == "apple-notes":
        return apple_notes_install_memo(brew_path, resumed_after_homebrew=True)
    print(json.dumps({
        "ok": True,
        "reason": "homebrew_install_succeeded",
        "brewPath": brew_path,
        "installerReturnCode": result.returncode,
    }, sort_keys=True))
    return 0

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
            "actionReview": None,
            "dailyPlan": None,
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
        "actionReview": progress.get("actionReview") if isinstance(progress.get("actionReview"), dict) else None,
        "dailyPlan": progress.get("dailyPlan") if isinstance(progress.get("dailyPlan"), dict) else None,
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
    action_review = None
    daily_plan = None
    if not has_unfinished_source:
        state, action_review = prepare_action_review(state)
        if action_review.get("status") == "skipped":
            state, daily_plan = prepare_daily_plan(state)
    if daily_plan and daily_plan.get("status") in {"ready", "attention"}:
        combined_prompt = source_completion_result_block(source_id, summary_text, detail_lines) + "\n\n" + daily_plan_handoff_prompt(daily_plan)
    elif action_review and action_review.get("status") in {"ready", "attention"}:
        combined_prompt = source_action_review_handoff_prompt(
            source_id,
            summary_text,
            action_review,
            detail_lines=detail_lines,
        )
    else:
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
    if action_review:
        payload["actionReview"] = action_review
    if daily_plan:
        payload["dailyPlan"] = daily_plan
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
        if not parsed["ingestFile"]:
            run_state["ingestFailureReason"] = "ingest_file_required"
            run_path = save_source_run_state(source_id, run_state)
            state = set_fallback_row_state(
                state, source_id, "attention", fallback_phase_for_step("ingest"), "ingest",
                timestamp=timestamp, attention_reason="ingest_file_required",
                result_summary="A user-approved ingest file is required.", run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, "ingest"))
            payload.update({"ok": False, "reason": "ingest_file_required"})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        ingest_file = Path(parsed["ingestFile"]).expanduser()
        try:
            ingest_body = ingest_file.read_text(encoding="utf-8")
        except Exception:
            run_state["ingestFailureReason"] = "ingest_file_unreadable"
            run_path = save_source_run_state(source_id, run_state)
            state = set_fallback_row_state(
                state, source_id, "attention", fallback_phase_for_step("ingest"), "ingest",
                timestamp=timestamp, attention_reason="ingest_file_unreadable",
                result_summary="The approved ingest file could not be read.", run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, "ingest"))
            payload.update({"ok": False, "reason": "ingest_file_unreadable"})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        title = sanitize_control_plane_text(parsed["ingestTitle"] or source_id, limit=120)
        provenance = sanitize_control_plane_text(parsed["ingestProvenance"] or "user-approved export", limit=180)
        logical_id = title or source_id
        record = {
            "connectorID": source_id,
            "logicalRecordID": logical_id,
            "slug": deterministic_slug(source_id, logical_id),
            "markdown": "# " + title + "\n\n> Provenance: " + provenance + "\n\n" + ingest_body,
            "originURI": "uncataloged://" + prompt_file_safe_name(logical_id),
        }
        acquisition = {
            "approvedScope": run_state.get("ingestScope"),
            "discoveredCount": 1,
            "selectedCount": 1,
            "normalizedCount": 1,
            "failedCount": 0,
            "diagnosticCount": 0,
            "cancelled": False,
            "complete": True,
        }
        attempt_id = str(uuid.uuid4())
        receipt = submit_connector_ingestion(
            source_id, [record], acquisition, state, attempt_id, gbrain_state_path
        )
        run_state.update({
            "ingestAttemptID": attempt_id,
            "acquisitionReceipt": acquisition,
            "ingestReceipt": receipt,
            "ingestedRecordCount": 1,
            "updatedAt": now(),
        })
        projection = ingest_projection(receipt)
        if not projection["complete"]:
            run_state["ingestFailureReason"] = projection["attentionReason"]
            run_path = save_source_run_state(source_id, run_state)
            state = set_fallback_row_state(
                state, source_id, "attention", fallback_phase_for_step("ingest"), "ingest",
                timestamp=timestamp, attention_reason=projection["attentionReason"],
                result_summary="Common GBrain ingestion did not complete.", run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, "ingest"))
            payload.update({"ok": False, "reason": projection["attentionReason"]})
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
        receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
        projection = ingest_projection(receipt)
        if not projection["complete"]:
            run_path = save_source_run_state(source_id, run_state)
            state = set_fallback_row_state(
                state, source_id, "attention", fallback_phase_for_step("verify_readback"), "verify_readback",
                timestamp=timestamp, attention_reason=projection["attentionReason"] or "readbackMissing",
                result_summary="Common GBrain readback is incomplete.", run_state_path=run_path,
            )
            save_json(state)
            payload = summary(state)
            payload.update(source_next_prompt_payload(state, source_id, "verify_readback"))
            payload.update({"ok": False, "reason": projection["attentionReason"] or "readbackMissing"})
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        run_state.update({
            "readbackStatus": "passed",
            "verifiedRecordCount": receipt.get("verifiedRecordCount"),
            "verifiedAt": now(),
        })
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
