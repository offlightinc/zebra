from common import *

def notion_playbook():
    return parse_playbook_markdown(
        playbook_dir / "notion.ntn-cli.v1.md",
        notion_playbook_fallback,
    )

def notion_scope_prompt_text():
    language = onboarding_language()
    if language == "ko":
        return textwrap.dedent('''
        Notion에서 GBrain에 가져올 대상을 정해주세요.

        1. Page URL/ID 기준으로 현재 page만 가져오기
        2. Page URL/ID 기준으로 현재 page와 하위 page까지 가져오기
        3. Data source/database URL/ID 기준으로 pages/rows 전체 가져오기
        4. URL/ID를 모르면 Notion workspace 후보 찾기
        5. Notion workspace 전체 가져오기
        6. Notion 건너뛰기
        ''').strip()
    if language == "ja":
        return textwrap.dedent('''
        Notion から GBrain に取り込む対象を選んでください。

        1. Page URL/ID で現在の page だけを取り込む
        2. Page URL/ID で現在の page と下位 page を取り込む
        3. Data source/database URL/ID で pages/rows 全体を取り込む
        4. URL/ID が分からない場合は Notion workspace の候補を探す
        5. Notion workspace 全体を取り込む
        6. Notion をスキップする
        ''').strip()
    return textwrap.dedent('''
    Choose what Zebra should import from Notion into GBrain.

    1. Import only the current page by Page URL/ID
    2. Import the current page and child pages by Page URL/ID
    3. Import all pages/rows from a data source/database URL/ID
    4. Find candidates with Notion workspace search if you do not know the URL/ID
    5. Import the whole Notion workspace
    6. Skip Notion
    ''').strip()

