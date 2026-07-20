import Foundation

/// Installs the Zebra-owned CLI facade for interactive terminal tasks.
///
/// Consumers submit an allowlisted task. The facade persists a typed request,
/// then uses the cmux CLI bundled with the current Zebra terminal solely as the
/// transport for creating a focused terminal surface in the current workspace.
/// Raw commands and arbitrary executables are never accepted from callers.
enum ZebraInteractiveTerminalRunner {
    static let executableName = "zebra-interactive-terminal-runner"

    static func install(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let url = directory.appendingPathComponent(executableName, isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try helperScript.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }

    static let helperScript = #"""
    #!/bin/sh
    set -eu

    PYTHON_BIN="/usr/bin/python3"
    if [ ! -x "$PYTHON_BIN" ]; then
      echo "python3 is required for zebra-interactive-terminal-runner" >&2
      exit 69
    fi

    PAYLOAD="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/zebra-interactive-terminal-runner.XXXXXX")"
    trap '/bin/rm -f "$PAYLOAD"' EXIT HUP INT TERM
    /bin/chmod 600 "$PAYLOAD"
    /bin/cat > "$PAYLOAD" <<'PY'
    import datetime
    import fcntl
    import hashlib
    import json
    import os
    import pathlib
    import re
    import subprocess
    import sys
    import tempfile
    import time

    SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
    TASKS = {
        "fixture-success": {"sources": None},
        "fixture-failure": {"sources": None},
        "fixture-cancel": {"sources": None},
        "source-onboarding-homebrew-install": {"sources": {"apple-notes", "apple-reminders"}},
    }

    def now():
        return datetime.datetime.now(datetime.timezone.utc).isoformat()

    def state_root():
        override = os.environ.get("ZEBRA_INTERACTIVE_TERMINAL_RUNNER_STATE_DIR", "").strip()
        if override:
            return pathlib.Path(override)
        return pathlib.Path.home() / "Library/Application Support/zebra/interactive-terminal-runner"

    def atomic_json(path, payload, exclusive=False):
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        data = json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
        if exclusive:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            return
        fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def load_json(path):
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def fail(message, code=64):
        print(json.dumps({"ok": False, "error": message}, sort_keys=True), file=sys.stderr)
        raise SystemExit(code)

    def parse_options(arguments, allowed):
        result = {}
        index = 0
        while index < len(arguments):
            option = arguments[index]
            if option not in allowed or index + 1 >= len(arguments):
                fail("unsupported or incomplete option")
            result[option] = arguments[index + 1]
            index += 2
        return result

    def safe_identifier(value, label, required=True):
        value = (value or "").strip()
        if not value and not required:
            return ""
        if not SAFE_ID.fullmatch(value):
            fail("invalid " + label)
        return value

    def request_id_for(kind, run_id):
        digest = hashlib.sha256((kind + "\0" + run_id).encode("utf-8")).hexdigest()[:32]
        return "zitr-" + digest

    def request_path(request_id):
        return state_root() / "requests" / (request_id + ".json")

    def receipt_path(request_id):
        return state_root() / "receipts" / (request_id + ".json")

    def write_receipt(request_id, status, **extra):
        payload = {"schemaVersion": 1, "requestID": request_id, "status": status, "updatedAt": now()}
        payload.update(extra)
        atomic_json(receipt_path(request_id), payload)
        return payload

    def update_receipt(request_id, **extra):
        path = receipt_path(request_id)
        payload = load_json(path) if path.exists() else {
            "schemaVersion": 1, "requestID": request_id, "status": "failed"
        }
        payload.update(extra)
        payload["updatedAt"] = now()
        atomic_json(path, payload)
        return payload

    def record_launch(request_id, surface_id, workspace_id):
        path = receipt_path(request_id)
        existing = load_json(path) if path.exists() else None
        if existing and existing.get("status") in {"running", "succeeded", "failed", "canceled"}:
            existing["surfaceID"] = existing.get("surfaceID") or surface_id
            existing["workspaceID"] = workspace_id
            existing["updatedAt"] = now()
            atomic_json(path, existing)
            return existing
        return write_receipt(request_id, "launched", surfaceID=surface_id, workspaceID=workspace_id)

    def wait_for_completion(request_id):
        if os.environ.get("ZEBRA_INTERACTIVE_TERMINAL_RUNNER_WAIT", "1") == "0":
            return None
        raw_timeout = os.environ.get("ZEBRA_INTERACTIVE_TERMINAL_RUNNER_WAIT_TIMEOUT", "86400")
        try:
            timeout = max(1.0, float(raw_timeout))
        except ValueError:
            fail("invalid wait timeout")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            path = receipt_path(request_id)
            receipt = load_json(path) if path.exists() else None
            if receipt and receipt.get("status") in {"succeeded", "failed", "canceled"}:
                return receipt
            time.sleep(0.1)
        return write_receipt(request_id, "failed", error="terminal_task_timeout")

