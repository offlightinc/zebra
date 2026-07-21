from domain import deterministic_slug
from gbrain_ingest import submit_connector_ingestion
from state import ingest_projection
from playbooks import parse_playbook_markdown
from common import *

def imessage_playbook():
    return parse_playbook_markdown(
        playbook_dir / "imessage.imsg-cli.v1.md",
        imessage_playbook_fallback,
    )

def imessage_scope_summary(run_state):
    language = onboarding_language()
    scope = run_state.get("scope") or "not selected"
    if scope == "updated-since":
        since = str(run_state.get("since") or "not selected")
        if language == "ko":
            return since + " 이후 업데이트된 대화방"
        if language == "ja":
            return since + "以降に更新された会話"
        return "recently updated conversations since " + since
    if scope == "selected-threads":
        threads = run_state.get("selectedThreadIDs") if isinstance(run_state.get("selectedThreadIDs"), list) else []
        summaries = run_state.get("selectedThreadSummaries") if isinstance(run_state.get("selectedThreadSummaries"), list) else []
        summary_by_id = {}
        for item in summaries:
            if isinstance(item, dict):
                chat_id = str(item.get("chatID") or "").strip()
                summary = str(item.get("summary") or item.get("label") or "").strip()
                if chat_id and summary:
                    summary_by_id[chat_id] = summary
        labels = []
        for item in threads:
            chat_id = str(item)
            labels.append(summary_by_id.get(chat_id) or ("chat_id " + chat_id))
        thread_list = ", ".join(labels) if labels else "none"
        if language == "ko":
            return "선택한 대화방: " + thread_list
        if language == "ja":
            return "選択した会話: " + thread_list
        return "selected conversations: " + thread_list
    if scope == "all-threads":
        if language == "ko":
            return "전체 대화방"
        if language == "ja":
            return "すべての会話"
        return "all conversations"
    if scope == "skip":
        if language == "ko":
            return "이번 Source Onboarding에서 iMessage 건너뛰기"
        if language == "ja":
            return "このSource OnboardingではiMessageをスキップ"
        return "skip iMessage for this Source Onboarding session"
    return str(scope)

