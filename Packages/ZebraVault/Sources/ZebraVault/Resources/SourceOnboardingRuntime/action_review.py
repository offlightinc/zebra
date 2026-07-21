import re
import uuid
from pathlib import Path

from state import ingest_projection


def prepare(state, *, state_path, ensure_progress, records, now, target_directory,
            write_json_file, source_completion_status, save_json):
    progress = ensure_progress(state)
    existing = progress.get("actionReview") if isinstance(progress.get("actionReview"), dict) else None
    if existing and existing.get("required"):
        return state, existing
    timestamp = now()
    source_records_value = records(state)
    review_id = str(uuid.uuid4())
    target = target_directory(state)
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
    manifest_path = state_path.parent / "source-action-review-manifest.json"
    write_json_file(manifest_path, {
        "schemaVersion": 1,
        "reviewID": review_id,
        "brainTargetPath": target_path,
        "sourceOnboardingStatePath": str(state_path),
        "createdAt": timestamp,
        "sources": source_records_value,
        "existingTaskPaths": existing_task_paths,
    })
    skill_path = target / ".gbrain-adapter/skills/source-to-tasks/SKILL.md" if target is not None else None
    if target is None or not source_records_value:
        status_value, reason = "skipped", "no_eligible_artifacts"
    elif skill_path is None or not skill_path.is_file():
        status_value, reason = "attention", "source_to_tasks_skill_missing"
    else:
        status_value, reason = "ready", None
    review = {
        "required": True, "status": status_value, "reviewID": review_id,
        "manifestPath": str(manifest_path), "skillPath": str(skill_path) if skill_path is not None else None,
        "eligibleSourceCount": len(source_records_value), "candidateCount": None, "approvedCount": None,
        "taskPaths": [], "reason": reason, "updatedAt": timestamp,
    }
    progress["actionReview"] = review
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    save_json(state)
    return state, review


def source_records(state, ensure_progress, ensure_execution_order, load_run_state, display_name):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    records = []
    for source_id in ensure_execution_order(progress):
        row = rows.get(source_id) if isinstance(rows.get(source_id), dict) else {}
        if row.get("status") != "checked":
            continue
        run_state = load_run_state(source_id)
        ingest_receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else None
        acquisition_receipt = run_state.get("acquisitionReceipt") if isinstance(run_state.get("acquisitionReceipt"), dict) else None
        projection = ingest_projection(ingest_receipt or {}, acquisition_receipt)
        if not ingest_receipt or projection.get("complete") is not True:
            continue
        readbacks = ingest_receipt.get("readbacks") if isinstance(ingest_receipt.get("readbacks"), list) else []
        verified = [
            {"slug": item.get("slug"), "sourceID": item.get("sourceID"), "identityMatch": True}
            for item in readbacks
            if isinstance(item, dict)
            and item.get("identityMatch") is True
            and isinstance(item.get("slug"), str) and item.get("slug")
            and isinstance(item.get("sourceID"), str) and item.get("sourceID")
        ]
        if verified and len(verified) == ingest_receipt.get("verifiedRecordCount"):
            records.append({
                "sourceID": source_id,
                "displayName": row.get("displayName") or display_name(source_id),
                "gbrainRecords": verified,
                "resultSummary": row.get("resultSummary") or run_state.get("completionSummary"),
                "runStatePath": row.get("runStatePath"),
            })
    return records


def parse_args(args):
    parsed = {"status": "", "candidateCount": None, "approvedCount": None, "taskPaths": [], "reason": ""}
    index = 0
    while index < len(args):
        token = args[index]
        if token == "--status" and index + 1 < len(args):
            parsed["status"] = args[index + 1].strip().lower()
        elif token == "--candidate-count" and index + 1 < len(args):
            parsed["candidateCount"] = int(args[index + 1])
        elif token == "--approved-count" and index + 1 < len(args):
            parsed["approvedCount"] = int(args[index + 1])
        elif token == "--task-path" and index + 1 < len(args):
            parsed["taskPaths"].append(args[index + 1])
        elif token == "--reason" and index + 1 < len(args):
            parsed["reason"] = args[index + 1].strip()
        else:
            raise ValueError("unknown or incomplete argument: " + token)
        index += 2
    return parsed


def validated_task_path(state, raw_path, target_directory, ensure_progress, load_json):
    target = target_directory(state)
    if target is None:
        return None, "gbrain_target_missing"
    target = target.resolve(strict=False)
    candidate = Path(raw_path).expanduser()
    if not candidate.is_absolute():
        candidate = target / candidate
    candidate = candidate.resolve(strict=False)
    try:
        candidate.relative_to((target / "tasks").resolve(strict=False))
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
    existing = manifest.get("existingTaskPaths") if isinstance(manifest.get("existingTaskPaths"), list) else []
    if str(candidate) in existing:
        return None, "task_preexisted_action_review"
    return str(candidate), None
