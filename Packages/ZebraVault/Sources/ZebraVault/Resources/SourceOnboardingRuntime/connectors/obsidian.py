from domain import deterministic_slug
from gbrain_ingest import submit_connector_ingestion
from state import ingest_projection
from playbooks import parse_playbook_markdown
from common import *

def obsidian_playbook():
    return parse_playbook_markdown(
        playbook_dir / "obsidian.direct-markdown.v1.md",
        obsidian_playbook_fallback,
    )

def obsidian_choose_scope_instruction(language):
    if language == "ko":
        return textwrap.dedent('''
        사용자에게 아래 다섯 가지 선택지만 보여주세요:

        ```text
        Obsidian 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 note 범위를 정해야 합니다.

        어떤 범위로 가져올까요?

        1. 전체 vault
        2. 선택한 폴더
        3. 특정 note 파일
        4. 최근/샘플 일부
        5. 지금은 Obsidian 건너뛰기
        ```

        1번은 `zebra-source-onboarding obsidian choose-scope --scope whole`을 실행하세요.
        2번은 vault 기준 상대 폴더 경로를 확인한 뒤 `zebra-source-onboarding obsidian choose-scope --scope folders --folder "<relative-folder>"`를 실행하세요. 폴더가 여러 개면 `--folder`를 여러 번 넘기세요.
        3번은 vault 기준 상대 Markdown 파일 경로를 확인한 뒤 `zebra-source-onboarding obsidian choose-scope --scope file --file "<relative-note-path.md>"`를 실행하세요.
        4번은 `zebra-source-onboarding obsidian choose-scope --scope sample`을 실행하세요.
        5번은 `zebra-source-onboarding obsidian choose-scope --scope skip`을 실행하세요.

        큰 vault나 폴더에는 private/sensitive note가 포함될 수 있습니다. smoke read 성공은 접근 확인일 뿐 ingest 승인으로 보지 마세요.
        ''').strip()
    if language == "ja":
        return textwrap.dedent('''
        ユーザーには次の5つの選択肢だけを表示してください:

        ```text
        Obsidianへのアクセス確認は完了しました。次にbrainへ保存するnoteの範囲を決めます。

        どの範囲を取り込みますか？

        1. vault全体
        2. 選択したフォルダ
        3. 特定のnoteファイル
        4. 最近/サンプルの一部
        5. 今回はObsidianをスキップ
        ```

        1番は`zebra-source-onboarding obsidian choose-scope --scope whole`を実行してください。
        2番はvault基準の相対フォルダパスを確認し、`zebra-source-onboarding obsidian choose-scope --scope folders --folder "<relative-folder>"`を実行してください。複数フォルダの場合は`--folder`を複数回渡してください。
        3番はvault基準の相対Markdownファイルパスを確認し、`zebra-source-onboarding obsidian choose-scope --scope file --file "<relative-note-path.md>"`を実行してください。
        4番は`zebra-source-onboarding obsidian choose-scope --scope sample`を実行してください。
        5番は`zebra-source-onboarding obsidian choose-scope --scope skip`を実行してください。

        大きいvaultやフォルダにはprivate/sensitive noteが含まれる可能性があります。smoke read成功はアクセス確認だけで、ingest承認ではありません。
        ''').strip()
    return textwrap.dedent('''
    Present exactly these five choices to the user:

    ```text
    Obsidian access is verified. Now choose which notes to save into brain.

    Which scope should be ingested?

    1. Whole vault
    2. Selected folders
    3. Specific note file
    4. Recent/sample subset
    5. Skip Obsidian for now
    ```

    If the user chooses option 1, run `zebra-source-onboarding obsidian choose-scope --scope whole`.
    If the user chooses option 2, confirm the vault-relative folder path and run `zebra-source-onboarding obsidian choose-scope --scope folders --folder "<relative-folder>"`. Pass one `--folder` per folder.
    If the user chooses option 3, confirm the vault-relative Markdown file path and run `zebra-source-onboarding obsidian choose-scope --scope file --file "<relative-note-path.md>"`.
    If the user chooses option 4, run `zebra-source-onboarding obsidian choose-scope --scope sample`.
    If the user chooses option 5, run `zebra-source-onboarding obsidian choose-scope --scope skip`.

    Large vaults or folders may contain private/sensitive notes. Smoke read success proves access only; it is not ingest approval.
    ''').strip()

