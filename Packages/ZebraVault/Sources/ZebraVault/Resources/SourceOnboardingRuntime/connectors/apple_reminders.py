from common import *

def apple_reminders_playbook():
    return parse_playbook_markdown(
        playbook_dir / "apple-reminders.eventkit.v1.md",
        apple_reminders_playbook_fallback,
    )

def apple_reminders_scope_summary(run_state):
    language = onboarding_language()
    scope = run_state.get("scope") or "not selected"
    if scope == "all-open":
        if language == "ko":
            return "모든 list의 open/incomplete reminders"
        if language == "ja":
            return "すべてのlistのopen/incomplete reminders"
        return "all open reminders"
    if scope == "one-list":
        list_name = str(run_state.get("list") or "not selected")
        if language == "ko":
            return "list `" + list_name + "`의 open/incomplete reminders"
        if language == "ja":
            return "list `" + list_name + "` のopen/incomplete reminders"
        return "open reminders from list `" + list_name + "`"
    if scope in {"today", "week", "overdue"}:
        return str(scope)
    if scope == "custom":
        parts = []
        lists = run_state.get("lists") if isinstance(run_state.get("lists"), list) else []
        if lists:
            parts.append("lists: " + ", ".join(str(item) for item in lists))
        status = run_state.get("status")
        if status:
            parts.append("status: " + str(status))
        due = run_state.get("dueWindow")
        if due:
            parts.append("due window: " + str(due))
        parts.append("completed included: " + str(bool(run_state.get("includeCompleted"))).lower())
        cap = run_state.get("itemCap")
        if cap is not None:
            parts.append("item cap: " + str(cap))
        return "custom (" + "; ".join(parts) + ")"
    if scope == "skip":
        if language == "ko":
            return "이번 Source Onboarding에서 Apple Reminders 건너뛰기"
        if language == "ja":
            return "このSource OnboardingではApple Remindersをスキップ"
        return "skip Apple Reminders for this Source Onboarding session"
    return str(scope)

def apple_reminders_ingest_plan_summary(run_state):
    count = run_state.get("expectedCount")
    count_text = str(count) if count is not None else "unknown"
    fields = run_state.get("observedReminderFields") if isinstance(run_state.get("observedReminderFields"), list) else []
    fields_text = ", ".join(str(item) for item in fields) if fields else "unknown until approved read"
    artifact = run_state.get("plannedArtifactPath") or run_state.get("artifactPath") or "will be created under the selected brain repo sources directory"
    bounded = "bounded" if run_state.get("itemCap") is not None else "full approved scope"
    language = onboarding_language()
    if language == "ko":
        return textwrap.dedent(f'''
        선택된 Apple Reminders ingest plan입니다.

        - 선택한 범위: `{apple_reminders_scope_summary(run_state)}`
        - completed 포함 여부: `{str(bool(run_state.get("includeCompleted"))).lower()}`
        - full vs bounded: `{bounded}`
        - 예상 reminder 수: `{count_text}`
        - 저장할 필드: `{fields_text}`
        - unsupported fields: EventKit 경로에서 sections, smart lists, tags, attachments, urgent/private flags는 보장하지 않습니다.
        - artifact path: `{artifact}`
        - readback plan: 생성된 artifact에서 `source: apple-reminders`와 `playbook: apple-reminders.eventkit.v1`를 확인합니다.
        - redaction policy: raw EventKit dump는 저장하지 않고, 승인된 scope 안에서 Zebra adapter가 실제 반환한 필드만 markdown으로 씁니다.

        ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding apple-reminders confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding apple-reminders confirm-plan --answer no`를 실행하세요.
        ''').strip()
    return textwrap.dedent(f'''
    Resolved Apple Reminders ingest plan:

    - Selected scope: `{apple_reminders_scope_summary(run_state)}`
    - Completed included: `{str(bool(run_state.get("includeCompleted"))).lower()}`
    - Full vs bounded: `{bounded}`
    - Expected reminder count: `{count_text}`
    - Fields to store: `{fields_text}`
    - Unsupported fields: sections, smart lists, tags, attachments, and urgent/private flags are not guaranteed through EventKit.
    - Artifact path: `{artifact}`
    - Readback plan: require `source: apple-reminders` plus `playbook: apple-reminders.eventkit.v1` in the generated artifact.
    - Redaction policy: do not store a raw EventKit dump; write only fields returned by Zebra's adapter from the approved scope.

    Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding apple-reminders confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding apple-reminders confirm-plan --answer no`.
    ''').strip()

