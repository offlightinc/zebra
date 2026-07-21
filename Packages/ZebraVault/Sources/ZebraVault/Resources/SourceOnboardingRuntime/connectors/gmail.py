from common import *

def gmail_readiness_record(status, env_path, connection_path=None, repair_kind=None, reasons=None):
    return {
        "status": status,
        "connectionPath": connection_path,
        "envPath": str(env_path),
        "localArtifact": local_email_artifact(),
        "repairKind": repair_kind,
        "reasons": reasons or [],
    }

def gmail_readiness():
    env_path = home / ".gbrain/.env"
    required = {"CLAWVISOR_URL", "CLAWVISOR_AGENT_TOKEN", "CLAWVISOR_TASK_ID"}
    keys = parse_env_keys(env_path)
    has_required = required.issubset(keys)
    if has_required:
        return gmail_readiness_record(
            "unverified",
            env_path,
            connection_path="existing_clawvisor_gmail_connection_path",
            reasons=["email_connection_unverified"],
        )
    return gmail_readiness_record(
        "missing_env",
        env_path,
        reasons=["clawvisor_email_env_missing_or_incomplete"],
    )

def update_gmail_readiness(status, env_path, connection_path=None, repair_kind=None, reasons=None):
    state = load_or_create_state()
    source_readiness = state.get("sourceReadiness")
    if not isinstance(source_readiness, dict):
        source_readiness = {}
    source_readiness["gmail"] = gmail_readiness_record(
        status,
        env_path,
        connection_path=connection_path,
        repair_kind=repair_kind,
        reasons=reasons,
    )
    state["sourceReadiness"] = source_readiness
    state["updatedAt"] = now()
    save_json(state)
    return state