def obsidian_step_prompt(step_id, state, row):
    playbook = obsidian_playbook()
    run_state = load_source_run_state("obsidian")
    section = playbook.get("sections", {}).get(step_id, "")
    language = onboarding_language()
    path = ""
    if not section:
        section = "Follow the current Obsidian playbook step and continue only through the zebra-source-onboarding helper CLI."
    vault = run_state.get("selectedVaultPath") or run_state.get("candidateVaultPath") or "not selected"
    scope = run_state.get("scope") or "not selected"
    estimated = run_state.get("estimatedFileCount")
    if estimated is None:
        estimated = "unknown"
    ingest_status = (run_state.get("ingestReceipt") or {}).get("failure") or ("verified" if (run_state.get("ingestReceipt") or {}).get("complete") else "not started")
    unreadable_roots = run_state.get("unreadableCandidateRoots") if isinstance(run_state.get("unreadableCandidateRoots"), list) else []
    if step_id == "discover_vault" and unreadable_roots:
        lines = []
        for item in unreadable_roots:
            if not isinstance(item, dict):
                continue
            root_path = item.get("path") or "unknown"
            reason = item.get("reason") or "unreadable"
            message = item.get("message") or ""
            detail = " - `" + str(root_path) + "` (" + str(reason) + ")"
            if message:
                detail = detail + ": " + str(message)
            lines.append(detail)
        if lines:
            if language == "ko":
                section = section + "\n\n" + "Zebra가 아래 자동 탐색 위치를 확인하지 못했습니다. 자동 탐색 결과가 불완전할 수 있음을 사용자에게 알리고, 필요하면 정확한 Obsidian vault 경로를 물어보세요:\n" + "\n".join(lines)
            elif language == "ja":
                section = section + "\n\n" + "Zebraは次の自動探索場所を確認できませんでした。自動探索結果が不完全な可能性をユーザーに伝え、必要であれば正確なObsidian vaultパスを尋ねてください:\n" + "\n".join(lines)
            else:
                section = section + "\n\n" + "Zebra could not inspect these automatic discovery roots. Tell the user that automatic discovery may be incomplete and ask for the exact Obsidian vault path if needed:\n" + "\n".join(lines)
    if step_id == "confirm_vault_if_needed":
        candidate = run_state.get("candidateVaultPath")
        candidates = run_state.get("candidateVaultPaths") if isinstance(run_state.get("candidateVaultPaths"), list) else []
        if candidate:
            method = run_state.get("discoveryMethod") or "automatic_discovery"
            if language == "ko":
                section = section + "\n\n" + textwrap.dedent(f'''
                Zebra가 `{method}`에서 `.obsidian/`을 포함한 Obsidian vault 후보를 찾았습니다:

                `{candidate}`

                이 경로를 Obsidian vault로 사용할지 사용자에게 확인하세요. 맞다면 다음 명령을 실행하세요:

                ```bash
                zebra-source-onboarding obsidian verify-vault --path "{candidate}"
                ```

                아니라면 올바른 vault 경로를 물어보고 `zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`를 실행하세요.
                ''').strip()
            elif language == "ja":
                section = section + "\n\n" + textwrap.dedent(f'''
                Zebraは`{method}`から`.obsidian/`を含むObsidian vault候補を見つけました:

                `{candidate}`

                このパスをObsidian vaultとして使用するかユーザーに確認してください。正しければ次のコマンドを実行してください:

                ```bash
                zebra-source-onboarding obsidian verify-vault --path "{candidate}"
                ```

                違う場合は正しいvaultパスを尋ね、`zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`を実行してください。
                ''').strip()
            else:
                section = section + "\n\n" + textwrap.dedent(f'''
                Zebra found this Obsidian-like vault candidate from `{method}` because it contains `.obsidian/`:

                `{candidate}`

                Ask the user to confirm whether this is the Obsidian vault to use. If yes, run:

                ```bash
                zebra-source-onboarding obsidian verify-vault --path "{candidate}"
                ```

                If no, ask for the correct vault path and run `zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`.
                ''').strip()
        elif candidates:
            method = run_state.get("discoveryMethod") or "automatic_discovery"
            candidate_lines = "\n".join("- `" + str(item) + "`" for item in candidates)
            if language == "ko":
                section = section + "\n\n" + "Zebra가 `" + str(method) + "`에서 여러 `.obsidian/` vault 후보를 찾았습니다. 사용할 vault를 사용자에게 물어본 뒤 `zebra-source-onboarding obsidian verify-vault --path <vault-path>`를 실행하세요. 후보:\n\n" + candidate_lines
            elif language == "ja":
                section = section + "\n\n" + "Zebraは`" + str(method) + "`から複数の`.obsidian/` vault候補を見つけました。使用するvaultをユーザーに確認し、`zebra-source-onboarding obsidian verify-vault --path <vault-path>`を実行してください。候補:\n\n" + candidate_lines
            else:
                section = section + "\n\n" + "Zebra found multiple `.obsidian/` vault candidates from `" + str(method) + "`. Ask the user which one to use, then run `zebra-source-onboarding obsidian verify-vault --path <vault-path>`. Candidates:\n\n" + candidate_lines
    if step_id == "choose_ingest_scope":
        section = obsidian_choose_scope_instruction(language)
    if step_id == "smoke_read" and run_state.get("smokeReadStatus") == "inconclusive":
        observed = run_state.get("observedReasons") if isinstance(run_state.get("observedReasons"), list) else []
        observed_text = ", ".join(str(item) for item in observed) or "read_failed"
        suspected = run_state.get("suspectedCause")
        if language == "ko":
            recovery = textwrap.dedent(f'''
            시험한 최대 5개 Markdown에서는 본문 읽기에 성공하지 못했습니다. 이것만으로 vault 전체를 읽을 수 없다고 판단하지 마세요.

            관찰된 오류: `{observed_text}`

            현재 선택한 vault와 onboarding 진행 상태를 유지하세요. 관찰된 오류에 맞는 조치 후 `zebra-source-onboarding obsidian smoke-read`를 다시 실행하거나, 사용자가 읽을 수 있다고 알고 있는 Markdown 파일을 확인하세요.
            ''').strip()
            if suspected == "icloud_not_materialized":
                recovery += "\n\niCloud 파일이 아직 로컬에 준비되지 않았을 가능성이 있습니다. Finder 또는 Obsidian에서 다운로드 상태를 확인한 뒤 다시 시도하도록 안내하세요. 이를 확정 원인으로 말하지 마세요."
        elif language == "ja":
            recovery = textwrap.dedent(f'''
            試した最大5件のMarkdownでは本文の読み取りに成功しませんでした。これだけでvault全体が読み取れないとは判断しないでください。

            観測したエラー: `{observed_text}`

            選択中のvaultとonboardingの進行状態を維持してください。観測したエラーに応じた対応後に`zebra-source-onboarding obsidian smoke-read`を再実行するか、ユーザーが読み取れると分かっているMarkdownファイルを確認してください。
            ''').strip()
            if suspected == "icloud_not_materialized":
                recovery += "\n\niCloudファイルがまだローカルに用意されていない可能性があります。FinderまたはObsidianでダウンロード状態を確認してから再試行するよう案内し、確定原因として説明しないでください。"
        else:
            recovery = textwrap.dedent(f'''
            The sampled Markdown reads did not prove that the entire vault is unreadable. None of the maximum five attempted samples could be opened.

            Observed errors: `{observed_text}`

            Preserve the selected vault and onboarding cursor. After addressing the observed errors, run `zebra-source-onboarding obsidian smoke-read` again or ask for a Markdown file the user knows is readable.
            ''').strip()
            if suspected == "icloud_not_materialized":
                recovery += "\n\nThe iCloud files may not be available locally yet. Tell the user to check their download state in Finder or Obsidian and retry, without presenting this as a confirmed cause."
        section = section + "\n\n" + recovery
    if step_id == "confirm_ingest_plan":
        section = section + "\n\n" + obsidian_ingest_plan_summary(run_state)
    return textwrap.dedent(f'''
    Zebra Source Onboarding: Obsidian is the active source.

    Playbook: {playbook.get("id", "obsidian.direct-markdown")} {playbook.get("version", "v1")}
    Current step: `{step_id}`
    Current vault path: `{vault}`
    Current ingest scope: `{scope}`
    Approximate file count: `{estimated}`
    Current GBrain ingest status: `{ingest_status}`

    Boundary rules:
    - Work only this Obsidian step. Do not start Notion, iMessage, Gmail, or another source unless the helper prints that source as the next active source.
    - Use direct Markdown filesystem access. Do not require Obsidian CLI or Clawvisor for Obsidian.
    - Do not use the GBrain write target path or `gbrainTargetPath` as the Obsidian source vault. If the user wants Obsidian, use an automatic `.obsidian/` candidate from this prompt or ask for the actual Obsidian vault path.
    - Do not edit `source-onboarding-state.json` directly. The helper CLI is the only Source Onboarding state write path.
    - Do not store Markdown bodies, large file lists, or prompt bodies in Source Onboarding state.
    - Continue only from helper stdout `nextPrompt`; use `nextPromptPath` only as a fallback/debug file.

    Playbook step instructions:

    {section}
    ''').strip()