def notion_workspace_confirmation_text(run_state):
    language = onboarding_language()
    candidate_count = run_state.get("workspaceCandidateCount")
    candidate_text = str(candidate_count) if candidate_count is not None else "unknown"
    if language == "ko":
        return textwrap.dedent(f'''
        Notion workspace 전체 ingest는 범위가 클 수 있으므로 아직 ingest를 시작하지 않습니다.

        확인된 후보 수: `{candidate_text}`

        진행 전 안내:
        - 예상 시간: workspace 크기와 Notion API 응답 속도에 따라 오래 걸릴 수 있습니다.
        - 토큰/임베딩 비용 가능성: GBrain markdown artifact를 import/embedding할 때 비용이 발생할 수 있습니다.
        - 권한 누락 가능성: `ntn`이 접근할 수 없는 private page/data source는 일부 누락될 수 있습니다.
        - 민감 정보 가능성: private/sensitive page, people directory, attachment metadata가 포함될 수 있습니다.

        전체 workspace ingest를 계속하려면 `zebra-source-onboarding notion confirm-workspace --answer yes`를 실행하세요.
        취소하려면 `zebra-source-onboarding notion confirm-workspace --answer no`를 실행하세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent(f'''
        Notion workspace 全体の ingest は範囲が広くなる可能性があるため、まだ ingest は開始しません。

        確認済み候補数: `{candidate_text}`

        続行前の確認:
        - 想定時間: workspace の規模と Notion API の応答速度によって長くかかる場合があります。
        - トークン/embedding コストの可能性: GBrain markdown artifact を import/embedding するときにコストが発生する場合があります。
        - 権限不足の可能性: `ntn` がアクセスできない private page/data source は一部欠落する場合があります。
        - 機密情報の可能性: private/sensitive page, people directory, attachment metadata が含まれる場合があります。

        workspace 全体の ingest を続ける場合は `zebra-source-onboarding notion confirm-workspace --answer yes` を実行してください。
        キャンセルする場合は `zebra-source-onboarding notion confirm-workspace --answer no` を実行してください。
        ''').strip()
    return textwrap.dedent(f'''
    Whole-workspace Notion ingest can be broad, so Zebra has not started ingest yet.

    Confirmed candidate count: `{candidate_text}`

    Before continuing:
    - Expected duration: this can take a long time depending on workspace size and Notion API response speed.
    - Token/embedding cost possibility: importing/embedding the GBrain markdown artifact may incur cost.
    - Permission gaps: private pages/data sources that `ntn` cannot access may be omitted.
    - Sensitive information possibility: private/sensitive pages, people directory data, and attachment metadata may be included.

    To continue whole-workspace ingest, run `zebra-source-onboarding notion confirm-workspace --answer yes`.
    To cancel, run `zebra-source-onboarding notion confirm-workspace --answer no`.
    ''').strip()

def notion_choose_scope_instruction(run_state):
    language = onboarding_language()
    candidates = run_state.get("searchCandidates") if isinstance(run_state.get("searchCandidates"), list) else []
    candidate_text = ""
    if candidates:
        lines = []
        for index, item in enumerate(candidates, start=1):
            if not isinstance(item, dict):
                continue
            title = item.get("title") or "Untitled"
            kind = item.get("object") or item.get("kind") or "unknown"
            item_id = item.get("id") or "unknown"
            lines.append(f"{index}. {kind}: {title} ({item_id})")
        if lines:
            heading = "Notion workspace candidates:" if language == "en" else "Notion workspace 候補:" if language == "ja" else "Notion workspace 후보:"
            candidate_text = "\n\n" + heading + "\n" + "\n".join(lines)
    if language == "ko":
        return notion_scope_prompt_text() + candidate_text + "\n\n" + textwrap.dedent('''

        실행 명령:
        - 1번: `zebra-source-onboarding notion choose-scope --scope page --target "<page-url-or-id>"`
        - 2번: `zebra-source-onboarding notion choose-scope --scope page-subtree --target "<page-url-or-id>"`
        - 3번: `zebra-source-onboarding notion choose-scope --scope data-source --target "<data-source-or-database-url-or-id>"`
        - 4번: `zebra-source-onboarding notion choose-scope --scope workspace-search`
        - 5번: `zebra-source-onboarding notion choose-scope --scope workspace-all`
        - 6번: `zebra-source-onboarding notion choose-scope --scope skip`

        `workspace-search`는 웹 검색이 아니라 인증된 Notion workspace 내부 `ntn api v1/search page_size:=10` 후보 조회입니다.
        Smoke read는 target이 정해지면 helper가 자동 실행하므로 별도로 사용자에게 묻지 마세요.
        ''').strip()
    if language == "ja":
        return notion_scope_prompt_text() + candidate_text + "\n\n" + textwrap.dedent('''

        実行コマンド:
        - 1番: `zebra-source-onboarding notion choose-scope --scope page --target "<page-url-or-id>"`
        - 2番: `zebra-source-onboarding notion choose-scope --scope page-subtree --target "<page-url-or-id>"`
        - 3番: `zebra-source-onboarding notion choose-scope --scope data-source --target "<data-source-or-database-url-or-id>"`
        - 4番: `zebra-source-onboarding notion choose-scope --scope workspace-search`
        - 5番: `zebra-source-onboarding notion choose-scope --scope workspace-all`
        - 6番: `zebra-source-onboarding notion choose-scope --scope skip`

        `workspace-search` は web search ではなく、認証済み Notion workspace 内で `ntn api v1/search page_size:=10` を使って候補を取得します。
        Smoke read は target が決まると helper が自動実行するため、別途ユーザーに確認しないでください。
        ''').strip()
    return notion_scope_prompt_text() + candidate_text + "\n\n" + textwrap.dedent('''

    Commands:
    - Option 1: `zebra-source-onboarding notion choose-scope --scope page --target "<page-url-or-id>"`
    - Option 2: `zebra-source-onboarding notion choose-scope --scope page-subtree --target "<page-url-or-id>"`
    - Option 3: `zebra-source-onboarding notion choose-scope --scope data-source --target "<data-source-or-database-url-or-id>"`
    - Option 4: `zebra-source-onboarding notion choose-scope --scope workspace-search`
    - Option 5: `zebra-source-onboarding notion choose-scope --scope workspace-all`
    - Option 6: `zebra-source-onboarding notion choose-scope --scope skip`

    `workspace-search` is not web search. It searches the authenticated Notion workspace with `ntn api v1/search page_size:=10`.
    Do not ask the user for separate smoke-read approval; the helper runs smoke read automatically after a target is selected.
    ''').strip()

def notion_step_instruction(step_id, run_state):
    language = onboarding_language()
    if step_id == "check_ntn_cli":
        return textwrap.dedent('''
        Work only the Notion `check_ntn_cli` step.

        Run:

        ```bash
        zebra-source-onboarding notion check-cli
        ```

        If `ntn` is missing, report the helper's compact attention reason `ntn_cli_missing` and tell the user the expected install path is the official `ntn` CLI. The default install command is:

        ```bash
        curl -fsSL https://ntn.dev | bash
        ```

        If that install path fails and `npm` is available, use this fallback:

        ```bash
        npm install --global ntn
        ```

        After installation, run `ntn --version` and authenticate with `ntn login`. Do not install anything unless the user explicitly asks.

        Continue only from the returned `nextPrompt`.
        ''').strip()
    if step_id == "choose_scope":
        return notion_choose_scope_instruction(run_state)
    if step_id == "confirm_workspace_ingest":
        return notion_workspace_confirmation_text(run_state)
    if step_id == "ingest_notion":
        if language == "ko":
            return "이제 `zebra-source-onboarding notion ingest`를 실행하세요. whole-workspace ingest가 아니거나 `workspaceConfirmed`가 true이면 smoke-read나 batch 확인을 다시 묻지 마세요."
        if language == "ja":
            return "`zebra-source-onboarding notion ingest` を実行してください。whole-workspace ingest でない場合、または `workspaceConfirmed` が true の場合は、smoke-read や batch 確認を再度ユーザーに求めないでください。"
        return "Run `zebra-source-onboarding notion ingest`. Do not ask for another smoke-read or batch confirmation unless this is whole-workspace ingest and `workspaceConfirmed` is not true."
    if step_id == "verify_readback":
        if language == "ko":
            return "`zebra-source-onboarding notion verify-readback`을 실행하고, 그 stdout에서 나온 다음 단계만 따르세요."
        if language == "ja":
            return "`zebra-source-onboarding notion verify-readback` を実行し、その stdout に出た次の手順だけに従ってください。"
        return "Run `zebra-source-onboarding notion verify-readback` and continue only from its stdout."
    if language == "ko":
        return "현재 Notion playbook step을 따르고 `zebra-source-onboarding` helper CLI를 통해서만 계속 진행하세요."
    if language == "ja":
        return "現在の Notion playbook step に従い、`zebra-source-onboarding` helper CLI だけで続行してください。"
    return "Follow the current Notion playbook step and continue only through the zebra-source-onboarding helper CLI."

def notion_step_prompt(step_id, state, row):
    playbook = notion_playbook()
    run_state = load_source_run_state("notion")
    language = onboarding_language()
    section = notion_step_instruction(step_id, run_state)
    target = run_state.get("target") or "not selected"
    scope = run_state.get("scope") or "not selected"
    artifact = run_state.get("artifactPath") or "not created"
    if language == "ko":
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Notion이 활성 source입니다.

        Playbook: {playbook.get("id", "notion.ntn-cli")} {playbook.get("version", "v1")}
        현재 단계: `{step_id}`
        현재 Notion 범위: `{scope}`
        현재 Notion target: `{target}`
        현재 ingest artifact: `{artifact}`

        경계 규칙:
        - 이 Notion 단계만 진행하세요. helper가 다른 source를 다음 active source로 출력하지 않는 한 iMessage, Gmail, Obsidian 또는 다른 source를 시작하지 마세요.
        - 공식 `ntn` CLI 경로를 사용하세요. 기본 인증은 `ntn login`이고, `ntn login --no-browser`는 headless fallback일 때만 사용합니다.
        - `source-onboarding-state.json`을 직접 편집하지 마세요. Source Onboarding state 쓰기는 helper CLI만 담당합니다.
        - prompt body, OAuth code, token, signed URL, credential-like query string을 저장하지 마세요.
        - Notion data source ingest는 GBrain용 markdown/page artifact 변환으로 다루고, native Notion database ingest로 가정하지 마세요.
        - helper stdout의 `nextPrompt`에서만 계속 진행하세요. `nextPromptPath`는 fallback/debug 파일로만 사용하세요.

        Playbook 단계 안내:

        {section}
        ''').strip()
    if language == "ja":
        return textwrap.dedent(f'''
        Zebra Source Onboarding: Notion が現在のアクティブな source です。

        Playbook: {playbook.get("id", "notion.ntn-cli")} {playbook.get("version", "v1")}
        現在の step: `{step_id}`
        現在の Notion scope: `{scope}`
        現在の Notion target: `{target}`
        現在の ingest artifact: `{artifact}`

        境界ルール:
        - この Notion step だけを進めてください。helper が別の source を次の active source として出力しない限り、iMessage, Gmail, Obsidian, または他の source を開始しないでください。
        - 公式 `ntn` CLI を使ってください。基本認証は `ntn login` で、`ntn login --no-browser` は headless fallback の場合だけ使います。
        - `source-onboarding-state.json` を直接編集しないでください。Source Onboarding state の書き込みは helper CLI だけが行います。
        - prompt body, OAuth code, token, signed URL, credential-like query string を保存しないでください。
        - Notion data source ingest は GBrain 用の markdown/page artifact 変換として扱い、native Notion database ingest と仮定しないでください。
        - helper stdout の `nextPrompt` からだけ続行してください。`nextPromptPath` は fallback/debug file としてのみ使ってください。

        Playbook step の案内:

        {section}
        ''').strip()
    return textwrap.dedent(f'''
    Zebra Source Onboarding: Notion is the active source.

    Playbook: {playbook.get("id", "notion.ntn-cli")} {playbook.get("version", "v1")}
    Current step: `{step_id}`
    Current Notion scope: `{scope}`
    Current Notion target: `{target}`
    Current ingest artifact: `{artifact}`

    Boundary rules:
    - Work only this Notion step. Do not start iMessage, Gmail, Obsidian, or another source unless the helper prints that source as the next active source.
    - Use the official `ntn` CLI path. Primary auth is `ntn login`; `ntn login --no-browser` is only the headless fallback.
    - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
    - Do not store prompt bodies, OAuth codes, tokens, signed URLs, or credential-like query strings.
    - Treat Notion data source ingest as markdown/page artifact conversion for GBrain, not native Notion database ingest.
    - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

    Playbook step instructions:

    {section}
    ''').strip()