def gmail_step_prompt(step_id, state, row):
    env_path = str(home / ".gbrain/.env")
    if step_id == "connect_clawvisor":
        return textwrap.dedent('''
        Zebra Source Onboarding: Gmail is the active source.

        Work only the Gmail/Clawvisor step `connect_clawvisor`. Do not start Notion, Obsidian, iMessage, or any other source runner in this session.

        Your first response must use the existing Zebra Gmail onboarding structure. Start by giving the user this Clawvisor connection instruction, with the numbered steps preserved:

        Zebra는 Clawvisor를 통해 Gmail, Calendar, Contacts 접근 권한을 안전하게 연결합니다.
        아래 순서대로 진행하세요.

        1. https://app.clawvisor.com/register 을 열고 Google로 sign up 또는 sign in 하세요.
        2. Clawvisor에서 왼쪽 sidebar의 Agents를 열고 GBrain을 선택한 뒤 Create GBrain agent를 클릭하세요.
        3. Google service authorization과 task approval을 이어서 진행하세요.
        4. 마지막 Env vars step에 도달하면 세 줄의 export env lines를 이 터미널에 그대로 붙여넣으세요.

        위 안내의 마지막에는 반드시 “Clawvisor Agents 페이지에 GBrain 연결 항목이 보이지 않나요?”라고 물으세요. No이면 기존 GBrain wizard를 계속하고 fallback을 언급하지 마세요. Yes이면 그 응답에서는 짧게 확인만 하고, 다음 turn에서만 Clawvisor에 로그인한 상태로 `Agents → Other agent`를 열어 자신의 `user_id`가 이미 포함된 setup prompt 전체를 복사해 현재 Zebra terminal agent에 붙여넣으라고 안내하세요. `user_id`를 추측하거나 별도 입력으로 요구하지 마세요.

        Other agent setup prompt 수행 뒤에는 Clawvisor catalog에서 Gmail, Google Calendar, Google Contacts 연결 상태를 확인하세요. 미연결 서비스는 Accounts 화면에서 OAuth 연결하도록 안내하고 완료 후 catalog를 다시 조회하세요. catalog가 반환한 활성 service identifier를 그대로 사용해 `lifetime: standing` GBrain task를 만들고 사용자 승인을 기다려 task ID를 확보하세요. account alias, curl, JSON 수정을 사용자에게 요구하지 마세요. 이후 canonical 3-key를 env에 저장하고 두 verifier가 성공한 뒤에만 완료 처리하세요. `user_id`, agent token, task ID를 Source Onboarding state나 로그에 기록하지 마세요.

        Those three canonical env vars are:

            export CLAWVISOR_URL="https://app.clawvisor.com"
            export CLAWVISOR_AGENT_TOKEN="cvis_..."
            export CLAWVISOR_TASK_ID="..."

        When the user pastes the env lines:
          1. Parse exactly `CLAWVISOR_URL`, `CLAWVISOR_AGENT_TOKEN`, and `CLAWVISOR_TASK_ID`. Ignore old Zebra-only keys if they appear.
          2. Upsert only those three canonical keys into Zebra's env file while preserving unrelated lines, then restrict the file permissions.
          3. Run `zebra-source-onboarding gmail verify-env`.
          4. Continue from the `nextPrompt` printed by that command.

        Do not ask for a Gmail account. Do not ask for a separate Gmail task id. Do not show the user any local file path, chmod instruction, or file-editing procedure. Persisting the env values is your job, not the user's. Do not search the web for Clawvisor API docs. The helper CLI is the only state write path for Gmail source progress.
        ''').strip()
    if step_id == "verify_env":
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Gmail env verification needs attention.

        Work only the Gmail/Clawvisor step `verify_env`. Do not start other source runners.

        Zebra could not verify the required Clawvisor env keys in `{env_path}`.

        Ask the user to revisit Clawvisor's Connect an Agent -> GBrain flow and paste the three env lines again. Then upsert only `CLAWVISOR_URL`, `CLAWVISOR_AGENT_TOKEN`, and `CLAWVISOR_TASK_ID`, rerun `zebra-source-onboarding gmail verify-env`, and continue from the returned `nextPrompt`.
        ''').strip()
    if step_id == "verify_connection":
        return textwrap.dedent('''
        Zebra Source Onboarding: Gmail env is present. Verify the Clawvisor Gmail connection now.

        Work only the Gmail/Clawvisor step `verify_connection`. Do not start other source runners.

        Run `zebra-source-onboarding gmail verify-connection`.

        That helper performs the Clawvisor task lookup and Gmail gateway smoke check. Do not hand-write curl calls and do not search for alternate Clawvisor API docs. If it succeeds, continue from its `nextPrompt`. If it fails, report the exact failing stage from stdout and ask the user to revisit the matching Clawvisor step.
        ''').strip()
    if step_id == "complete":
        return textwrap.dedent('''
        Zebra Source Onboarding: Gmail is complete.

        Do not run more Gmail verification commands. Briefly tell the user that Gmail is connected for Zebra Source Onboarding, then stop unless Zebra has printed a next source prompt.
        ''').strip()
    return textwrap.dedent('''
    Zebra Source Onboarding: Gmail needs attention.

    Work only the current Gmail/Clawvisor repair step. Do not start other source runners. Use the helper stdout to identify the failing stage, repair that stage, and rerun the matching `zebra-source-onboarding gmail ...` command.
    ''').strip()

def set_gmail_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
    timestamp = timestamp or now()
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("gmail") if isinstance(rows.get("gmail"), dict) else source_row_for("gmail", timestamp)
    row["status"] = row_status
    row["phase"] = phase
    row["selectionState"] = "confirmed"
    row["playbookID"] = gmail_playbook["id"]
    row["playbookVersion"] = gmail_playbook["version"]
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
    rows["gmail"] = row
    progress["sourceRows"] = rows
    if "gmail" not in ensure_execution_order(progress):
        progress["executionOrder"].append("gmail")
    if row_status in {"checked", "skipped"}:
        if progress.get("activeSourceID") == "gmail":
            progress["activeSourceID"] = None
    else:
        progress["activeSourceID"] = "gmail"
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    return state

def should_update_gmail_runner(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    if progress.get("activeSourceID") == "gmail":
        return True
    if "gmail" not in ensure_execution_order(progress):
        return False
    return isinstance(rows.get("gmail"), dict) and rows["gmail"].get("playbookID") == gmail_playbook["id"]

def strip_optional_quotes(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value

def dotenv_values():
    env_path = home / ".gbrain/.env"
    values = {}
    raw = env_path.read_text(encoding="utf-8")
    for line in raw.splitlines():
        text = line.strip()
        if not text or text.startswith("#") or "=" not in text:
            continue
        if text.startswith("export "):
            text = text[len("export "):].lstrip()
        key, value = text.split("=", 1)
        key = key.strip()
        if key:
            values[key] = strip_optional_quotes(value)
    return env_path, values

def persisted_env():
    try:
        env_path, values = dotenv_values()
    except Exception:
        env_path = home / ".gbrain/.env"
        values = {}
    return env_path, values

def request_json(method, url, token, body=None):
    try:
        data = None
        headers = {"Authorization": "Bearer " + token}
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {}
        except Exception:
            payload = {"error": raw}
        return error.code, payload
    except Exception as error:
        return 0, {"error": type(error).__name__, "detail": str(error)}

def is_gmail_service(service):
    service = (service or "").strip()
    return service == "google.gmail" or service.startswith("google.gmail:")

def gmail_service_from_task(value):
    if isinstance(value, dict):
        service = value.get("service")
        if isinstance(service, str) and is_gmail_service(service):
            return service
        actions = value.get("authorized_actions")
        if isinstance(actions, list):
            for action in actions:
                service = gmail_service_from_task(action)
                if service:
                    return service
        for key in ("task", "data", "result"):
            service = gmail_service_from_task(value.get(key))
            if service:
                return service
    if isinstance(value, list):
        for item in value:
            service = gmail_service_from_task(item)
            if service:
                return service
    return ""

def gmail_verify_env():
    env_path, env = persisted_env()
    required = [
        "CLAWVISOR_URL",
        "CLAWVISOR_AGENT_TOKEN",
        "CLAWVISOR_TASK_ID",
    ]
    missing = [key for key in required if not env.get(key, "").strip()]
    if missing:
        state = update_gmail_readiness(
            "missing_env",
            env_path,
            reasons=["missing:" + ",".join(missing)],
        )
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "connect",
                "verify_env",
                attention_reason="missing:" + ",".join(missing),
            )
            save_json(state)
            payload = {"ok": False, "missing": missing, "path": str(env_path)}
            payload.update(source_next_prompt_payload(state, "gmail", "verify_env"))
            print(json.dumps(payload, sort_keys=True))
            return 1
    else:
        state = update_gmail_readiness(
            "unverified",
            env_path,
            connection_path="clawvisor_env_available",
            reasons=["email_connection_unverified"],
        )
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "running",
                "smoke",
                "verify_connection",
            )
            save_json(state)
            payload = {"ok": True, "missing": missing, "path": str(env_path)}
            payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
            print(json.dumps(payload, sort_keys=True))
            return 0
    print(json.dumps({"ok": not missing, "missing": missing, "path": str(env_path)}, sort_keys=True))
    return 0 if not missing else 1

def gmail_verify_connection():
    env_path, env = persisted_env()
    required = ["CLAWVISOR_URL", "CLAWVISOR_AGENT_TOKEN", "CLAWVISOR_TASK_ID"]
    missing = [key for key in required if not env.get(key, "").strip()]
    if missing:
        state = update_gmail_readiness(
            "missing_env",
            env_path,
            reasons=["missing:" + ",".join(missing)],
        )
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "connect",
                "verify_env",
                attention_reason="missing:" + ",".join(missing),
            )
            save_json(state)
            payload = {"ok": False, "stage": "env", "missing": missing, "path": str(env_path)}
            payload.update(source_next_prompt_payload(state, "gmail", "verify_env"))
            print(json.dumps(payload, sort_keys=True))
            return 1
        print(json.dumps({"ok": False, "stage": "env", "missing": missing, "path": str(env_path)}, sort_keys=True))
        return 1
    base_url = env["CLAWVISOR_URL"].strip().rstrip("/")
    token = env["CLAWVISOR_AGENT_TOKEN"].strip()
    task_id = env["CLAWVISOR_TASK_ID"].strip()
    task_url = base_url + "/api/tasks/" + urllib.parse.quote(task_id, safe="")
    status, task = request_json("GET", task_url, token)
    if status == 0:
        reason = "task_request_failed:redacted"
        state = update_gmail_readiness(
            "attention",
            env_path,
            connection_path="clawvisor_task_lookup",
            repair_kind="task_request_failed",
            reasons=[reason],
        )
        payload = {"ok": False, "stage": "task", "status": status, "reason": reason}
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "smoke",
                "verify_connection",
                attention_reason=reason,
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
        print(json.dumps(payload, sort_keys=True))
        return 1
    if status < 200 or status >= 300:
        state = update_gmail_readiness(
            "attention",
            env_path,
            connection_path="clawvisor_task_lookup",
            repair_kind="task_lookup_failed",
            reasons=["task_http_status:" + str(status)],
        )
        payload = {"ok": False, "stage": "task", "status": status, "reason": "task_lookup_failed"}
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "smoke",
                "verify_connection",
                attention_reason="task_http_status:" + str(status),
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
        print(json.dumps(payload, sort_keys=True))
        return 1
    service = gmail_service_from_task(task)
    if not service:
        state = update_gmail_readiness(
            "attention",
            env_path,
            connection_path="clawvisor_task_lookup",
            repair_kind="gmail_service_missing",
            reasons=["no_authorized_google_gmail_service"],
        )
        payload = {"ok": False, "stage": "task", "reason": "no authorized google.gmail service"}
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "smoke",
                "verify_connection",
                attention_reason="no_authorized_google_gmail_service",
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
        print(json.dumps(payload, sort_keys=True))
        return 1
    gateway_body = {
        "task_id": task_id,
        "session_id": str(uuid.uuid4()),
        "service": service,
        "action": "list_messages",
        "params": {"query": "newer_than:7d", "max_results": 1},
        "reason": "Verify Zebra can read Gmail through the approved Clawvisor task before marking Source Onboarding Gmail integration complete.",
    }
    gateway_url = base_url + "/api/gateway/request?wait=true"
    status, gateway = request_json("POST", gateway_url, token, gateway_body)
    if status == 0:
        reason = "gateway_request_failed"
        state = update_gmail_readiness(
            "attention",
            env_path,
            connection_path="clawvisor_service:" + service,
            repair_kind="gateway_request_failed",
            reasons=[reason],
        )
        payload = {"ok": False, "stage": "gateway", "status": status, "service": service, "reason": reason}
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "smoke",
                "verify_connection",
                attention_reason=reason,
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
        print(json.dumps(payload, sort_keys=True))
        return 1
    if status < 200 or status >= 300:
        state = update_gmail_readiness(
            "attention",
            env_path,
            connection_path="clawvisor_service:" + service,
            repair_kind="gateway_failed",
            reasons=["gateway_http_status:" + str(status)],
        )
        payload = {"ok": False, "stage": "gateway", "status": status, "service": service, "reason": "gateway_failed"}
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "smoke",
                "verify_connection",
                attention_reason="gateway_http_status:" + str(status),
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
        print(json.dumps(payload, sort_keys=True))
        return 1
    gateway_status = gateway.get("status") if isinstance(gateway, dict) else None
    if gateway_status and gateway_status not in ("executed", "approved", "completed", "success"):
        state = update_gmail_readiness(
            "attention",
            env_path,
            connection_path="clawvisor_service:" + service,
            repair_kind="gateway_pending_or_rejected",
            reasons=["gateway_status:" + str(gateway_status)],
        )
        payload = {"ok": False, "stage": "gateway", "status": gateway_status, "service": service, "reason": "gateway_pending_or_rejected"}
        if should_update_gmail_runner(state):
            state = set_gmail_row_state(
                state,
                "attention",
                "smoke",
                "verify_connection",
                attention_reason="gateway_status:" + str(gateway_status),
            )
            save_json(state)
            payload.update(source_next_prompt_payload(state, "gmail", "verify_connection"))
        print(json.dumps(payload, sort_keys=True))
        return 1
    state = update_gmail_readiness(
        "ready",
        env_path,
        connection_path="clawvisor_service:" + service,
        reasons=[],
    )
    payload = {"ok": True, "service": service}
    if should_update_gmail_runner(state):
        state = mark_source_completion_pending(
            state,
            "gmail",
            "checked",
            "Gmail Clawvisor gateway smoke check passed for service " + service,
        )
        save_json(state)
        payload.update(source_next_prompt_payload(state, "gmail", "complete"))
    print(json.dumps(payload, sort_keys=True))
    return 0

def gmail_command():
    if not args:
        print("gmail requires a subcommand", file=sys.stderr)
        return 2
    pending_code = reject_if_completion_report_pending("gmail")
    if pending_code is not None:
        return pending_code
    subcommand = args[0]
    if subcommand == "verify-env":
        return gmail_verify_env()
    if subcommand == "verify-connection":
        return gmail_verify_connection()
    print("unknown gmail subcommand: " + subcommand, file=sys.stderr)
    return 2