def imessage_ingest_plan_summary(run_state):
    internal_window = run_state.get("internalWindow") if isinstance(run_state.get("internalWindow"), dict) else {}
    message_limit = internal_window.get("messageLimitPerThread") or "bounded"
    thread_limit = internal_window.get("threadListLimit") or "bounded"
    thread_count = run_state.get("estimatedThreadCount")
    if thread_count is None:
        thread_count = "unknown"
    language = onboarding_language()
    if language == "ko":
        return textwrap.dedent(f'''
        선택된 iMessage ingest plan입니다.

        - 선택한 범위: `{imessage_scope_summary(run_state)}`
        - 예상 대화방 수: `{thread_count}`
        - 내부 bounded window: 대화방당 최대 `{message_limit}`개 메시지, 이 helper slice에서 최대 `{thread_limit}`개 대화방
        - 민감정보 안내: 승인된 범위에는 raw message text, phone/email identifier, contact name, OTP/security text, timestamp, thread/message ID, attachment/reaction metadata가 저장될 수 있습니다.
        - Ingest 방식: 승인된 iMessage 범위를 정규화해 공통 GBrain ingestion에 제출합니다.
        - 검증 계획: 같은 source scope에서 모든 예상 slug를 `gbrain get`으로 확인합니다.

        ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding imessage confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding imessage confirm-plan --answer no`를 실행하세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent(f'''
        選択されたiMessage ingest planです。

        - 選択した範囲: `{imessage_scope_summary(run_state)}`
        - 推定会話数: `{thread_count}`
        - 内部bounded window: 1会話あたり最大`{message_limit}`件のメッセージ、このhelper sliceでは最大`{thread_limit}`件の会話
        - 機微情報の注意: 承認された範囲にはraw message text、phone/email identifier、contact name、OTP/security text、timestamp、thread/message ID、attachment/reaction metadataが保存される可能性があります。
        - Ingest方式: 承認されたiMessage範囲を正規化し、共通GBrain ingestionへ渡します。
        - 検証計画: 同じsource scopeですべての期待slugを`gbrain get`で確認します。

        ingestを実行する前にユーザーから明示的な承認を得てください。承認されたら`zebra-source-onboarding imessage confirm-plan --answer yes`を実行し、承認されなければ`zebra-source-onboarding imessage confirm-plan --answer no`を実行してください。
        ''').strip()
    return textwrap.dedent(f'''
    Resolved iMessage ingest plan:

    - Selected scope: `{imessage_scope_summary(run_state)}`
    - Estimated conversation count: `{thread_count}`
    - Internal bounded window: up to `{message_limit}` messages per conversation and up to `{thread_limit}` conversations for this helper slice
    - Sensitive data notice: approved scope may store raw message text, phone/email identifiers, contact names, OTP/security texts, timestamps, thread/message IDs, and attachment/reaction metadata.
    - Ingest mode: normalize the approved iMessage scope and submit it to common GBrain ingestion.
    - Verification plan: use `gbrain get` for every expected slug in the same source scope.

    Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding imessage confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding imessage confirm-plan --answer no`.
    ''').strip()

def imessage_step_prompt(step_id, state, row):
    playbook = imessage_playbook()
    run_state = load_source_run_state("imessage")
    section = playbook.get("sections", {}).get(step_id, "")
    language = onboarding_language()
    if not section:
        section = "Follow the current iMessage playbook step and continue only through the zebra-source-onboarding helper CLI."
    if step_id == "choose_ingest_scope":
        if language == "ko":
            scope_instruction = textwrap.dedent('''
            사용자에게 아래 네 가지 선택지만 보여주세요:

            ```text
            iMessage 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 대화방 범위를 정해야 합니다.

            어떤 범위로 가져올까요?

            1. 최근 날짜 이후 업데이트된 대화방
            2. 특정 대화방
            3. 대화방 전체
            4. 지금은 iMessage 건너뛰기
            ```

            사용자가 1번을 고르면 날짜를 물어보고 `zebra-source-onboarding imessage choose-scope --scope updated-since --since YYYY-MM-DD`를 실행하세요.
            사용자가 2번을 고르면 아래 후보 목록에서 선택한 `chat_id`를 확인한 뒤 `zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"`를 실행하세요.
            사용자가 3번을 고르면 `zebra-source-onboarding imessage choose-scope --scope all-threads`를 실행하세요.
            사용자가 4번을 고르면 `zebra-source-onboarding imessage choose-scope --scope skip`을 실행하세요.

            사용자가 2번을 고를 때는 아래 후보 목록을 사용하세요. 표시 label과 `chat_id`를 보여주고, 선택된 row id를 `--chat-id`로 넘기세요.

            메시지 개수 slicing은 사용자 선택지로 노출하지 마세요. helper가 내부 bounded window를 run state와 최종 confirm plan에 기록합니다.
            ''').strip()
        elif language == "ja":
            scope_instruction = textwrap.dedent('''
            ユーザーには次の4つの選択肢だけを表示してください:

            ```text
            iMessageへのアクセス確認は完了しました。次にbrainへ保存する会話の範囲を決めます。

            どの範囲を取り込みますか？

            1. 最近の日付以降に更新された会話
            2. 特定の会話
            3. すべての会話
            4. 今回はiMessageをスキップ
            ```

            ユーザーが1番を選んだら日付を尋ね、`zebra-source-onboarding imessage choose-scope --scope updated-since --since YYYY-MM-DD`を実行してください。
            ユーザーが2番を選んだら下の候補一覧から選択された`chat_id`を確認し、`zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"`を実行してください。
            ユーザーが3番を選んだら`zebra-source-onboarding imessage choose-scope --scope all-threads`を実行してください。
            ユーザーが4番を選んだら`zebra-source-onboarding imessage choose-scope --scope skip`を実行してください。

            ユーザーが2番を選ぶ場合は下の候補一覧を使ってください。表示labelと`chat_id`を示し、選択されたrow idを`--chat-id`に渡してください。

            メッセージ件数によるslicingはユーザー選択肢として表示しないでください。helperが内部bounded windowをrun stateと最終confirm planへ記録します。
            ''').strip()
        else:
            scope_instruction = textwrap.dedent('''
            Present exactly these four choices to the user:

            ```text
            iMessage 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 대화방 범위를 정해야 합니다.

            어떤 범위로 가져올까요?

            1. 최근 날짜 이후 업데이트된 대화방
            2. 특정 대화방
            3. 대화방 전체
            4. 지금은 iMessage 건너뛰기
            ```

            If the user chooses option 1, ask for the date and run `zebra-source-onboarding imessage choose-scope --scope updated-since --since YYYY-MM-DD`.
            If the user chooses option 2, identify the selected conversation ID from the available iMessage data and run `zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"`.
            If the user chooses option 3, run `zebra-source-onboarding imessage choose-scope --scope all-threads`.
            If the user chooses option 4, run `zebra-source-onboarding imessage choose-scope --scope skip`.

            Use the candidate list below when the user chooses option 2. Show the label and chat_id, then run `zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"` with the selected row id.

            Do not expose message-count slicing as a user option. The helper records an internal bounded window in run state and the final confirm plan.
            ''').strip()
        section = section + "\n\n" + scope_instruction + "\n\n" + imessage_conversation_choices(limit=10)
    if step_id == "confirm_ingest_plan":
        section = section + "\n\n" + imessage_ingest_plan_summary(run_state)
    command_path = run_state.get("imsgCommandPath") or "not verified"
    access = run_state.get("accessStatus") or "not verified"
    smoke = run_state.get("smokeHistoryStatus") or "not run"
    receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
    ingest_status = "passed" if receipt.get("complete") is True else receipt.get("failure") or "not started"
    return textwrap.dedent(f'''
    Zebra Source Onboarding: iMessage is the active source.

    Playbook: {playbook.get("id", "imessage.imsg-cli")} {playbook.get("version", "v1")}
    Current step: `{step_id}`
    imsg command path: `{command_path}`
    Messages access status: `{access}`
    Smoke history status: `{smoke}`
    Current ingest scope: `{imessage_scope_summary(run_state)}`
    Current GBrain ingest status: `{ingest_status}`

    Boundary rules:
    - Work only this iMessage step. Do not start Notion, Obsidian, Gmail, or another source unless the helper prints that source as the next active source.
    - Smoke-read is read-only access verification. It is not completion and not ingest approval.
    - Actual ingest/write must stay within the user-approved conversation scope.
    - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
    - Do not store raw message bodies, large chat/history JSON, prompt bodies, or transcripts in Source Onboarding state.
    - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

    Playbook step instructions:

    {section}
    ''').strip()

def set_imessage_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
    timestamp = timestamp or now()
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("imessage") if isinstance(rows.get("imessage"), dict) else source_row_for("imessage", timestamp)
    playbook = imessage_playbook()
    row["status"] = row_status
    row["phase"] = phase
    row["selectionState"] = "confirmed"
    row["playbookID"] = playbook["id"]
    row["playbookVersion"] = playbook["version"]
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
    rows["imessage"] = row
    progress["sourceRows"] = rows
    if "imessage" not in ensure_execution_order(progress):
        progress["executionOrder"].append("imessage")
    if row_status in {"checked", "skipped"}:
        if progress.get("activeSourceID") == "imessage":
            progress["activeSourceID"] = None
    else:
        progress["activeSourceID"] = "imessage"
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    return state

def start_imessage_from_next(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("imessage") if isinstance(rows.get("imessage"), dict) else {}
    playbook = imessage_playbook()
    if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
        step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "imessage", step_id))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    run_state = load_source_run_state("imessage")
    run_state.update({
        "updatedAt": now(),
    })
    run_path = save_source_run_state("imessage", run_state)
    state = set_imessage_row_state(
        state,
        "running",
        "preflight",
        playbook["initialStepID"],
        run_state_path=run_path,
    )
    save_json(state)
    payload = summary(state)
    payload.update(source_next_prompt_payload(state, "imessage", playbook["initialStepID"]))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def imessage_run_state_with_command_path():
    run_state = load_source_run_state("imessage")
    command_path = required_cli_command_path("imessage", run_state)
    return run_state, command_path

def imessage_items(value):
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        for key in ("chats", "items", "data", "results", "messages"):
            nested = value.get(key)
            if isinstance(nested, list):
                return [item for item in nested if isinstance(item, dict)]
        return [value]
    return []

def imessage_chat_id(item):
    if not isinstance(item, dict):
        return ""
    for key in ("chat_id", "chatID", "chatId", "id", "guid", "chat_guid", "chatGuid"):
        value = item.get(key)
        if value is not None and str(value):
            return str(value)
    return ""

def imessage_updated_at(item):
    if not isinstance(item, dict):
        return ""
    for key in ("updated_at", "updatedAt", "last_message_at", "lastMessageAt", "date", "timestamp"):
        value = item.get(key)
        if value is not None and str(value):
            return str(value)
    return ""

def imessage_first_string(item, keys):
    if not isinstance(item, dict):
        return ""
    for key in keys:
        value = item.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""

def imessage_chat_participants(item):
    if not isinstance(item, dict):
        return []
    participants = item.get("participants")
    if isinstance(participants, list):
        values = []
        for participant in participants:
            if isinstance(participant, dict):
                value = imessage_first_string(participant, ["contact_name", "display_name", "name", "identifier", "address", "handle"])
            else:
                value = str(participant).strip() if participant is not None else ""
            if value:
                values.append(value)
        return values
    return []

def imessage_format_handle(value):
    raw = str(value or "").strip()
    digits = re.sub(r"\D", "", raw)
    if raw.startswith("+82"):
        national = digits[2:] if digits.startswith("82") else digits
        if national.startswith("10") and len(national) == 10:
            return "+82 " + national[:2] + "-" + national[2:6] + "-" + national[6:]
        if national.startswith("2") and len(national) >= 8:
            return "+82 " + national[:1] + "-" + national[1:-4] + "-" + national[-4:]
        if len(national) == 8:
            return "+82 " + national[:4] + "-" + national[4:]
    return raw

def imessage_chat_display_label(item):
    label = imessage_first_string(item, ["contact_name", "display_name", "name"])
    handle = imessage_first_string(item, ["identifier", "address", "handle"])
    if not handle:
        participants = imessage_chat_participants(item)
        handle = participants[0] if participants else ""
    formatted_handle = imessage_format_handle(handle)
    if label and label not in {handle, formatted_handle}:
        return label + (" (" + formatted_handle + ")" if formatted_handle else "")
    return formatted_handle or label or imessage_chat_id(item) or "unknown conversation"

def imessage_chat_kind(item, language=None):
    is_group = bool(item.get("is_group") or item.get("isGroup") or item.get("group")) if isinstance(item, dict) else False
    language = language or onboarding_language()
    if language == "ko":
        return "그룹 대화" if is_group else "개인 대화"
    if language == "ja":
        return "グループ会話" if is_group else "個別会話"
    return "Group" if is_group else "Direct"

def imessage_display_time(value, language=None):
    raw = str(value or "").strip()
    if not raw:
        language = language or onboarding_language()
        if language == "ko":
            return "시간 알 수 없음"
        if language == "ja":
            return "時刻不明"
        return "unknown time"
    return raw[:16].replace("T", " ")

def imessage_chat_plan_summary(item, language=None):
    language = language or onboarding_language()
    chat_id = imessage_chat_id(item) or "unknown"
    label = imessage_chat_display_label(item)
    service = imessage_first_string(item, ["service", "service_name", "serviceName"]) or "unknown service"
    if service == "unknown service":
        if language == "ko":
            service = "서비스 알 수 없음"
        elif language == "ja":
            service = "サービス不明"
    timestamp = imessage_display_time(imessage_updated_at(item), language=language)
    separator = " · " if language in {"ko", "ja"} else " - "
    detail = service + separator + imessage_chat_kind(item, language=language) + separator + timestamp + separator + "chat_id " + chat_id
    if label and label != chat_id:
        return label + " (" + detail + ")"
    return "chat_id " + chat_id

def imessage_conversation_choices(limit=10):
    language = onboarding_language()
    _, result, chats = imessage_chats(limit=limit, failure_reason="history_read_failed")
    if not result.get("ok"):
        if language == "ko":
            return "최근 iMessage 대화방 후보를 가져오지 못했습니다: " + str(result.get("reason") or "history_read_failed")
        if language == "ja":
            return "最近のiMessage会話候補を取得できませんでした: " + str(result.get("reason") or "history_read_failed")
        return "Recent conversation candidates could not be listed: " + str(result.get("reason") or "history_read_failed")
    if not chats:
        if language == "ko":
            return "`imsg chats`가 최근 iMessage 대화방 후보를 반환하지 않았습니다."
        if language == "ja":
            return "`imsg chats`は最近のiMessage会話候補を返しませんでした。"
        return "No recent conversation candidates were returned by `imsg chats`."
    if language == "ko":
        lines = ["옵션 2에서 사용할 최근 iMessage 대화방 후보:"]
    elif language == "ja":
        lines = ["オプション2で使用する最近のiMessage会話候補:"]
    else:
        lines = ["Recent conversation candidates for option 2:"]
    for index, item in enumerate(chats, start=1):
        chat_id = imessage_chat_id(item) or "unknown"
        service = imessage_first_string(item, ["service", "service_name", "serviceName"]) or "unknown service"
        if service == "unknown service":
            if language == "ko":
                service = "서비스 알 수 없음"
            elif language == "ja":
                service = "サービス不明"
        timestamp = imessage_display_time(imessage_updated_at(item), language=language)
        lines.append(str(index) + ". " + imessage_chat_display_label(item))
        separator = " · " if language in {"ko", "ja"} else " - "
        lines.append("   " + service + separator + imessage_chat_kind(item, language=language) + separator + timestamp + separator + "chat_id " + chat_id)
    return "\n".join(lines)

def imessage_chats(limit=20, failure_reason="messages_full_disk_access_missing"):
    run_state, result = run_imsg(
        ["chats", "--limit", str(limit), "--json"],
        failure_reason=failure_reason,
    )
    if not result.get("ok"):
        return run_state, result, []
    return run_state, result, imessage_items(parse_json_output(result.get("stdout") or ""))

def imessage_history(chat_id, limit=200):
    return run_imsg(["history", "--chat-id", str(chat_id), "--limit", str(limit), "--json"], timeout=30)



def imessage_internal_window():
    return {
        "messageLimitPerThread": 200,
        "threadListLimit": 50,
        "checkpoint": "not_started",
    }

def imessage_resolve_selected_thread_summaries(run_state, thread_ids):
    if not thread_ids:
        run_state["selectedThreadSummaries"] = []
        run_state["selectedThreadSummaryStatus"] = "not_needed"
        return
    internal_window = run_state.get("internalWindow") if isinstance(run_state.get("internalWindow"), dict) else imessage_internal_window()
    thread_limit = max(int(internal_window.get("threadListLimit") or 50), len(thread_ids))
    run_state_for_chats, result, chats = imessage_chats(
        limit=thread_limit,
        failure_reason="history_read_failed",
    )
    for key in ("imsgCommandPath", "imsgVersion", "cliStatus"):
        if run_state_for_chats.get(key):
            run_state[key] = run_state_for_chats[key]
    run_state["selectedThreadSummaryListLimit"] = thread_limit
    if not result.get("ok"):
        run_state["selectedThreadSummaryStatus"] = "failed"
        run_state["selectedThreadSummaryFailureReason"] = result.get("reason") or "history_read_failed"
        run_state["selectedThreadSummaries"] = [
            {"chatID": str(chat_id), "summary": "chat_id " + str(chat_id)}
            for chat_id in thread_ids
        ]
        return
    by_id = {}
    for item in chats:
        chat_id = imessage_chat_id(item)
        if chat_id:
            by_id[str(chat_id)] = item
    summaries = []
    missing = []
    for chat_id in thread_ids:
        normalized = str(chat_id)
        item = by_id.get(normalized)
        if item:
            summaries.append({
                "chatID": normalized,
                "label": imessage_chat_display_label(item),
                "summary": imessage_chat_plan_summary(item),
            })
        else:
            missing.append(normalized)
            summaries.append({"chatID": normalized, "summary": "chat_id " + normalized})
    run_state["selectedThreadSummaries"] = summaries
    run_state["selectedThreadSummaryStatus"] = "partial" if missing else "passed"
    if missing:
        run_state["selectedThreadSummaryMissingIDs"] = missing

def imessage_scope_thread_ids(run_state):
    scope = run_state.get("scope")
    if scope == "selected-threads":
        values = run_state.get("selectedThreadIDs")
        thread_ids = [str(item) for item in values] if isinstance(values, list) else []
        imessage_resolve_selected_thread_summaries(run_state, thread_ids)
        run_state["resolvedThreadIDs"] = thread_ids
        run_state["estimatedThreadCount"] = len(thread_ids)
        return thread_ids
    internal_window = run_state.get("internalWindow") if isinstance(run_state.get("internalWindow"), dict) else imessage_internal_window()
    thread_limit = int(internal_window.get("threadListLimit") or 50)
    run_state_for_chats, result, chats = imessage_chats(
        limit=thread_limit,
        failure_reason="history_read_failed",
    )
    for key in ("imsgCommandPath", "imsgVersion", "cliStatus"):
        if run_state_for_chats.get(key):
            run_state[key] = run_state_for_chats[key]
    run_state["resolvedThreadListLimit"] = thread_limit
    if not result.get("ok"):
        run_state["threadResolutionStatus"] = "failed"
        run_state["threadResolutionFailureReason"] = result.get("reason") or "history_read_failed"
        return []
    run_state["threadResolutionStatus"] = "passed"
    run_state["threadResolutionCandidateCount"] = len(chats)
    if scope == "updated-since":
        since = run_state.get("since") or ""
        filtered = []
        for item in chats:
            updated_at = imessage_updated_at(item)
            if updated_at and updated_at[:10] >= since:
                chat_id = imessage_chat_id(item)
                if chat_id:
                    filtered.append(chat_id)
        run_state["resolvedThreadIDs"] = filtered
        run_state["estimatedThreadCount"] = len(filtered)
        return filtered
    if scope == "all-threads":
        thread_ids = [imessage_chat_id(item) for item in chats if imessage_chat_id(item)]
        run_state["resolvedThreadIDs"] = thread_ids
        run_state["estimatedThreadCount"] = len(thread_ids)
        return thread_ids
    return []

def valid_date(value):
    return bool(re.match(r"^\d{4}-\d{2}-\d{2}$", value or ""))

def imessage_check_cli():
    return check_required_cli("imessage")

def imessage_check_access():
    state = load_or_create_state()
    run_state, result, chats = imessage_chats(
        limit=1,
        failure_reason="messages_full_disk_access_missing",
    )
    if not result.get("ok"):
        reason = result.get("reason") or "messages_full_disk_access_missing"
        run_state.update({
            "accessStatus": "failed",
            "accessFailureReason": reason,
            "accessFailureStderr": (result.get("stderr") or "")[:500],
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "attention",
            "preflight",
            "check_full_disk_access",
            attention_reason=reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": reason}
        payload.update(source_next_prompt_payload(state, "imessage", "check_full_disk_access"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({
        "accessStatus": "passed",
        "estimatedThreadCount": len(chats) if chats else 0,
        "updatedAt": now(),
    })
    run_path = save_source_run_state("imessage", run_state)
    state = set_imessage_row_state(
        state,
        "running",
        "smoke",
        "smoke_history",
        run_state_path=run_path,
        result_summary="iMessage chat listing succeeded.",
    )
    save_json(state)
    payload = {"ok": True, "estimatedThreadCount": len(chats) if chats else 0}
    payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def imessage_smoke_history():
    state = load_or_create_state()
    run_state, result, chats = imessage_chats(
        limit=5,
        failure_reason="history_read_failed",
    )
    if not result.get("ok") or not chats:
        reason = result.get("reason") or "history_read_failed"
        run_state.update({
            "smokeHistoryStatus": "failed",
            "smokeFailureReason": reason,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "attention",
            "smoke",
            "smoke_history",
            attention_reason=reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": reason}
        payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    chat_id = imessage_chat_id(chats[0])
    if not chat_id:
        reason = "history_read_failed"
        run_state.update({
            "smokeHistoryStatus": "failed",
            "smokeFailureReason": reason,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "attention",
            "smoke",
            "smoke_history",
            attention_reason=reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": reason}
        payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    history_state, history_result = imessage_history(chat_id, limit=1)
    if not history_result.get("ok"):
        reason = history_result.get("reason") or "history_read_failed"
        run_state.update(history_state)
        run_state.update({
            "smokeHistoryStatus": "failed",
            "smokeFailureReason": reason,
            "smokeChatID": chat_id,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "attention",
            "smoke",
            "smoke_history",
            attention_reason=reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": reason}
        payload.update(source_next_prompt_payload(state, "imessage", "smoke_history"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update(history_state)
    run_state.update({
        "smokeHistoryStatus": "passed",
        "smokeChatID": chat_id,
        "estimatedThreadCount": len(chats),
        "updatedAt": now(),
    })
    run_path = save_source_run_state("imessage", run_state)
    state = set_imessage_row_state(
        state,
        "running",
        "ingest",
        "choose_ingest_scope",
        run_state_path=run_path,
        result_summary="iMessage read-only smoke history passed.",
    )
    save_json(state)
    payload = {"ok": True, "smokeChatID": chat_id, "estimatedThreadCount": len(chats)}
    payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def imessage_choose_scope():
    scope = single_flag_value("--scope")
    state = load_or_create_state()
    run_state = load_source_run_state("imessage")
    if scope == "skip":
        run_state.update({"scope": "skip", "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "imessage",
            "skipped",
            "iMessage skipped for this Source Onboarding session.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "skipped": True}
        payload.update(source_next_prompt_payload(state, "imessage", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    if scope == "updated-since":
        since = single_flag_value("--since")
        if not valid_date(since):
            print("--since YYYY-MM-DD is required when --scope updated-since", file=sys.stderr)
            return 2
        run_state.update({
            "scope": scope,
            "since": since,
            "selectedThreadIDs": [],
        })
    elif scope == "selected-threads":
        chat_ids = parse_flag_value("--chat-id")
        if not chat_ids:
            print("--chat-id is required when --scope selected-threads", file=sys.stderr)
            return 2
        run_state.update({
            "scope": scope,
            "selectedThreadIDs": chat_ids,
        })
    elif scope == "all-threads":
        run_state.update({
            "scope": scope,
            "selectedThreadIDs": [],
        })
    else:
        print("--scope must be updated-since, selected-threads, all-threads, or skip", file=sys.stderr)
        return 2
    run_state.update({
        "internalWindow": imessage_internal_window(),
        "planConfirmed": False,
        "sensitiveNoticeConfirmed": False,
        "updatedAt": now(),
    })
    thread_ids = imessage_scope_thread_ids(run_state)
    run_state["estimatedThreadCount"] = len(thread_ids)
    run_path = save_source_run_state("imessage", run_state)
    state = set_imessage_row_state(
        state,
        "running",
        "ingest",
        "confirm_ingest_plan",
        run_state_path=run_path,
        result_summary="iMessage ingest scope selected: " + scope,
    )
    save_json(state)
    payload = {"ok": True, "scope": scope, "estimatedThreadCount": run_state.get("estimatedThreadCount")}
    payload.update(source_next_prompt_payload(state, "imessage", "confirm_ingest_plan"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def imessage_confirm_plan():
    answer = single_flag_value("--answer").strip().lower()
    if answer not in {"yes", "y", "no", "n"}:
        print("--answer must be yes or no", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("imessage")
    if answer in {"no", "n"}:
        run_state.update({
            "planConfirmed": False,
            "sensitiveNoticeConfirmed": False,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("imessage", run_state)
        state = set_imessage_row_state(
            state,
            "attention",
            "ingest",
            "choose_ingest_scope",
            attention_reason="ingest_plan_rejected",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_rejected"}
        payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if not run_state.get("scope") or run_state.get("scope") == "skip":
        state = set_imessage_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
        save_json(state)
        payload = {"ok": False, "reason": "ingest_scope_required"}
        payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({
        "planConfirmed": True,
        "sensitiveNoticeConfirmed": True,
        "confirmedAt": now(),
        "updatedAt": now(),
    })
    run_path = save_source_run_state("imessage", run_state)
    state = set_imessage_row_state(
        state,
        "running",
        "ingest",
        "ingest_messages",
        run_state_path=run_path,
        result_summary="iMessage ingest plan confirmed.",
    )
    save_json(state)
    payload = {"ok": True, "scope": run_state.get("scope")}
    payload.update(source_next_prompt_payload(state, "imessage", "ingest_messages"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def imessage_ingest():
    state = load_or_create_state(); run_state = load_source_run_state("imessage")
    if not run_state.get("scope") or run_state.get("scope") == "skip":
        state = set_imessage_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required"); save_json(state)
        payload = {"ok": False, "reason": "ingest_scope_required"}; payload.update(source_next_prompt_payload(state, "imessage", "choose_ingest_scope")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    if not run_state.get("planConfirmed"):
        state = set_imessage_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed"); save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}; payload.update(source_next_prompt_payload(state, "imessage", "confirm_ingest_plan")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    thread_ids = imessage_scope_thread_ids(run_state)
    if not thread_ids:
        reason = run_state.get("threadResolutionFailureReason") or "no_threads_in_approved_scope"; state = set_imessage_row_state(state, "attention", "ingest", "ingest_messages", attention_reason=reason); save_json(state)
        payload = {"ok": False, "reason": reason}; payload.update(source_next_prompt_payload(state, "imessage", "ingest_messages")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    records, failures = [], []; message_limit = int((run_state.get("internalWindow") or {}).get("messageLimitPerThread") or 200)
    for chat_id in thread_ids:
        history_state, result = imessage_history(chat_id, limit=message_limit)
        if not result.get("ok"):
            failures.append({"logicalRecordID": str(chat_id), "reason": result.get("reason") or "history_read_failed"}); continue
        messages = imessage_items(parse_json_output(result.get("stdout") or ""))
        body = "# iMessage conversation\n\n```json\n" + json.dumps(messages, ensure_ascii=False, indent=2) + "\n```\n"
        logical_id = str(chat_id) + "/" + str((run_state.get("internalWindow") or {}).get("startDate") or "recent")
        records.append({"connectorID": "imessage", "logicalRecordID": logical_id, "slug": deterministic_slug("imessage", logical_id), "markdown": body, "originURI": "imessage://" + str(chat_id)})
    acquisition = {"discoveredCount": len(thread_ids), "selectedCount": len(thread_ids), "normalizedCount": len(records), "failedCount": len(failures), "diagnosticCount": 0, "cancelled": False, "complete": not failures and len(records) == len(thread_ids)}
    attempt_id = str(uuid.uuid4()); receipt = submit_connector_ingestion("imessage", records, acquisition, state, attempt_id, gbrain_state_path)
    run_state.update({"ingestAttemptID": attempt_id, "acquisitionReceipt": acquisition, "ingestReceipt": receipt, "ingestedThreadCount": len(records), "acquisitionDiagnostics": failures[:8], "updatedAt": now()})
    run_path = save_source_run_state("imessage", run_state); projection = ingest_projection(receipt)
    state = set_imessage_row_state(state, "running" if projection["complete"] else "attention", "verify", "verify_readback", attention_reason=projection["attentionReason"], run_state_path=run_path, result_summary="GBrain ingest attempted for " + str(len(records)) + " iMessage conversations."); save_json(state)
    payload = {"ok": projection["complete"], "reason": projection["attentionReason"], "ingestedThreadCount": len(records)}; payload.update(source_next_prompt_payload(state, "imessage", "verify_readback")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 0 if projection["complete"] else 1


def imessage_verify_readback():
    state = load_or_create_state(); run_state = load_source_run_state("imessage"); receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}; projection = ingest_projection(receipt)
    if not projection["complete"]:
        state = set_imessage_row_state(state, "attention", "verify", "verify_readback", attention_reason=projection["attentionReason"] or "readbackMissing", run_state_path=save_source_run_state("imessage", run_state)); save_json(state)
        payload = {"ok": False, "reason": projection["attentionReason"] or "readbackMissing"}; payload.update(source_next_prompt_payload(state, "imessage", "verify_readback")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()}); state = mark_source_completion_pending(state, "imessage", "checked", "GBrain ingest/readback verified for " + str(receipt.get("verifiedRecordCount") or 0) + " iMessage conversations.", run_state=run_state); save_json(state)
    payload = {"ok": True, "readbackStatus": "passed", "verifiedRecordCount": receipt.get("verifiedRecordCount")}; payload.update(source_next_prompt_payload(state, "imessage", "complete")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 0


def imessage_command():
    if not args:
        print("imessage requires a subcommand", file=sys.stderr)
        return 2
    pending_code = reject_if_completion_report_pending("imessage")
    if pending_code is not None:
        return pending_code
    subcommand = args[0]
    if subcommand == "check-cli":
        return imessage_check_cli()
    if subcommand == "check-access":
        return imessage_check_access()
    if subcommand == "smoke-history":
        return imessage_smoke_history()
    if subcommand == "choose-scope":
        return imessage_choose_scope()
    if subcommand == "confirm-plan":
        return imessage_confirm_plan()
    if subcommand == "ingest":
        return imessage_ingest()
    if subcommand == "verify-readback":
        return imessage_verify_readback()
    print("unknown imessage subcommand: " + subcommand, file=sys.stderr)
    return 2
