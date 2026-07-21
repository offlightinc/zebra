from domain import deterministic_slug
from gbrain_ingest import submit_connector_ingestion
from state import ingest_projection
from playbooks import parse_playbook_markdown
from connectors.apple_reminders import (
    apple_reminders_brew_path,
    apple_reminders_command_result,
    apple_reminders_install_answer,
)
from common import *

def apple_notes_playbook():
    return parse_playbook_markdown(
        playbook_dir / "apple-notes.memo-cli.v1.md",
        apple_notes_playbook_fallback,
    )

def apple_notes_scope_summary(run_state):
    language = onboarding_language()
    scope = run_state.get("scope") or "not selected"
    if scope == "folder":
        folder = str(run_state.get("folder") or "not selected")
        if language == "ko":
            return "폴더: " + folder
        if language == "ja":
            return "フォルダ: " + folder
        return "folder: " + folder
    if scope == "search":
        query = str(run_state.get("query") or "not selected")
        if language == "ko":
            return "검색어: " + query
        if language == "ja":
            return "検索語: " + query
        return "search query: " + query
    if scope == "selected-notes":
        note_ids = run_state.get("selectedNoteIDs") if isinstance(run_state.get("selectedNoteIDs"), list) else []
        return "selected note ids: " + (", ".join(str(item) for item in note_ids) if note_ids else "none")
    if scope == "sample":
        if language == "ko":
            return "작은 샘플: 최대 3개 노트"
        if language == "ja":
            return "小さなサンプル: 最大3件のノート"
        return "small sample: up to 3 notes"
    if scope == "skip":
        if language == "ko":
            return "이번 Source Onboarding에서 Apple Notes 건너뛰기"
        if language == "ja":
            return "このSource OnboardingではApple Notesをスキップ"
        return "skip Apple Notes for this Source Onboarding session"
    return str(scope)