def set_notion_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
    timestamp = timestamp or now()
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("notion") if isinstance(rows.get("notion"), dict) else source_row_for("notion", timestamp)
    playbook = notion_playbook()
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
    rows["notion"] = row
    progress["sourceRows"] = rows
    if "notion" not in ensure_execution_order(progress):
        progress["executionOrder"].append("notion")
    if row_status in {"checked", "skipped"}:
        if progress.get("activeSourceID") == "notion":
            progress["activeSourceID"] = None
    else:
        progress["activeSourceID"] = "notion"
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    return state

def should_update_notion_runner(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    if progress.get("activeSourceID") == "notion":
        return True
    if "notion" not in ensure_execution_order(progress):
        return False
    row = rows.get("notion")
    return isinstance(row, dict) and row.get("playbookID") == notion_playbook()["id"]

def required_cli_preflight_passed(source_id):
    spec = required_cli_specs[source_id]
    run_state = load_source_run_state(source_id)
    command_path = required_cli_command_path(source_id, run_state)
    return run_state.get(spec["statusKey"]) == "passed" and bool(command_path)

def require_cli_preflight_or_attention(source_id):
    spec = required_cli_specs[source_id]
    if required_cli_preflight_passed(source_id):
        return None
    state = load_or_create_state()
    run_state = load_source_run_state(source_id)
    command_path = required_cli_command_path(source_id, run_state)
    if command_path:
        spec = required_cli_specs[source_id]
        version = ""
        try:
            result = subprocess.run([command_path, "--version"], text=True, capture_output=True, timeout=5)
            version = (result.stdout or result.stderr or "").strip()
        except Exception:
            version = ""
        run_state.update({
            spec["statusKey"]: "passed",
            spec["pathKey"]: command_path,
            spec["versionKey"]: version,
            "phase": "preflight",
            "step": spec["nextStep"],
            "updatedAt": now(),
        })
        run_path = save_source_run_state(source_id, run_state)
        state = set_cli_source_row_state(
            source_id,
            state,
            "running",
            "preflight",
            spec["nextStep"],
            run_state_path=run_path,
            result_summary=spec["binary"] + " CLI found at " + command_path,
        )
        save_json(state)
        return None
    run_state.update({
        spec["statusKey"]: "missing",
        "phase": "preflight",
        "step": spec["checkStep"],
        "updatedAt": now(),
    })
    run_path = save_source_run_state(source_id, run_state)
    state = set_cli_source_row_state(
        source_id,
        state,
        "attention",
        "preflight",
        spec["checkStep"],
        attention_reason=spec["missingReason"],
        run_state_path=run_path,
    )
    save_json(state)
    payload = {"ok": False, "reason": spec["missingReason"]}
    payload.update(source_next_prompt_payload(state, source_id, spec["checkStep"]))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 1

def start_notion_from_next(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("notion") if isinstance(rows.get("notion"), dict) else {}
    playbook = notion_playbook()
    if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
        step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "notion", step_id))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    run_state = load_source_run_state("notion")
    run_state.update({
        "phase": "preflight",
        "step": playbook["initialStepID"],
        "updatedAt": now(),
    })
    run_path = save_source_run_state("notion", run_state)
    state = set_notion_row_state(
        state,
        "running",
        "preflight",
        playbook["initialStepID"],
        run_state_path=run_path,
    )
    save_json(state)
    payload = summary(state)
    payload.update(source_next_prompt_payload(state, "notion", playbook["initialStepID"]))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def notion_artifact_path(state=None):
    target = None
    if isinstance(state, dict):
        target = state.get("entryContext", {}).get("gbrainTargetPath")
    if target and Path(target).is_dir():
        directory = Path(target) / "sources"
    else:
        directory = state_path.parent / "source-ingest-artifacts"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / "notion-source-onboarding.md"

