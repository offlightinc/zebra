import contextlib
import fcntl
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time

from domain import FAILURES, normalized_record, reconciliation


MAX_PUT_STDIN_BYTES = 5_000_000


class ProcessClient:
    def __init__(self, binding):
        self.binding = binding
        self.environment = os.environ.copy()
        self.environment.update({str(key): str(value) for key, value in binding.get("environment", {}).items()})
        self.environment["GBRAIN_SOURCE"] = binding["sourceID"]

    def run(self, arguments, stdin=None, timeout=300):
        try:
            completed = subprocess.run(
                [self.binding["executable"], *arguments],
                input=stdin,
                capture_output=True,
                text=True,
                cwd=self.binding["workingDirectory"],
                env=self.environment,
                timeout=timeout,
                check=False,
            )
            return {
                "exitCode": completed.returncode,
                "stdout": completed.stdout,
                "stderr": completed.stderr,
            }
        except subprocess.TimeoutExpired as error:
            return {"exitCode": 124, "stdout": error.stdout or "", "stderr": error.stderr or "timeout"}
        except Exception as error:
            return {"exitCode": 126, "stdout": "", "stderr": type(error).__name__}


def _json_result(result):
    if result.get("exitCode") != 0:
        return None
    try:
        payload = json.loads(str(result.get("stdout") or "").strip())
    except (TypeError, ValueError):
        return None
    return payload if isinstance(payload, dict) else None


def _current_source(payload):
    current = payload.get("current") if isinstance(payload.get("current"), dict) else payload
    return current.get("sourceId") or current.get("source_id") or current.get("id")


def _current_local_path(payload):
    current = payload.get("current") if isinstance(payload.get("current"), dict) else payload
    return current.get("localPath") or current.get("local_path")


def _canonical(value):
    return str(pathlib.Path(value).expanduser().resolve())


def _validate_binding(binding):
    executable = pathlib.Path(str(binding.get("executable") or "")).expanduser()
    working = pathlib.Path(str(binding.get("workingDirectory") or "")).expanduser()
    source_id = str(binding.get("sourceID") or "").strip()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        return "gbrainRuntimeMissing"
    if not working.is_dir():
        return "targetBindingMismatch"
    if not source_id:
        return "sourceRoutingMismatch"
    return None


def _verify_route(client):
    payload = _json_result(client.run(["sources", "current", "--json"], timeout=30))
    if payload is None:
        return "targetBindingMismatch"
    if str(_current_source(payload) or "") != client.binding["sourceID"]:
        return "sourceRoutingMismatch"
    local_path = _current_local_path(payload)
    if local_path and _canonical(local_path) != _canonical(client.binding["workingDirectory"]):
        return "targetBindingMismatch"
    return None


def _safe_component(value):
    cleaned = re.sub(r"[^a-z0-9._-]+", "-", str(value).lower()).strip("-.")
    return cleaned or "record"


def _staged_text(record):
    return "\n".join([
        "---",
        "slug: " + record["slug"],
        "source_kind: " + record["connectorID"],
        "source_uri: " + record["originURI"],
        "ingested_via: zebra-source-onboarding",
        "zebra_identity_digest: " + record["identityDigest"],
        "---",
        "",
        record["markdown"],
    ])


def _write_staging(root, records, attempt_id):
    manifest = []
    seen_paths = set()
    seen_slugs = set()
    for record in records:
        relative = pathlib.Path(_safe_component(record["connectorID"])) / (_safe_component(record["logicalRecordID"]) + ".md")
        if str(relative) in seen_paths or record["slug"] in seen_slugs:
            raise ValueError("duplicate_record_identity")
        seen_paths.add(str(relative))
        seen_slugs.add(record["slug"])
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(_staged_text(record), encoding="utf-8")
        destination.chmod(0o600)
        manifest.append({
            "connectorID": record["connectorID"],
            "logicalRecordID": record["logicalRecordID"],
            "relativePath": str(relative),
            "slug": record["slug"],
            "identityDigest": record["identityDigest"],
        })
    manifest_path = root / "zebra-ingest-manifest.json"
    manifest_path.write_text(json.dumps({"schemaVersion": 1, "attemptID": attempt_id, "records": manifest}, sort_keys=True) + "\n", encoding="utf-8")
    manifest_path.chmod(0o600)
    return manifest


