#!/usr/bin/env python3
"""Read-only Slack API comparison against Zebra captured JSONL."""
import datetime as dt
import glob
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

APP_SUPPORT = Path("/Users/han/Library/Application Support/zebra")
STATE = APP_SUPPORT / "onboarding/source-onboarding-state.json"
CHANNEL_NAMES = ["zebra", "brain"]
START = dt.datetime(2026, 7, 12, 15, 0, 0, tzinfo=dt.timezone.utc)  # Jul 13 00:00 KST


def api(token, method, **params):
    url = "https://slack.com/api/" + method
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < 3:
                time.sleep(min(int(error.headers.get("Retry-After", "1")), 30))
                continue
            raise
        if not payload.get("ok"):
            raise RuntimeError(method + ": " + str(payload.get("error", "unknown_error")))
        return payload
    raise RuntimeError(method + ": retry_exhausted")


def pages(token, method, array_key, **params):
    values = []
    cursor = ""
    while True:
        query = dict(params)
        query["limit"] = 200
        if cursor:
            query["cursor"] = cursor
        payload = api(token, method, **query)
        values.extend(payload.get(array_key, []))
        cursor = payload.get("response_metadata", {}).get("next_cursor", "")
        if not cursor:
            return values


def load_jsonl(pattern):
    values = []
    for name in glob.glob(pattern):
        with open(name, encoding="utf-8") as handle:
            for line in handle:
                if line.strip():
                    values.append(json.loads(line))
    return values


def expected_roles(message, user_id):
    roles = set()
    if message.get("user") == user_id:
        roles.add("authored")
    if "<@" + user_id + ">" in message.get("text", ""):
        roles.add("mentioned")
    if any(user_id in reaction.get("users", []) for reaction in message.get("reactions", [])):
        roles.add("reacted")
    return roles


