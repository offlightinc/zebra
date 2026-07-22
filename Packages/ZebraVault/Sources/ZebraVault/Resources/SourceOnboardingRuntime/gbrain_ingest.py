import contextlib
import fcntl
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time

from domain import FAILURES, deterministic_slug, identity_digest, normalized_record, reconciliation


MAX_INDEX_ATTEMPTS = 3
INDEX_RETRY_DELAYS = (2, 10)


class ProcessClient:
    def __init__(self, binding, cancellation_path=None):
        self.binding = binding
        self.environment = os.environ.copy()
        self.environment.update({str(key): str(value) for key, value in binding.get("environment", {}).items()})
        self.environment["GBRAIN_SOURCE"] = binding["sourceID"]
        self.last_result = None
        self.cancellation_path = pathlib.Path(cancellation_path).expanduser() if cancellation_path else None

    def cancelled(self):
        return self.cancellation_path is not None and self.cancellation_path.exists()

    def run(self, arguments, stdin=None, timeout=300):
        if self.cancelled():
            self.last_result = {"exitCode": 130, "stdout": "", "stderr": "cancelled", "cancelled": True}
            return self.last_result
        process = None
        try:
            process = subprocess.Popen(
                [self.binding["executable"], *arguments],
                stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd=self.binding["workingDirectory"],
                env=self.environment,
            )
            deadline = time.monotonic() + timeout
            pending_input = stdin
            while True:
                if self.cancelled():
                    process.terminate()
                    try:
                        stdout, stderr = process.communicate(timeout=1)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        stdout, stderr = process.communicate()
                    self.last_result = {
                        "exitCode": 130, "stdout": stdout or "", "stderr": stderr or "cancelled", "cancelled": True,
                    }
                    return self.last_result
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    process.kill()
                    stdout, stderr = process.communicate()
                    self.last_result = {"exitCode": 124, "stdout": stdout or "", "stderr": stderr or "timeout"}
                    return self.last_result
                try:
                    stdout, stderr = process.communicate(input=pending_input, timeout=min(0.1, remaining))
                    break
                except subprocess.TimeoutExpired:
                    pending_input = None
            self.last_result = {
                "exitCode": process.returncode,
                "stdout": stdout,
                "stderr": stderr,
            }
            return self.last_result
        except Exception as error:
            if process is not None and process.poll() is None:
                process.kill()
                process.communicate()
            self.last_result = {"exitCode": 126, "stdout": "", "stderr": type(error).__name__}
            return self.last_result


def _json_result(result):
    if result.get("exitCode") != 0:
        return None
    stdout = str(result.get("stdout") or "").strip()
    candidates = [stdout]
    candidates.extend(reversed([line.strip() for line in stdout.splitlines() if line.strip()]))
    for candidate in candidates:
        try:
            payload = json.loads(candidate)
        except (TypeError, ValueError):
            continue
        if isinstance(payload, dict):
            return payload
    return None


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
    route_result = client.run(["sources", "current", "--json"], timeout=30)
    if route_result.get("cancelled"):
        return "cancelled"
    payload = _json_result(route_result)
    if payload is None:
        return "targetBindingMismatch"
    if str(_current_source(payload) or "") != client.binding["sourceID"]:
        return "sourceRoutingMismatch"
    local_path = _current_local_path(payload)
    if local_path and _canonical(local_path) != _canonical(client.binding["workingDirectory"]):
        return "targetBindingMismatch"
    return None


def _staged_text(record):
    return "\n".join([
        "---",
        "slug: " + record["slug"],
        "source_kind: " + record["connectorID"],
        "source_uri: " + json.dumps(record["originURI"], ensure_ascii=False),
        "ingested_via: zebra-source-onboarding",
        "zebra_identity_digest: " + record["identityDigest"],
        "zebra_source_schema: 1",
        "zebra_managed: true",
        "zebra_connector: " + record["connectorID"],
        "zebra_external_id: " + json.dumps(record["logicalRecordID"], ensure_ascii=False),
        "zebra_source_uri: " + json.dumps(record["originURI"], ensure_ascii=False),
        "zebra_ingested_via: zebra-source-onboarding",
        "zebra_source_content_sha256: " + record["identityDigest"],
        "zebra_record_state: active",
        "---",
        "",
        record["markdown"],
    ])