def set_obsidian_row_state(state, row_status, phase, step_id, timestamp=None, attention_reason=None, result_summary=None, run_state_path=None):
    timestamp = timestamp or now()
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("obsidian") if isinstance(rows.get("obsidian"), dict) else source_row_for("obsidian", timestamp)
    playbook = obsidian_playbook()
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
    rows["obsidian"] = row
    progress["sourceRows"] = rows
    if "obsidian" not in ensure_execution_order(progress):
        progress["executionOrder"].append("obsidian")
    if row_status in {"checked", "skipped"}:
        if progress.get("activeSourceID") == "obsidian":
            progress["activeSourceID"] = None
    else:
        progress["activeSourceID"] = "obsidian"
    state["status"] = source_completion_status(state)
    state["updatedAt"] = timestamp
    return state

def should_update_obsidian_runner(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    if progress.get("activeSourceID") == "obsidian":
        return True
    if "obsidian" not in ensure_execution_order(progress):
        return False
    row = rows.get("obsidian")
    return isinstance(row, dict) and row.get("playbookID") == obsidian_playbook()["id"]

def obsidian_error_reason(error, missing_reason="sample_file_not_found"):
    error_number = getattr(error, "errno", None)
    if isinstance(error, FileNotFoundError) or error_number == errno.ENOENT:
        return missing_reason
    if isinstance(error, PermissionError) or error_number in {errno.EPERM, errno.EACCES}:
        return "access_denied"
    if error_number == errno.EDEADLK:
        return "read_temporarily_unavailable"
    return "read_failed"

def obsidian_relative_path(vault, path):
    try:
        return str(Path(path).relative_to(vault))
    except Exception:
        return Path(path).name or "."

def obsidian_error_diagnostic(vault, path, error, missing_reason="sample_file_not_found"):
    error_number = getattr(error, "errno", None)
    message = getattr(error, "strerror", None) or type(error).__name__
    return {
        "path": obsidian_relative_path(vault, path),
        "reason": obsidian_error_reason(error, missing_reason=missing_reason),
        "errorType": type(error).__name__,
        "errno": error_number,
        "message": str(message)[:240],
    }

def markdown_scan_for_vault(vault_path, folders=None, limit=None):
    vault = Path(vault_path).expanduser()
    if not vault.is_dir():
        return {"files": [], "traversalDiagnostics": [], "complete": False}
    roots = []
    if folders:
        for folder in folders:
            candidate = (vault / folder).resolve(strict=False)
            try:
                candidate.relative_to(vault.resolve(strict=False))
                if candidate.exists():
                    roots.append(candidate)
            except Exception:
                continue
    if not roots:
        roots = [vault]
    files = []
    traversal_diagnostics = []

    def record_walk_error(error):
        if len(traversal_diagnostics) >= 8:
            return
        error_path = getattr(error, "filename", None) or vault
        traversal_diagnostics.append(
            obsidian_error_diagnostic(vault, error_path, error, missing_reason="vault_not_found")
        )

    for root in roots:
        for current, dirnames, filenames in os.walk(root, onerror=record_walk_error):
            dirnames[:] = [
                name for name in dirnames
                if not name.startswith(".") and name not in {".obsidian", "__MACOSX"}
            ]
            for filename in filenames:
                if not filename.lower().endswith(".md"):
                    continue
                path = Path(current) / filename
                try:
                    path.relative_to(vault)
                except Exception:
                    continue
                files.append(path)
                if limit and len(files) >= limit:
                    return {
                        "files": files,
                        "traversalDiagnostics": traversal_diagnostics,
                        "complete": not traversal_diagnostics,
                    }
    return {
        "files": files,
        "traversalDiagnostics": traversal_diagnostics,
        "complete": not traversal_diagnostics,
    }

def markdown_files_for_vault(vault_path, folders=None, limit=None):
    return markdown_scan_for_vault(vault_path, folders=folders, limit=limit)["files"]

def obsidian_file_for_vault(vault_path, value):
    if not value:
        return {"ok": False, "reason": "file_path_required"}
    vault = Path(vault_path).expanduser()
    if not vault.is_dir():
        return {"ok": False, "reason": "vault_path_required"}
    raw = str(value).strip()
    if not raw:
        return {"ok": False, "reason": "file_path_required"}
    path = Path(raw).expanduser()
    if path.is_absolute():
        return {"ok": False, "reason": "file_path_must_be_relative"}
    if any((part not in {".", ".."} and part.startswith(".")) or part == "__MACOSX" for part in path.parts):
        return {"ok": False, "reason": "file_path_not_allowed"}
    vault_resolved = vault.resolve(strict=False)

    def candidate_record(candidate):
        resolved = candidate.resolve(strict=False)
        try:
            relative = resolved.relative_to(vault_resolved)
        except Exception:
            return {"ok": False, "reason": "file_path_outside_vault"}
        if not resolved.exists():
            return {"ok": False, "reason": "file_not_found"}
        if not resolved.is_file():
            return {"ok": False, "reason": "file_path_not_file"}
        if resolved.suffix.lower() != ".md":
            return {"ok": False, "reason": "file_path_not_markdown"}
        return {"ok": True, "path": str(resolved), "relative": str(relative)}

    result = candidate_record(vault / path)
    if result.get("ok") or path.suffix or result.get("reason") != "file_not_found":
        return result
    return candidate_record(vault / Path(raw + ".md"))

def obsidian_markdown_files_for_scope(vault_path, run_state):
    scope = run_state.get("scope")
    folders = run_state.get("folders") if isinstance(run_state.get("folders"), list) else []
    if scope == "file":
        selected = run_state.get("files") if isinstance(run_state.get("files"), list) else []
        files = []
        for item in selected:
            result = obsidian_file_for_vault(vault_path, item)
            if result.get("ok"):
                files.append(Path(result["path"]))
        return files
    return markdown_files_for_vault(
        vault_path,
        folders=folders if scope == "folders" else None,
        limit=5 if scope == "sample" else None,
    )

def vault_validation(value):
    if not value:
        return {"ok": False, "reason": "vault_path_required", "path": ""}
    path = Path(value).expanduser()
    try:
        path.stat()
    except FileNotFoundError:
        return {"ok": False, "reason": "vault_not_found", "path": canonical_path(path)}
    except Exception as error:
        return {
            "ok": False,
            "reason": obsidian_error_reason(error, missing_reason="vault_not_found"),
            "path": canonical_path(path),
        }
    if not path.is_dir():
        return {"ok": False, "reason": "vault_path_not_directory", "path": canonical_path(path)}
    canonical = canonical_path(path)
    broad_roots = {canonical_path(home), canonical_path(home / "Desktop"), canonical_path(home / "Documents")}
    if canonical in broad_roots:
        return {"ok": False, "reason": "vault_path_too_broad", "path": canonical}
    first_scan = markdown_scan_for_vault(canonical, limit=1)
    markdown_files = first_scan["files"]
    marker = (Path(canonical) / ".obsidian").is_dir()
    if not markdown_files and first_scan["traversalDiagnostics"]:
        observed = list(dict.fromkeys(
            item.get("reason") for item in first_scan["traversalDiagnostics"] if item.get("reason")
        ))
        reason = observed[0] if len(observed) == 1 else "vault_listing_failed"
        return {
            "ok": False,
            "reason": reason,
            "path": canonical,
            "observedReasons": observed,
            "traversalDiagnostics": first_scan["traversalDiagnostics"],
        }
    if not markdown_files:
        return {"ok": False, "reason": "no_markdown_files", "path": canonical}
    full_scan = markdown_scan_for_vault(canonical)
    count = len(full_scan["files"])
    return {
        "ok": True,
        "path": canonical,
        "hasObsidianMarker": marker,
        "estimatedFileCount": count,
        "partialAccess": bool(full_scan["traversalDiagnostics"]),
        "traversalDiagnostics": full_scan["traversalDiagnostics"],
    }

def discovery_error_record(path, error):
    reason = "permission_denied" if isinstance(error, PermissionError) else "unreadable"
    return {
        "path": str(path),
        "reason": reason,
        "message": str(error),
    }

def deduped_paths(paths):
    deduped = []
    seen = set()
    for path in paths:
        canonical = canonical_path(path)
        if canonical in seen:
            continue
        seen.add(canonical)
        deduped.append(path)
    return deduped

def obsidian_registry_candidate_paths():
    paths = []
    diagnostics = []
    registry = home / "Library/Application Support/obsidian/obsidian.json"
    try:
        data = json.loads(registry.read_text(encoding="utf-8"))
        vaults = data.get("vaults") if isinstance(data, dict) else {}
        if isinstance(vaults, dict):
            for item in vaults.values():
                if not isinstance(item, dict):
                    continue
                raw_path = item.get("path")
                if isinstance(raw_path, str) and raw_path:
                    paths.append(Path(raw_path).expanduser())
    except FileNotFoundError:
        pass
    except Exception as error:
        diagnostics.append(discovery_error_record(registry, error))
    return deduped_paths(paths), diagnostics

def fallback_obsidian_candidate_paths():
    paths = []
    diagnostics = []
    icloud_root = home / "Library/Mobile Documents/iCloud~md~obsidian/Documents"
    try:
        if icloud_root.exists() and icloud_root.is_dir():
            paths.extend(sorted(child for child in icloud_root.iterdir() if child.is_dir()))
    except Exception as error:
        diagnostics.append(discovery_error_record(icloud_root, error))
    cloud_storage = home / "Library/CloudStorage"
    try:
        if cloud_storage.exists() and cloud_storage.is_dir():
            for pattern in ("OneDrive*", "GoogleDrive*"):
                paths.extend(sorted(child for child in cloud_storage.glob(pattern) if child.is_dir()))
    except Exception as error:
        diagnostics.append(discovery_error_record(cloud_storage, error))
    paths.extend([
        home / "Dropbox",
        home / "Documents/Obsidian",
        home / "Obsidian",
    ])
    return deduped_paths(paths), diagnostics

def discover_obsidian_marker_candidates():
    candidates = {}
    diagnostics = []
    broad_roots = {
        canonical_path(home),
        canonical_path(home / "Desktop"),
        canonical_path(home / "Documents"),
        canonical_path(home / "Library/Mobile Documents"),
        canonical_path(home / "Library/Mobile Documents/iCloud~md~obsidian/Documents"),
    }
    registry_paths, registry_diagnostics = obsidian_registry_candidate_paths()
    diagnostics.extend(registry_diagnostics)
    for discovery_method, paths in [("obsidian_registry", registry_paths)]:
        for path in paths:
            try:
                if not path.is_dir() or not (path / ".obsidian").is_dir():
                    continue
            except Exception as error:
                diagnostics.append(discovery_error_record(path, error))
                continue
            vault = canonical_path(path)
            if vault in broad_roots:
                continue
            validation = vault_validation(vault)
            if validation.get("ok") and validation.get("hasObsidianMarker"):
                validation["discoveryMethod"] = discovery_method
                candidates[vault] = validation
    if not candidates:
        fallback_paths, fallback_diagnostics = fallback_obsidian_candidate_paths()
        diagnostics.extend(fallback_diagnostics)
        for path in fallback_paths:
            try:
                if not path.is_dir() or not (path / ".obsidian").is_dir():
                    continue
            except Exception as error:
                diagnostics.append(discovery_error_record(path, error))
                continue
            vault = canonical_path(path)
            if vault in broad_roots:
                continue
            validation = vault_validation(vault)
            if validation.get("ok") and validation.get("hasObsidianMarker"):
                validation["discoveryMethod"] = "bounded_fallback_path"
                candidates[vault] = validation
    return list(candidates.values()), diagnostics

def obsidian_ingest_plan_summary(run_state):
    vault = run_state.get("selectedVaultPath") or "not selected"
    scope = run_state.get("scope") or "not selected"
    folders = run_state.get("folders") if isinstance(run_state.get("folders"), list) else []
    files = run_state.get("files") if isinstance(run_state.get("files"), list) else []
    count = run_state.get("estimatedFileCount")
    count_text = str(count) if count is not None else "unknown"
    duration = run_state.get("durationClass") or duration_class(count)
    scope_detail = scope
    if scope == "whole":
        scope_detail = "whole vault"
    if scope == "folders":
        scope_detail = "folders: " + (", ".join(folders) if folders else "none")
    if scope == "file":
        scope_detail = "file: " + (", ".join(files) if files else "none")
    if scope == "sample":
        scope_detail = "recent/sample subset: up to 5 Markdown files"
    language = onboarding_language()
    if language == "ko":
        localized_scope_detail = scope_detail
        if scope == "whole":
            localized_scope_detail = "전체 vault"
        elif scope == "folders":
            localized_scope_detail = "선택한 폴더: " + (", ".join(folders) if folders else "없음")
        elif scope == "file":
            localized_scope_detail = "특정 note 파일: " + (", ".join(files) if files else "없음")
        elif scope == "sample":
            localized_scope_detail = "최근/샘플 일부: 최대 5개 Markdown 파일"
        elif scope == "skip":
            localized_scope_detail = "이번 Source Onboarding에서 Obsidian 건너뛰기"
        return textwrap.dedent(f'''
        선택된 Obsidian ingest plan입니다.
        - Vault 경로: `{vault}`
        - 선택한 범위: `{localized_scope_detail}`
        - 예상 Markdown 파일 수: `{count_text}`
        - 제외 경로/정책: `.obsidian/`, hidden directory, `__MACOSX`, Markdown이 아닌 파일, 선택된 vault 밖의 경로는 제외합니다.
        - 예상 소요 등급: `{duration}`
        - Ingest 방식: 승인된 note를 private staging에 정규화한 뒤 검증된 source ID로 GBrain import를 실행합니다.
        - 검증 계획: 같은 GBrain source scope에서 모든 예상 slug를 `gbrain get`으로 읽고 identity를 확인합니다.

        ingest를 실행하기 전에 사용자에게 명시적으로 승인받으세요. 승인하면 `zebra-source-onboarding obsidian confirm-plan --answer yes`를 실행하고, 승인하지 않으면 `zebra-source-onboarding obsidian confirm-plan --answer no`를 실행하세요.
        ''').strip()
    if language == "ja":
        localized_scope_detail = scope_detail
        if scope == "whole":
            localized_scope_detail = "vault全体"
        elif scope == "folders":
            localized_scope_detail = "選択したフォルダ: " + (", ".join(folders) if folders else "なし")
        elif scope == "file":
            localized_scope_detail = "特定のnoteファイル: " + (", ".join(files) if files else "なし")
        elif scope == "sample":
            localized_scope_detail = "最近/サンプルの一部: 最大5件のMarkdownファイル"
        elif scope == "skip":
            localized_scope_detail = "このSource OnboardingではObsidianをスキップ"
        return textwrap.dedent(f'''
        選択されたObsidian ingest planです。
        - Vaultパス: `{vault}`
        - 選択した範囲: `{localized_scope_detail}`
        - 推定Markdownファイル数: `{count_text}`
        - 除外パス/ポリシー: `.obsidian/`、hidden directory、`__MACOSX`、Markdown以外のファイル、選択されたvault外のパスは除外します。
        - 想定所要時間クラス: `{duration}`
        - Ingest方式: 承認済みnoteをprivate stagingへ正規化し、検証済みsource IDでGBrain importを実行します。
        - 検証計画: 同じGBrain source scopeですべての期待slugを`gbrain get`し、identityを確認します。

        ingestを実行する前にユーザーから明示的な承認を得てください。承認されたら`zebra-source-onboarding obsidian confirm-plan --answer yes`を実行し、承認されなければ`zebra-source-onboarding obsidian confirm-plan --answer no`を実行してください。
        ''').strip()
    return textwrap.dedent(f'''
    Resolved Obsidian ingest plan:
    - Vault path: `{vault}`
    - Selected scope: `{scope_detail}`
    - Approximate Markdown file count: `{count_text}`
    - Excluded paths/policies: `.obsidian/`, hidden directories, `__MACOSX`, non-Markdown files, and paths outside the selected vault.
    - Expected duration class: `{duration}`
    - Ingest mode: normalize approved notes in private staging, then run GBrain import with the verified source ID.
    - Verification plan: run `gbrain get` for every expected slug in the same GBrain source scope and verify identity.

    Ask the user for explicit approval before running ingest. If approved, run `zebra-source-onboarding obsidian confirm-plan --answer yes`. If not approved, run `zebra-source-onboarding obsidian confirm-plan --answer no`.
    ''').strip()



def gbrain_target_paths(state):
    paths = set()
    entry = state.get("entryContext") if isinstance(state.get("entryContext"), dict) else {}
    for key in ("gbrainWriteTargetPath", "gbrainTargetPath", "selectedVaultPath"):
        path = existing_directory(entry.get(key) or "")
        if path:
            paths.add(path)
    env_path = existing_directory(gbrain_write_target_path)
    if env_path:
        paths.add(env_path)
    _, resolved_target_path, _ = resolve_gbrain_target()
    if resolved_target_path:
        paths.add(resolved_target_path)
    return paths

def is_gbrain_target_path(state, value):
    path = existing_directory(value)
    return bool(path and path in gbrain_target_paths(state))

def start_obsidian_from_next(state):
    progress = ensure_progress(state)
    rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
    row = rows.get("obsidian") if isinstance(rows.get("obsidian"), dict) else {}
    playbook = obsidian_playbook()
    if row.get("playbookID") == playbook["id"] and row.get("status") in {"running", "attention"}:
        step_id = row.get("playbookStepID") if row.get("playbookStepID") in playbook["steps"] else playbook["initialStepID"]
        payload = summary(state)
        payload.update(source_next_prompt_payload(state, "obsidian", step_id))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    discovered, discovery_diagnostics = discover_obsidian_marker_candidates()
    if len(discovered) == 1:
        validation = discovered[0]
        run_state = load_source_run_state("obsidian")
        run_state.update({
            "selectedVaultPath": validation["path"],
            "hasObsidianMarker": validation.get("hasObsidianMarker"),
            "estimatedFileCount": validation.get("estimatedFileCount"),
            "discoveryMethod": validation.get("discoveryMethod") or "single_obsidian_marker_candidate",
            "updatedAt": now(),
        })
        if discovery_diagnostics:
            run_state["unreadableCandidateRoots"] = discovery_diagnostics
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "running",
            "smoke",
            "smoke_read",
            run_state_path=run_path,
            result_summary="Single Obsidian vault candidate selected from " + str(validation.get("discoveryMethod") or "automatic_discovery") + " with " + str(validation.get("estimatedFileCount")) + " Markdown files.",
        )
        save_json(state)
        payload = {"ok": True, "path": validation["path"], "estimatedFileCount": validation.get("estimatedFileCount")}
        payload.update(source_next_prompt_payload(state, "obsidian", "smoke_read"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    if len(discovered) > 1:
        run_state = load_source_run_state("obsidian")
        run_state.update({
            "candidateVaultPaths": [item.get("path") for item in discovered],
            "discoveryMethod": discovered[0].get("discoveryMethod") or "multiple_obsidian_marker_candidates",
            "updatedAt": now(),
        })
        if discovery_diagnostics:
            run_state["unreadableCandidateRoots"] = discovery_diagnostics
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "attention",
            "preflight",
            "confirm_vault_if_needed",
            attention_reason="multiple_obsidian_vault_candidates",
            run_state_path=run_path,
        )
        save_json(state)
        payload = summary(state)
        payload["ok"] = False
        payload["reason"] = "multiple_obsidian_vault_candidates"
        payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if discovery_diagnostics:
        run_state = load_source_run_state("obsidian")
        run_state.update({
            "unreadableCandidateRoots": discovery_diagnostics,
            "updatedAt": now(),
        })
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "attention",
            "preflight",
            "discover_vault",
            attention_reason="obsidian_candidate_discovery_unreadable",
            run_state_path=run_path,
        )
        save_json(state)
        payload = summary(state)
        payload["ok"] = False
        payload["reason"] = "obsidian_candidate_discovery_unreadable"
        payload.update(source_next_prompt_payload(state, "obsidian", "discover_vault"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    state = set_obsidian_row_state(state, "running", "preflight", "discover_vault")
    save_json(state)
    payload = summary(state)
    payload.update(source_next_prompt_payload(state, "obsidian", "discover_vault"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def obsidian_verify_vault():
    path = single_flag_value("--path")
    state = load_or_create_state()
    if is_gbrain_target_path(state, path):
        run_state = load_source_run_state("obsidian")
        run_state.update({
            "rejectedCandidateReason": "gbrain_target_is_not_obsidian_source_vault",
            "updatedAt": now(),
        })
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "attention",
            "preflight",
            "confirm_vault_if_needed",
            attention_reason="gbrain_target_is_not_obsidian_source_vault",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "gbrain_target_is_not_obsidian_source_vault"}
        payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    validation = vault_validation(path)
    if validation.get("ok"):
        run_state = load_source_run_state("obsidian")
        run_state.update({
            "selectedVaultPath": validation["path"],
            "hasObsidianMarker": validation.get("hasObsidianMarker"),
            "estimatedFileCount": validation.get("estimatedFileCount"),
            "updatedAt": now(),
        })
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "running",
            "smoke",
            "smoke_read",
            run_state_path=run_path,
            result_summary="Obsidian vault path validated with " + str(validation.get("estimatedFileCount")) + " Markdown files.",
        )
        save_json(state)
        payload = {"ok": True, "path": validation["path"], "estimatedFileCount": validation.get("estimatedFileCount")}
        payload.update(source_next_prompt_payload(state, "obsidian", "smoke_read"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    run_state = load_source_run_state("obsidian")
    run_state.update({"candidateVaultPath": path, "updatedAt": now()})
    run_path = save_source_run_state("obsidian", run_state)
    state = set_obsidian_row_state(
        state,
        "attention",
        "preflight",
        "confirm_vault_if_needed",
        attention_reason=validation.get("reason") or "invalid_vault_path",
        run_state_path=run_path,
    )
    save_json(state)
    payload = {"ok": False, "path": validation.get("path") or path, "reason": validation.get("reason")}
    payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 1

def obsidian_smoke_read():
    state = load_or_create_state()
    run_state = load_source_run_state("obsidian")
    vault = run_state.get("selectedVaultPath")
    validation = vault_validation(vault)
    if not validation.get("ok"):
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "attention",
            "preflight",
            "confirm_vault_if_needed",
            attention_reason=validation.get("reason") or "vault_path_required",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": validation.get("reason") or "vault_path_required"}
        payload.update(source_next_prompt_payload(state, "obsidian", "confirm_vault_if_needed"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    scan = markdown_scan_for_vault(vault, limit=5)
    files = scan["files"]
    readable = None
    diagnostics = []
    for path in files:
        try:
            _ = path.read_text(encoding="utf-8", errors="replace")[:2048]
            readable = path
            break
        except Exception as error:
            diagnostics.append(obsidian_error_diagnostic(Path(vault), path, error))
            continue
    if not readable:
        observed_reasons = list(dict.fromkeys(
            item.get("reason") for item in diagnostics if item.get("reason")
        ))
        suspected_cause = None
        if (
            "read_temporarily_unavailable" in observed_reasons
            and "/Library/Mobile Documents/" in str(Path(vault))
        ):
            suspected_cause = "icloud_not_materialized"
        run_state.update({
            "smokeReadStatus": "inconclusive",
            "attemptedFileCount": len(diagnostics),
            "observedReasons": observed_reasons,
            "sampleDiagnostics": diagnostics,
            "partialAccess": bool(scan["traversalDiagnostics"]),
            "traversalDiagnostics": scan["traversalDiagnostics"],
            "updatedAt": now(),
        })
        if suspected_cause:
            run_state["suspectedCause"] = suspected_cause
        else:
            run_state.pop("suspectedCause", None)
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "attention",
            "smoke",
            "smoke_read",
            attention_reason="smoke_read_inconclusive",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {
            "ok": False,
            "reason": "smoke_read_inconclusive",
            "attemptedFileCount": len(diagnostics),
            "observedReasons": observed_reasons,
            "sampleDiagnostics": diagnostics,
            "partialAccess": bool(scan["traversalDiagnostics"]),
            "retryable": True,
        }
        if scan["traversalDiagnostics"]:
            payload["traversalDiagnostics"] = scan["traversalDiagnostics"]
        if suspected_cause:
            payload["suspectedCause"] = suspected_cause
        payload.update(source_next_prompt_payload(state, "obsidian", "smoke_read"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    relative = str(readable.relative_to(Path(vault)))
    observed_reasons = list(dict.fromkeys(
        item.get("reason") for item in diagnostics if item.get("reason")
    ))
    partial_access = bool(diagnostics or scan["traversalDiagnostics"])
    run_state.update({
        "smokeReadStatus": "passed",
        "smokeReadSamplePath": relative,
        "attemptedFileCount": len(diagnostics) + 1,
        "estimatedFileCount": validation.get("estimatedFileCount"),
        "partialAccess": partial_access,
        "sampleWarnings": diagnostics,
        "observedReasons": observed_reasons,
        "traversalDiagnostics": scan["traversalDiagnostics"],
        "updatedAt": now(),
    })
    run_path = save_source_run_state("obsidian", run_state)
    state = set_obsidian_row_state(
        state,
        "running",
        "ingest",
        "choose_ingest_scope",
        run_state_path=run_path,
        result_summary="Obsidian smoke read passed for " + relative,
    )
    save_json(state)
    payload = {
        "ok": True,
        "samplePath": relative,
        "attemptedFileCount": len(diagnostics) + 1,
        "estimatedFileCount": validation.get("estimatedFileCount"),
        "partialAccess": partial_access,
        "sampleWarnings": diagnostics,
        "observedReasons": observed_reasons,
    }
    if scan["traversalDiagnostics"]:
        payload["traversalDiagnostics"] = scan["traversalDiagnostics"]
    payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def obsidian_choose_scope():
    scope = single_flag_value("--scope")
    folders = parse_flag_value("--folder")
    selected_file = single_flag_value("--file")
    if scope not in {"whole", "folders", "file", "sample", "skip"}:
        print("--scope must be whole, folders, file, sample, or skip", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("obsidian")
    vault = run_state.get("selectedVaultPath")
    if scope == "skip":
        run_state.update({"scope": "skip", "updatedAt": now()})
        state = mark_source_completion_pending(
            state,
            "obsidian",
            "skipped",
            "Obsidian skipped for this Source Onboarding session.",
            run_state=run_state,
        )
        save_json(state)
        payload = {"ok": True, "skipped": True}
        payload.update(source_next_prompt_payload(state, "obsidian", "complete"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 0
    if scope == "folders" and not folders:
        print("--folder is required when --scope folders", file=sys.stderr)
        return 2
    relative_files = []
    if scope == "file":
        validation = obsidian_file_for_vault(vault, selected_file)
        if not validation.get("ok"):
            print(str(validation.get("reason") or "invalid_file_path"), file=sys.stderr)
            return 2
        relative_files = [validation["relative"]]
    run_state.update({
        "scope": scope,
        "folders": folders if scope == "folders" else [],
        "files": relative_files,
    })
    files = obsidian_markdown_files_for_scope(vault, run_state)
    total = len(markdown_files_for_vault(vault, folders=folders)) if scope == "folders" else len(files)
    run_state.update({
        "scope": scope,
        "estimatedFileCount": total,
        "durationClass": duration_class(total),
        "planConfirmed": False,
        "updatedAt": now(),
    })
    run_path = save_source_run_state("obsidian", run_state)
    state = set_obsidian_row_state(
        state,
        "running",
        "ingest",
        "confirm_ingest_plan",
        run_state_path=run_path,
        result_summary="Obsidian ingest scope selected: " + scope,
    )
    save_json(state)
    payload = {"ok": True, "scope": scope, "folders": folders, "estimatedFileCount": total, "durationClass": duration_class(total)}
    payload.update(source_next_prompt_payload(state, "obsidian", "confirm_ingest_plan"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def obsidian_confirm_plan():
    answer = single_flag_value("--answer").strip().lower()
    if answer not in {"yes", "y", "no", "n"}:
        print("--answer must be yes or no", file=sys.stderr)
        return 2
    state = load_or_create_state()
    run_state = load_source_run_state("obsidian")
    if answer in {"no", "n"}:
        run_state.update({"planConfirmed": False, "updatedAt": now()})
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(
            state,
            "attention",
            "ingest",
            "choose_ingest_scope",
            attention_reason="ingest_plan_rejected",
            run_state_path=run_path,
        )
        save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_rejected"}
        payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    if not run_state.get("scope") or run_state.get("scope") == "skip":
        payload = {"ok": False, "reason": "ingest_scope_required"}
        state = set_obsidian_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="ingest_scope_required")
        save_json(state)
        payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({"planConfirmed": True, "confirmedAt": now(), "updatedAt": now()})
    run_path = save_source_run_state("obsidian", run_state)
    state = set_obsidian_row_state(
        state,
        "running",
        "ingest",
        "ingest_markdown",
        run_state_path=run_path,
        result_summary="Obsidian ingest plan confirmed.",
    )
    save_json(state)
    payload = {"ok": True, "scope": run_state.get("scope"), "estimatedFileCount": run_state.get("estimatedFileCount")}
    payload.update(source_next_prompt_payload(state, "obsidian", "ingest_markdown"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0

def obsidian_ingest():
    state = load_or_create_state()
    run_state = load_source_run_state("obsidian")
    if not run_state.get("planConfirmed"):
        state = set_obsidian_row_state(state, "attention", "ingest", "confirm_ingest_plan", attention_reason="ingest_plan_unconfirmed")
        save_json(state)
        payload = {"ok": False, "reason": "ingest_plan_unconfirmed"}
        payload.update(source_next_prompt_payload(state, "obsidian", "confirm_ingest_plan"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    vault = run_state.get("selectedVaultPath")
    scope = run_state.get("scope")
    if scope == "file":
        files = obsidian_markdown_files_for_scope(vault, run_state)
        traversal_diagnostics = []
    else:
        scan = markdown_scan_for_vault(
            vault,
            folders=run_state.get("folders") if scope == "folders" else None,
            limit=5 if scope == "sample" else None,
        )
        files = scan["files"]
        traversal_diagnostics = scan["traversalDiagnostics"]
    if scope == "file" and not files:
        state = set_obsidian_row_state(state, "attention", "ingest", "choose_ingest_scope", attention_reason="selected_file_unavailable")
        save_json(state)
        payload = {"ok": False, "reason": "selected_file_unavailable"}
        payload.update(source_next_prompt_payload(state, "obsidian", "choose_ingest_scope"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    attempt_id = str(uuid.uuid4())
    records = []
    read_failures = []
    for source_path in files:
        try:
            relative = str(source_path.relative_to(Path(vault)))
            body = source_path.read_text(encoding="utf-8")
            records.append({
                "connectorID": "obsidian",
                "logicalRecordID": relative,
                "slug": deterministic_slug("obsidian", str(Path(relative).with_suffix(""))),
                "markdown": body,
                "originURI": "obsidian://" + relative,
            })
        except Exception as error:
            read_failures.append(obsidian_error_diagnostic(Path(vault), source_path, error))
    acquisition = {
        "discoveredCount": int(run_state.get("estimatedFileCount") or len(files)),
        "selectedCount": len(files),
        "normalizedCount": len(records),
        "failedCount": len(read_failures),
        "diagnosticCount": len(traversal_diagnostics),
        "cancelled": False,
        "complete": not read_failures and not traversal_diagnostics and len(records) == len(files),
    }
    receipt = submit_connector_ingestion("obsidian", records, acquisition, state, attempt_id, gbrain_state_path)
    run_state.update({
        "ingestAttemptID": attempt_id,
        "acquisitionReceipt": acquisition,
        "ingestReceipt": receipt,
        "selectedFileCount": len(files),
        "successfullyReadFileCount": len(records),
        "failedReadFileCount": len(read_failures),
        "acquisitionDiagnostics": (traversal_diagnostics + read_failures)[:8],
        "completionReportPending": False,
        "updatedAt": now(),
    })
    run_path = save_source_run_state("obsidian", run_state)
    projection = ingest_projection(receipt)
    if not projection["complete"]:
        state = set_obsidian_row_state(state, "attention", "verify", "verify_readback", attention_reason=projection["attentionReason"], run_state_path=run_path)
        save_json(state)
        payload = {"ok": False, "reason": projection["attentionReason"], "acquisition": acquisition}
        payload.update(source_next_prompt_payload(state, "obsidian", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    state = set_obsidian_row_state(state, "running", "verify", "verify_readback", run_state_path=run_path, result_summary="GBrain ingested and read back " + str(len(records)) + " Obsidian notes.")
    save_json(state)
    payload = {"ok": True, "ingestAttemptID": attempt_id, "ingestedFileCount": len(records), "verifiedRecordCount": receipt.get("verifiedRecordCount")}
    payload.update(source_next_prompt_payload(state, "obsidian", "verify_readback"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


def obsidian_verify_readback():
    state = load_or_create_state()
    run_state = load_source_run_state("obsidian")
    receipt = run_state.get("ingestReceipt") if isinstance(run_state.get("ingestReceipt"), dict) else {}
    projection = ingest_projection(receipt)
    if not projection["complete"]:
        run_path = save_source_run_state("obsidian", run_state)
        state = set_obsidian_row_state(state, "attention", "verify", "verify_readback", attention_reason=projection["attentionReason"] or "readbackMissing", run_state_path=run_path)
        save_json(state)
        payload = {"ok": False, "reason": projection["attentionReason"] or "readbackMissing"}
        payload.update(source_next_prompt_payload(state, "obsidian", "verify_readback"))
        print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
        return 1
    run_state.update({"readbackStatus": "passed", "verifiedAt": now(), "updatedAt": now()})
    state = mark_source_completion_pending(state, "obsidian", "checked", "GBrain ingest/readback verified for " + str(receipt.get("verifiedRecordCount") or 0) + " Obsidian notes.", run_state=run_state)
    save_json(state)
    payload = {"ok": True, "readbackStatus": "passed", "verifiedRecordCount": receipt.get("verifiedRecordCount")}
    payload.update(source_next_prompt_payload(state, "obsidian", "complete"))
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


def obsidian_command():
    if not args:
        print("obsidian requires a subcommand", file=sys.stderr)
        return 2
    pending_code = reject_if_completion_report_pending("obsidian")
    if pending_code is not None:
        return pending_code
    subcommand = args[0]
    if subcommand == "verify-vault":
        return obsidian_verify_vault()
    if subcommand == "smoke-read":
        return obsidian_smoke_read()
    if subcommand == "choose-scope":
        return obsidian_choose_scope()
    if subcommand == "confirm-plan":
        return obsidian_confirm_plan()
    if subcommand == "ingest":
        return obsidian_ingest()
    if subcommand == "verify-readback":
        return obsidian_verify_readback()
    print("unknown obsidian subcommand: " + subcommand, file=sys.stderr)
    return 2