@contextlib.contextmanager
def _bulk_lock(client, private_root):
    home = client.environment.get("GBRAIN_HOME")
    lock_root = pathlib.Path(home).expanduser() if home else private_root
    lock_root.mkdir(parents=True, exist_ok=True)
    lock_path = lock_root / ".zebra-source-onboarding-import.lock"
    handle = lock_path.open("a+")
    deadline = time.monotonic() + 300
    acquired = False
    try:
        while time.monotonic() < deadline:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
                break
            except BlockingIOError:
                time.sleep(0.05)
        if not acquired:
            raise TimeoutError("bulk_import_lock_timeout")
        yield
    finally:
        if acquired:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


def _summary_counts(payload):
    summary = payload.get("summary") if isinstance(payload.get("summary"), dict) else payload
    values = {}
    for key in ("imported", "skipped", "errors"):
        value = summary.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        if value < 0 or int(value) != value:
            return None
        values[key] = int(value)
    return values


def _write_through_failed(payload):
    if not isinstance(payload, dict):
        return False
    value = payload.get("writeThrough")
    if isinstance(value, dict):
        return value.get("ok") is False or value.get("failed") is True
    return value is False or payload.get("writeThroughFailed") is True


def _readback(client, record):
    result = client.run(["get", record["slug"]], timeout=60)
    if result.get("exitCode") != 0:
        return {"slug": record["slug"], "sourceID": client.binding["sourceID"], "identityMatch": False, "failure": "readbackMissing"}
    match = re.search(r"(?m)^zebra_identity_digest:\s*([a-f0-9]{64})\s*$", str(result.get("stdout") or ""))
    identity_match = bool(match and match.group(1) == record["identityDigest"])
    return {
        "slug": record["slug"],
        "sourceID": client.binding["sourceID"],
        "identityMatch": identity_match,
        "failure": None if identity_match else "readbackIdentityMismatch",
    }


def run_ingest(request):
    acquisition = dict(request.get("acquisition") or {})
    raw_records = request.get("records") if isinstance(request.get("records"), list) else []
    expected_count = len(raw_records)
    if acquisition.get("complete") is not True or acquisition.get("cancelled"):
        result = reconciliation(acquisition, {}, [], expected_count)
        return {**result, "attemptID": request.get("attemptID"), "write": {}, "readbacks": []}

    binding = dict(request.get("binding") or {})
    binding_failure = _validate_binding(binding)
    if binding_failure:
        write = {"failure": binding_failure}
        result = reconciliation(acquisition, write, [], expected_count)
        return {**result, "attemptID": request.get("attemptID"), "write": write, "readbacks": []}

    client = ProcessClient(binding)
    routing_failure = _verify_route(client)
    if routing_failure:
        write = {"failure": routing_failure}
        result = reconciliation(acquisition, write, [], expected_count)
        return {**result, "attemptID": request.get("attemptID"), "write": write, "readbacks": []}

    write = {"failure": None, "sourceID": binding["sourceID"], "expectedCount": expected_count}
    readbacks = []
    staging = None
    private_root = pathlib.Path(request.get("privateRoot") or tempfile.gettempdir()).expanduser()
    private_root.mkdir(parents=True, exist_ok=True)
    try:
        records = [normalized_record(value) for value in raw_records]
        staging = pathlib.Path(tempfile.mkdtemp(prefix="zebra-gbrain-ingest-", dir=str(private_root)))
        staging.chmod(0o700)
        _write_staging(staging, records, request.get("attemptID"))
        single_fits_stdin = len(records) == 1 and len(_staged_text(records[0]).encode("utf-8")) <= MAX_PUT_STDIN_BYTES
        mode = "singleRetry" if single_fits_stdin and (len(records) == 1 or request.get("mode") == "singleRetry") else "bulk"
        write["mode"] = mode
        if mode == "bulk":
            workers = max(1, min(int(request.get("workers") or 4), 8))
            with _bulk_lock(client, private_root):
                process = client.run([
                    "import", str(staging), "--source-id", binding["sourceID"],
                    "--workers", str(workers), "--fresh", "--json",
                ], timeout=1800)
            if process.get("exitCode") != 0:
                write["failure"] = "importProcessFailed"
            else:
                payload = _json_result(process)
                counts = _summary_counts(payload) if payload is not None else None
                if counts is None:
                    write["failure"] = "importResultMalformed"
                elif _write_through_failed(payload):
                    write["failure"] = "writeThroughFailed"
                elif counts["errors"] > 0 or counts["imported"] + counts["skipped"] != len(records):
                    write["failure"] = "importCountMismatch"
                else:
                    write.update(counts)
        else:
            record = records[0]
            staged = _staged_text(record)
            process = client.run([
                "put", record["slug"], "--source-kind", record["connectorID"],
                "--source-uri", record["originURI"], "--ingested-via", "zebra-source-onboarding",
            ], stdin=staged, timeout=300)
            if process.get("exitCode") != 0:
                write["failure"] = "importProcessFailed"
            else:
                payload = _json_result(process)
                if payload is None:
                    write["failure"] = "importResultMalformed"
                elif _write_through_failed(payload):
                    write["failure"] = "writeThroughFailed"
                else:
                    write["imported"] = 1
        if write.get("failure") is None:
            readbacks = [_readback(client, record) for record in records]
    except TimeoutError:
        write["failure"] = "importProcessFailed"
    except Exception:
        write["failure"] = "stagingFailed"
    finally:
        if staging is not None:
            shutil.rmtree(staging, ignore_errors=True)

    result = reconciliation(acquisition, write, readbacks, expected_count)
    if result.get("failure") not in FAILURES and result.get("failure") is not None:
        result["failure"] = "importProcessFailed"
        result["complete"] = False
    return {**result, "attemptID": request.get("attemptID"), "write": write, "readbacks": readbacks}