def _write_staging(root, records, attempt_id):
    manifest = []
    seen_paths = set()
    seen_slugs = set()
    for record in records:
        relative = pathlib.Path(record["slug"] + ".md")
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


def _sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def _frontmatter_value(text, key):
    match = re.search(r"(?m)^" + re.escape(key) + r":\s*(.*?)\s*$", text)
    if not match:
        return None
    value = match.group(1).strip()
    try:
        decoded = json.loads(value)
        return str(decoded) if decoded is not None else None
    except (TypeError, ValueError):
        return value


def _markdown_body(text):
    match = re.match(r"\A---\n.*?\n---\n\n?(.*)\Z", text, flags=re.DOTALL)
    return match.group(1) if match else None


def _safe_destination(root, relative):
    root = root.expanduser().resolve()
    if not root.is_dir():
        raise ValueError("target_root_missing")
    if relative.is_absolute() or any(part in {"", ".", "..", ".git", ".gbrain"} for part in relative.parts):
        raise ValueError("unsafe_canonical_path")
    destination = root / relative
    if os.path.commonpath([str(root), str(destination.resolve(strict=False))]) != str(root):
        raise ValueError("path_escapes_target")
    current = root
    for part in relative.parts[:-1]:
        current = current / part
        if current.exists() and current.is_symlink():
            raise ValueError("symlink_in_canonical_path")
    if destination.is_symlink():
        raise ValueError("symlink_canonical_file")
    return destination


def _existing_file_disposition(destination, record, expected_text):
    if not destination.exists():
        return "created"
    if not destination.is_file() or destination.is_symlink():
        raise ValueError("foreign_file_collision")
    existing = destination.read_text(encoding="utf-8")
    if existing == expected_text:
        return "unchanged"
    ownership = (
        _frontmatter_value(existing, "zebra_managed") in {"true", "True"}
        and _frontmatter_value(existing, "zebra_connector") == record["connectorID"]
        and _frontmatter_value(existing, "zebra_external_id") == record["logicalRecordID"]
        and _frontmatter_value(existing, "slug") == record["slug"]
    )
    if not ownership:
        raise ValueError("foreign_file_collision")
    body = _markdown_body(existing)
    recorded_digest = _frontmatter_value(existing, "zebra_identity_digest")
    if body is None or recorded_digest is None or identity_digest(body) != recorded_digest:
        raise ValueError("user_modified_file")
    return "updated"


def _atomic_write(destination, content, disposition, mode=None):
    if disposition == "unchanged":
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    previous_mode = mode if mode is not None else (destination.stat().st_mode & 0o777 if destination.exists() else 0o644)
    descriptor, temporary_name = tempfile.mkstemp(prefix="." + destination.name + ".zebra-tmp-", dir=str(destination.parent))
    temporary = pathlib.Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, previous_mode)
        os.replace(temporary, destination)
        directory_fd = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if temporary.exists():
            temporary.unlink()


