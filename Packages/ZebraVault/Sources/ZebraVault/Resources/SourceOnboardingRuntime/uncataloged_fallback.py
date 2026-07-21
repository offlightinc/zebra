def record_for(progress, source_id):
    records = progress.get("uncatalogedSources")
    if not isinstance(records, list):
        return {}
    return next(
        (item for item in records if isinstance(item, dict) and item.get("normalizedValue") == source_id),
        {},
    )


def source_row_for(progress, source_id, timestamp, playbook):
    record = record_for(progress, source_id)
    return {
        "id": source_id,
        "displayName": record.get("displayName") or record.get("rawValue") or source_id,
        "type": "uncataloged",
        "phase": "intake",
        "status": "unchecked",
        "selectionState": "confirmed",
        "playbookID": playbook["id"],
        "playbookVersion": playbook["version"],
        "updatedAt": timestamp,
    }


def is_source_row(row, playbook):
    return isinstance(row, dict) and (
        row.get("type") == "uncataloged" or row.get("playbookID") == playbook["id"]
    )


def phase_for_step(step_id):
    if step_id in {"classify_source", "research_access_paths", "choose_strategy"}:
        return "investigate"
    if step_id == "smoke_read":
        return "preflight"
    if step_id in {"propose_ingest_scope", "confirm_ingest_plan"}:
        return "scope"
    return {"ingest": "ingest", "verify_readback": "verify", "complete": "complete"}.get(step_id, "intake")


def next_step_id(step_id, playbook):
    steps = playbook["steps"]
    if step_id not in steps:
        return playbook["initialStepID"]
    index = steps.index(step_id)
    return steps[index + 1] if index + 1 < len(steps) else "complete"