def apple_reminders_scope_choices_instruction(language):
    if language == "ko":
        return textwrap.dedent('''
        사용자에게 아래 다섯 가지 선택지만 보여주세요:

        ```text
        Apple Reminders 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 미리알림 범위를 정해야 합니다.

        어떤 범위로 가져올까요?

        1. 열려 있는 모든 미리알림
        2. 특정 list 하나
        3. 오늘 또는 이번 주
        4. 직접 설정
        5. 지금은 Apple Reminders 건너뛰기
        ```

        1번은 `zebra-source-onboarding apple-reminders choose-scope --scope all-open`를 실행하세요.
        2번은 smoke 결과의 `lists`에서 사용자가 고른 항목의 ID를 확인한 뒤 `zebra-source-onboarding apple-reminders choose-scope --scope one-list --list-id "<list-id>"`를 실행하세요. 제목은 표시용일 뿐이며 같은 제목의 다른 list를 함께 선택하지 마세요.
        3번은 사용자가 오늘을 고르면 `--scope today`, 이번 주를 고르면 `--scope week`로 실행하세요.
        4번은 completed 포함, overdue-only, 여러 list, completed 포함 전체, item cap/sample 같은 세부 조건을 확인한 뒤 `--scope custom`과 smoke 결과의 `--list-id`, `--include-completed yes`, `--status open|completed|all`, `--due-window overdue|today|week|all`, 필요한 경우 `--item-cap <n>`을 조합해 실행하세요.
        5번은 `zebra-source-onboarding apple-reminders choose-scope --scope skip`을 실행하세요.

        sample cap을 기본값처럼 만들지 마세요. 사용자가 bounded/sample ingest를 명시적으로 원할 때만 `--item-cap`을 사용하세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent('''
        ユーザーには次の5つの選択肢だけを表示してください:

        ```text
        Apple Remindersへのアクセス確認は完了しました。次にbrainへ保存するリマインダーの範囲を決めます。

        どの範囲を取り込みますか？

        1. 未完了のすべてのリマインダー
        2. 特定のlist 1つ
        3. 今日または今週
        4. カスタム
        5. 今回はApple Remindersをスキップ
        ```

        ユーザーが1番を選んだら`zebra-source-onboarding apple-reminders choose-scope --scope all-open`を実行してください。
        ユーザーが2番を選んだらsmoke結果の`lists`から選択した項目のIDを確認し、`zebra-source-onboarding apple-reminders choose-scope --scope one-list --list-id "<list-id>"`を実行してください。タイトルは表示専用です。
        ユーザーが3番を選んだら、今日なら`--scope today`、今週なら`--scope week`を実行してください。
        ユーザーが4番を選んだら、completedを含めるか、overdue-only、複数list、completedを含む全件、item cap/sampleなどの条件を確認し、`--scope custom`にsmoke結果の`--list-id`、`--include-completed yes`、`--status open|completed|all`、`--due-window overdue|today|week|all`、必要なら`--item-cap <n>`を組み合わせて実行してください。
        ユーザーが5番を選んだら`zebra-source-onboarding apple-reminders choose-scope --scope skip`を実行してください。

        sample capをデフォルト扱いにしないでください。ユーザーがbounded/sample ingestを明示的に望む場合だけ`--item-cap`を使ってください。
        ''').strip()
    return textwrap.dedent('''
    Present exactly these five choices to the user:

    ```text
    Apple Reminders access is verified. Now choose which reminders to save into brain.

    Which scope should be ingested?

    1. All open reminders
    2. One list
    3. Today or this week
    4. Custom
    5. Skip Apple Reminders for now
    ```

    If the user chooses option 1, run `zebra-source-onboarding apple-reminders choose-scope --scope all-open`.
    If the user chooses option 2, use the selected entry's ID from the smoke result `lists` and run `zebra-source-onboarding apple-reminders choose-scope --scope one-list --list-id "<list-id>"`. Titles are display-only; never select other lists that share the title.
    If the user chooses option 3, run `--scope today` for today or `--scope week` for this week.
    If the user chooses option 4, ask only for the custom details needed for completed reminders, overdue-only, multiple lists, all including completed, or item cap/sample choices. Then run `--scope custom` with the selected smoke-result `--list-id` values, `--include-completed yes`, `--status open|completed|all`, `--due-window overdue|today|week|all`, and optional `--item-cap <n>`.
    If the user chooses option 5, run `zebra-source-onboarding apple-reminders choose-scope --scope skip`.

    Do not make a sample cap the default. Use `--item-cap` only when the user explicitly wants a bounded/sample ingest.
    ''').strip()

def apple_reminders_step_prompt(step_id, state, row):
    playbook = apple_reminders_playbook()
    run_state = load_source_run_state("apple-reminders")
    section = playbook.get("sections", {}).get(step_id, "")
    language = onboarding_language()
    if not section:
        section = "Follow the current Apple Reminders playbook step and continue only through the zebra-source-onboarding helper CLI."
    if step_id == "check_reminders_permission":
        section = section + "\n\n" + textwrap.dedent('''
        This permission is macOS access to Apple Reminders data, not Homebrew, sudo, administrator, or terminal permission. Zebra owns the system request. If the helper returns `reminders_permission_consent_required`, ask one yes/no question and pass the answer with `--permission-answer yes|no`. If denied, guide the user to System Settings > Privacy & Security > Reminders > Zebra, and offer retry or skip.
        ''').strip()
    if step_id == "choose_ingest_scope":
        section = apple_reminders_scope_choices_instruction(language)
    if step_id == "confirm_ingest_plan":
        section = section + "\n\n" + apple_reminders_ingest_plan_summary(run_state)
    permission = run_state.get("authorizationStatus") or "not verified"
    smoke = run_state.get("smokeStatus") or "not run"
    artifact = run_state.get("artifactPath") or "not created"
    return textwrap.dedent(f'''
    Zebra Source Onboarding: Apple Reminders is the active source.

    Playbook: {playbook.get("id", "apple-reminders.eventkit")} {playbook.get("version", "v1")}
    Current step: `{step_id}`
    macOS Apple Reminders data access: `{permission}`
    Smoke status: `{smoke}`
    Current ingest scope: `{apple_reminders_scope_summary(run_state)}`
    Current ingest artifact: `{artifact}`

    Boundary rules:
    - Work only this Apple Reminders step. Do not start Notion, Obsidian, iMessage, Gmail, Apple Notes, or another source unless the helper prints that source as the next active source.
    - Use only Zebra's app-owned EventKit request/receipt path. Do not install or invoke Homebrew or remindctl and do not read Reminders databases directly.
    - EventKit permission lets Zebra read Apple Reminders data. It is not administrator, installation, sudo, or terminal permission.
    - Smoke-read is read-only access verification. It is not completion and not ingest approval.
    - Actual ingest/write must stay within the user-approved reminders scope.
    - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
    - Do not store raw reminder JSON, large reminder lists, prompt bodies, or transcripts in Source Onboarding state.
    - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

    Playbook step instructions:

    {section}
    ''').strip()

def set_apple_reminders_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
    timestamp = timestamp or now()
    canonical_run_state = load_json(Path(run_state_path)) if run_state_path else {}
    workflow_status = canonical_run_state.get("workflowStatus") if isinstance(canonical_run_state, dict) else None
    if workflow_status == "completed":
        row_status = "skipped" if canonical_run_state.get("completionDisposition") == "skipped" else "checked"
        phase = "complete"
        step_id = "complete"
    elif row_status in {"checked", "skipped"}:
        row_status = "attention" if workflow_status in {"attention", "failed", "cancelled", "reconciliationRequired"} else "running"
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("apple-reminders") if isinstance(rows.get("apple-reminders"), dict) else source_row_for("apple-reminders", timestamp)
    playbook = apple_reminders_playbook()
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
    rows["apple-reminders"] = row
    progress["sourceRows"] = rows
    if "apple-reminders" not in ensure_execution_order(progress):
        progress["executionOrder"].append("apple-reminders")
    if row_status in {"checked", "skipped"}:
        if progress.get("activeSourceID") == "apple-reminders":
            progress["activeSourceID"] = None
    else:
        progress["activeSourceID"] = "apple-reminders"
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    return state

def should_update_apple_reminders_runner(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    if progress.get("activeSourceID") == "apple-reminders":
        return True
    if "apple-reminders" not in ensure_execution_order(progress):
        return False
    row = rows.get("apple-reminders")
    return isinstance(row, dict) and row.get("playbookID") == apple_reminders_playbook()["id"]

def start_apple_reminders_from_next(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("apple-reminders") if isinstance(rows.get("apple-reminders"), dict) else {}
    playbook = apple_reminders_playbook()
    if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
        step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "apple-reminders", step_id))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    run_state = load_source_run_state("apple-reminders")
    run_state.update({
        "phase": "preflight",
        "step": playbook["initialStepID"],
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-reminders", run_state)
    state = set_apple_reminders_row_state(
        state,
        "running",
        "preflight",
        playbook["initialStepID"],
        run_state_path=run_path,
    )
    save_json(state)
    payload = summary(state)
    payload.update(source_next_prompt_payload(state, "apple-reminders", playbook["initialStepID"]))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def write_private_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        os.chmod(path.parent, 0o700)
    except Exception:
        pass
    temporary = path.with_suffix(path.suffix + ".tmp-" + str(uuid.uuid4()))
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
    os.chmod(path, 0o600)

def apple_reminders_eventkit_request(operation, source_run_id, scope=None, timeout=30):
    request_id = str(uuid.uuid4())
    request_directory = reminders_eventkit_dir / "requests"
    receipt_directory = reminders_eventkit_dir / "receipts"
    request_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    receipt_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    for directory in (reminders_eventkit_dir, request_directory, receipt_directory):
        try:
            os.chmod(directory, 0o700)
        except Exception:
            pass
    request = {
        "schemaVersion": 1,
        "requestID": request_id,
        "sourceID": "apple-reminders",
        "sourceRunID": source_run_id,
        "operation": operation,
        "createdAt": now(),
        "schemaProvenance": "zebra-reminders-eventkit.v1",
        "helperBuildProvenance": os.environ.get("ZEBRA_BUILD_PROVENANCE") or "unavailable",
    }
    if scope is not None:
        request["scope"] = scope
    request_path = request_directory / (request_id + ".json")
    receipt_path = receipt_directory / (request_id + ".json")
    write_private_json(request_path, request)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        receipt = load_json(receipt_path)
        if (
            receipt.get("requestID") == request_id
            and receipt.get("sourceRunID") == source_run_id
            and receipt.get("executionOwner") == "zebra-app"
            and receipt.get("state") in {"succeeded", "failed", "cancelled"}
        ):
            for path in (request_path, receipt_path):
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            return receipt
        time.sleep(0.05)
    try:
        request_path.unlink()
    except FileNotFoundError:
        pass
    return {
        "schemaVersion": 1,
        "requestID": request_id,
        "sourceRunID": source_run_id,
        "operation": operation,
        "state": "failed",
        "executionOwner": "zebra-app",
        "authorizationStatus": "failed",
        "failureReason": "reminders_app_unavailable",
        "retryable": True,
        "createdAt": request["createdAt"],
        "startedAt": request["createdAt"],
        "completedAt": now(),
    }

def apple_reminders_source_run_id(run_state):
    value = str(run_state.get("sourceRunID") or "").strip()
    if not value:
        value = str(uuid.uuid4())
        run_state["sourceRunID"] = value
    return value

def apple_reminders_eventkit_scope(run_state):
    scope = str(run_state.get("scope") or "")
    result = {
        "kind": scope,
        "listIDs": [],
        "listTitles": [],
        "status": "open",
        "dueWindow": "all",
    }
    if scope == "one-list":
        result["listIDs"] = [str(run_state.get("listID") or "")]
        result["listTitles"] = [str(run_state.get("list") or "")]
    elif scope == "today":
        result["dueWindow"] = "today"
    elif scope == "week":
        result["dueWindow"] = "week"
    elif scope == "custom":
        result["listIDs"] = [str(item) for item in (run_state.get("listIDs") or [])]
        result["listTitles"] = [str(item) for item in (run_state.get("lists") or [])]
        result["status"] = str(run_state.get("status") or "open")
        result["dueWindow"] = str(run_state.get("dueWindow") or "all")
    elif scope == "skip":
        result["status"] = "all"
    cap = run_state.get("itemCap")
    if isinstance(cap, int):
        result["itemCap"] = cap
    return result

def apple_reminders_receipt_failure(receipt, fallback):
    return str(receipt.get("failureReason") or fallback)

def apple_reminders_transition(run_state, target):
    allowed = {
        None: {"discovering", "scopeProposed"},
        "discovering": {"scopeProposed", "failed", "cancelled", "attention"},
        "scopeProposed": {"discovering", "scopeProposed", "scopeApproved", "completionPending", "failed", "cancelled", "attention"},
        "scopeApproved": {"fetching", "scopeProposed", "failed", "cancelled", "attention"},
        "fetching": {"reconciliationRequired", "readyToCommit", "failed", "cancelled", "attention"},
        "reconciliationRequired": {"discovering", "fetching", "scopeProposed", "cancelled", "attention"},
        "readyToCommit": {"artifactCommitted", "failed", "cancelled", "attention"},
        "artifactCommitted": {"readbackPassed", "failed", "attention"},
        "readbackPassed": {"completionPending", "failed", "attention"},
        "completionPending": {"completed", "failed", "attention"},
        "completed": set(),
        "failed": set(),
        "cancelled": set(),
        "attention": {"discovering", "scopeProposed", "scopeApproved", "fetching", "cancelled"},
    }
    current = run_state.get("workflowStatus")
    if target not in allowed.get(current, set()):
        raise RuntimeError("invalid Apple Reminders workflow transition: " + str(current) + " -> " + str(target))
    run_state["workflowStatus"] = target
    return run_state

def apple_reminders_brew_path():
    override_present = "ZEBRA_SOURCE_ONBOARDING_BREW_PATH" in os.environ
    override = os.environ.get("ZEBRA_SOURCE_ONBOARDING_BREW_PATH", "").strip()
    if override_present:
        return override if homebrew_candidate_is_verified(override) else ""
    candidates = [shutil.which("brew") or ""]
    prefix = os.environ.get("HOMEBREW_PREFIX", "").strip()
    if prefix:
        candidates.append(str(Path(prefix) / "bin" / "brew"))
    if "ZEBRA_SOURCE_ONBOARDING_BREW_STANDARD_PATHS" in os.environ:
        standard_paths = [
            value.strip()
            for value in os.environ.get("ZEBRA_SOURCE_ONBOARDING_BREW_STANDARD_PATHS", "").split(os.pathsep)
            if value.strip()
        ]
    else:
        standard_paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    candidates.extend(standard_paths)
    candidates.append(homebrew_login_shell_candidate())
    seen = set()
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        if homebrew_candidate_is_verified(candidate):
            return str(Path(candidate).resolve())
    return ""

def apple_reminders_command_result(command, timeout=120):
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
        return {
            "ok": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": (result.stdout or "")[:1000],
            "stderr": (result.stderr or "")[:1000],
        }
    except subprocess.TimeoutExpired as error:
        return {
            "ok": False,
            "returncode": 124,
            "stdout": (error.stdout or "")[:1000],
            "stderr": (error.stderr or "command timed out")[:1000],
        }
    except Exception as error:
        return {
            "ok": False,
            "returncode": 1,
            "stdout": "",
            "stderr": str(error)[:1000],
        }

def apple_reminders_install_answer(flag):
    answer = single_flag_value(flag).strip().lower()
    if answer in {"yes", "y"}:
        return "yes"
    if answer in {"no", "n"}:
        return "no"
    return ""

def apple_reminders_check_access():
    state = load_or_create_state()
    run_state = load_source_run_state("apple-reminders")
    source_run_id = apple_reminders_source_run_id(run_state)
    answer = apple_reminders_install_answer("--permission-answer")
    status_receipt = apple_reminders_eventkit_request(
        "authorization-status", source_run_id, timeout=10
    )
    initial_status = str(status_receipt.get("authorizationStatus") or "failed")
    final_receipt = status_receipt
    if initial_status == "notDetermined":
        if answer == "no":
            run_state.update({
                "permissionRequestAsked": True,
                "permissionRequestAnswer": "no",
                "authorizationStatus": "notDetermined",
                "permissionStatus": "notDetermined",
                "updatedAt": now(),
            })
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(
                state, "attention", "preflight", "check_reminders_permission",
                attention_reason="reminders_permission_declined",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {
                "ok": False,
                "reason": "reminders_permission_declined",
                "authorizationStatus": "notDetermined",
                "retryable": True,
            }
            payload.update(source_next_prompt_payload(state, "apple-reminders", "check_reminders_permission"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        if answer != "yes":
            run_state.update({
                "permissionRequestAsked": True,
                "permissionRequestAnswer": None,
                "authorizationStatus": "notDetermined",
                "permissionStatus": "notDetermined",
                "updatedAt": now(),
            })
            run_path = save_source_run_state("apple-reminders", run_state)
            state = set_apple_reminders_row_state(
                state, "attention", "preflight", "check_reminders_permission",
                attention_reason="reminders_permission_consent_required",
                run_state_path=run_path,
            )
            save_json(state)
            payload = {
                "ok": False,
                "reason": "reminders_permission_consent_required",
                "authorizationStatus": "notDetermined",
                "retryable": True,
            }
            payload.update(source_next_prompt_payload(state, "apple-reminders", "check_reminders_permission"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        final_receipt = apple_reminders_eventkit_request(
            "request-authorization", source_run_id, timeout=90
        )
    final_status = str(final_receipt.get("authorizationStatus") or "failed")
    failure_reason = apple_reminders_receipt_failure(
        final_receipt, "reminders_permission_request_failed"
    )
    run_state.update({
        "permissionRequestAsked": initial_status == "notDetermined",
        "permissionRequestAnswer": answer or run_state.get("permissionRequestAnswer"),
        "authorizationStatus": final_status,
        "permissionStatus": final_status,
        "permissionInitialStatus": initial_status,
        "permissionExecutionOwner": final_receipt.get("executionOwner"),
        "permissionRequestState": final_receipt.get("state"),
        "updatedAt": now(),
    })
    if final_receipt.get("state") != "succeeded" or final_status != "authorized":
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "attention",
            "preflight",
            "check_reminders_permission",
            attention_reason=failure_reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {
            "ok": False,
            "reason": failure_reason,
            "authorizationStatus": final_status,
            "retryable": bool(final_receipt.get("retryable")),
        }
        payload.update(source_next_prompt_payload(state, "apple-reminders", "check_reminders_permission"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_path = save_source_run_state("apple-reminders", run_state)
    state = set_apple_reminders_row_state(
        state,
        "running",
        "smoke",
        "smoke_list_reminders",
        run_state_path=run_path,
        result_summary="Apple Reminders data access authorized for Zebra.",
    )
    save_json(state)
    payload = {
        "ok": True,
        "authorizationStatus": final_status,
        "permissionStatus": final_status,
        "executionOwner": final_receipt.get("executionOwner"),
    }
    payload.update(source_next_prompt_payload(state, "apple-reminders", "smoke_list_reminders"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def reminder_items(value):
    if isinstance(value, list):
        return [item for item in value if isinstance(item, dict)]
    if isinstance(value, dict):
        for key in ("reminders", "items", "data", "results"):
            nested = value.get(key)
            if isinstance(nested, list):
                return [item for item in nested if isinstance(item, dict)]
        return [value]
    return []

def reminder_field_names(items):
    fields = []
    seen = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        for key in item.keys():
            text = str(key)
            if text not in seen:
                seen.add(text)
                fields.append(text)
    return fields

def reminder_list_title(item):
    if not isinstance(item, dict):
        return ""
    for key in ("title", "name", "list", "listName"):
        value = item.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""

def apple_reminders_smoke_list():
    state = load_or_create_state()
    run_state = load_source_run_state("apple-reminders")
    if run_state.get("authorizationStatus") != "authorized":
        state = set_apple_reminders_row_state(
            state, "attention", "preflight", "check_reminders_permission",
            attention_reason="reminders_permission_required",
        )
        save_json(state)
        payload = {"ok": False, "reason": "reminders_permission_required"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "check_reminders_permission"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    apple_reminders_transition(run_state, "discovering")
    save_source_run_state("apple-reminders", run_state)
    source_run_id = apple_reminders_source_run_id(run_state)
    receipt = apple_reminders_eventkit_request("smoke-read", source_run_id, timeout=30)
    if receipt.get("state") != "succeeded":
        reason = apple_reminders_receipt_failure(receipt, "reminders_fetch_failed")
        apple_reminders_transition(run_state, "cancelled" if receipt.get("state") == "cancelled" else "failed")
        run_state.update({
            "smokeStatus": "cancelled" if receipt.get("state") == "cancelled" else "failed",
            "smokeFailureReason": reason,
            "authorizationStatus": receipt.get("authorizationStatus"),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(state, "attention", "smoke", "smoke_list_reminders", attention_reason=reason, run_state_path=run_path)
        save_json(state)
        payload = {
            "ok": False,
            "reason": reason,
            "authorizationStatus": receipt.get("authorizationStatus"),
            "retryable": bool(receipt.get("retryable")),
        }
        payload.update(source_next_prompt_payload(state, "apple-reminders", "smoke_list_reminders"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    result = receipt.get("result") if isinstance(receipt.get("result"), dict) else {}
    reminder_lists = [
        {
            "id": str(item.get("id")),
            "title": str(item.get("title")),
            "openReminderCount": int(item.get("openReminderCount") or 0),
        }
        for item in (result.get("lists") or [])
        if isinstance(item, dict) and item.get("id") and item.get("title")
    ][:20]
    list_titles = result.get("listTitles") if isinstance(result.get("listTitles"), list) else []
    fields = result.get("supportedFields") if isinstance(result.get("supportedFields"), list) else []
    list_count = int(result.get("listCount") or 0)
    open_count = int(result.get("openReminderCount") or 0)
    apple_reminders_transition(run_state, "scopeProposed")
    run_state.update({
        "smokeStatus": "passed",
        "listCount": list_count,
        "openReminderCount": open_count,
        "reminderLists": reminder_lists,
        "listTitles": list_titles[:20],
        "observedReminderFields": fields,
        "observedFields": fields,
        "smokeExecutionOwner": receipt.get("executionOwner"),
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-reminders", run_state)
    state = set_apple_reminders_row_state(
        state,
        "running",
        "ingest",
        "choose_ingest_scope",
        run_state_path=run_path,
        result_summary="Apple Reminders read-only smoke passed.",
    )
    save_json(state)
    payload = {
        "ok": True,
        "listCount": list_count,
        "openReminderCount": open_count,
        "lists": reminder_lists,
        "listTitles": list_titles[:20],
        "executionOwner": receipt.get("executionOwner"),
    }
    payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_reminders_choose_scope():
    scope = single_flag_value("--scope")
    if scope not in {"all-open", "one-list", "today", "week", "custom", "skip"}:
        print("--scope must be all-open, one-list, today, week, custom, or skip", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("apple-reminders")
    if scope == "skip":
        if run_state.get("workflowStatus") != "scopeProposed":
            apple_reminders_transition(run_state, "scopeProposed")
        apple_reminders_transition(run_state, "completionPending")
        run_state.update({
            "scope": "skip", "ingestStatus": "skipped", "readbackStatus": "skipped",
            "phase": "complete", "step": "complete", "updatedAt": now(),
        })
        state = mark_source_completion_pending(
            state,
            "apple-reminders",
            "skipped",
            "Apple Reminders skipped for this Source Onboarding session.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "skipped": True}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    run_state = load_source_run_state("apple-reminders")
    if run_state.get("smokeStatus") != "passed":
        state = set_apple_reminders_row_state(
            state, "attention", "smoke", "smoke_list_reminders",
            attention_reason="reminders_smoke_required",
        )
        save_json(state)
        payload = {"ok": False, "reason": "reminders_smoke_required"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "smoke_list_reminders"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    update = {"scope": scope}
    available_lists = run_state.get("reminderLists") if isinstance(run_state.get("reminderLists"), list) else []
    available_by_id = {
        str(item.get("id")): item
        for item in available_lists
        if isinstance(item, dict) and item.get("id") and item.get("title")
    }
    if scope == "one-list":
        list_id = single_flag_value("--list-id")
        if not list_id:
            print("--list-id is required when --scope one-list", file=sys.stderr)
            return 2
        if list_id not in available_by_id:
            print("--list-id must identify a list returned by smoke-list", file=sys.stderr)
            return 2
        list_name = str(available_by_id[list_id].get("title"))
        update["listID"] = list_id
        update["list"] = list_name
        update["includeCompleted"] = False
        update["status"] = "open"
    if scope == "custom":
        list_ids = parse_flag_value("--list-id")
        if parse_flag_value("--list") and not list_ids:
            print("--list-id is required for each custom list selection", file=sys.stderr)
            return 2
        invalid_list_ids = [item for item in list_ids if item not in available_by_id]
        if invalid_list_ids:
            print("--list-id must identify a list returned by smoke-list", file=sys.stderr)
            return 2
        lists = [str(available_by_id[item].get("title")) for item in list_ids]
        include_completed = apple_reminders_install_answer("--include-completed") == "yes"
        status = single_flag_value("--status") or ("all" if include_completed else "open")
        due_window = single_flag_value("--due-window") or "all"
        if due_window not in {"overdue", "today", "week", "all"}:
            print("--due-window must be overdue, today, week, or all", file=sys.stderr)
            return 2
        if status not in {"open", "completed", "all"}:
            print("--status must be open, completed, or all", file=sys.stderr)
            return 2
        update.update({
            "listIDs": list_ids,
            "lists": lists,
            "includeCompleted": include_completed,
            "status": status,
            "dueWindow": due_window,
        })
    cap_text = single_flag_value("--item-cap")
    if cap_text:
        try:
            cap_value = int(cap_text)
        except Exception:
            print("--item-cap must be an integer", file=sys.stderr)
            return 2
        if cap_value < 0:
            print("--item-cap must be non-negative", file=sys.stderr)
            return 2
        update["itemCap"] = cap_value
    elif "itemCap" in run_state:
        run_state.pop("itemCap", None)
    approved_list_ids = ([str(update.get("listID"))] if scope == "one-list" else [str(item) for item in update.get("listIDs", [])])
    approved_list_titles = ([str(update.get("list"))] if scope == "one-list" else [str(item) for item in update.get("lists", [])])
    selected_open_count = sum(
        int(available_by_id[item].get("openReminderCount") or 0)
        for item in approved_list_ids if item in available_by_id
    ) if approved_list_ids else None
    approved_scope = {
        "kind": scope,
        "listIDs": approved_list_ids,
        "listTitles": approved_list_titles,
        "status": str(update.get("status") or "open"),
        "dueWindow": str(update.get("dueWindow") or ("today" if scope == "today" else "week" if scope == "week" else "all")),
        "observedOpenReminderCount": selected_open_count,
    }
    if isinstance(update.get("itemCap"), int):
        approved_scope["itemCap"] = update["itemCap"]
    run_state.update(update)
    expected_count = run_state.get("openReminderCount") if scope == "all-open" else selected_open_count
    fields = run_state.get("observedReminderFields") if isinstance(run_state.get("observedReminderFields"), list) else []
    apple_reminders_transition(run_state, "scopeProposed")
    run_state.update({
        "expectedCount": expected_count,
        "approvedScope": approved_scope,
        "ingestStatus": "pending",
        "readbackStatus": "pending",
        "observedReminderFields": fields,
        "planConfirmed": False,
        "plannedArtifactPath": str(apple_reminders_artifact_path(state)),
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-reminders", run_state)
    state = set_apple_reminders_row_state(
        state,
        "running",
        "ingest",
        "confirm_ingest_plan",
        run_state_path=run_path,
        result_summary="Apple Reminders ingest scope selected: " + scope,
    )
    save_json(state)
    payload = {"ok": True, "scope": scope, "expectedCount": expected_count, "fields": fields}
    payload.update(source_next_prompt_payload(state, "apple-reminders", "confirm_ingest_plan"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_reminders_confirm_plan():
    answer = single_flag_value("--answer").strip().lower()
    if answer not in {"yes", "y", "no", "n"}:
        print("--answer must be yes or no", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("apple-reminders")
    if answer in {"no", "n"}:
        apple_reminders_transition(run_state, "attention")
        run_state.update({"planConfirmed": False, "updatedAt": now()})
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "attention",
            "ingest",
            "choose_ingest_scope",
            attention_reason="ingest_plan_rejected",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_rejected"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if not run_state.get("scope") or run_state.get("scope") == "skip":
        state = set_apple_reminders_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
        save_json(state)
        payload = {"ok": False, "reason": "ingest_scope_required"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    apple_reminders_transition(run_state, "scopeApproved")
    run_state.update({"planConfirmed": True, "confirmedAt": now(), "updatedAt": now()})
    run_path = save_source_run_state("apple-reminders", run_state)
    state = set_apple_reminders_row_state(
        state,
        "running",
        "ingest",
        "ingest_reminders",
        run_state_path=run_path,
        result_summary="Apple Reminders ingest plan confirmed.",
    )
    save_json(state)
    payload = {"ok": True, "scope": run_state.get("scope"), "expectedCount": run_state.get("expectedCount")}
    payload.update(source_next_prompt_payload(state, "apple-reminders", "ingest_reminders"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_reminders_artifact_path(state=None):
    target = None
    if isinstance(state, dict):
        target = state.get("entryContext", {}).get("gbrainTargetPath")
    if target and Path(target).is_dir():
        directory = Path(target) / "sources"
    else:
        directory = state_path.parent / "source-ingest-artifacts"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / "apple-reminders-eventkit.md"

def apple_reminders_item_list_name(item, run_state):
    if not isinstance(item, dict):
        return str(run_state.get("list") or "unknown")
    for key in ("listTitle", "list", "listName", "calendar", "calendarTitle"):
        value = item.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    return str(run_state.get("list") or "unknown")

def apple_reminders_field_value(value):
    if value is None:
        return ""
    if isinstance(value, (str, int, float, bool)):
        return str(value)
    return json.dumps(value, ensure_ascii=False, sort_keys=True)

def apple_reminders_ingest():
    state = load_or_create_state()
    run_state = load_source_run_state("apple-reminders")
    if not run_state.get("scope") or run_state.get("scope") == "skip":
        state = set_apple_reminders_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
        save_json(state)
        payload = {"ok": False, "reason": "ingest_scope_required"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if not run_state.get("planConfirmed"):
        state = set_apple_reminders_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
        save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    source_run_id = apple_reminders_source_run_id(run_state)
    apple_reminders_transition(run_state, "fetching")
    run_state.update({"ingestStatus": "pending", "readbackStatus": "pending", "updatedAt": now()})
    save_source_run_state("apple-reminders", run_state)
    receipt = apple_reminders_eventkit_request(
        "scope-read",
        source_run_id,
        scope=run_state.get("approvedScope") if isinstance(run_state.get("approvedScope"), dict) else apple_reminders_eventkit_scope(run_state),
        timeout=60,
    )
    if receipt.get("state") != "succeeded":
        reason = apple_reminders_receipt_failure(receipt, "reminders_ingest_read_failed")
        terminal_status = "cancelled" if receipt.get("state") == "cancelled" else "failed"
        apple_reminders_transition(run_state, terminal_status)
        run_state.update({"ingestStatus": terminal_status, "readbackStatus": "pending", "ingestFailureReason": reason, "updatedAt": now()})
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(state, "attention", "ingest", "ingest_reminders", attention_reason=reason, run_state_path=run_path)
        save_json(state)
        payload = {
            "ok": False,
            "reason": reason,
            "retryable": bool(receipt.get("retryable")),
        }
        payload.update(source_next_prompt_payload(state, "apple-reminders", "ingest_reminders"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    result = receipt.get("result") if isinstance(receipt.get("result"), dict) else {}
    items = result.get("reminders") if isinstance(result.get("reminders"), list) else []
    diagnostics = {
        "requestedCalendarCount": int(receipt.get("requestedCalendarCount") or result.get("requestedCalendarCount") or 0),
        "resolvedCalendarCount": int(receipt.get("resolvedCalendarCount") or result.get("resolvedCalendarCount") or 0),
        "fetchedReminderCount": int(receipt.get("fetchedReminderCount") or result.get("fetchedReminderCount") or 0),
        "resultReminderCount": int(receipt.get("resultReminderCount") or result.get("resultReminderCount") or len(items)),
        "outcome": str(receipt.get("outcome") or result.get("outcome") or "succeeded"),
        "reason": receipt.get("reason") or result.get("reason"),
        "schemaProvenance": receipt.get("schemaProvenance") or "zebra-reminders-eventkit.v1",
        "buildProvenance": receipt.get("buildProvenance") or "unavailable",
    }
    approved_scope = run_state.get("approvedScope") if isinstance(run_state.get("approvedScope"), dict) else {}
    observed_open_count = approved_scope.get("observedOpenReminderCount")
    accept_empty = apple_reminders_install_answer("--accept-empty") == "yes"
    mismatch = isinstance(observed_open_count, int) and observed_open_count > 0 and len(items) == 0
    if mismatch and not accept_empty:
        reason = "scope_changed_or_result_mismatch"
        apple_reminders_transition(run_state, "reconciliationRequired")
        run_state.update({
            "ingestStatus": "mismatch",
            "readbackStatus": "pending", "attentionReason": reason,
            "ingestDiagnostics": {**diagnostics, "outcome": "attention", "reason": reason},
            "updatedAt": now(),
        })
        run_state.pop("artifactPath", None)
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(state, "attention", "ingest", "ingest_reminders", attention_reason=reason, run_state_path=run_path)
        save_json(state)
        payload = {"ok": False, "workflowStatus": "reconciliationRequired", "ingestStatus": "mismatch", "readbackStatus": "pending", **diagnostics}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "ingest_reminders"))
        payload["reason"] = reason
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if len(items) == 0:
        diagnostics["outcome"] = "confirmed-empty"
        diagnostics["reason"] = "explicit_empty_approval" if mismatch else "discovery_confirmed_empty"
    fields = reminder_field_names(items)
    apple_reminders_transition(run_state, "readyToCommit")
    artifact = apple_reminders_artifact_path(state)
    today = now()[:10]
    lines = [
        "# Apple Reminders Source Onboarding Ingest",
        "",
        "source: apple-reminders",
        "playbook: apple-reminders.eventkit.v1",
        "schema: zebra-reminders-eventkit.v1",
        "scope: " + str(run_state.get("scope")),
        "scope_summary: " + apple_reminders_scope_summary(run_state),
        "completed_included: " + str(bool(run_state.get("includeCompleted"))).lower(),
        "item_count: " + str(len(items)),
        "fields_returned: " + (", ".join(fields) if fields else "none"),
        "redaction_policy: approved scope only; raw EventKit dump not stored",
        "",
        "## Reminders",
    ]
    for index, item in enumerate(items, start=1):
        list_name = apple_reminders_item_list_name(item, run_state)
        title = str(item.get("title") or item.get("name") or ("Reminder " + str(index))) if isinstance(item, dict) else "Reminder " + str(index)
        lines.extend(["", "### " + title, ""])
        if isinstance(item, dict):
            for key in fields:
                if key in item:
                    lines.append("- " + str(key) + ": " + apple_reminders_field_value(item.get(key)))
        lines.append("")
        lines.append('[Source: Apple Reminders list "' + list_name + '", ' + today + ']')
    artifact.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    apple_reminders_transition(run_state, "artifactCommitted")
    run_state.update({
        "ingestStatus": "succeeded",
        "readbackStatus": "pending",
        "ingestDiagnostics": diagnostics,
        "artifactPath": str(artifact),
        "ingestedReminderCount": len(items),
        "observedReminderFields": fields,
        "ingestOperation": "eventkit.scope-read",
        "ingestExecutionOwner": receipt.get("executionOwner"),
        "ingestedAt": now(),
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-reminders", run_state)
    state = set_apple_reminders_row_state(
        state,
        "running",
        "verify",
        "verify_readback",
        run_state_path=run_path,
        result_summary="Apple Reminders ingest artifact written for " + str(len(items)) + " reminders.",
    )
    save_json(state)
    payload = {"ok": True, "artifactPath": str(artifact), "ingestedReminderCount": len(items), **diagnostics}
    payload.update(source_next_prompt_payload(state, "apple-reminders", "verify_readback"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_reminders_verify_readback():
    state = load_or_create_state()
    run_state = load_source_run_state("apple-reminders")
    if run_state.get("workflowStatus") != "artifactCommitted" or run_state.get("ingestStatus") != "succeeded":
        payload = {"ok": False, "reason": "reminders_completion_gate_blocked"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "ingest_reminders"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    artifact = Path(run_state.get("artifactPath") or "")
    try:
        text = artifact.read_text(encoding="utf-8")
    except Exception:
        text = ""
    required_lines = {
        "source: apple-reminders",
        "playbook: apple-reminders.eventkit.v1",
        "schema: zebra-reminders-eventkit.v1",
        "scope: " + str(run_state.get("scope")),
        "item_count: " + str(run_state.get("ingestedReminderCount") or 0),
    }
    artifact_lines = set(text.splitlines())
    if not required_lines.issubset(artifact_lines):
        apple_reminders_transition(run_state, "attention")
        run_state.update({"readbackStatus": "failed", "updatedAt": now()})
        run_path = save_source_run_state("apple-reminders", run_state)
        state = set_apple_reminders_row_state(
            state,
            "attention",
            "verify",
            "verify_readback",
            attention_reason="readback_failed",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "readback_failed"}
        payload.update(source_next_prompt_payload(state, "apple-reminders", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    apple_reminders_transition(run_state, "readbackPassed")
    run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()})
    state = mark_source_completion_pending(
        state,
        "apple-reminders",
        "checked",
        "Apple Reminders EventKit ingest readback verified for " + str(run_state.get("ingestedReminderCount") or 0) + " reminders.",
        run_state=run_state,
    )
    run_state = load_source_run_state("apple-reminders")
    apple_reminders_transition(run_state, "completionPending")
    run_state.update({"updatedAt": now()})
    save_source_run_state("apple-reminders", run_state)
    save_json(state)
    payload = {"ok": True, "artifactPath": str(artifact), "readbackStatus": "passed"}
    payload.update(source_next_prompt_payload(state, "apple-reminders", "complete"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_reminders_command():
    if not args:
        print("apple-reminders requires a subcommand", file=sys.stderr)
        return 2
    pending_code = reject_if_completion_report_pending("apple-reminders")
    if pending_code is not None:
        return pending_code
    subcommand = args[0]
    if subcommand == "check-access":
        return apple_reminders_check_access()
    if subcommand == "smoke-list":
        return apple_reminders_smoke_list()
    if subcommand == "choose-scope":
        return apple_reminders_choose_scope()
    if subcommand == "confirm-plan":
        return apple_reminders_confirm_plan()
    if subcommand == "ingest":
        return apple_reminders_ingest()
    if subcommand == "verify-readback":
        return apple_reminders_verify_readback()
    print("unknown apple-reminders subcommand: " + subcommand, file=sys.stderr)
    return 2