    def restore_origin_focus(request_id, request, cli, socket):
        workspace = request.get("originWorkspaceID", "")
        surface = request.get("originSurfaceID", "")
        if not workspace or not surface:
            return update_receipt(request_id, originFocusStatus="unavailable")
        params = {"workspace_id": workspace, "surface_id": surface}
        environment = os.environ.copy()
        environment["CMUX_SOCKET_PATH"] = socket
        completed = subprocess.run(
            [cli, "rpc", "surface.focus", json.dumps(params, separators=(",", ":"))],
            text=True,
            capture_output=True,
            env=environment,
        )
        if completed.returncode == 0:
            return update_receipt(request_id, originFocusStatus="focused")
        return update_receipt(request_id, originFocusStatus="failed", originFocusError="surface_focus_failed")

    def shell_quote(value):
        return "'" + value.replace("'", "'\\''") + "'"

    def receipt_is_stale(receipt):
        if receipt.get("status") not in {"launched", "running"}:
            return False
        raw_seconds = os.environ.get("ZEBRA_INTERACTIVE_TERMINAL_RUNNER_STALE_SECONDS", "86400")
        try:
            stale_seconds = max(0.0, float(raw_seconds))
            updated = datetime.datetime.fromisoformat(receipt.get("updatedAt", ""))
            if updated.tzinfo is None:
                updated = updated.replace(tzinfo=datetime.timezone.utc)
        except (TypeError, ValueError):
            return True
        return (datetime.datetime.now(datetime.timezone.utc) - updated).total_seconds() >= stale_seconds

    def start(arguments):
        options = parse_options(arguments, {"--task", "--source", "--run-id", "--request-id"})
        kind = safe_identifier(options.get("--task"), "task")
        if kind not in TASKS:
            fail("unsupported task")
        run_id = safe_identifier(options.get("--run-id"), "run id")
        source = safe_identifier(options.get("--source"), "source", required=False)
        sources = TASKS[kind]["sources"]
        if sources is None and source:
            fail("source is not valid for task")
        if sources is not None and source not in sources:
            fail("unsupported source")
        request_id = safe_identifier(
            options.get("--request-id") or request_id_for(kind, run_id),
            "request id",
        )
        request = {
            "schemaVersion": 1,
            "id": request_id,
            "kind": kind,
            "payload": {"source": source} if source else {},
            "originRunID": run_id,
            "originWorkspaceID": os.environ.get("CMUX_WORKSPACE_ID", "").strip(),
            "originSurfaceID": os.environ.get("CMUX_SURFACE_ID", "").strip(),
            "requestedAt": now(),
        }
        path = request_path(request_id)
        duplicate = False
        try:
            atomic_json(path, request, exclusive=True)
        except FileExistsError:
            duplicate = True
            existing = load_json(path)
            if existing.get("kind") != kind or existing.get("originRunID") != run_id or existing.get("payload") != request["payload"]:
                fail("request id collision", 73)
            receipt = load_json(receipt_path(request_id)) if receipt_path(request_id).exists() else None
            if receipt and receipt.get("status") != "launch_failed" and not receipt_is_stale(receipt):
                print(json.dumps({"ok": True, "duplicate": True, "request": existing, "receipt": receipt}, sort_keys=True))
                return 0
            if receipt_is_stale(receipt or {}):
                write_receipt(request_id, "launch_failed", error="stale_terminal_task")
            request = existing

        lock_path = state_root() / "locks" / (request_id + ".lock")
        lock_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        lock_handle = lock_path.open("a+")
        os.chmod(lock_path, 0o600)
        try:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(json.dumps({"ok": True, "duplicate": True, "pending": True, "request": request}, sort_keys=True))
            return 0

        cli = os.environ.get("CMUX_BUNDLED_CLI_PATH", "").strip()
        socket = os.environ.get("CMUX_SOCKET_PATH", "").strip()
        workspace = os.environ.get("CMUX_WORKSPACE_ID", "").strip()
        if not cli or not os.path.isfile(cli) or not os.access(cli, os.X_OK):
            write_receipt(request_id, "launch_failed", error="zebra_cli_unavailable")
            fail("Zebra bundled terminal CLI is unavailable", 69)
        if not socket:
            write_receipt(request_id, "launch_failed", error="zebra_socket_unavailable")
            fail("Zebra terminal socket is unavailable", 69)
        if not workspace:
            write_receipt(request_id, "launch_failed", error="origin_workspace_unavailable")
            fail("origin Zebra workspace is unavailable", 69)