def run_onboarding_ingest(request):
    acquisition = dict(request.get("acquisition") or {})
    if acquisition.get("complete") is not True:
        write = {"failure": "acquisitionIncomplete"}
        result = reconciliation(acquisition, write, [], len(request.get("records") or []))
        return {**result, "attemptID": request.get("attemptID"), "write": write, "readbacks": []}
    try:
        state = json.loads(pathlib.Path(request["gbrainStatePath"]).expanduser().read_text(encoding="utf-8"))
    except Exception:
        state = {}
    receipt = state.get("receipt") if isinstance(state.get("receipt"), dict) else {}
    targets = receipt.get("targets") if isinstance(receipt.get("targets"), dict) else {}
    selected_path = request.get("selectedTargetPath")
    target_key = None
    target = None
    if selected_path:
        selected = _canonical(selected_path)
        for key, candidate in targets.items():
            if isinstance(candidate, dict) and candidate.get("vaultPath") and _canonical(candidate["vaultPath"]) == selected:
                target_key, target = key, candidate
                break
    if target is None and not selected_path:
        target_key = receipt.get("primaryTargetKey")
        target = targets.get(target_key) if target_key else None
    readiness = receipt.get("globalReadiness") if isinstance(receipt.get("globalReadiness"), dict) else {}
    if not isinstance(target, dict) or target.get("complete") is not True:
        binding_failure = "targetBindingMismatch"
    elif not target.get("sourceId"):
        binding_failure = "sourceRoutingMismatch"
    else:
        binding_failure = None
    executable = (target or {}).get("gbrainExecutablePath") or readiness.get("gbrainExecutablePath")
    binding = state.get("activeGBrainBinding") if isinstance(state.get("activeGBrainBinding"), dict) else {}
    environment = {}
    if binding.get("gbrainHomePath"):
        environment["GBRAIN_HOME"] = binding["gbrainHomePath"]
    if binding_failure:
        acquisition = dict(request.get("acquisition") or {})
        write = {"failure": binding_failure}
        result = reconciliation(acquisition, write, [], len(request.get("records") or []))
        return {**result, "attemptID": request.get("attemptID"), "write": write, "readbacks": []}
    enriched = dict(request)
    enriched["binding"] = {
        "executable": executable,
        "workingDirectory": target.get("vaultPath"),
        "sourceID": target.get("sourceId"),
        "environment": environment,
    }
    enriched.setdefault("privateRoot", str(pathlib.Path(request["gbrainStatePath"]).parent / "private-ingest-staging"))
    return run_ingest(enriched)


def submit_connector_ingestion(connector_id, records, acquisition, state, attempt_id, gbrain_state_path):
    entry = state.get("entryContext") if isinstance(state.get("entryContext"), dict) else {}
    return run_onboarding_ingest({
        "attemptID": attempt_id,
        "connectorID": connector_id,
        "gbrainStatePath": str(gbrain_state_path),
        "selectedTargetPath": entry.get("gbrainTargetPath") or entry.get("gbrainWriteTargetPath"),
        "acquisition": acquisition,
        "records": records,
    })