def sanitize_notion_text(value):
    text = str(value or "")
    text = re.sub("secret_[A-Za-z0-9_\-]+", "REDACTED_SECRET", text)
    text = re.sub("ntn_[A-Za-z0-9_\-]+", "REDACTED_NTN_TOKEN", text)
    text = re.sub("([\"'](?:oauth[_-]?code|access[_-]?token|refresh[_-]?token|id[_-]?token|authorization|cookie)[\"']\s*:\s*)[\"'][^\"']+[\"']", "\\1\"REDACTED\"", text, flags=re.IGNORECASE)
    text = re.sub("([\"']code[\"']\s*:\s*)[\"'][A-Za-z0-9_\-]{8,}[\"']", "\\1\"REDACTED\"", text, flags=re.IGNORECASE)
    text = re.sub("oauth[_-]?code[=:][A-Za-z0-9_\-]+", "oauth_code=REDACTED", text, flags=re.IGNORECASE)
    text = re.sub("code[=:][A-Za-z0-9_\-]{8,}", "code=REDACTED", text, flags=re.IGNORECASE)
    text = re.sub("([?&][^\n\s)\"',}]*(token|signature|x-amz|X-Amz|expires|credential)[^\n\s)\"',}]*)", "?REDACTED_QUERY", text, flags=re.IGNORECASE)
    return text

def sanitize_notion_value(value):
    if isinstance(value, dict):
        sanitized = {}
        for key, item in value.items():
            raw_key = str(key)
            lower = raw_key.lower()
            normalized_key = re.sub("[^a-z0-9]", "", lower)
            sensitive_exact = {
                "code",
                "oauthcode",
                "accesstoken",
                "refreshtoken",
                "idtoken",
                "authorization",
                "cookie",
            }
            if normalized_key in sensitive_exact or any(word in lower for word in ("token", "secret", "oauth", "authorization", "cookie", "credential", "signature")):
                sanitized[key] = "REDACTED"
            else:
                sanitized[key] = sanitize_notion_value(item)
        return sanitized
    if isinstance(value, list):
        return [sanitize_notion_value(item) for item in value]
    if isinstance(value, str):
        return sanitize_notion_text(value)
    return value

