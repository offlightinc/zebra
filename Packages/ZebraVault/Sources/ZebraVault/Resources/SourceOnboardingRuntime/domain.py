import hashlib


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
    "cancelled",
})


def normalized_markdown(value):
    return str(value or "").replace("\r\n", "\n").replace("\r", "\n").rstrip() + "\n"


def identity_digest(markdown):
    return hashlib.sha256(normalized_markdown(markdown).encode("utf-8")).hexdigest()


def normalized_record(value):
    record = dict(value)
    record["connectorID"] = str(record.get("connectorID") or "").strip()
    record["logicalRecordID"] = str(record.get("logicalRecordID") or "").strip()
    record["slug"] = str(record.get("slug") or "").strip().strip("/")
    record["originURI"] = str(record.get("originURI") or "").strip()
    record["markdown"] = normalized_markdown(record.get("markdown"))
    record["identityDigest"] = identity_digest(record["markdown"])
    if not all(record.get(key) for key in ("connectorID", "logicalRecordID", "slug", "originURI")):
        raise ValueError("record_identity_missing")
    return record


def reconciliation(acquisition, write, readbacks, expected_count):
    if acquisition.get("cancelled"):
        failure = "cancelled"
    elif acquisition.get("complete") is not True:
        failure = "acquisitionIncomplete"
    elif write.get("failure"):
        failure = write["failure"]
    elif len(readbacks) != expected_count:
        failure = "readbackMissing"
    else:
        failure = next((item.get("failure") for item in readbacks if item.get("failure")), None)
    return {
        "complete": failure is None,
        "failure": failure,
        "retryable": failure not in {None, "cancelled", "acquisitionIncomplete", "targetBindingMismatch", "sourceRoutingMismatch"},
        "expectedRecordCount": expected_count,
        "verifiedRecordCount": sum(1 for item in readbacks if item.get("identityMatch") is True),
    }
