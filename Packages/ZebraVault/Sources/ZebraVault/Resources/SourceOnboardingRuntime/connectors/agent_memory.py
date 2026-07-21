from domain import deterministic_slug
from gbrain_ingest import submit_connector_ingestion
from state import ingest_projection
from common import *

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

def agent_memory_playbook():
    return agent_memory_playbook_fallback

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
    receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
    ingest_status = "passed" if receipt.get("complete") is True else receipt.get("failure") or "not started"
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
        - Ingest path: common GBrain ingestion with exact source-scoped readback

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
    Current GBrain ingest status: `{ingest_status}`

    Boundary rules:
    - Work only this existing agent memory step. Do not start another source unless the helper prints that source as the next active source.
    - Use the zebra-source-onboarding helper as the only Source Onboarding state write path.
    - Do not edit `source-onboarding-state.json` directly.
    - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

    Step instructions:

    {instruction}
    ''').strip()

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
    run_state.update({
        "phase": "review",
        "step": "review_found_agents",
        "foundUnitCount": len(units),
        "foundSummary": agent_memory_unit_summary(units),
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
        payload = {"ok": False, "reason": "ingest_scope_required"}
        payload.update(source_next_prompt_payload(state, "agent-memory", "review_found_agents"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    if not run_state.get("planConfirmed") or not run_state.get("approvedAt"):
        state = set_agent_memory_row_state(state, "attention", "confirm", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
        save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}
        payload.update(source_next_prompt_payload(state, "agent-memory", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    units = agent_memory_selected_units(run_state)
    records, failures = [], []
    for unit in units:
        source_path = Path(unit["path"])
        try:
            body = source_path.read_text(encoding="utf-8")
            logical_id = str(unit.get("agentID") or unit.get("displayName") or "agent") + "/" + source_path.name
            records.append({"connectorID": "agent-memory", "logicalRecordID": logical_id, "slug": deterministic_slug("agent-memory", logical_id), "markdown": body, "originURI": "agent-memory://" + logical_id})
        except Exception as error:
            failures.append({"logicalRecordID": source_path.name, "reason": type(error).__name__})
    acquisition = {"discoveredCount": len(units), "selectedCount": len(units), "normalizedCount": len(records), "failedCount": len(failures), "diagnosticCount": 0, "cancelled": False, "complete": not failures and len(records) == len(units)}
    attempt_id = str(uuid.uuid4())
    receipt = submit_connector_ingestion("agent-memory", records, acquisition, state, attempt_id, gbrain_state_path)
    run_state.update({"ingestAttemptID": attempt_id, "acquisitionReceipt": acquisition, "ingestReceipt": receipt, "ingestedUnitCount": len(records), "acquisitionDiagnostics": failures[:8], "phase": "verify", "step": "verify_readback", "updatedAt": now()})
    run_path = save_source_run_state("agent-memory", run_state)
    projection = ingest_projection(receipt, acquisition)
    state = set_agent_memory_row_state(state, "running" if projection["complete"] else "attention", "verify", "verify_readback", attention_reason=projection["attentionReason"], run_state_path=run_path, result_summary="GBrain ingest attempted for " + str(len(records)) + " agent memory records.")
    save_json(state)
    payload = {"ok": projection["complete"], "reason": projection["attentionReason"], "ingestedUnitCount": len(records)}
    payload.update(source_next_prompt_payload(state, "agent-memory", "verify_readback")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0 if projection["complete"] else 1


def agent_memory_verify_readback():
    return verify_common_ingestion_completion("agent-memory", "agent memory records")


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