def extract_notion_id(value):
    text = str(value or "").strip()
    if not text:
        return ""
    text = text.split("?")[0].rstrip("/")
    tail = text.rsplit("/", 1)[-1]
    if "-" in tail:
        maybe = tail.rsplit("-", 1)[-1]
        if len(maybe) >= 16:
            return maybe
    return tail or text

def notion_run_state_with_command_path():
    run_state = load_source_run_state("notion")
    command_path = required_cli_command_path("notion", run_state)
    return run_state, command_path

def run_ntn(ntn_args, timeout=60):
    _, command_path = notion_run_state_with_command_path()
    if not command_path:
        return {"ok": False, "status": 127, "args": list(ntn_args), "stdout": "", "stderr": "ntn_cli_missing", "json": None}
    try:
        completed = subprocess.run(
            [command_path] + list(ntn_args),
            text=True,
            capture_output=True,
            timeout=timeout,
        )
        stdout = sanitize_notion_text(completed.stdout)
        stderr = sanitize_notion_text(completed.stderr)
        payload = None
        try:
            payload = sanitize_notion_value(json.loads(stdout)) if stdout.strip() else None
        except Exception:
            payload = None
        return {
            "ok": completed.returncode == 0,
            "status": completed.returncode,
            "args": list(ntn_args),
            "stdout": stdout,
            "stderr": stderr,
            "json": payload,
        }
    except FileNotFoundError:
        return {"ok": False, "status": 127, "args": list(ntn_args), "stdout": "", "stderr": "ntn_cli_missing", "json": None}
    except subprocess.TimeoutExpired:
        return {"ok": False, "status": 124, "args": list(ntn_args), "stdout": "", "stderr": "ntn_timeout", "json": None}

def notion_search_candidates(search_result):
    payload = search_result.get("json")
    raw_items = []
    if isinstance(payload, dict):
        if isinstance(payload.get("results"), list):
            raw_items = payload.get("results")
        elif isinstance(payload.get("data"), list):
            raw_items = payload.get("data")
        elif isinstance(payload.get("object"), str):
            raw_items = [payload]
    elif isinstance(payload, list):
        raw_items = payload
    candidates = []
    for item in raw_items[:10]:
        if not isinstance(item, dict):
            continue
        item_id = str(item.get("id") or item.get("page_id") or item.get("data_source_id") or "")
        title = item.get("title")
        if not title and isinstance(item.get("properties"), dict):
            for prop in item["properties"].values():
                if isinstance(prop, dict) and isinstance(prop.get("title"), list) and prop["title"]:
                    title = "".join(part.get("plain_text", "") for part in prop["title"] if isinstance(part, dict))
                    break
        if not title and isinstance(item.get("name"), str):
            title = item.get("name")
        kind = str(item.get("object") or item.get("type") or item.get("kind") or "unknown")
        candidates.append({
            "id": sanitize_notion_text(item_id),
            "title": sanitize_notion_text(title or "Untitled"),
            "object": sanitize_notion_text(kind),
        })
    return candidates

def notion_smoke_for_scope(scope, target):
    target_id = extract_notion_id(target)
    if scope in {"page", "page-subtree"}:
        return run_ntn(["pages", "get", target_id])
    if scope == "data-source":
        return run_ntn(["datasources", "query", target_id, "--limit", "5", "--json"])
    return {"ok": False, "status": 2, "args": [], "stdout": "", "stderr": "unsupported_scope", "json": None}

def notion_smoke_summary(scope, target, smoke):
    stdout = smoke.get("stdout") or ""
    stderr = smoke.get("stderr") or ""
    body = stdout.strip() or stderr.strip()
    if len(body) > 1200:
        body = body[:1200] + "...(truncated)"
    return {
        "scope": scope,
        "target": sanitize_notion_text(target),
        "targetID": sanitize_notion_text(extract_notion_id(target)),
        "status": smoke.get("status"),
        "command": "ntn " + " ".join(smoke.get("args") or []),
        "sample": body,
    }

def notion_fetch_result_summary(label, result):
    stdout = result.get("stdout") or ""
    stderr = result.get("stderr") or ""
    body = stdout.strip() or stderr.strip()
    if len(body) > 4000:
        body = body[:4000] + "...(truncated)"
    return {
        "label": sanitize_notion_text(label),
        "status": result.get("status"),
        "ok": bool(result.get("ok")),
        "command": "ntn " + " ".join(result.get("args") or []),
        "sample": body,
    }