def _atomic_json(destination, payload):
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.parent.chmod(0o700)
    encoded = (json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
    _atomic_write(destination, encoded, "created", mode=0o600)


def _operation_receipt_path(private_root, operation_id):
    identity = str(operation_id or "missing-operation-id")
    filename = hashlib.sha256(identity.encode("utf-8")).hexdigest() + ".json"
    return private_root / "durable-ingest-receipts" / filename


def _persist_operation_transition(receipt_path, operation_id, state, **fields):
    payload = {
        "schemaVersion": 1,
        "operationID": operation_id,
        "state": state,
        **fields,
    }
    _atomic_json(receipt_path, payload)
    return payload


def _persist_canonical_files(root, records):
    results = []
    for record in records:
        try:
            relative = pathlib.Path(record["slug"] + ".md")
            destination = _safe_destination(root, relative)
            text = _staged_text(record)
            disposition = _existing_file_disposition(destination, record, text)
            encoded = text.encode("utf-8")
            _atomic_write(destination, encoded, disposition)
            persisted = destination.read_bytes()
            if persisted != encoded or destination.is_symlink() or not destination.is_file():
                raise OSError("canonical_verification_failed")
            results.append({
                "slug": record["slug"],
                "relativePath": relative.as_posix(),
                "fileSHA256": _sha256_bytes(persisted),
                "sourceContentSHA256": record["identityDigest"],
                "createdOrUpdated": disposition,
                "persisted": True,
            })
        except ValueError as error:
            return results, "filesystemConflict", str(error)
        except Exception as error:
            return results, "filesystemPersistFailed", type(error).__name__
    return results, None, None


def _reverify_canonical_files(root, records):
    for record in records:
        try:
            relative = pathlib.Path(record["slug"] + ".md")
            destination = _safe_destination(root, relative)
            expected = _staged_text(record).encode("utf-8")
            if not destination.is_file() or destination.is_symlink() or destination.read_bytes() != expected:
                return "filesystemConflict", "canonical_changed_during_index"
        except ValueError as error:
            return "filesystemConflict", str(error)
        except Exception as error:
            return "filesystemPersistFailed", type(error).__name__
    return None, None


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
    return payload.get("ok") is False or value is False or payload.get("writeThroughFailed") is True


def _readback(client, record):
    result = client.run(["get", record["slug"]], timeout=60)
    if result.get("cancelled"):
        return {"slug": record["slug"], "sourceID": client.binding["sourceID"], "identityMatch": False, "failure": "cancelled"}
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


def _import_once(client, private_root, records, attempt_id, workers, ordinal):
    import_root = pathlib.Path(tempfile.mkdtemp(
        prefix="zebra-gbrain-import-" + str(attempt_id or "attempt") + "-" + str(ordinal) + "-",
        dir=str(private_root),
    ))
    import_root.chmod(0o700)
    try:
        _write_staging(import_root, records, attempt_id)
        with _bulk_lock(client, private_root):
            process = client.run([
                "import", str(import_root), "--source-id", client.binding["sourceID"],
                "--workers", str(workers), "--json",
            ], timeout=1800)
        if process.get("cancelled"):
            return "cancelled", None, process
        if process.get("exitCode") != 0:
            diagnostic = (str(process.get("stdout") or "") + "\n" + str(process.get("stderr") or "")).lower()
            permanent_markers = (
                "embedding_credentials_missing", "missing openai_api_key", "missing voyage_api_key",
                "no brain configured", "configuration error", "invalid configuration",
            )
            if any(marker in diagnostic for marker in permanent_markers):
                return "indexConfigurationFailed", None, process
            return "importProcessFailed", None, process
        payload = _json_result(process)
        counts = _summary_counts(payload) if payload is not None else None
        if counts is None:
            return "importResultMalformed", None, process
        if counts["errors"] > 0 or counts["imported"] + counts["skipped"] != len(records):
            return "importCountMismatch", counts, process
        return None, counts, process
    finally:
        shutil.rmtree(import_root, ignore_errors=True)


def _retry_delays(request):
    supplied = request.get("retryDelays")
    if isinstance(supplied, list) and len(supplied) >= 2:
        try:
            return tuple(max(0, float(value)) for value in supplied[:2])
        except (TypeError, ValueError):
            pass
    return INDEX_RETRY_DELAYS


def run_ingest(request):
    acquisition = dict(request.get("acquisition") or {})
    raw_records = request.get("records") if isinstance(request.get("records"), list) else []
    expected_count = len(raw_records)
    acquisition_result = reconciliation(acquisition, {}, [], expected_count)
    if acquisition_result.get("failure") in {"acquisitionIncomplete", "cancelled"}:
        result = acquisition_result
        return {**result, "attemptID": request.get("attemptID"), "write": {}, "readbacks": []}

    binding = dict(request.get("binding") or {})
    binding_failure = _validate_binding(binding)
    if binding_failure:
        write = {"failure": binding_failure}
        result = reconciliation(acquisition, write, [], expected_count)
        return {**result, "attemptID": request.get("attemptID"), "write": write, "readbacks": []}

    client = ProcessClient(binding, cancellation_path=request.get("cancellationPath"))
    routing_failure = _verify_route(client)
    if routing_failure:
        route_result = client.last_result or {}
        write = {
            "failure": routing_failure,
            "processExitCode": route_result.get("exitCode"),
        }
        result = reconciliation(acquisition, write, [], expected_count)
        return {**result, "attemptID": request.get("attemptID"), "write": write, "readbacks": []}

    write = {
        "failure": None,
        "sourceID": binding["sourceID"],
        "expectedCount": expected_count,
        "mode": "fileImport",
        "fresh": False,
    }
    readbacks = []
    private_root = pathlib.Path(request.get("privateRoot") or tempfile.gettempdir()).expanduser()
    private_root.mkdir(parents=True, exist_ok=True)
    operation_receipt_path = _operation_receipt_path(private_root, request.get("attemptID"))
    filesystem = {"required": request.get("persistCanonical") is True, "state": "notRequired", "records": []}
    index = {
        "state": "pending",
        "fresh": False,
        "attemptCount": 0,
        "maxAttemptCount": MAX_INDEX_ATTEMPTS,
        "retryDelaysSeconds": list(INDEX_RETRY_DELAYS),
        "records": [],
    }
    try:
        records = [normalized_record(value) for value in raw_records]
        if request.get("persistCanonical") is True:
            operation_records = [
                {
                    "slug": record["slug"],
                    "relativePath": record["slug"] + ".md",
                    "sourceContentSHA256": record["identityDigest"],
                }
                for record in records
            ]
            try:
                _persist_operation_transition(
                    operation_receipt_path,
                    request.get("attemptID"),
                    "prepared",
                    sourceID=binding["sourceID"],
                    brainRoot=_canonical(binding["workingDirectory"]),
                    records=operation_records,
                )
                filesystem_records, filesystem_failure, filesystem_detail = _persist_canonical_files(
                    pathlib.Path(binding["workingDirectory"]), records,
                )
                filesystem["records"] = filesystem_records
                filesystem["persistedCount"] = len(filesystem_records)
                if filesystem_failure is None:
                    filesystem["state"] = "verified"
                    _persist_operation_transition(
                        operation_receipt_path,
                        request.get("attemptID"),
                        "filePersisted",
                        sourceID=binding["sourceID"],
                        brainRoot=_canonical(binding["workingDirectory"]),
                        filesystem=filesystem,
                        records=operation_records,
                    )
                else:
                    filesystem.update({
                        "state": "conflict" if filesystem_failure == "filesystemConflict" else "failed",
                        "failure": filesystem_detail,
                    })
                    write["failure"] = filesystem_failure
            except Exception as error:
                filesystem.update({
                    "state": "failed",
                    "failure": "operation_receipt_" + type(error).__name__,
                })
                write["failure"] = "filesystemPersistFailed"

        if write.get("failure") is None:
            workers = max(1, min(int(request.get("workers") or 4), 8))
            delays = _retry_delays(request)
            pending = list(records)
            verified = {}
            attempt_counts = {record["slug"]: 0 for record in records}
            last_failure = None
            aggregate = {"imported": 0, "skipped": 0, "errors": 0}
            for ordinal in range(1, MAX_INDEX_ATTEMPTS + 1):
                if not pending:
                    break
                if client.cancelled():
                    last_failure = "cancelled"
                    break
                if ordinal > 1:
                    time.sleep(delays[ordinal - 2])
                for record in pending:
                    attempt_counts[record["slug"]] += 1
                failure, counts, _ = _import_once(
                    client, private_root, pending, request.get("attemptID"), workers, ordinal,
                )
                index["attemptCount"] = max(attempt_counts.values(), default=0)
                if failure == "cancelled":
                    last_failure = failure
                    break
                if failure in {"importResultMalformed", "indexConfigurationFailed"}:
                    last_failure = failure
                    break
                if counts:
                    for key in aggregate:
                        aggregate[key] += counts[key]
                current_readbacks = [_readback(client, record) for record in pending]
                next_pending = []
                for record, readback in zip(pending, current_readbacks):
                    if readback.get("identityMatch") is True:
                        verified[record["slug"]] = readback
                    else:
                        next_pending.append(record)
                        if readback.get("failure") == "readbackIdentityMismatch":
                            last_failure = "readbackIdentityMismatch"
                pending = next_pending
                if not pending:
                    last_failure = failure if failure == "importCountMismatch" else None
                    break
                if last_failure == "readbackIdentityMismatch":
                    break
                last_failure = failure or "readbackMissing"
                if last_failure not in {"importProcessFailed", "importCountMismatch", "readbackMissing"}:
                    break
            readbacks = [
                verified.get(record["slug"]) or _readback(client, record)
                for record in records
            ]
            if last_failure is None and all(item.get("identityMatch") is True for item in readbacks):
                canonical_failure = None
                canonical_detail = None
                if request.get("persistCanonical") is True:
                    canonical_failure, canonical_detail = _reverify_canonical_files(
                        pathlib.Path(binding["workingDirectory"]), records,
                    )
                if canonical_failure is None:
                    aggregate["errors"] = 0
                    write.update(aggregate)
                    write["failure"] = None
                    index["state"] = "verified"
                else:
                    filesystem.update({
                        "state": "conflict" if canonical_failure == "filesystemConflict" else "failed",
                        "failure": canonical_detail,
                    })
                    write["failure"] = canonical_failure
                    index["state"] = "failed"
            else:
                write["failure"] = last_failure or next(
                    (item.get("failure") for item in readbacks if item.get("failure")),
                    "readbackMissing",
                )
                index["state"] = "indexPending" if write["failure"] in {
                    "importProcessFailed", "importCountMismatch", "readbackMissing",
                } else "failed"
            index["records"] = [
                {
                    "slug": record["slug"],
                    "attemptCount": attempt_counts[record["slug"]],
                    "readbackVerified": verified.get(record["slug"]) is not None,
                }
                for record in records
            ]
    except TimeoutError:
        write["failure"] = "importProcessFailed"
        index["state"] = "indexPending"
    except Exception:
        write["failure"] = "stagingFailed"
        index["state"] = "failed"

    expected_slugs = [deterministic_slug(value.get("connectorID"), value.get("logicalRecordID")) for value in raw_records]
    result = reconciliation(
        acquisition,
        write,
        readbacks,
        expected_count,
        expected_slugs=expected_slugs,
        expected_source_id=binding.get("sourceID"),
    )
    if result.get("failure") not in FAILURES and result.get("failure") is not None:
        result["failure"] = "importProcessFailed"
        result["complete"] = False
    output = {
        **result,
        "schemaVersion": 2,
        "operationID": request.get("attemptID"),
        "state": (
            "complete" if result.get("complete")
            else "conflict" if filesystem.get("state") == "conflict"
            else "filesystemFailed" if filesystem.get("state") == "failed"
            else index.get("state", "failed")
        ),
        "retryable": index.get("state") == "indexPending",
        "attemptID": request.get("attemptID"),
        "acquisition": acquisition,
        "filesystem": filesystem,
        "index": index,
        "write": write,
        "readbacks": readbacks,
    }
    if request.get("persistCanonical") is True:
        output["operationReceiptPath"] = str(operation_receipt_path)
        try:
            _persist_operation_transition(
                operation_receipt_path,
                request.get("attemptID"),
                output["state"],
                sourceID=binding["sourceID"],
                brainRoot=_canonical(binding["workingDirectory"]),
                filesystem=filesystem,
                index=index,
                write=write,
                readbacks=readbacks,
                complete=output.get("complete") is True,
                retryable=output.get("retryable") is True,
            )
        except Exception as error:
            output.update({
                "complete": False,
                "state": "filesystemFailed",
                "failure": "filesystemPersistFailed",
                "retryable": True,
                "operationReceiptFailure": type(error).__name__,
            })
    return output


def run_onboarding_ingest(request):
    acquisition = dict(request.get("acquisition") or {})
    expected_count = len(request.get("records") or [])
    acquisition_result = reconciliation(acquisition, {}, [], expected_count)
    if acquisition_result.get("failure") in {"acquisitionIncomplete", "cancelled"}:
        write = {"failure": acquisition_result["failure"]}
        result = reconciliation(acquisition, write, [], expected_count)
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
        "persistCanonical": connector_id == "apple-reminders",
        "acquisition": acquisition,
        "records": records,
    })
