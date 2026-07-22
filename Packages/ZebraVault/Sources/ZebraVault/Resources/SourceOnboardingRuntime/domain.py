import hashlib
import re
import unicodedata


FAILURES = frozenset({
    "acquisitionIncomplete",
    "stagingFailed",
    "gbrainRuntimeMissing",
    "targetBindingMismatch",
    "sourceRoutingMismatch",
    "importProcessFailed",
    "importResultMalformed",
    "importCountMismatch",
    "readbackMissing",
    "readbackIdentityMismatch",
    "writeThroughFailed",
    "filesystemPersistFailed",
    "filesystemConflict",
    "indexConfigurationFailed",
    "cancelled",
})


def normalized_markdown(value):
    return str(value or "").replace("\r\n", "\n").replace("\r", "\n").rstrip() + "\n"


def identity_digest(markdown):
    return hashlib.sha256(normalized_markdown(markdown).encode("utf-8")).hexdigest()


def deterministic_slug(connector_id, logical_record_id):
    connector = re.sub(r"[^a-z0-9._-]+", "-", str(connector_id or "source").lower()).strip("-.") or "source"
    logical = unicodedata.normalize("NFKC", str(logical_record_id or "record")).replace("\\", "/")
    parts = []
    for value in logical.split("/"):
        safe = re.sub(r"[^a-z0-9._-]+", "-", value.lower()).strip("-.")
        if safe:
            parts.append(safe)
    relative = "/".join(parts) or hashlib.sha256(logical.encode("utf-8")).hexdigest()[:16]
    return "sources/" + connector + "/" + relative


def normalized_record(value):
    record = dict(value)
    record["connectorID"] = str(record.get("connectorID") or "").strip()
    record["logicalRecordID"] = str(record.get("logicalRecordID") or "").strip()
    supplied_slug = str(record.get("slug") or "").strip().strip("/")
    record["originURI"] = str(record.get("originURI") or "").strip()
    record["markdown"] = normalized_markdown(record.get("markdown"))
    record["identityDigest"] = identity_digest(record["markdown"])
    if not all(record.get(key) for key in ("connectorID", "logicalRecordID", "originURI")):
        raise ValueError("record_identity_missing")
    expected_slug = deterministic_slug(record["connectorID"], record["logicalRecordID"])
    if supplied_slug and supplied_slug != expected_slug:
        raise ValueError("record_slug_mismatch")
    record["slug"] = expected_slug
    return record


def _receipt_count(acquisition, key):
    value = acquisition.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return None
    return value


def acquisition_failure(acquisition, expected_count):
    if acquisition.get("cancelled") is True:
        return "cancelled"
    counts = {
        key: _receipt_count(acquisition, key)
        for key in ("discoveredCount", "selectedCount", "normalizedCount", "failedCount", "diagnosticCount")
    }
    if acquisition.get("complete") is not True or any(value is None for value in counts.values()):
        return "acquisitionIncomplete"
    if counts["failedCount"] != 0 or counts["diagnosticCount"] != 0:
        return "acquisitionIncomplete"
    if counts["selectedCount"] > counts["discoveredCount"]:
        return "acquisitionIncomplete"
    if counts["normalizedCount"] != counts["selectedCount"] or counts["normalizedCount"] != expected_count:
        return "acquisitionIncomplete"
    return None


def reconciliation(
    acquisition,
    write,
    readbacks,
    expected_count,
    expected_slugs=None,
    expected_source_id=None,
):
    failure = acquisition_failure(acquisition, expected_count)
    if failure is None and write.get("failure"):
        failure = write["failure"]
    elif failure is None and len(readbacks) != expected_count:
        failure = "readbackMissing"
    elif failure is None:
        failure = next((item.get("failure") for item in readbacks if item.get("failure")), None)
    if failure is None and expected_source_id:
        if any(str(item.get("sourceID") or "") != str(expected_source_id) for item in readbacks):
            failure = "sourceRoutingMismatch"
    actual_slugs = [str(item.get("slug") or "") for item in readbacks]
    if failure is None and len(set(actual_slugs)) != len(actual_slugs):
        failure = "readbackMissing"
    if failure is None and expected_slugs is not None:
        expected = [str(value) for value in expected_slugs]
        if set(actual_slugs) != set(expected):
            failure = "readbackIdentityMismatch"
    if failure is None and any(item.get("identityMatch") is not True for item in readbacks):
        failure = "readbackIdentityMismatch"
    return {
        "complete": failure is None,
        "failure": failure,
        "retryable": failure not in {
            None, "cancelled", "acquisitionIncomplete", "targetBindingMismatch",
            "sourceRoutingMismatch", "filesystemConflict", "indexConfigurationFailed",
        },
        "expectedRecordCount": expected_count,
        "verifiedRecordCount": sum(1 for item in readbacks if item.get("identityMatch") is True),
        "expectedSlugs": list(expected_slugs) if expected_slugs is not None else None,
        "expectedSourceID": expected_source_id,
    }