def notion_ingest_fetch_results(run_state):
    scope = run_state.get("scope")
    target_id = run_state.get("targetID") or extract_notion_id(run_state.get("target"))
    results = []
    if scope == "page":
        results.append(notion_fetch_result_summary("page", run_ntn(["pages", "get", target_id])))
    elif scope == "page-subtree":
        results.append(notion_fetch_result_summary("page", run_ntn(["pages", "get", target_id])))
        results.append(notion_fetch_result_summary(
            "page-subtree-children",
            run_ntn(["blocks", "children", "list", target_id, "--recursive", "--json"], timeout=180),
        ))
    elif scope == "data-source":
        results.append(notion_fetch_result_summary(
            "data-source-pages",
            run_ntn(["datasources", "query", target_id, "--json"], timeout=180),
        ))
    elif scope == "workspace-all":
        candidates = run_state.get("searchCandidates") if isinstance(run_state.get("searchCandidates"), list) else []
        for index, item in enumerate(candidates[:50], start=1):
            if not isinstance(item, dict):
                continue
            item_id = item.get("id")
            if not item_id:
                continue
            results.append(notion_fetch_result_summary(
                "workspace-candidate-" + str(index),
                run_ntn(["pages", "get", item_id], timeout=120),
            ))
    return results

def notion_ingest_fetch_passed(scope, results):
    if scope == "page-subtree":
        labels = {
            item.get("label"): bool(item.get("ok"))
            for item in results
            if isinstance(item, dict)
        }
        return bool(labels.get("page")) and bool(labels.get("page-subtree-children"))
    return any(isinstance(item, dict) and item.get("ok") for item in results)