def apple_notes_ingest_plan_summary(run_state):
    count = run_state.get("estimatedNoteCount")
    count_text = str(count) if count is not None else "unknown"
    language = onboarding_language()
    if language == "ko":
        return textwrap.dedent(f'''
        선택된 Apple Notes ingest plan입니다.

        - 선택한 범위: `{apple_notes_scope_summary(run_state)}`
        - 예상 노트 수: `{count_text}`
        - 민감정보 안내: 승인된 범위에는 개인 메모, 회사 메모, 링크, 사람 이름, 계정 정보처럼 민감할 수 있는 note body가 저장될 수 있습니다.
        - Ingest 방식: `memo` CLI로 승인된 노트만 읽어 정규화한 뒤 공통 GBrain ingestion에 제출합니다.
        - 검증 계획: 같은 source scope에서 모든 예상 slug를 `gbrain get`으로 확인합니다.

        ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding apple-notes confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding apple-notes confirm-plan --answer no`를 실행하세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent(f'''
        選択されたApple Notes ingest planです。

        - 選択した範囲: `{apple_notes_scope_summary(run_state)}`
        - 推定ノート数: `{count_text}`
        - 機微情報の注意: 承認された範囲には個人メモ、仕事メモ、リンク、人名、アカウント情報など機微になり得るnote bodyが保存される可能性があります。
        - Ingest方式: `memo` CLIで承認済みノートだけを読み、正規化して共通GBrain ingestionへ渡します。
        - 検証計画: 同じsource scopeですべての期待slugを`gbrain get`で確認します。

        ingestを実行する前にユーザーから明示的な承認を得てください。承認されたら`zebra-source-onboarding apple-notes confirm-plan --answer yes`を実行し、承認されなければ`zebra-source-onboarding apple-notes confirm-plan --answer no`を実行してください。
        ''').strip()
    return textwrap.dedent(f'''
    Resolved Apple Notes ingest plan:

    - Selected scope: `{apple_notes_scope_summary(run_state)}`
    - Estimated note count: `{count_text}`
    - Sensitive data notice: approved scope may store note bodies containing personal notes, work notes, links, names, or account-like information.
    - Ingest mode: read only approved notes with the `memo` CLI, normalize them, and submit them to common GBrain ingestion.
    - Verification plan: use `gbrain get` for every expected slug in the same source scope.

    Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding apple-notes confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding apple-notes confirm-plan --answer no`.
    ''').strip()

def apple_notes_check_memo_cli_instruction(language):
    if language == "ko":
        return textwrap.dedent('''
        Apple Notes `check_memo_cli` 단계만 진행하세요.

        먼저 실행:

        ```bash
        zebra-source-onboarding apple-notes check-cli
        ```

        helper가 `memo`와 Homebrew를 모두 확인한 뒤 반환하는 단일 install-plan 질문만 그대로 물으세요. Homebrew가 있으면 memo만, 둘 다 없으면 Homebrew와 memo를 함께 설치하는 질문을 한 번만 합니다. 사용자 답변 뒤 helper stdout의 정확한 `--install-answer` 명령을 실행하고 별도 설치 동의를 만들지 마세요.

        이후에는 helper stdout의 `nextPrompt`에서만 계속 진행하세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent('''
        Apple Notes の `check_memo_cli` step だけを進めてください。

        まず実行:

        ```bash
        zebra-source-onboarding apple-notes check-cli
        ```

        helper が `memo` と Homebrew の両方を確認して返す単一の install-plan 質問だけをそのまま尋ねます。Homebrew があれば memo のみ、両方なければ Homebrew と memo を一緒にインストールする質問を一度だけ行います。回答後は helper stdout の正確な `--install-answer` コマンドを実行し、別の同意質問を作らないでください。

        以後は helper stdout の `nextPrompt` だけに従って続行してください。
        ''').strip()
    return textwrap.dedent('''
    Work only the Apple Notes `check_memo_cli` step.

    Run:

    ```bash
    zebra-source-onboarding apple-notes check-cli
    ```

    Ask only the single install-plan question returned after the helper checks both `memo` and Homebrew. If Homebrew exists it asks for `memo` only; if both are missing it asks once for Homebrew and `memo` together. After the answer, run the exact `--install-answer` command from helper stdout and do not create a separate install-consent question.

    Continue only from the returned `nextPrompt`.
    ''').strip()

def apple_notes_step_prompt(step_id, state, row):
    playbook = apple_notes_playbook()
    run_state = load_source_run_state("apple-notes")
    section = playbook.get("sections", {}).get(step_id, "")
    language = onboarding_language()
    if not section:
        section = "Follow the current Apple Notes playbook step and continue only through the zebra-source-onboarding helper CLI."
    if step_id == "check_memo_cli":
        section = apple_notes_check_memo_cli_instruction(language)
    if step_id == "choose_ingest_scope":
        if language == "ko":
            section = section + "\n\n" + textwrap.dedent('''
            사용자에게 아래 다섯 가지 선택지만 보여주세요:

            ```text
            Apple Notes 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 메모 범위를 정해야 합니다.

            어떤 범위로 가져올까요?

            1. 특정 폴더
            2. 검색어로 찾은 메모
            3. 특정 note 번호
            4. 작은 샘플
            5. 지금은 Apple Notes 건너뛰기
            ```

            1번은 `zebra-source-onboarding apple-notes choose-scope --scope folder --folder "<folder>"`를 실행하세요.
            2번은 `zebra-source-onboarding apple-notes choose-scope --scope search --query "<query>"`를 실행하세요.
            3번은 `zebra-source-onboarding apple-notes choose-scope --scope selected-notes --note-id <memo-list-number>`를 실행하세요. note id는 `memo notes` 목록의 `NNN.` 값을 그대로 사용합니다.
            4번은 `zebra-source-onboarding apple-notes choose-scope --scope sample`을 실행하세요.
            5번은 `zebra-source-onboarding apple-notes choose-scope --scope skip`을 실행하세요.
            ''').strip()
        else:
            section = section + "\n\n" + textwrap.dedent('''
            Present exactly these five choices to the user:

            1. A specific folder
            2. Notes matching a search query
            3. Specific note numbers
            4. A small sample
            5. Skip Apple Notes for now

            Commands:
            - Folder: `zebra-source-onboarding apple-notes choose-scope --scope folder --folder "<folder>"`
            - Search: `zebra-source-onboarding apple-notes choose-scope --scope search --query "<query>"`
            - Selected notes: `zebra-source-onboarding apple-notes choose-scope --scope selected-notes --note-id <memo-list-number>`
            - Sample: `zebra-source-onboarding apple-notes choose-scope --scope sample`
            - Skip: `zebra-source-onboarding apple-notes choose-scope --scope skip`

            Note IDs are the global `NNN.` values shown by `memo notes`, not a local row index.
            ''').strip()
    if step_id == "confirm_ingest_plan":
        section = section + "\n\n" + apple_notes_ingest_plan_summary(run_state)
    command_path = run_state.get("memoCommandPath") or "not verified"
    access = run_state.get("accessStatus") or "not verified"
    smoke = run_state.get("smokeListStatus") or "not run"
    receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
    ingest_status = "passed" if receipt.get("complete") is True else receipt.get("failure") or "not started"
    return textwrap.dedent(f'''
    Zebra Source Onboarding: Apple Notes is the active source.

    Playbook: {playbook.get("id", "apple-notes.memo-cli")} {playbook.get("version", "v1")}
    Current step: `{step_id}`
    memo command path: `{command_path}`
    Notes Automation/access status: `{access}`
    Smoke list status: `{smoke}`
    Current ingest scope: `{apple_notes_scope_summary(run_state)}`
    Current GBrain ingest status: `{ingest_status}`

    Boundary rules:
    - Work only this Apple Notes step. Do not start Notion, Obsidian, iMessage, Gmail, or another source unless the helper prints that source as the next active source.
    - Use the `memo` CLI. Do not read Apple Notes databases directly and do not implement custom AppleScript in this runner.
    - Smoke-read is read-only access verification. It is not completion and not ingest approval.
    - Actual ingest/write must stay within the user-approved Notes scope.
    - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
    - Do not store note bodies, large note lists, prompt bodies, or transcripts in Source Onboarding state.
    - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

    Playbook step instructions:

    {section}
    ''').strip()

def set_apple_notes_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
    timestamp = timestamp or now()
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("apple-notes") if isinstance(rows.get("apple-notes"), dict) else source_row_for("apple-notes", timestamp)
    playbook = apple_notes_playbook()
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
    rows["apple-notes"] = row
    progress["sourceRows"] = rows
    if "apple-notes" not in ensure_execution_order(progress):
        progress["executionOrder"].append("apple-notes")
    if row_status in {"checked", "skipped"}:
        if progress.get("activeSourceID") == "apple-notes":
            progress["activeSourceID"] = None
    else:
        progress["activeSourceID"] = "apple-notes"
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    return state

def should_update_apple_notes_runner(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    if progress.get("activeSourceID") == "apple-notes":
        return True
    if "apple-notes" not in ensure_execution_order(progress):
        return False
    row = rows.get("apple-notes")
    return isinstance(row, dict) and row.get("playbookID") == apple_notes_playbook()["id"]

def start_apple_notes_from_next(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("apple-notes") if isinstance(rows.get("apple-notes"), dict) else {}
    playbook = apple_notes_playbook()
    if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
        step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "apple-notes", step_id))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    run_state = load_source_run_state("apple-notes")
    run_state.update({
        "phase": "preflight",
        "step": playbook["initialStepID"],
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-notes", run_state)
    state = set_apple_notes_row_state(
        state,
        "running",
        "preflight",
        playbook["initialStepID"],
        run_state_path=run_path,
    )
    save_json(state)
    payload = summary(state)
    payload.update(source_next_prompt_payload(state, "apple-notes", playbook["initialStepID"]))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def homebrew_install_pty_prompt(source_id, run_id):
    language = onboarding_language()
    resume_command = f"zebra-source-onboarding {source_id} check-cli"
    install_command = (
        "zebra-interactive-terminal-runner start "
        f"--task source-onboarding-homebrew-install --source {source_id} --run-id {run_id}"
    )
    if language == "ko":
        return textwrap.dedent(f'''
        Homebrew 설치 동의가 확인됐습니다. 다음 Zebra 공통 runner 명령을 현재 Zebra terminal에서 실행하세요:

        `{install_command}`

        Zebra가 같은 pane에 별도 terminal을 열고 설치를 시작합니다. 비밀번호는 새 terminal에 직접 입력하세요. 성공하면 terminal이 자동으로 닫힙니다. 그 뒤 `{resume_command}`를 실행해 `brew`를 재검증하고 현재 source step부터 계속하세요. 비밀번호를 채팅, 명령 인자, 로그 또는 state에 기록하지 마세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent(f'''
        Homebrew のインストール同意を確認しました。現在の Zebra terminal で次の共通 runner command を実行してください。

        `{install_command}`

        Zebra は同じ pane に別 terminal を開きます。パスワードは新しい terminal に直接入力してください。成功すると terminal は自動的に閉じます。その後 `{resume_command}` を実行してください。パスワードを chat、arguments、logs、state に保存しないでください。
        ''').strip()
    return textwrap.dedent(f'''
    Homebrew install consent is confirmed. Run this shared Zebra runner command in the current Zebra terminal:

    `{install_command}`

    Zebra opens a separate terminal in the same pane. Enter the password directly there. On success the terminal closes automatically. Then run `{resume_command}` to recheck `brew` and resume the source step. Never put the password in chat, arguments, logs, or state.
    ''').strip()

def record_homebrew_pty_required(state, run_state, source_id, step):
    interactive_run_id = run_state.get("interactiveTerminalRunID") or str(uuid.uuid4())
    run_state.update({
        "homebrewInstallAsked": True,
        "homebrewInstallAnswer": "yes",
        "homebrewInstallResult": {"status": "pty_required"},
        "installCommandRun": False,
        "interactiveTerminalRunID": interactive_run_id,
        "updatedAt": now(),
    })
    run_path = save_source_run_state(source_id, run_state)
    if source_id == "apple-reminders":
        state = set_apple_reminders_row_state(
            state, "attention", "preflight", step,
            attention_reason="homebrew_install_pty_required",
            run_state_path=run_path,
        )
    else:
        state = set_apple_notes_row_state(
            state, "attention", "preflight", step,
            attention_reason="homebrew_install_pty_required",
            run_state_path=run_path,
        )
    save_json(state)
    print(json.dumps({
        "ok": False,
        "reason": "homebrew_install_pty_required",
        "nextPrompt": homebrew_install_pty_prompt(source_id, interactive_run_id),
    }, ensure_ascii=False, sort_keys=True))
    return 1

def apple_notes_run_state_with_command_path():
    run_state = load_source_run_state("apple-notes")
    command_path = required_cli_command_path("apple-notes", run_state)
    return run_state, command_path

def apple_notes_failure_reason(result, default_reason="memo_notes_read_failed"):
    stderr = str(result.get("stderr") or "").lower()
    stdout = str(result.get("stdout") or "").lower()
    combined = stderr + "\n" + stdout
    if any(token in combined for token in ("not authorized", "automation", "tcc", "operation not permitted", "permission")):
        return "notes_automation_denied"
    if result.get("returncode") == 127:
        return "memo_cli_missing"
    return default_reason

def run_memo(arguments, timeout=20, failure_reason="memo_notes_read_failed"):
    run_state, command_path = apple_notes_run_state_with_command_path()
    if not command_path:
        return run_state, {
            "ok": False,
            "reason": "memo_cli_missing",
            "stdout": "",
            "stderr": "",
            "returncode": 127,
        }
    try:
        result = subprocess.run(
            [command_path] + list(arguments),
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        payload = {
            "ok": result.returncode == 0,
            "reason": None if result.returncode == 0 else failure_reason,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode,
        }
        if not payload["ok"]:
            payload["reason"] = apple_notes_failure_reason(payload, failure_reason)
        return run_state, payload
    except subprocess.TimeoutExpired as error:
        return run_state, {
            "ok": False,
            "reason": failure_reason,
            "stdout": error.stdout or "",
            "stderr": error.stderr or "memo command timed out",
            "returncode": 124,
        }
    except Exception as error:
        return run_state, {
            "ok": False,
            "reason": failure_reason,
            "stdout": "",
            "stderr": str(error),
            "returncode": 1,
        }

def memo_note_ids_from_text(text):
    ids = []
    seen = set()
    for line in str(text or "").splitlines():
        match = re.match(r"^\s*(\d+)\.", line)
        if not match:
            continue
        note_id = match.group(1)
        if note_id not in seen:
            seen.add(note_id)
            ids.append(note_id)
    return ids

def memo_preview(text, limit=4000):
    value = str(text or "").strip()
    return value[:limit]



def apple_notes_install_consent_prompt(homebrew_required):
    language = onboarding_language()
    if homebrew_required:
        if language == "ko":
            question = "Apple Notes ingest에 필요한 Homebrew와 memo CLI를 지금 모두 설치할까요? (yes/no)"
        elif language == "ja":
            question = "Apple Notes ingest に必要な Homebrew と memo CLI を今すぐ両方インストールしますか？ (yes/no)"
        else:
            question = "Apple Notes ingest requires Homebrew and the memo CLI. Install Homebrew and the memo CLI now? (yes/no)"
    else:
        if language == "ko":
            question = "Apple Notes ingest에 필요한 memo CLI를 Homebrew로 지금 설치할까요? (yes/no)"
        elif language == "ja":
            question = "Apple Notes ingest に必要な memo CLI を Homebrew で今すぐインストールしますか？ (yes/no)"
        else:
            question = "Apple Notes ingest requires the memo CLI. Install only the memo CLI with Homebrew now? (yes/no)"
    command = "zebra-source-onboarding apple-notes check-cli --install-answer yes"
    decline = "zebra-source-onboarding apple-notes check-cli --install-answer no"
    return question + "\n\nIf yes, run `" + command + "`. If no, run `" + decline + "`."

def apple_notes_install_plan(homebrew_required, status="awaiting_consent", answer=None):
    plan = {
        "homebrewRequired": bool(homebrew_required),
        "memoRequired": True,
        "status": status,
        "resumeSource": "apple-notes",
        "resumeStep": "check_memo_cli",
        "updatedAt": now(),
    }
    if answer:
        plan["answer"] = answer
    return plan

def apple_notes_record_install_attention(state, run_state, reason, plan):
    run_state.update({
        "cliStatus": "missing",
        "phase": "preflight",
        "step": "check_memo_cli",
        "installPlan": plan,
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-notes", run_state)
    state = set_apple_notes_row_state(
        state, "attention", "preflight", "check_memo_cli",
        attention_reason=reason,
        run_state_path=run_path,
    )
    save_json(state)
    return run_path

def apple_notes_install_memo(brew_path, resumed_after_homebrew=False):
    brew_bin = str(Path(brew_path).resolve().parent)
    path_entries = [entry for entry in os.environ.get("PATH", "").split(os.pathsep) if entry]
    if brew_bin not in path_entries:
        os.environ["PATH"] = os.pathsep.join([brew_bin] + path_entries)
    print_progress(
        "Homebrew installation verified.",
        "Homebrew 설치를 확인했습니다.",
        "Homebrew のインストールを確認しました。",
    )
    state = load_or_create_state()
    run_state = load_source_run_state("apple-notes")
    plan = run_state.get("installPlan") if isinstance(run_state.get("installPlan"), dict) else apple_notes_install_plan(False)
    completed_stages = plan.get("completedStages") if isinstance(plan.get("completedStages"), list) else []
    plan.update({
        "answer": "yes",
        "status": "installing_memo",
        "homebrewPath": brew_path,
        "homebrewStatus": "succeeded" if resumed_after_homebrew else "already_installed",
        "updatedAt": now(),
    })
    run_state["installPlan"] = plan
    save_source_run_state("apple-notes", run_state)

    print_progress(
        "Installing memo...",
        "memo를 설치하는 중입니다...",
        "memo をインストールしています...",
    )

    if "memo_tap" not in completed_stages:
        tap_result = apple_reminders_command_result([brew_path, "tap", "antoniorodr/memo"], timeout=300)
        if not tap_result.get("ok"):
            plan.update({"status": "failed", "failedStage": "memo_tap", "result": tap_result, "updatedAt": now()})
            apple_notes_record_install_attention(state, run_state, "memo_install_failed", plan)
            print(json.dumps({"ok": False, "reason": "memo_install_failed", "failedStage": "memo_tap", "installPlan": plan}, ensure_ascii=False, sort_keys=True))
            return 1
        completed_stages.append("memo_tap")
        plan["completedStages"] = completed_stages
        plan.pop("failedStage", None)
        plan.pop("result", None)
        run_state["installPlan"] = plan
        save_source_run_state("apple-notes", run_state)

    install_result = apple_reminders_command_result([brew_path, "install", "antoniorodr/memo/memo"], timeout=1800)
    if not install_result.get("ok"):
        plan.update({"status": "failed", "failedStage": "memo_install", "result": install_result, "updatedAt": now()})
        apple_notes_record_install_attention(state, run_state, "memo_install_failed", plan)
        print(json.dumps({"ok": False, "reason": "memo_install_failed", "failedStage": "memo_install", "installPlan": plan}, ensure_ascii=False, sort_keys=True))
        return 1
    if "memo_install" not in completed_stages:
        completed_stages.append("memo_install")
    plan["completedStages"] = completed_stages

    print_progress(
        "Verifying memo installation...",
        "memo 설치를 확인하는 중입니다...",
        "memo のインストールを確認しています...",
    )
    memo_path = required_cli_command_path("apple-notes", run_state)
    if not memo_path:
        plan.update({"status": "failed", "failedStage": "memo_verify", "updatedAt": now()})
        apple_notes_record_install_attention(state, run_state, "memo_install_verify_failed", plan)
        print(json.dumps({"ok": False, "reason": "memo_install_verify_failed", "failedStage": "memo_verify", "installPlan": plan}, ensure_ascii=False, sort_keys=True))
        return 1
    version_result = apple_reminders_command_result([memo_path, "--version"], timeout=10)
    if not version_result.get("ok"):
        plan.update({"status": "failed", "failedStage": "memo_verify", "result": version_result, "updatedAt": now()})
        apple_notes_record_install_attention(state, run_state, "memo_install_verify_failed", plan)
        print(json.dumps({"ok": False, "reason": "memo_install_verify_failed", "failedStage": "memo_verify", "installPlan": plan}, ensure_ascii=False, sort_keys=True))
        return 1

    plan.update({
        "status": "succeeded",
        "memoPath": memo_path,
        "memoVersion": (version_result.get("stdout") or version_result.get("stderr") or "").strip(),
        "updatedAt": now(),
    })
    run_state["installPlan"] = plan
    save_source_run_state("apple-notes", run_state)
    result = check_required_cli("apple-notes")
    if result == 0:
        print_progress(
            "Homebrew and memo installation completed.",
            "Homebrew와 memo 설치가 완료되었습니다.",
            "Homebrew と memo のインストールが完了しました。",
        )
    return result

def apple_notes_check_cli():
    state = load_or_create_state()
    run_state = load_source_run_state("apple-notes")
    if not required_cli_command_path("apple-notes", run_state):
        brew_path = apple_reminders_brew_path()
        homebrew_required = not bool(brew_path)
        answer = apple_reminders_install_answer("--install-answer")
        if not answer:
            # Backward compatibility for a prompt already emitted by Zebra.
            answer = apple_reminders_install_answer("--homebrew-install-answer")
        existing_plan = run_state.get("installPlan") if isinstance(run_state.get("installPlan"), dict) else None
        if not answer and existing_plan and existing_plan.get("answer") == "yes":
            if homebrew_required:
                apple_notes_record_install_attention(state, run_state, "homebrew_install_pty_required", existing_plan)
                return record_homebrew_pty_required(state, run_state, "apple-notes", "check_memo_cli")
            return apple_notes_install_memo(brew_path, resumed_after_homebrew=bool(existing_plan.get("homebrewRequired")))
        if answer == "yes":
            plan = apple_notes_install_plan(homebrew_required, status="approved", answer="yes")
            apple_notes_record_install_attention(state, run_state, "homebrew_install_pty_required" if homebrew_required else "memo_install_approved", plan)
            if homebrew_required:
                return record_homebrew_pty_required(state, run_state, "apple-notes", "check_memo_cli")
            return apple_notes_install_memo(brew_path)
        if answer == "no":
            plan = apple_notes_install_plan(homebrew_required, status="declined", answer="no")
            apple_notes_record_install_attention(state, run_state, "apple_notes_install_declined", plan)
            print(json.dumps({"ok": False, "reason": "apple_notes_install_declined", "installPlan": plan}, ensure_ascii=False, sort_keys=True))
            return 1
        plan = apple_notes_install_plan(homebrew_required)
        apple_notes_record_install_attention(state, run_state, "apple_notes_install_consent_required", plan)
        print(json.dumps({
            "ok": False,
            "reason": "apple_notes_install_consent_required",
            "installPlan": plan,
            "nextPrompt": apple_notes_install_consent_prompt(homebrew_required),
        }, ensure_ascii=False, sort_keys=True))
        return 1
    return check_required_cli("apple-notes")

def apple_notes_check_access():
    state = load_or_create_state()
    run_state, result = run_memo(["notes", "-fl"], timeout=20, failure_reason="notes_automation_denied")
    if not result.get("ok"):
        reason = result.get("reason") or "notes_automation_denied"
        run_state.update({
            "accessStatus": "failed",
            "accessFailureReason": reason,
            "accessFailureStderr": (result.get("stderr") or "")[:500],
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "attention",
            "preflight",
            "check_notes_automation",
            attention_reason=reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": reason}
        payload.update(source_next_prompt_payload(state, "apple-notes", "check_notes_automation"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({
        "accessStatus": "passed",
        "folderListPreview": memo_preview(result.get("stdout")),
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-notes", run_state)
    state = set_apple_notes_row_state(
        state,
        "running",
        "smoke",
        "smoke_list_notes",
        run_state_path=run_path,
        result_summary="Apple Notes folder/list command succeeded through memo.",
    )
    save_json(state)
    payload = {"ok": True, "folderListPreview": memo_preview(result.get("stdout"), limit=500)}
    payload.update(source_next_prompt_payload(state, "apple-notes", "smoke_list_notes"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_notes_smoke_list():
    state = load_or_create_state()
    run_state, result = run_memo(["notes", "-fl"], timeout=20, failure_reason="memo_notes_list_failed")
    if not result.get("ok") or not str(result.get("stdout") or "").strip():
        run_state, retry = run_memo(["notes", "-nc", "-fl"], timeout=25, failure_reason="memo_notes_list_failed")
        if retry.get("ok") and str(retry.get("stdout") or "").strip():
            result = retry
    if not result.get("ok") or not str(result.get("stdout") or "").strip():
        reason = result.get("reason") or "memo_notes_list_failed"
        run_state.update({
            "smokeListStatus": "failed",
            "smokeFailureReason": reason,
            "smokeFailureStderr": (result.get("stderr") or "")[:500],
            "updatedAt": now(),
        })
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "attention",
            "smoke",
            "smoke_list_notes",
            attention_reason=reason,
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": reason}
        payload.update(source_next_prompt_payload(state, "apple-notes", "smoke_list_notes"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    note_ids = memo_note_ids_from_text(result.get("stdout"))
    run_state.update({
        "smokeListStatus": "passed",
        "folderListPreview": memo_preview(result.get("stdout")),
        "smokeNoteIDs": note_ids[:20],
        "estimatedNoteCount": len(note_ids) if note_ids else None,
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-notes", run_state)
    state = set_apple_notes_row_state(
        state,
        "running",
        "ingest",
        "choose_ingest_scope",
        run_state_path=run_path,
        result_summary="Apple Notes read-only smoke list passed.",
    )
    save_json(state)
    payload = {"ok": True, "estimatedNoteCount": len(note_ids) if note_ids else None}
    payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_notes_estimate_scope(run_state):
    scope = run_state.get("scope")
    if scope == "selected-notes":
        return list(run_state.get("selectedNoteIDs") or [])
    if scope == "sample":
        ids = run_state.get("smokeNoteIDs") if isinstance(run_state.get("smokeNoteIDs"), list) else []
        if ids:
            return [str(item) for item in ids[:3]]
        _, result = run_memo(["notes"], timeout=20, failure_reason="memo_notes_list_failed")
        return memo_note_ids_from_text(result.get("stdout"))[:3] if result.get("ok") else []
    if scope == "folder":
        folder = str(run_state.get("folder") or "")
        _, result = run_memo(["notes", "-f", folder], timeout=25, failure_reason="memo_notes_list_failed")
        return memo_note_ids_from_text(result.get("stdout")) if result.get("ok") else []
    if scope == "search":
        query = str(run_state.get("query") or "")
        _, result = run_memo(["notes", "-s", query], timeout=25, failure_reason="memo_notes_list_failed")
        return memo_note_ids_from_text(result.get("stdout")) if result.get("ok") else []
    return []

def apple_notes_choose_scope():
    scope = single_flag_value("--scope")
    state = load_or_create_state()
    run_state = load_source_run_state("apple-notes")
    if scope == "skip":
        run_state.update({"scope": "skip", "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "apple-notes",
            "skipped",
            "Apple Notes skipped for this Source Onboarding session.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "skipped": True}
        payload.update(source_next_prompt_payload(state, "apple-notes", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    if scope == "folder":
        folder = single_flag_value("--folder")
        if not folder:
            print("--folder is required when --scope folder", file=sys.stderr)
            return 2
        run_state.update({"scope": scope, "folder": folder})
    elif scope == "search":
        query = single_flag_value("--query")
        if not query:
            print("--query is required when --scope search", file=sys.stderr)
            return 2
        run_state.update({"scope": scope, "query": query})
    elif scope == "selected-notes":
        note_ids = parse_flag_value("--note-id")
        if not note_ids:
            print("--note-id is required when --scope selected-notes", file=sys.stderr)
            return 2
        run_state.update({"scope": scope, "selectedNoteIDs": [str(item) for item in note_ids]})
    elif scope == "sample":
        run_state.update({"scope": scope})
    else:
        print("--scope must be folder, search, selected-notes, sample, or skip", file=sys.stderr)
        return 2
    note_ids = apple_notes_estimate_scope(run_state)
    run_state.update({
        "resolvedNoteIDs": note_ids,
        "estimatedNoteCount": len(note_ids),
        "planConfirmed": False,
        "updatedAt": now(),
    })
    run_path = save_source_run_state("apple-notes", run_state)
    state = set_apple_notes_row_state(
        state,
        "running",
        "ingest",
        "confirm_ingest_plan",
        run_state_path=run_path,
        result_summary="Apple Notes ingest scope selected: " + scope,
    )
    save_json(state)
    payload = {"ok": True, "scope": scope, "estimatedNoteCount": len(note_ids)}
    payload.update(source_next_prompt_payload(state, "apple-notes", "confirm_ingest_plan"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_notes_confirm_plan():
    answer = single_flag_value("--answer").strip().lower()
    if answer not in {"yes", "y", "no", "n"}:
        print("--answer must be yes or no", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("apple-notes")
    if answer in {"no", "n"}:
        run_state.update({"planConfirmed": False, "updatedAt": now()})
        run_path = save_source_run_state("apple-notes", run_state)
        state = set_apple_notes_row_state(
            state,
            "attention",
            "ingest",
            "choose_ingest_scope",
            attention_reason="ingest_plan_rejected",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_rejected"}
        payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if not run_state.get("scope") or run_state.get("scope") == "skip":
        state = set_apple_notes_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
        save_json(state)
        payload = {"ok": False, "reason": "ingest_scope_required"}
        payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({"planConfirmed": True, "confirmedAt": now(), "updatedAt": now()})
    run_path = save_source_run_state("apple-notes", run_state)
    state = set_apple_notes_row_state(
        state,
        "running",
        "ingest",
        "ingest_notes",
        run_state_path=run_path,
        result_summary="Apple Notes ingest plan confirmed.",
    )
    save_json(state)
    payload = {"ok": True, "scope": run_state.get("scope"), "estimatedNoteCount": run_state.get("estimatedNoteCount")}
    payload.update(source_next_prompt_payload(state, "apple-notes", "ingest_notes"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def apple_notes_read_note(note_id):
    _, result = run_memo(["notes", "-v", str(note_id)], timeout=25, failure_reason="memo_note_read_failed")
    if not result.get("ok"):
        _, retry = run_memo(["notes", "-nc", "-v", str(note_id)], timeout=30, failure_reason="memo_note_read_failed")
        if retry.get("ok"):
            result = retry
    return result

def apple_notes_ingest():
    state = load_or_create_state(); run_state = load_source_run_state("apple-notes")
    if not run_state.get("scope") or run_state.get("scope") == "skip":
        state = set_apple_notes_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required"); save_json(state)
        payload = {"ok": False, "reason": "ingest_scope_required"}; payload.update(source_next_prompt_payload(state, "apple-notes", "choose_ingest_scope")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    if not run_state.get("planConfirmed"):
        state = set_apple_notes_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed"); save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}; payload.update(source_next_prompt_payload(state, "apple-notes", "confirm_ingest_plan")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    note_ids = run_state.get("resolvedNoteIDs") if isinstance(run_state.get("resolvedNoteIDs"), list) else apple_notes_estimate_scope(run_state)
    if not note_ids:
        reason = "no_notes_in_approved_scope"; state = set_apple_notes_row_state(state, "attention", "ingest", "ingest_notes", attention_reason=reason); save_json(state)
        payload = {"ok": False, "reason": reason}; payload.update(source_next_prompt_payload(state, "apple-notes", "ingest_notes")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    records, failures = [], []
    for note_id in note_ids:
        result = apple_notes_read_note(note_id)
        if not result.get("ok"):
            failures.append({"logicalRecordID": str(note_id), "reason": result.get("reason") or "memo_note_read_failed"}); continue
        records.append({"connectorID": "apple-notes", "logicalRecordID": str(note_id), "slug": deterministic_slug("apple-notes", str(note_id)), "markdown": str(result.get("stdout") or ""), "originURI": "apple-notes://" + str(note_id)})
    acquisition = {"discoveredCount": len(note_ids), "selectedCount": len(note_ids), "normalizedCount": len(records), "failedCount": len(failures), "diagnosticCount": 0, "cancelled": False, "complete": not failures and len(records) == len(note_ids)}
    attempt_id = str(uuid.uuid4()); receipt = submit_connector_ingestion("apple-notes", records, acquisition, state, attempt_id, gbrain_state_path)
    run_state.update({"ingestAttemptID": attempt_id, "acquisitionReceipt": acquisition, "ingestReceipt": receipt, "ingestedNoteCount": len(records), "acquisitionDiagnostics": failures[:8], "updatedAt": now()})
    run_path = save_source_run_state("apple-notes", run_state); projection = ingest_projection(receipt)
    state = set_apple_notes_row_state(state, "running" if projection["complete"] else "attention", "verify", "verify_readback", attention_reason=projection["attentionReason"], run_state_path=run_path, result_summary="GBrain ingest attempted for " + str(len(records)) + " Apple Notes."); save_json(state)
    payload = {"ok": projection["complete"], "reason": projection["attentionReason"], "ingestedNoteCount": len(records)}; payload.update(source_next_prompt_payload(state, "apple-notes", "verify_readback")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 0 if projection["complete"] else 1


def apple_notes_verify_readback():
    state = load_or_create_state(); run_state = load_source_run_state("apple-notes"); receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}; projection = ingest_projection(receipt)
    if not projection["complete"]:
        state = set_apple_notes_row_state(state, "attention", "verify", "verify_readback", attention_reason=projection["attentionReason"] or "readbackMissing", run_state_path=save_source_run_state("apple-notes", run_state)); save_json(state)
        payload = {"ok": False, "reason": projection["attentionReason"] or "readbackMissing"}; payload.update(source_next_prompt_payload(state, "apple-notes", "verify_readback")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 1
    run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()}); state = mark_source_completion_pending(state, "apple-notes", "checked", "GBrain ingest/readback verified for " + str(receipt.get("verifiedRecordCount") or 0) + " Apple Notes.", run_state=run_state); save_json(state)
    payload = {"ok": True, "readbackStatus": "passed", "verifiedRecordCount": receipt.get("verifiedRecordCount")}; payload.update(source_next_prompt_payload(state, "apple-notes", "complete")); print(json.dumps(payload, ensure_ascii=False, sort_keys=True)); return 0


def apple_notes_command():
    if not args:
        print("apple-notes requires a subcommand", file=sys.stderr)
        return 2
    pending_code = reject_if_completion_report_pending("apple-notes")
    if pending_code is not None:
        return pending_code
    subcommand = args[0]
    if subcommand == "check-cli":
        return apple_notes_check_cli()
    if subcommand == "check-access":
        return apple_notes_check_access()
    if subcommand == "smoke-list":
        return apple_notes_smoke_list()
    if subcommand == "choose-scope":
        return apple_notes_choose_scope()
    if subcommand == "confirm-plan":
        return apple_notes_confirm_plan()
    if subcommand == "ingest":
        return apple_notes_ingest()
    if subcommand == "verify-readback":
        return apple_notes_verify_readback()
    print("unknown apple-notes subcommand: " + subcommand, file=sys.stderr)
    return 2