def main():
    state = json.loads(STATE.read_text())
    readiness = state["sourceReadiness"]["slack"]
    workspace_id = readiness["workspaceID"]
    user_id = readiness["authorizedUserID"]
    account = workspace_id + ":" + user_id
    token = subprocess.run(
        ["security", "find-generic-password", "-s", "com.offlight.zebra.slack.user-token",
         "-a", account, "-w"], check=True, capture_output=True, text=True
    ).stdout.strip()

    identity = api(token, "auth.test")
    if identity.get("team_id") != workspace_id or identity.get("user_id") != user_id:
        raise RuntimeError("keychain_identity_mismatch")

    conversations = pages(
        token, "conversations.list", "channels",
        types="public_channel,private_channel", exclude_archived="true"
    )
    by_name = {channel.get("name"): channel for channel in conversations}
    missing_channels = [name for name in CHANNEL_NAMES if name not in by_name]
    if missing_channels:
        raise RuntimeError("channels_not_found: " + ",".join(missing_channels))

    root = APP_SUPPORT / f"outer-brain/slack/{workspace_id}/captured"
    raw = load_jsonl(str(root / "raw/*.jsonl"))
    projected = load_jsonl(str(root / "threads/*.jsonl"))
    raw_by_key = {}
    for item in raw:
        key = (item["conversation_id"], item["payload"].get("ts"))
        raw_by_key.setdefault(key, []).append(item["payload"])
    raw_keys = set(raw_by_key)
    projected_by_key = {}
    projected_payloads_by_key = {}
    for item in projected:
        payload = item.get("payload", {})
        channel_id = item["thread_id"].split(":", 2)[1]
        key = (channel_id, payload.get("ts"))
        projected_by_key.setdefault(key, set()).update(item.get("footprint_roles", []))
        projected_payloads_by_key.setdefault(key, []).append(payload)

    now = dt.datetime.now(dt.timezone.utc)
    result = {
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "range_start": START.isoformat().replace("+00:00", "Z"),
        "range_end": now.isoformat().replace("+00:00", "Z"),
        "workspace_id": workspace_id,
        "authorized_user_id": user_id,
        "channels": [],
    }

    for name in CHANNEL_NAMES:
        channel_id = by_name[name]["id"]
        history = pages(
            token, "conversations.history", "messages", channel=channel_id,
            oldest=str(START.timestamp()), latest=str(now.timestamp()), inclusive="true"
        )
        messages = {message.get("ts"): message for message in history if message.get("ts")}
        for root_message in list(history):
            if root_message.get("reply_count", 0) and root_message.get("ts"):
                replies = pages(token, "conversations.replies", "messages",
                                channel=channel_id, ts=root_message["ts"])
                for reply in replies:
                    if reply.get("ts") and float(reply["ts"]) >= START.timestamp():
                        messages[reply["ts"]] = reply

        expected = {}
        for timestamp, message in messages.items():
            roles = expected_roles(message, user_id)
            if roles:
                expected[(channel_id, timestamp)] = roles

        missing_raw = []
        missing_projection = []
        role_mismatches = []
        raw_payload_mismatches = []
        projection_payload_mismatches = []
        content_fields = ["text", "user", "ts", "thread_ts", "subtype", "blocks",
                          "attachments", "files", "reactions"]

        def mismatched_fields(expected_message, candidates):
            if not candidates:
                return []
            comparisons = []
            for candidate in candidates:
                comparisons.append([field for field in content_fields
                                    if expected_message.get(field) != candidate.get(field)])
            return min(comparisons, key=len)

        for key, roles in sorted(expected.items(), key=lambda item: float(item[0][1])):
            detail = {"message_ts": key[1], "expected_roles": sorted(roles),
                      "is_reply": bool(messages[key[1]].get("thread_ts"))}
            if key not in raw_keys:
                missing_raw.append(detail)
            else:
                fields = mismatched_fields(messages[key[1]], raw_by_key[key])
                if fields:
                    raw_payload_mismatches.append({**detail, "mismatched_fields": fields})
            if key not in projected_by_key:
                missing_projection.append(detail)
            else:
                fields = mismatched_fields(messages[key[1]], projected_payloads_by_key[key])
                if fields:
                    projection_payload_mismatches.append({**detail, "mismatched_fields": fields})
                actual = projected_by_key[key]
                missing_roles = roles - actual
                if missing_roles:
                    role_mismatches.append({**detail, "actual_roles": sorted(actual),
                                            "missing_roles": sorted(missing_roles)})

        seeded_threads = set()
        for key in expected:
            message = messages[key[1]]
            seeded_threads.add(message.get("thread_ts") or message.get("ts"))
        expected_context = []
        for timestamp, message in messages.items():
            root_ts = message.get("thread_ts") or message.get("ts")
            if root_ts in seeded_threads:
                expected_context.append((channel_id, timestamp))
        missing_context_raw = [key[1] for key in expected_context if key not in raw_keys]
        missing_context_projection = [key[1] for key in expected_context if key not in projected_by_key]

        role_counts = {role: 0 for role in ["authored", "mentioned", "reacted"]}
        reply_role_counts = {role: 0 for role in ["authored", "mentioned", "reacted"]}
        for key, roles in expected.items():
            is_reply = bool(messages[key[1]].get("thread_ts"))
            for role in roles:
                role_counts[role] += 1
                if is_reply:
                    reply_role_counts[role] += 1

        result["channels"].append({
            "name": name,
            "channel_id": channel_id,
            "api_messages_in_range": len(messages),
            "expected_footprint_messages": len(expected),
            "expected_role_counts": role_counts,
            "expected_reply_role_counts": reply_role_counts,
            "expected_context_messages": len(expected_context),
            "missing_raw": missing_raw,
            "missing_projection": missing_projection,
            "role_mismatches": role_mismatches,
            "raw_payload_mismatches": raw_payload_mismatches,
            "projection_payload_mismatches": projection_payload_mismatches,
            "missing_context_raw_ts": missing_context_raw,
            "missing_context_projection_ts": missing_context_projection,
        })

    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        sys.exit(1)