def notion_choose_scope():
    scope = single_flag_value("--scope")
    target = single_flag_value("--target")
    if scope not in {"page", "page-subtree", "data-source", "workspace-search", "workspace-all", "skip"}:
        print("--scope must be page, page-subtree, data-source, workspace-search, workspace-all, or skip", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("notion")
    if scope == "skip":
        run_state.update({"scope": "skip", "phase": "complete", "step": "complete", "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "notion",
            "skipped",
            "Notion skipped for this Source Onboarding session.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "skipped": True}
        payload.update(source_next_prompt_payload(state, "notion", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    preflight_code = require_cli_preflight_or_attention("notion")
    if preflight_code is not None:
        return preflight_code
    run_state = load_source_run_state("notion")
    if scope == "workspace-search":
        search = run_ntn(["api", "v1/search", "page_size:=10"])
        candidates = notion_search_candidates(search)
        run_state.update({
            "scope": "workspace-search",
            "phase": "preflight",
            "step": "choose_scope",
            "searchStatus": "passed" if search.get("ok") else "failed",
            "searchCandidates": candidates,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "attention",
            "preflight",
            "choose_scope",
            attention_reason="notion_candidate_selection_required" if search.get("ok") else "notion_workspace_search_failed",
            run_state_path=run_path,
            result_summary="Notion workspace search returned " + str(len(candidates)) + " candidates.",
        )
        save_json(state)
        payload = {"ok": bool(search.get("ok")), "scope": scope, "candidates": candidates}
        if not search.get("ok"):
            payload["reason"] = "notion_workspace_search_failed"
        payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0 if search.get("ok") else 1
    if scope == "workspace-all":
        search = run_ntn(["api", "v1/search", "page_size:=10"])
        if not search.get("ok"):
            candidates = notion_search_candidates(search)
            run_state.update({
                "scope": "workspace-all",
                "phase": "preflight",
                "step": "choose_scope",
                "searchStatus": "failed",
                "searchCandidates": candidates,
                "updatedAt": now(),
            })
            run_path = save_source_run_state("notion", run_state)
            state = set_notion_row_state(
                state,
                "attention",
                "preflight",
                "choose_scope",
                attention_reason="notion_workspace_search_failed",
                run_state_path=run_path,
                result_summary="Notion workspace search failed before whole-workspace estimate.",
            )
            save_json(state)
            payload = {"ok": False, "scope": scope, "reason": "notion_workspace_search_failed", "candidates": candidates}
            payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
            return 1
        candidates = notion_search_candidates(search)
        representative_smoke = None
        if candidates:
            first_id = candidates[0].get("id")
            if first_id:
                representative_smoke = run_ntn(["pages", "get", first_id])
        run_state.update({
            "scope": "workspace-all",
            "phase": "estimate",
            "step": "confirm_workspace_ingest",
            "workspaceCandidateCount": len(candidates),
            "searchStatus": "passed",
            "searchCandidates": candidates,
            "representativeSmokeStatus": representative_smoke.get("status") if isinstance(representative_smoke, dict) else None,
            "workspaceConfirmed": False,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "attention",
            "estimate",
            "confirm_workspace_ingest",
            attention_reason="workspace_ingest_confirmation_required",
            run_state_path=run_path,
            result_summary="Notion whole-workspace estimate prepared with " + str(len(candidates)) + " search candidates.",
        )
        save_json(state)
        payload = {"ok": True, "scope": scope, "workspaceCandidateCount": len(candidates), "workspaceConfirmed": False}
        payload.update(source_next_prompt_payload(state, "notion", "confirm_workspace_ingest"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    if not target:
        print("--target is required for page, page-subtree, and data-source scopes", file=sys.stderr)
        return 2
    smoke = notion_smoke_for_scope(scope, target)
    smoke_summary = notion_smoke_summary(scope, target, smoke)
    if not smoke.get("ok"):
        run_state.update({
            "scope": scope,
            "target": sanitize_notion_text(target),
            "targetID": sanitize_notion_text(extract_notion_id(target)),
            "phase": "smoke",
            "step": "choose_scope",
            "smokeStatus": "failed",
            "smokeSummary": smoke_summary,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "attention",
            "smoke",
            "choose_scope",
            attention_reason="notion_smoke_read_failed",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "scope": scope, "reason": "notion_smoke_read_failed", "smoke": smoke_summary}
        payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({
        "scope": scope,
        "target": sanitize_notion_text(target),
        "targetID": sanitize_notion_text(extract_notion_id(target)),
        "phase": "ingest",
        "step": "ingest_notion",
        "smokeStatus": "passed",
        "smokeSummary": smoke_summary,
        "updatedAt": now(),
    })
    run_path = save_source_run_state("notion", run_state)
    state = set_notion_row_state(
        state,
        "running",
        "ingest",
        "ingest_notion",
        run_state_path=run_path,
        result_summary="Notion smoke read passed for " + scope + " target.",
    )
    save_json(state)
    payload = {"ok": True, "scope": scope, "targetID": run_state.get("targetID"), "smoke": smoke_summary}
    payload.update(source_next_prompt_payload(state, "notion", "ingest_notion"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def notion_confirm_workspace():
    answer = single_flag_value("--answer").strip().lower()
    if answer not in {"yes", "y", "no", "n"}:
        print("--answer must be yes or no", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("notion")
    if answer in {"no", "n"}:
        run_state.update({
            "workspaceConfirmed": False,
            "phase": "preflight",
            "step": "choose_scope",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "attention",
            "preflight",
            "choose_scope",
            attention_reason="workspace_ingest_confirmation_declined",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "workspace_ingest_confirmation_declined"}
        payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if run_state.get("scope") != "workspace-all":
        print("workspace confirmation is only valid after --scope workspace-all", file=sys.stderr)
        return 2
    run_state.update({
        "workspaceConfirmed": True,
        "confirmedAt": now(),
        "phase": "ingest",
        "step": "ingest_notion",
        "updatedAt": now(),
    })
    run_path = save_source_run_state("notion", run_state)
    state = set_notion_row_state(
        state,
        "running",
        "ingest",
        "ingest_notion",
        run_state_path=run_path,
        result_summary="Notion whole-workspace ingest confirmed.",
    )
    save_json(state)
    payload = {"ok": True, "workspaceConfirmed": True}
    payload.update(source_next_prompt_payload(state, "notion", "ingest_notion"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def notion_artifact_markdown(run_state):
    scope = run_state.get("scope") or "unknown"
    target = run_state.get("target") or "workspace"
    title = "Notion Source Onboarding Ingest"
    smoke = run_state.get("smokeSummary") if isinstance(run_state.get("smokeSummary"), dict) else {}
    candidates = run_state.get("searchCandidates") if isinstance(run_state.get("searchCandidates"), list) else []
    ingest_results = run_state.get("ingestResults") if isinstance(run_state.get("ingestResults"), list) else []
    lines = [
        "---",
        "type: source-ingest",
        "source: notion",
        "source_kind: notion",
        "playbook: notion.ntn-cli.v1",
        "scope: " + sanitize_notion_text(scope),
        "source_uri: " + sanitize_notion_text(target),
        "notion_target_id: " + sanitize_notion_text(run_state.get("targetID") or ""),
        "created: " + now(),
        "---",
        "",
        "# " + title,
        "",
        "This artifact was generated by Zebra Source Onboarding from Notion via `ntn`.",
        "",
        "## Provenance",
        "",
        "- Source: Notion",
        "- Source kind: notion",
        "- Scope: " + sanitize_notion_text(scope),
        "- Source URI: " + sanitize_notion_text(target),
        "- Notion target ID: " + sanitize_notion_text(run_state.get("targetID") or ""),
        "- Ingest mode: markdown/page artifact conversion for GBrain, not native Notion database ingest",
        "",
        "## Smoke read",
        "",
    ]
    if smoke:
        lines.extend([
            "- Command: `" + sanitize_notion_text(smoke.get("command") or "") + "`",
            "- Status: `" + sanitize_notion_text(smoke.get("status")) + "`",
            "",
            "```text",
            sanitize_notion_text(smoke.get("sample") or ""),
            "```",
        ])
    elif candidates:
        lines.extend([
            "- Workspace candidate count: `" + str(len(candidates)) + "`",
            "",
            "## Workspace candidates",
            "",
        ])
        for item in candidates:
            if isinstance(item, dict):
                lines.append("- " + sanitize_notion_text(item.get("object") or "unknown") + ": " + sanitize_notion_text(item.get("title") or "Untitled") + " (" + sanitize_notion_text(item.get("id") or "") + ")")
    else:
        lines.append("- No smoke sample was persisted.")
    if ingest_results:
        lines.extend([
            "",
            "## Ingest fetch",
            "",
        ])
        for item in ingest_results:
            if not isinstance(item, dict):
                continue
            lines.extend([
                "### " + sanitize_notion_text(item.get("label") or "Notion fetch"),
                "",
                "- Command: `" + sanitize_notion_text(item.get("command") or "") + "`",
                "- Status: `" + sanitize_notion_text(item.get("status")) + "`",
                "",
                "```text",
                sanitize_notion_text(item.get("sample") or ""),
                "```",
                "",
            ])
    return sanitize_notion_text("\n".join(lines).rstrip() + "\n")

def notion_ingest():
    state = load_or_create_state()
    run_state = load_source_run_state("notion")
    scope = run_state.get("scope")
    if not scope or scope in {"skip", "workspace-search"}:
        state = set_notion_row_state(state, "attention", "preflight", "choose_scope", attention_reason="notion_scope_required")
        save_json(state)
        payload = {"ok": False, "reason": "notion_scope_required"}
        payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if scope == "workspace-all" and not run_state.get("workspaceConfirmed"):
        state = set_notion_row_state(state, "attention", "estimate", "confirm_workspace_ingest", attention_reason="workspace_ingest_confirmation_required")
        save_json(state)
        payload = {"ok": False, "reason": "workspace_ingest_confirmation_required"}
        payload.update(source_next_prompt_payload(state, "notion", "confirm_workspace_ingest"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if scope != "workspace-all" and run_state.get("smokeStatus") != "passed":
        state = set_notion_row_state(state, "attention", "smoke", "choose_scope", attention_reason="notion_smoke_read_required")
        save_json(state)
        payload = {"ok": False, "reason": "notion_smoke_read_required"}
        payload.update(source_next_prompt_payload(state, "notion", "choose_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    ingest_results = notion_ingest_fetch_results(run_state)
    if not notion_ingest_fetch_passed(scope, ingest_results):
        run_state.update({
            "ingestResults": ingest_results,
            "phase": "ingest",
            "step": "ingest_notion",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "attention",
            "ingest",
            "ingest_notion",
            attention_reason="notion_ingest_fetch_failed",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "notion_ingest_fetch_failed", "scope": scope, "ingestResults": ingest_results}
        payload.update(source_next_prompt_payload(state, "notion", "ingest_notion"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state["ingestResults"] = ingest_results
    artifact = notion_artifact_path(state)
    artifact.write_text(notion_artifact_markdown(run_state), encoding="utf-8")
    run_state.update({
        "artifactPath": str(artifact),
        "ingestedAt": now(),
        "phase": "verify",
        "step": "verify_readback",
        "updatedAt": now(),
    })
    run_path = save_source_run_state("notion", run_state)
    state = set_notion_row_state(
        state,
        "running",
        "verify",
        "verify_readback",
        run_state_path=run_path,
        result_summary="Notion ingest artifact written for scope " + str(scope) + ".",
    )
    save_json(state)
    payload = {"ok": True, "artifactPath": str(artifact), "scope": scope}
    payload.update(source_next_prompt_payload(state, "notion", "verify_readback"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def notion_verify_readback():
    state = load_or_create_state()
    run_state = load_source_run_state("notion")
    artifact = Path(run_state.get("artifactPath") or "")
    try:
        text = artifact.read_text(encoding="utf-8")
    except Exception:
        text = ""
    forbidden_patterns = [
        "secret_",
        "ntn_",
        "oauth_code=",
        "X-Amz-Signature",
    ]
    has_forbidden = any(pattern in text for pattern in forbidden_patterns)
    if "source_kind: notion" not in text or "playbook: notion.ntn-cli.v1" not in text or has_forbidden:
        run_state.update({"readbackStatus": "failed", "phase": "verify", "step": "verify_readback", "updatedAt": now()})
        run_path = save_source_run_state("notion", run_state)
        state = set_notion_row_state(
            state,
            "attention",
            "verify",
            "verify_readback",
            attention_reason="readback_failed",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "readback_failed", "hasForbiddenMaterial": has_forbidden}
        payload.update(source_next_prompt_payload(state, "notion", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "phase": "complete", "step": "complete", "updatedAt": now()})
    state = mark_source_completion_pending(
        state,
        "notion",
        "checked",
        "Notion ingest readback verified.",
        run_state=run_state,
    )
    save_json(state)
    payload = {"ok": True, "artifactPath": str(artifact), "readbackStatus": "passed"}
    payload.update(source_next_prompt_payload(state, "notion", "complete"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def notion_command():
    if not args:
        print("notion requires a subcommand", file=sys.stderr)
        return 2
    pending_code = reject_if_completion_report_pending("notion")
    if pending_code is not None:
        return pending_code
    subcommand = args[0]
    if subcommand == "check-cli":
        return check_required_cli("notion")
    if subcommand == "choose-scope":
        return notion_choose_scope()
    if subcommand == "confirm-workspace":
        return notion_confirm_workspace()
    if subcommand == "ingest":
        return notion_ingest()
    if subcommand == "verify-readback":
        return notion_verify_readback()
    print("unknown notion subcommand: " + subcommand, file=sys.stderr)
    return 2

