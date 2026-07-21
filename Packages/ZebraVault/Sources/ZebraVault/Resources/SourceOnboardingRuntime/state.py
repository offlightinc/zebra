import json
import os
from pathlib import Path

from domain import reconciliation


def load_json_file(path):
    try:
        with Path(path).open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def save_json_file(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, path)


def source_run_state_path(control_state_path, source_id):
    safe = "".join(
        character if character.isalnum() or character in "-_" else "-"
        for character in str(source_id or "source")
    ).strip("-_") or "source"
    directory = Path(control_state_path).parent / "source-run-state"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / (safe + ".json")


def load_source_run_state_file(control_state_path, source_id):
    return load_json_file(source_run_state_path(control_state_path, source_id))


def save_source_run_state_file(control_state_path, source_id, value):
    path = source_run_state_path(control_state_path, source_id)
    save_json_file(path, value)
    return str(path)


def ingest_projection(receipt, acquisition=None):
    acquisition_value = acquisition if isinstance(acquisition, dict) else receipt.get("acquisition")
    acquisition_value = acquisition_value if isinstance(acquisition_value, dict) else {}
    write = receipt.get("write") if isinstance(receipt.get("write"), dict) else {}
    if not write and receipt.get("complete") is False and receipt.get("failure"):
        write = {"failure": receipt.get("failure")}
    readbacks = receipt.get("readbacks") if isinstance(receipt.get("readbacks"), list) else []
    expected_count = receipt.get("expectedRecordCount")
    if isinstance(expected_count, bool) or not isinstance(expected_count, int) or expected_count < 0:
        expected_count = -1
    reconciled = reconciliation(
        acquisition_value,
        write,
        readbacks,
        expected_count,
        expected_slugs=receipt.get("expectedSlugs") if isinstance(receipt.get("expectedSlugs"), list) else None,
        expected_source_id=receipt.get("expectedSourceID"),
    )
    complete = reconciled.get("complete") is True
    return {
        "complete": complete,
        "rowStatus": "running" if complete else "attention",
        "phase": "complete" if complete else "ingest",
        "step": "complete" if complete else "verify_readback",
        "attentionReason": None if complete else reconciled.get("failure") or receipt.get("failure"),
        "retryable": reconciled.get("retryable") is True,
    }