        runner_executable = os.environ.get("ZEBRA_INTERACTIVE_TERMINAL_RUNNER_EXECUTABLE", "").strip()
        if not runner_executable:
            write_receipt(request_id, "launch_failed", error="runner_executable_unavailable")
            fail("Zebra terminal runner executable is unavailable", 69)
        initial_command = shell_quote(os.path.realpath(runner_executable)) + " execute --request " + shell_quote(request_id)
        params = {"workspace_id": workspace, "focus": True, "initial_command": initial_command}
        pane = os.environ.get("CMUX_PANE_ID", "").strip()
        if pane:
            params["pane_id"] = pane
        completed = subprocess.run(
            [cli, "rpc", "surface.create", json.dumps(params, separators=(",", ":"))],
            text=True,
            capture_output=True,
            env=os.environ.copy(),
        )
        if completed.returncode != 0:
            write_receipt(request_id, "launch_failed", error="terminal_launch_failed")
            fail("Zebra terminal creation failed", 70)
        try:
            response = json.loads(completed.stdout)
        except Exception:
            write_receipt(request_id, "launch_failed", error="invalid_terminal_response")
            fail("Zebra terminal returned an invalid response", 70)
        result = response.get("result") if isinstance(response, dict) and isinstance(response.get("result"), dict) else response
        surface_id = result.get("surface_id") if isinstance(result, dict) else None
        if not isinstance(surface_id, str) or not surface_id:
            write_receipt(request_id, "launch_failed", error="missing_surface_id")
            fail("Zebra terminal response did not include a surface", 70)
        receipt = record_launch(request_id, surface_id, workspace)
        completed_receipt = wait_for_completion(request_id)
        if completed_receipt is not None:
            receipt = completed_receipt
        if receipt.get("status") == "succeeded":
            receipt = restore_origin_focus(request_id, request, cli, socket)
        succeeded = receipt.get("status") not in {"failed", "canceled"}
        print(json.dumps({"ok": succeeded, "duplicate": duplicate, "request": request, "receipt": receipt}, sort_keys=True))
        return 0 if succeeded else 1

    def execute(arguments):
        options = parse_options(arguments, {"--request"})
        request_id = safe_identifier(options.get("--request"), "request id")
        path = request_path(request_id)
        if not path.exists():
            fail("request not found", 66)
        request = load_json(path)
        kind = request.get("kind")
        if kind not in TASKS:
            fail("unsupported stored task")
        write_receipt(request_id, "running", surfaceID=os.environ.get("CMUX_SURFACE_ID", ""))

        if kind == "fixture-success":
            returncode = 0
        elif kind == "fixture-failure":
            returncode = 42
        elif kind == "fixture-cancel":
            returncode = 130
        else:
            source = request.get("payload", {}).get("source", "")
            if source not in TASKS[kind]["sources"]:
                fail("invalid stored source")
            runner_executable = os.environ.get("ZEBRA_INTERACTIVE_TERMINAL_RUNNER_EXECUTABLE", "").strip()
            helper = pathlib.Path(runner_executable).resolve().parent / "zebra-source-onboarding"
            if not helper.is_file() or not os.access(helper, os.X_OK):
                returncode = 69
            else:
                returncode = subprocess.call([str(helper), "install-homebrew", "--source", source])

        status = "succeeded" if returncode == 0 else ("canceled" if returncode == 130 else "failed")
        receipt = write_receipt(request_id, status, exitCode=returncode)
        print(json.dumps({"ok": returncode == 0, "receipt": receipt}, sort_keys=True))
        if returncode == 0:
            return 0
        language = os.environ.get("ZEBRA_ONBOARDING_LANGUAGE", "en").strip().lower()
        status_command = "zebra-interactive-terminal-runner status --request " + request_id
        if language == "ko":
            message = "작업에 실패했습니다. 이 terminal은 확인을 위해 열어 둡니다. 상태 확인: " + status_command + ". 닫으려면 exit를 입력하세요."
        elif language == "ja":
            message = "タスクに失敗しました。確認のため、この terminal を開いたままにします。状態確認: " + status_command + "。閉じるには exit を入力してください。"
        else:
            message = "Task failed. This terminal remains open for inspection. Check status: " + status_command + ". Type exit to close it."
        print("\n" + message + "\n", file=sys.stderr, flush=True)
        if os.environ.get("ZEBRA_INTERACTIVE_TERMINAL_RUNNER_KEEP_SHELL", "1") == "0":
            return returncode
        shell = os.environ.get("SHELL", "/bin/zsh")
        os.execv(shell, [shell, "-l"])

    def status(arguments):
        options = parse_options(arguments, {"--request"})
        request_id = safe_identifier(options.get("--request"), "request id")
        path = receipt_path(request_id)
        print(json.dumps({"ok": True, "receipt": load_json(path) if path.exists() else None}, sort_keys=True))
        return 0

    if len(sys.argv) < 2:
        fail("usage: zebra-interactive-terminal-runner <start|execute|status>")
    command = sys.argv[1]
    if command == "start":
        raise SystemExit(start(sys.argv[2:]))
    if command == "execute":
        raise SystemExit(execute(sys.argv[2:]))
    if command == "status":
        raise SystemExit(status(sys.argv[2:]))
    fail("unsupported command")
    PY
    ZEBRA_INTERACTIVE_TERMINAL_RUNNER_EXECUTABLE="$0" "$PYTHON_BIN" "$PAYLOAD" "$@"
    """#
}
