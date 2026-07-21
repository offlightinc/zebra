from datetime import datetime
from pathlib import Path


def parse_args(args):
    parsed = {"status": "", "calendarCoverage": "", "freeMinutes": None, "scheduledMinutes": None,
              "plannedTaskCount": None, "taskPaths": [], "calendarWriteStatus": "",
              "calendarEventIDs": [], "reason": ""}
    index = 0
    while index < len(args):
        token = args[index]
        mappings = {"--status": "status", "--calendar-coverage": "calendarCoverage",
                    "--calendar-write-status": "calendarWriteStatus", "--reason": "reason"}
        integer_mappings = {"--free-minutes": "freeMinutes", "--scheduled-minutes": "scheduledMinutes",
                            "--task-count": "plannedTaskCount"}
        if token in mappings and index + 1 < len(args):
            parsed[mappings[token]] = args[index + 1].strip().lower() if token in {"--status", "--calendar-write-status"} else args[index + 1].strip()
        elif token in integer_mappings and index + 1 < len(args):
            parsed[integer_mappings[token]] = int(args[index + 1])
        elif token == "--task-path" and index + 1 < len(args):
            parsed["taskPaths"].append(args[index + 1].strip())
        elif token == "--event-id" and index + 1 < len(args):
            parsed["calendarEventIDs"].append(args[index + 1].strip())
        else:
            raise ValueError("unknown or incomplete argument: " + token)
        index += 2
    return parsed


def task_frontmatter(path):
    try:
        lines = path.read_text(encoding="utf-8")[:16384].splitlines()
    except Exception:
        return None
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


def parse_timestamp(raw):
    if not isinstance(raw, str) or not raw.strip():
        return None
    value = raw.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None and parsed.utcoffset() is not None else None


def validated_task_path(state, raw_path, target_directory):
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
        return None, "planned_task_path_outside_tasks"
    if candidate.suffix.lower() != ".md" or not candidate.is_file():
        return None, "planned_task_file_missing"
    values = task_frontmatter(candidate)
    if not isinstance(values, dict) or values.get("type", "").lower() != "task":
        return None, "planned_task_type_missing"
    start_raw, end_raw = values.get("planned_start_at"), values.get("planned_end_at")
    if not start_raw or not end_raw:
        return None, "planned_task_interval_missing"
    start, end = parse_timestamp(start_raw), parse_timestamp(end_raw)
    if start is None or end is None:
        return None, "planned_task_timestamp_invalid"
    if end <= start:
        return None, "planned_task_interval_invalid"
    return str(candidate), None


def validated_task_paths(state, raw_paths, target_directory):
    validated, seen = [], set()
    for raw_path in raw_paths:
        task_path, reason = validated_task_path(state, raw_path, target_directory)
        if reason:
            return None, reason, raw_path
        if task_path in seen:
            return None, "planned_task_path_duplicate", raw_path
        seen.add(task_path)
        validated.append(task_path)
    return validated, None, None


def prepare(state, *, ensure_progress, now, target_directory, adapter_state_path,
            load_json, source_completion_status, save_json):
    progress = ensure_progress(state)
    existing = progress.get("dailyPlan") if isinstance(progress.get("dailyPlan"), dict) else None
    if existing and existing.get("required"):
        return state, existing
    timestamp = now()
    target = target_directory(state)
    skill_path = target / ".gbrain-adapter/skills/zebra-daily-planner/SKILL.md" if target is not None else None
    adapter = load_json(adapter_state_path)
    receipt = adapter.get("receipt") if isinstance(adapter.get("receipt"), dict) else {}
    checks = receipt.get("checks") if isinstance(receipt.get("checks"), dict) else {}
    expected = checks.get("adapterSkillZebraDailyPlanner") is True
    if target is None or not expected:
        required, status = False, "skipped"
        reason = "gbrain_target_missing" if target is None else "legacy_adapter_without_daily_planner"
    elif skill_path is None or not skill_path.is_file():
        required, status, reason = True, "attention", "zebra_daily_planner_skill_missing"
    else:
        required, status, reason = True, "ready", None
    daily_plan = {
        "required": required, "status": status,
        "skillPath": str(skill_path) if skill_path is not None else None,
        "calendarCoverage": None, "freeMinutes": None, "scheduledMinutes": None,
        "plannedTaskCount": None, "scheduledTaskPaths": [], "calendarWriteStatus": None,
        "calendarEventIDs": [], "reason": reason, "updatedAt": timestamp,
    }
    progress["dailyPlan"] = daily_plan
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    save_json(state)
    return state, daily_plan
