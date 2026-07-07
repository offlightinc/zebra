import Foundation

struct ZebraSourceReplayRunner {
    private let onboardingDirectory: URL
    private let fileManager: FileManager

    init(
        onboardingDirectory: URL = ZebraGBrainOnboardingStore.onboardingDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.onboardingDirectory = onboardingDirectory
        self.fileManager = fileManager
    }

    func installHelperScript() -> URL? {
        let directory = onboardingDirectory.appendingPathComponent("bin", isDirectory: true)
        let url = directory.appendingPathComponent("zebra-source-replay", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.helperScript.write(to: url, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try installReplayData()
            return url
        } catch {
            return nil
        }
    }

    private func installReplayData() throws {
        try installReplayResources(
            subdirectory: "SourceReplayFixtures",
            destination: onboardingDirectory
                .appendingPathComponent("source-replay", isDirectory: true)
                .appendingPathComponent("fixtures", isDirectory: true),
            fallbackFiles: Self.fallbackFixtures
        )
        try installReplayResources(
            subdirectory: "SourceReplayScenarios",
            destination: onboardingDirectory
                .appendingPathComponent("source-replay", isDirectory: true)
                .appendingPathComponent("scenarios", isDirectory: true),
            fallbackFiles: Self.fallbackScenarios
        )
    }

    private func installReplayResources(
        subdirectory: String,
        destination: URL,
        fallbackFiles: [String: String]
    ) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for (filename, fallback) in fallbackFiles {
            let output = destination.appendingPathComponent(filename, isDirectory: false)
            if let resource = Bundle.module.url(
                forResource: filename.replacingOccurrences(of: ".json", with: ""),
                withExtension: "json",
                subdirectory: subdirectory
            ) {
                if fileManager.fileExists(atPath: output.path) {
                    try fileManager.removeItem(at: output)
                }
                try fileManager.copyItem(at: resource, to: output)
            } else {
                try fallback.write(to: output, atomically: true, encoding: .utf8)
            }
        }
    }

    private static let fallbackScenarios = [
        "apple-notes.memo-cli.baseline.json": """
        {
          "schemaVersion": 1,
          "kind": "source-replay-scenario",
          "id": "apple-notes.memo-cli.baseline",
          "source": "apple-notes",
          "playbookID": "apple-notes.memo-cli",
          "playbookVersion": "v1",
          "fixture": "apple-notes.memo-cli.baseline.v1.json",
          "defaultRuntime": "selected",
          "defaultRunMode": "run",
          "defaultBatchID": "apple-notes-memo-cli-baseline",
          "defaultMaxTurns": 12,
          "defaultTimeout": 180,
          "preflightCommands": [
            {
              "id": "apple-notes.memo-automation-access",
              "argv": ["memo", "notes", "-fl"],
              "timeout": 300,
              "expectedExitCodes": [0],
              "failureReason": "notes_automation_permission_required",
              "prompt": "If macOS asks for Apple Notes or Automation access, approve it and let this command finish before the replay runtime starts."
            }
          ],
          "artifactScan": {
            "enabled": true,
            "excludeRuntimeHome": true
          }
        }
        """,
    ]

    private static let fallbackFixtures = [
        "apple-notes.memo-cli.baseline.v1.json": """
        {
          "schemaVersion": 1,
          "kind": "source-replay-fixture",
          "source": "apple-notes",
          "playbookID": "apple-notes.memo-cli",
          "playbookVersion": "v1",
          "purpose": "Apple Notes Source Onboarding baseline replay using the memo CLI and a small sample ingest scope.",
          "initialPrompt": "Run Zebra Source Onboarding for Apple Notes using the installed zebra-source-onboarding helper. Start by running `zebra-source-onboarding intake --raw \\"Apple Notes\\" --candidate \\"apple-notes=Apple Notes\\"`, then `zebra-source-onboarding confirm --answer yes`, then `zebra-source-onboarding next`. After every helper command, continue only from the JSON `nextPrompt` and current `nextPlaybookStepID`. When user input is needed, ask clearly; this replay fixture will answer by playbook step.",
          "interventions": [
            {
              "playbookStepID": "choose_ingest_scope",
              "matcher": {
                "type": "regex",
                "pattern": "(?i)(ingest scope|folder|search query|selected note|small sample|skip apple notes|범위|샘플|건너뛰기)"
              },
              "answer": "sample",
              "approval": "storable",
              "secretPolicy": "forbid_raw_secret"
            },
            {
              "playbookStepID": "confirm_ingest_plan",
              "matcher": {
                "type": "regex",
                "pattern": "(?i)(confirm.*plan|explicit approval|approved scope|ingest plan|승인|시작)"
              },
              "answer": "yes",
              "approval": "requires_human_approval",
              "secretPolicy": "forbid_raw_secret"
            }
          ]
        }
        """,
        "obsidian.direct-markdown.baseline.v1.json": """
        {
          "schemaVersion": 1,
          "kind": "source-replay-fixture",
          "source": "obsidian",
          "playbookID": "obsidian.direct-markdown",
          "playbookVersion": "v1",
          "purpose": "First Obsidian Source Onboarding baseline replay using direct Markdown access and a sample ingest scope.",
          "initialPrompt": "Run Zebra Source Onboarding for Obsidian using the installed zebra-source-onboarding helper. Start by running `zebra-source-onboarding intake --raw \\"Obsidian\\" --candidate \\"obsidian=Obsidian\\"`, then `zebra-source-onboarding confirm --answer yes`, then `zebra-source-onboarding next`. After every helper command, continue only from the JSON `nextPrompt` and current `nextPlaybookStepID`. When user input is needed, ask clearly; this replay fixture will answer by playbook step.",
          "interventions": [
            {
              "playbookStepID": "confirm_vault_if_needed",
              "matcher": {
                "type": "regex",
                "pattern": "(?i)(vault path|vault folder|\\\\.obsidian|correct vault|볼트|경로)"
              },
              "answerEnv": "ZEBRA_REPLAY_OBSIDIAN_VAULT_PATH",
              "approval": "storable",
              "secretPolicy": "forbid_raw_secret"
            },
            {
              "playbookStepID": "choose_ingest_scope",
              "matcher": {
                "type": "regex",
                "pattern": "(?i)(ingest scope|whole vault|sample|selected folders|skip|범위|샘플)"
              },
              "answer": "sample",
              "approval": "storable",
              "secretPolicy": "forbid_raw_secret"
            },
            {
              "playbookStepID": "confirm_ingest_plan",
              "matcher": {
                "type": "regex",
                "pattern": "(?i)(start this ingest plan|confirm.*plan|approved scope|ingest plan|승인|시작)"
              },
              "answer": "yes",
              "approval": "requires_human_approval",
              "secretPolicy": "forbid_raw_secret"
            }
          ]
        }
        """,
    ]

    private static let helperScript = """
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v python3 >/dev/null 2>&1; then
      echo "python3 is required for zebra-source-replay" >&2
      exit 1
    fi

    export ZEBRA_SOURCE_REPLAY_HELPER_PATH="$0"
    exec python3 - "$@" <<'PY'

    import argparse
    import hashlib
    import json
    import os
    import re
    import shutil
    import shlex
    import socket
    import subprocess
    import sys
    import threading
    import time
    import uuid
    from pathlib import Path

    def now_ms():
        return int(time.time() * 1000)

    def write_json(path, payload):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\\n", encoding="utf-8")

    def append_jsonl(path, payload):
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, sort_keys=True) + "\\n")

    def process_snapshot():
        try:
            completed = subprocess.run(
                ["ps", "-axo", "pid,ppid,etime,command"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=2,
            )
        except Exception:
            return []
        keywords = ("openclaw", "zebra-source-replay", "zebra-gbrain", "cmux", "node", "python", "rm ", "mv ", "zsh", "bash")
        rows = []
        for line in completed.stdout.splitlines()[:400]:
            lower = line.lower()
            if any(keyword in lower for keyword in keywords):
                rows.append(line[:500])
        return rows[-80:]

    def run_process(argv, cwd=None, env=None, timeout=240):
        started = now_ms()
        try:
            completed = subprocess.run(
                argv,
                cwd=str(cwd) if cwd else None,
                env=env,
                text=True,
                capture_output=True,
                timeout=timeout,
            )
            return {
                "argv": argv,
                "cwd": str(cwd) if cwd else None,
                "exitCode": completed.returncode,
                "stdout": completed.stdout,
                "stderr": completed.stderr,
                "startedAtMs": started,
                "finishedAtMs": now_ms(),
                "timedOut": False,
            }
        except subprocess.TimeoutExpired as exc:
            return {
                "argv": argv,
                "cwd": str(cwd) if cwd else None,
                "exitCode": 124,
                "stdout": exc.stdout or "",
                "stderr": exc.stderr or "timed out",
                "startedAtMs": started,
                "finishedAtMs": now_ms(),
                "timedOut": True,
            }

    def openclaw_text(payload):
        try:
            obj = json.loads(payload)
        except Exception:
            return payload
        result = obj.get("result") if isinstance(obj.get("result"), dict) else obj
        payloads = result.get("payloads") if isinstance(result.get("payloads"), list) else []
        texts = []
        for item in payloads:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                texts.append(item["text"])
        if texts:
            return "\\n".join(texts)
        text = result.get("finalAssistantVisibleText")
        return text if isinstance(text, str) else payload

    def hermes_session_id(stdout):
        match = re.search(r"^session_id:\\s*(\\S+)", stdout, re.MULTILINE)
        return match.group(1) if match else None

    def without_session_line(stdout):
        return "\\n".join(
            line for line in stdout.splitlines()
            if not line.startswith("session_id:") and not line.startswith("↻ Resumed session")
        ).strip()

    def write_probe_files(run_dir):
        (run_dir / "probe.txt").write_text("probe_file=ok\\n", encoding="utf-8")
        helper = run_dir / "probe-helper"
        helper.write_text(
            "#!/bin/sh\\n"
            "printf 'HELPER_CWD=%s\\\\n' \\"$(pwd)\\"\\n"
            "printf 'HELPER_MARKER=%s\\\\n' \\"${ZEBRA_REPLAY_HELPER_MARKER:-missing}\\"\\n"
            "printf 'HELPER_ARG=%s\\\\n' \\"${1:-missing}\\"\\n",
            encoding="utf-8",
        )
        helper.chmod(0o755)

    def make_run_dir(root, runtime, batch_id, run_id):
        run_dir = Path(root).expanduser() / "probe" / batch_id / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        return run_dir

    def record_turn(run_dir, runtime, turn, command_result, assistant_text):
        append_jsonl(run_dir / "transcript.jsonl", {
            "runtime": runtime,
            "turn": turn,
            "argv": command_result["argv"],
            "cwd": command_result["cwd"],
            "exitCode": command_result["exitCode"],
            "stdoutPath": f"helper-output/{turn}-stdout.txt",
            "stderrPath": f"helper-output/{turn}-stderr.txt",
            "assistantText": assistant_text,
        })
        output_dir = run_dir / "helper-output"
        output_dir.mkdir(exist_ok=True)
        (output_dir / f"{turn}-stdout.txt").write_text(command_result["stdout"], encoding="utf-8")
        (output_dir / f"{turn}-stderr.txt").write_text(command_result["stderr"], encoding="utf-8")

    sanitizer_state = {"redactedCount": 0}

    def sanitize_text(text):
        if not isinstance(text, str):
            return text
        patterns = [
            r"sk-[A-Za-z0-9_-]+",
            r"(?i)(refresh_token|authorization_code|oauth_code|access_token)([\\s:=]+)([^\\s\\\"',}]+)",
            r"https?://[^\\s]+(?:token|sig|signature|X-Amz-Signature)[^\\s]*",
        ]
        sanitized = text
        for pattern in patterns:
            if pattern.startswith("(?i)"):
                next_value, count = re.subn(pattern, lambda match: match.group(1) + match.group(2) + "REDACTED", sanitized)
            else:
                next_value, count = re.subn(pattern, "REDACTED_SECRET", sanitized)
            sanitizer_state["redactedCount"] += count
            sanitized = next_value
        return sanitized

    def sanitize_payload(payload):
        if isinstance(payload, str):
            return sanitize_text(payload)
        if isinstance(payload, list):
            return [sanitize_payload(item) for item in payload]
        if isinstance(payload, dict):
            return {key: sanitize_payload(value) for key, value in payload.items()}
        return payload

    def write_json_sanitized(path, payload):
        write_json(path, sanitize_payload(payload))

    def write_text_sanitized(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(sanitize_text(text), encoding="utf-8")

    def load_json(path):
        return json.loads(Path(path).expanduser().read_text(encoding="utf-8"))

    def load_json_if_present(path):
        path = Path(path).expanduser()
        if not path.exists():
            return {}
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            return loaded if isinstance(loaded, dict) else {}
        except Exception:
            return {}

    def replay_data_root():
        helper_path = os.environ.get("ZEBRA_SOURCE_REPLAY_HELPER_PATH") or sys.argv[0]
        return Path(helper_path).expanduser().resolve().parent.parent / "source-replay"

    def onboarding_root():
        helper_path = os.environ.get("ZEBRA_SOURCE_REPLAY_HELPER_PATH") or sys.argv[0]
        return Path(helper_path).expanduser().resolve().parent.parent

    def is_safe_data_id(value):
        return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", value) is not None

    def load_scenario(scenario_id):
        if not is_safe_data_id(scenario_id):
            return None, "invalid_scenario_id", None
        path = replay_data_root() / "scenarios" / f"{scenario_id}.json"
        if not path.exists():
            return None, "unknown_scenario", path
        try:
            scenario = load_json(path)
        except Exception:
            return None, "invalid_scenario", path
        if scenario.get("id") and scenario.get("id") != scenario_id:
            return None, "scenario_id_mismatch", path
        return scenario, None, path

    def resolve_fixture_path(scenario):
        fixture_name = scenario.get("fixture")
        if not is_safe_data_id(str(fixture_name).replace(".json", "")):
            return None
        path = replay_data_root() / "fixtures" / fixture_name
        return path if path.exists() else None

    def parse_key_value_inputs(items):
        parsed = {}
        for item in items or []:
            if "=" not in item:
                continue
            key, value = item.split("=", 1)
            if key:
                parsed[key] = value
        return parsed

    def runtime_state_path(args):
        configured = getattr(args, "runtime_state_path", "") or os.environ.get("ZEBRA_GBRAIN_RUNTIME_STATE") or ""
        return Path(configured).expanduser() if configured else onboarding_root() / "gbrain-runtime-state.json"

    def selected_runtime_from_receipt(args):
        path = runtime_state_path(args)
        state = load_json_if_present(path)
        receipt = state.get("receipt") if isinstance(state.get("receipt"), dict) else {}
        runtime = receipt.get("runtime")
        executable = receipt.get("executablePath")
        checks = receipt.get("checks") if isinstance(receipt.get("checks"), dict) else {}
        complete = (
            receipt.get("complete") is True
            and runtime in {"openclaw", "hermes"}
            and isinstance(executable, str)
            and executable
            and checks.get("credentials") is True
            and checks.get("runtimeConfigCommand") is True
            and checks.get("llmCall") is True
        )
        if not complete:
            return None, {
                "reason": "selected_runtime_missing",
                "selectedRuntimeReceiptPath": str(path),
            }
        return {
            "runtime": runtime,
            "executablePath": executable,
            "statePath": str(path),
        }, None

    def resolve_test_runtime(args):
        if args.runtime:
            if args.runtime == "openclaw":
                return {
                    "runtime": "openclaw",
                    "executablePath": args.openclaw_executable or "openclaw",
                    "statePath": None,
                }, None
            return {
                "runtime": "hermes",
                "executablePath": args.hermes_executable or "hermes",
                "statePath": None,
            }, None
        return selected_runtime_from_receipt(args)

    def file_metadata(path):
        path = Path(path).expanduser()
        if not path.exists():
            return {"exists": False}
        if not path.is_file():
            return {"exists": True, "isFile": False}
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return {
            "exists": True,
            "isFile": True,
            "size": path.stat().st_size,
            "sha256": digest.hexdigest(),
        }

    def openclaw_original_config_metadata(args):
        source_home = openclaw_source_home(args)
        config_path = source_home / "openclaw.json"
        return {
            "path": str(config_path),
            "metadata": file_metadata(config_path),
        }

    def openclaw_config_snapshot(path):
        path = Path(path).expanduser()
        output = {
            "path": str(path),
            "exists": False,
        }
        try:
            stat = path.stat()
        except FileNotFoundError:
            return output
        except Exception as exc:
            output["statError"] = str(exc)
            return output
        output.update({
            "exists": True,
            "isFile": path.is_file(),
            "size": stat.st_size,
            "mtimeNs": stat.st_mtime_ns,
            "ctimeNs": stat.st_ctime_ns,
            "dev": stat.st_dev,
            "ino": stat.st_ino,
            "mode": stat.st_mode & 0o777,
        })
        if not path.is_file():
            return output
        try:
            digest = hashlib.sha256()
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
            output["sha256"] = digest.hexdigest()
        except Exception as exc:
            output["hashError"] = str(exc)
        try:
            payload = load_json(path)
            output["topLevelKeys"] = sorted(payload.keys()) if isinstance(payload, dict) else []
            gateway = payload.get("gateway") if isinstance(payload, dict) else None
            output["gatewayPresent"] = isinstance(gateway, dict)
            output["gatewayMode"] = gateway.get("mode") if isinstance(gateway, dict) else None
            auth = gateway.get("auth") if isinstance(gateway, dict) and isinstance(gateway.get("auth"), dict) else None
            output["gatewayAuthPresent"] = isinstance(auth, dict)
            output["gatewayTokenPresent"] = bool(auth.get("token")) if isinstance(auth, dict) else False
        except Exception as exc:
            output["jsonError"] = str(exc)
        return output

    def snapshot_signature(snapshot):
        return "|".join(str(snapshot.get(key)) for key in ("exists", "size", "sha256", "dev", "ino", "gatewayMode", "gatewayTokenPresent"))

    def openclaw_audit_paths(args, run_dir):
        paths = [Path(run_dir) / "openclaw-config-audit.jsonl"]
        try:
            root_path = Path(args.root).expanduser() / "openclaw-config-audit.jsonl"
            if root_path != paths[0]:
                paths.append(root_path)
        except Exception:
            pass
        return paths

    def append_openclaw_audit(args, run_dir, payload):
        event = {
            "tsMs": now_ms(),
            "batchID": getattr(args, "batch_id", ""),
            "runID": getattr(args, "run_id", ""),
            **payload,
        }
        for path in openclaw_audit_paths(args, run_dir):
            append_jsonl(path, sanitize_payload(event))

    def audit_openclaw_config(args, run_dir, event, **extra):
        source_home = openclaw_source_home(args)
        source_config = source_home / "openclaw.json"
        env_config = extra.pop("envConfigPath", None)
        payload = {
            "event": event,
            "sourceHome": str(source_home),
            "sourceConfig": openclaw_config_snapshot(source_config),
            **extra,
        }
        if env_config:
            payload["envConfig"] = openclaw_config_snapshot(env_config)
        append_openclaw_audit(args, run_dir, payload)

    def start_openclaw_source_config_watcher(args, run_dir):
        source_config = openclaw_source_home(args) / "openclaw.json"
        stop_event = threading.Event()
        initial = openclaw_config_snapshot(source_config)
        append_openclaw_audit(args, run_dir, {
            "event": "openclaw.source_config.watch_started",
            "sourceConfig": initial,
            "processSnapshot": process_snapshot(),
        })

        def watch():
            previous = initial
            previous_signature = snapshot_signature(previous)
            while not stop_event.wait(0.2):
                current = openclaw_config_snapshot(source_config)
                current_signature = snapshot_signature(current)
                if current_signature == previous_signature:
                    continue
                append_openclaw_audit(args, run_dir, {
                    "event": "openclaw.source_config.changed",
                    "before": previous,
                    "after": current,
                    "processSnapshot": process_snapshot(),
                })
                previous = current
                previous_signature = current_signature

        thread = threading.Thread(target=watch, name="zebra-openclaw-config-watch", daemon=True)
        thread.start()
        return stop_event, thread

    def stop_openclaw_source_config_watcher(args, run_dir, watcher):
        if not watcher:
            return
        stop_event, thread = watcher
        stop_event.set()
        thread.join(timeout=1)
        audit_openclaw_config(args, run_dir, "openclaw.source_config.watch_stopped", processSnapshot=process_snapshot())

    def path_is_under(path, parent):
        try:
            Path(path).resolve().relative_to(Path(parent).resolve())
            return True
        except Exception:
            return False

    def scan_artifacts(run_dir, raw_inputs=None, excluded_roots=None):
        raw_inputs = [value for value in (raw_inputs or []) if isinstance(value, str) and value]
        excluded_roots = [Path(root) for root in (excluded_roots or []) if root]
        raw_input_leaks = []
        token_like_leaks = []
        large_note_body_leaks = []
        token_pattern = re.compile(r"(?i)(sk-[A-Za-z0-9_-]{8,}|refresh_token\\s*[:=]|access_token\\s*[:=]|authorization_code\\s*[:=]|X-Amz-Signature=)")
        for path in Path(run_dir).rglob("*"):
            if not path.is_file():
                continue
            if any(path_is_under(path, root) for root in excluded_roots):
                continue
            try:
                if path.stat().st_size > 1024 * 1024:
                    large_note_body_leaks.append(str(path))
                    continue
                text = path.read_text(encoding="utf-8")
            except Exception:
                continue
            for value in raw_inputs:
                if value in text:
                    raw_input_leaks.append(str(path))
            if token_pattern.search(text):
                token_like_leaks.append(str(path))
        leaks = {
            "rawInputLeaks": sorted(set(raw_input_leaks)),
            "tokenLikeLeaks": sorted(set(token_like_leaks)),
            "largeNoteBodyLeaks": sorted(set(large_note_body_leaks)),
        }
        return {
            "ok": not any(leaks.values()),
            **leaks,
        }

    def json_objects_from_text(text):
        decoder = json.JSONDecoder()
        for index, character in enumerate(text or ""):
            if character != "{":
                continue
            try:
                obj, _ = decoder.raw_decode(text[index:])
            except Exception:
                continue
            if isinstance(obj, dict):
                yield obj

    def first_next_prompt_payload(text):
        for obj in json_objects_from_text(text):
            if "nextPlaybookStepID" in obj:
                return obj
            result = obj.get("result") if isinstance(obj.get("result"), dict) else {}
            payloads = result.get("payloads") if isinstance(result.get("payloads"), list) else []
            for item in payloads:
                if not isinstance(item, dict) or not isinstance(item.get("text"), str):
                    continue
                nested = first_next_prompt_payload(item["text"])
                if nested:
                    return nested
        return None

    def read_state_step(state_path, source):
        if not state_path:
            return None
        path = Path(state_path).expanduser()
        if not path.exists():
            return None
        try:
            state = load_json(path)
        except Exception:
            return None
        progress = state.get("progress") if isinstance(state.get("progress"), dict) else {}
        rows = progress.get("sourceRows") if isinstance(progress.get("sourceRows"), dict) else {}
        row = rows.get(source) if isinstance(rows.get(source), dict) else {}
        step = row.get("playbookStepID")
        if isinstance(step, str) and step:
            return {
                "source": source,
                "playbookID": row.get("playbookID"),
                "playbookVersion": row.get("playbookVersion"),
                "playbookStepID": step,
            }
        return None

    def observe_playbook_step(run_dir, source, state_path, assistant_text):
        state_step = read_state_step(state_path, source)
        helper_payload = first_next_prompt_payload(assistant_text)
        helper_step = None
        if helper_payload:
            helper_step = {
                "source": helper_payload.get("nextSourceID") or source,
                "playbookID": helper_payload.get("nextPlaybookID"),
                "playbookVersion": helper_payload.get("nextPlaybookVersion"),
                "playbookStepID": helper_payload.get("nextPlaybookStepID"),
                "nextPrompt": helper_payload.get("nextPrompt"),
            }

        chosen = state_step or helper_step
        if not chosen or not chosen.get("playbookStepID"):
            return None

        source_of_truth = "state" if state_step else "helper_stdout_next_prompt"
        if state_step and helper_step and state_step.get("playbookStepID") == helper_step.get("playbookStepID"):
            source_of_truth = "state+helper_stdout_next_prompt"
        event = {
            "event": "playbook.step.observed",
            "source": chosen.get("source") or source,
            "playbookID": chosen.get("playbookID"),
            "playbookVersion": chosen.get("playbookVersion"),
            "playbookStepID": chosen.get("playbookStepID"),
            "sourceOfTruth": source_of_truth,
            "statePath": str(state_path) if state_path else None,
            "helperPlaybookStepID": helper_step.get("playbookStepID") if helper_step else None,
        }
        append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload(event))
        if helper_step and helper_step.get("nextPrompt") and not chosen.get("nextPrompt"):
            chosen["nextPrompt"] = helper_step.get("nextPrompt")
        chosen["sourceOfTruth"] = source_of_truth
        return chosen

    def normalize_fixture(raw):
        source = raw.get("source") or raw.get("sourceID") or raw.get("sourceId") or "unknown"
        playbook_id = raw.get("playbookID") or raw.get("playbookId")
        playbook_version = raw.get("playbookVersion") or raw.get("version") or "v1"
        if not playbook_id and isinstance(playbook_version, str) and ".v" in playbook_version:
            candidate_id, candidate_version = playbook_version.rsplit(".", 1)
            if candidate_version.startswith("v"):
                playbook_id = candidate_id
                playbook_version = candidate_version
        interventions = []
        for item in raw.get("interventions", []):
            if not isinstance(item, dict):
                continue
            interventions.append({
                "playbookStepID": item.get("playbookStepID") or item.get("playbookStepId") or item.get("stepID") or item.get("stepId"),
                "matcher": item.get("matcher") if isinstance(item.get("matcher"), dict) else {},
                "answer": item.get("answer") or "",
                "answerEnv": item.get("answerEnv") or item.get("answerENV") or "",
                "approval": item.get("approval") or item.get("humanApproval") or "requires_human_approval",
                "secretPolicy": item.get("secretPolicy") or "forbid_raw_secret",
            })
        return {
            "schemaVersion": raw.get("schemaVersion") or 1,
            "source": source,
            "playbookID": playbook_id or "unknown",
            "playbookVersion": playbook_version,
            "preflightCommands": raw.get("preflightCommands") if isinstance(raw.get("preflightCommands"), list) else [],
            "interventions": interventions,
            "initialPrompt": raw.get("initialPrompt"),
        }

    def normalize_preflight_command(item):
        if not isinstance(item, dict):
            return None
        argv = item.get("argv")
        if not isinstance(argv, list) or not argv or not all(isinstance(value, str) and value for value in argv):
            return None
        expected = item.get("expectedExitCodes")
        if not isinstance(expected, list) or not expected:
            expected = [0]
        expected_codes = []
        for value in expected:
            try:
                expected_codes.append(int(value))
            except Exception:
                continue
        if not expected_codes:
            expected_codes = [0]
        try:
            timeout = int(item.get("timeout") or 120)
        except Exception:
            timeout = 120
        return {
            "id": str(item.get("id") or "source-preflight"),
            "argv": argv,
            "timeout": max(1, timeout),
            "expectedExitCodes": expected_codes,
            "continueOnFailure": bool(item.get("continueOnFailure")),
            "failureReason": str(item.get("failureReason") or "source_preflight_failed"),
            "prompt": str(item.get("prompt") or ""),
        }

    def collect_preflight_commands(args, fixture):
        commands = []
        for item in fixture.get("preflightCommands") or []:
            normalized = normalize_preflight_command(item)
            if normalized:
                commands.append(normalized)
        for item in getattr(args, "preflight_commands", []) or []:
            normalized = normalize_preflight_command(item)
            if normalized:
                commands.append(normalized)
        return commands

    def run_source_preflights(args, fixture, run_dir, env):
        commands = collect_preflight_commands(args, fixture)
        results = []
        if not commands:
            return {"ok": True, "results": results}
        append_jsonl(run_dir / "intervention-events.jsonl", {
            "event": "source.preflight.started",
            "source": fixture["source"],
            "count": len(commands),
        })
        for index, command in enumerate(commands, start=1):
            started = now_ms()
            result = {
                "id": command["id"],
                "index": index,
                "argv": command["argv"],
                "timeout": command["timeout"],
                "expectedExitCodes": command["expectedExitCodes"],
                "prompt": command["prompt"],
            }
            try:
                completed = subprocess.run(
                    command["argv"],
                    cwd=run_dir,
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=command["timeout"],
                )
                result.update({
                    "exitCode": completed.returncode,
                    "ok": completed.returncode in command["expectedExitCodes"],
                    "durationMs": now_ms() - started,
                    "stdoutBytes": len((completed.stdout or "").encode("utf-8")),
                    "stderrPreview": sanitize_text((completed.stderr or "")[:1000]),
                })
            except FileNotFoundError:
                result.update({
                    "exitCode": 127,
                    "ok": False,
                    "durationMs": now_ms() - started,
                    "stdoutBytes": 0,
                    "stderrPreview": "command not found: " + command["argv"][0],
                })
            except subprocess.TimeoutExpired as error:
                stderr = error.stderr or "source preflight command timed out"
                result.update({
                    "exitCode": 124,
                    "ok": False,
                    "timedOut": True,
                    "durationMs": now_ms() - started,
                    "stdoutBytes": len((error.stdout or "").encode("utf-8")) if isinstance(error.stdout, str) else 0,
                    "stderrPreview": sanitize_text(str(stderr)[:1000]),
                })
            except Exception as error:
                result.update({
                    "exitCode": 1,
                    "ok": False,
                    "durationMs": now_ms() - started,
                    "stdoutBytes": 0,
                    "stderrPreview": sanitize_text(str(error)[:1000]),
                })
            results.append(result)
            append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({
                "event": "source.preflight.command",
                "source": fixture["source"],
                **result,
            }))
            if not result.get("ok") and not command["continueOnFailure"]:
                return {
                    "ok": False,
                    "reason": command["failureReason"],
                    "failedCommand": result,
                    "results": results,
                }
        return {"ok": True, "results": results}

    def matcher_matches(matcher, text):
        if not matcher:
            return True
        match_type = matcher.get("type") or "contains"
        target = matcher.get("text") or matcher.get("pattern") or ""
        text = text or ""
        if match_type == "contains":
            return target in text
        if match_type == "contains_case_insensitive":
            return target.lower() in text.lower()
        if match_type == "exact":
            return text.strip() == target
        if match_type == "regex":
            try:
                return re.search(target, text) is not None
            except re.error:
                return False
        return False

    def find_intervention(fixture, step_id, applied_steps):
        for intervention in fixture["interventions"]:
            if intervention.get("playbookStepID") == step_id and step_id not in applied_steps:
                return intervention
        return None

    def intervention_answer(intervention):
        answer_env = intervention.get("answerEnv")
        if isinstance(answer_env, str) and answer_env:
            value = os.environ.get(answer_env)
            if not value:
                return None, answer_env
            return value, None
        return intervention.get("answer") or "", None

    def make_replay_run_dir(root, batch_id, run_id):
        run_dir = Path(root).expanduser() / "run" / batch_id / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        return run_dir

    def replay_state_path(args, run_dir):
        return Path(args.state_path).expanduser() if getattr(args, "state_path", "") else run_dir / "source-onboarding-state.json"

    def replay_env(args, run_dir):
        state_path = replay_state_path(args, run_dir)
        env = os.environ.copy()
        env["ZEBRA_SOURCE_ONBOARDING_STATE"] = str(state_path)
        env["ZEBRA_SOURCE_REPLAY_RUN_DIR"] = str(run_dir)
        helper_bin = Path(sys.argv[0]).expanduser().resolve().parent
        env["PATH"] = str(helper_bin) + os.pathsep + env.get("PATH", "")
        return env

    def free_loopback_port():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            return int(sock.getsockname()[1])

    def openclaw_source_home(args):
        configured = getattr(args, "openclaw_home", "") or os.environ.get("OPENCLAW_HOME") or ""
        if configured:
            return Path(configured).expanduser()
        return Path.home() / ".openclaw"

    def prepare_openclaw_isolation(args, run_dir, env):
        source_home = openclaw_source_home(args)
        isolated_root = Path(args.root).expanduser() / "openclaw-home" / args.batch_id / args.run_id
        audit_openclaw_config(args, run_dir, "openclaw.isolation.prepare_started", processSnapshot=process_snapshot())
        if isolated_root.exists():
            shutil.rmtree(isolated_root)
        if source_home.exists():
            shutil.copytree(source_home, isolated_root, symlinks=True)
        else:
            isolated_root.mkdir(parents=True, exist_ok=True)

        config_path = isolated_root / "openclaw.json"
        config = load_json_if_present(config_path)
        state_dir = isolated_root
        state_dir.mkdir(parents=True, exist_ok=True)

        gateway = config.get("gateway") if isinstance(config.get("gateway"), dict) else {}
        auth = gateway.get("auth") if isinstance(gateway.get("auth"), dict) else {}
        token = auth.get("token") if isinstance(auth.get("token"), str) and auth.get("token") else uuid.uuid4().hex
        port = int(getattr(args, "openclaw_gateway_port", 0) or 0) or free_loopback_port()

        next_gateway = dict(gateway)
        next_gateway["mode"] = "local"
        next_gateway["bind"] = "loopback"
        next_gateway["port"] = port
        next_gateway["auth"] = {"mode": "token", "token": token}
        config["gateway"] = next_gateway
        write_json(config_path, config)

        env["OPENCLAW_HOME"] = str(isolated_root)
        env["OPENCLAW_CONFIG_PATH"] = str(config_path)
        env["OPENCLAW_STATE_DIR"] = str(state_dir)
        env["OPENCLAW_GATEWAY_TOKEN"] = token

        append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({
            "event": "openclaw.isolation.prepared",
            "sourceHome": str(source_home),
            "isolatedHome": str(isolated_root),
            "configPath": str(config_path),
            "stateDir": str(state_dir),
            "gatewayPort": port,
        }))
        audit_openclaw_config(
            args,
            run_dir,
            "openclaw.isolation.prepared",
            envConfigPath=str(config_path),
            isolatedHome=str(isolated_root),
            stateDir=str(state_dir),
            gatewayPort=port,
            processSnapshot=process_snapshot(),
        )
        return {
            "sourceHome": source_home,
            "isolatedHome": isolated_root,
            "configPath": config_path,
            "stateDir": state_dir,
            "gatewayPort": port,
            "token": token,
        }

    def start_openclaw_gateway(args, run_dir, env, isolation):
        if not isolation or getattr(args, "openclaw_skip_gateway", False):
            return None
        log_path = isolation["isolatedHome"] / "gateway.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_handle = log_path.open("a", encoding="utf-8")
        argv = [
            args.openclaw_executable,
            "gateway",
            "run",
            "--port", str(isolation["gatewayPort"]),
            "--auth", "token",
            "--bind", "loopback",
        ]
        audit_openclaw_config(args, run_dir, "openclaw.gateway.starting", argv=argv, envConfigPath=env.get("OPENCLAW_CONFIG_PATH"))
        try:
            process = subprocess.Popen(
                argv,
                cwd=str(run_dir),
                env=env,
                text=True,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
            )
        except Exception as exc:
            log_handle.write(f"failed to start gateway: {exc}\\n")
            log_handle.close()
            append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({
                "event": "openclaw.gateway.start_failed",
                "error": str(exc),
            }))
            audit_openclaw_config(
                args,
                run_dir,
                "openclaw.gateway.start_failed",
                argv=argv,
                envConfigPath=env.get("OPENCLAW_CONFIG_PATH"),
                error=str(exc),
                processSnapshot=process_snapshot(),
            )
            return None
        time.sleep(1.0)
        append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({
            "event": "openclaw.gateway.started",
            "pid": process.pid,
            "gatewayPort": isolation["gatewayPort"],
            "logPath": str(log_path),
            "exitedEarly": process.poll() is not None,
        }))
        audit_openclaw_config(
            args,
            run_dir,
            "openclaw.gateway.started",
            argv=argv,
            envConfigPath=env.get("OPENCLAW_CONFIG_PATH"),
            pid=process.pid,
            exitedEarly=process.poll() is not None,
            processSnapshot=process_snapshot(),
        )
        return {"process": process, "log": log_handle}

    def stop_openclaw_gateway(gateway_process):
        if not gateway_process:
            return
        process = gateway_process.get("process")
        log_handle = gateway_process.get("log")
        try:
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        finally:
            if log_handle:
                log_handle.close()

    def record_replay_turn(run_dir, runtime, turn_number, command_result, assistant_text):
        turn = f"turn-{turn_number:03d}"
        sanitized_result = sanitize_payload(command_result)
        append_jsonl(run_dir / "transcript.jsonl", {
            "runtime": runtime,
            "turn": turn,
            "argv": sanitized_result["argv"],
            "cwd": sanitized_result["cwd"],
            "exitCode": sanitized_result["exitCode"],
            "stdoutPath": f"helper-output/{turn}-stdout.txt",
            "stderrPath": f"helper-output/{turn}-stderr.txt",
            "assistantText": sanitize_text(assistant_text),
        })
        output_dir = run_dir / "helper-output"
        output_dir.mkdir(exist_ok=True)
        write_text_sanitized(output_dir / f"{turn}-stdout.txt", command_result["stdout"])
        write_text_sanitized(output_dir / f"{turn}-stderr.txt", command_result["stderr"])

    def send_openclaw_turn(args, run_dir, message, turn_number, env, agent, session_key):
        argv = [args.openclaw_executable, "agent", "--agent", agent, "--session-key", session_key, "--message", message, "--json", "--timeout", str(args.timeout)]
        audit_openclaw_config(
            args,
            run_dir,
            "openclaw.agent.turn.starting",
            turnNumber=turn_number,
            argv=argv[:7] + ["<message>", *argv[8:]],
            envConfigPath=env.get("OPENCLAW_CONFIG_PATH"),
        )
        result = run_process(
            argv,
            cwd=run_dir,
            env=env,
            timeout=args.timeout + 30,
        )
        audit_openclaw_config(
            args,
            run_dir,
            "openclaw.agent.turn.finished",
            turnNumber=turn_number,
            exitCode=result.get("exitCode"),
            envConfigPath=env.get("OPENCLAW_CONFIG_PATH"),
            processSnapshot=process_snapshot(),
        )
        text = openclaw_text(result["stdout"])
        record_replay_turn(run_dir, "openclaw", turn_number, result, text)
        return result, text

    def send_hermes_turn(args, run_dir, message, turn_number, env, session_id):
        argv = [args.hermes_executable, "chat", "-q", message, "--quiet"]
        if session_id:
            argv = [args.hermes_executable, "chat", "--resume", session_id, "-q", message, "--quiet"]
        result = run_process(argv, cwd=run_dir, env=env, timeout=args.timeout + 30)
        text = without_session_line(result["stdout"])
        record_replay_turn(run_dir, "hermes", turn_number, result, text)
        return result, text, hermes_session_id(result["stdout"] + "\\n" + result["stderr"])

    def execute_run(args):
        sanitizer_state["redactedCount"] = 0
        args.run_id = args.run_id or ("run-" + uuid.uuid4().hex[:12])
        run_dir = make_replay_run_dir(args.root, args.batch_id, args.run_id)
        fixture_raw = load_json(args.fixture)
        fixture = normalize_fixture(fixture_raw)
        state_path = replay_state_path(args, run_dir)
        prompt = args.prompt or fixture.get("initialPrompt") or f"Run Zebra Source Onboarding replay for source {fixture['source']}."
        if args.prompt_file:
            prompt = Path(args.prompt_file).expanduser().read_text(encoding="utf-8")
        write_text_sanitized(run_dir / "prompt.txt", prompt)
        write_json_sanitized(run_dir / "fixture.json", fixture)
        manifest = {
            "schemaVersion": 1,
            "kind": "source-replay-run",
            "command": "run",
            "runtime": args.runtime,
            "batchID": args.batch_id,
            "runID": args.run_id,
            "runDirectory": str(run_dir),
            "fixturePath": str(Path(args.fixture).expanduser()),
            "statePath": str(state_path),
        }
        write_json_sanitized(run_dir / "replay-manifest.json", manifest)

        env = replay_env(args, run_dir)
        applied_steps = set()
        unanswered = []
        exit_reason = "max_turns_exceeded"
        ok = False
        hermes_session = None
        hermes_resume_count = 0
        openclaw_agent = None
        openclaw_session_key = None
        openclaw_isolation = None
        openclaw_gateway_process = None
        openclaw_config_watcher = None
        message = prompt
        preflight_results = []

        try:
            preflight = run_source_preflights(args, fixture, run_dir, env)
            preflight_results = preflight.get("results") or []
            if not preflight.get("ok"):
                exit_reason = preflight.get("reason") or "source_preflight_failed"
                unanswered.append({
                    "source": fixture["source"],
                    "playbookStepID": None,
                    "reason": exit_reason,
                    "preflightCommandID": (preflight.get("failedCommand") or {}).get("id"),
                })
                summary = run_summary(args, fixture, run_dir, state_path, ok, exit_reason, applied_steps, unanswered, openclaw_agent, openclaw_session_key, hermes_session, hermes_resume_count, openclaw_isolation, preflight_results=preflight_results)
                summary["preflightFailure"] = preflight.get("failedCommand")
                write_json_sanitized(run_dir / "run-summary.json", summary)
                return summary

            if args.runtime == "openclaw":
                openclaw_config_watcher = start_openclaw_source_config_watcher(args, run_dir)
                openclaw_isolation = prepare_openclaw_isolation(args, run_dir, env)
                openclaw_gateway_process = start_openclaw_gateway(args, run_dir, env, openclaw_isolation)

            if args.runtime == "openclaw":
                safe_run_id = re.sub(r"[^A-Za-z0-9-]+", "-", args.run_id.lower()).strip("-") or "run"
                openclaw_agent = args.openclaw_agent or ("zebra-source-replay-" + safe_run_id[-32:])
                openclaw_session_key = f"agent:{openclaw_agent}:{args.run_id}"
                add_argv = [args.openclaw_executable, "agents", "add", openclaw_agent, "--workspace", str(run_dir), "--non-interactive", "--json"]
                audit_openclaw_config(args, run_dir, "openclaw.agents.add.starting", argv=add_argv, envConfigPath=env.get("OPENCLAW_CONFIG_PATH"))
                add_result = run_process(
                    add_argv,
                    cwd=run_dir,
                    env=env,
                    timeout=args.timeout,
                )
                append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({"event": "openclaw.agents.add", "result": add_result}))
                audit_openclaw_config(
                    args,
                    run_dir,
                    "openclaw.agents.add.finished",
                    exitCode=add_result.get("exitCode"),
                    envConfigPath=env.get("OPENCLAW_CONFIG_PATH"),
                    processSnapshot=process_snapshot(),
                )
                if add_result["exitCode"] != 0 and "already" not in (add_result["stdout"] + add_result["stderr"]).lower():
                    exit_reason = "openclaw_agent_add_failed"
                    summary = run_summary(args, fixture, run_dir, state_path, ok, exit_reason, applied_steps, unanswered, openclaw_agent, openclaw_session_key, hermes_session, hermes_resume_count, openclaw_isolation, preflight_results=preflight_results)
                    write_json_sanitized(run_dir / "run-summary.json", summary)
                    return summary

            for turn_number in range(1, args.max_turns + 1):
                if args.runtime == "openclaw":
                    result, assistant_text = send_openclaw_turn(args, run_dir, message, turn_number, env, openclaw_agent, openclaw_session_key)
                else:
                    result, assistant_text, observed_session = send_hermes_turn(args, run_dir, message, turn_number, env, hermes_session)
                    if hermes_session:
                        hermes_resume_count += 1
                    if observed_session and not hermes_session:
                        hermes_session = observed_session
                if result["exitCode"] != 0:
                    exit_reason = "runtime_failed"
                    break

                observed = observe_playbook_step(run_dir, fixture["source"], state_path, assistant_text)
                if not observed:
                    exit_reason = "step_not_observed"
                    unanswered.append({"source": fixture["source"], "playbookStepID": None})
                    break

                step_id = observed["playbookStepID"]
                if step_id == "complete":
                    ok = True
                    exit_reason = "completed"
                    break

                intervention = find_intervention(fixture, step_id, applied_steps)
                prompt_text = observed.get("nextPrompt") or assistant_text
                if not intervention:
                    exit_reason = "needs_human_intervention"
                    unanswered.append({"source": fixture["source"], "playbookStepID": step_id})
                    break
                matched = matcher_matches(intervention.get("matcher"), prompt_text)
                if not matched:
                    append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({
                        "event": "fixture.intervention.rejected",
                        "source": fixture["source"],
                        "playbookID": fixture["playbookID"],
                        "playbookVersion": fixture["playbookVersion"],
                        "playbookStepID": step_id,
                        "matcherResult": "not_matched",
                        "answerSource": "fixture",
                        "approval": intervention.get("approval"),
                    }))
                    exit_reason = "needs_human_intervention"
                    unanswered.append({"source": fixture["source"], "playbookStepID": step_id, "reason": "matcher_not_matched"})
                    break
                answer, missing_env = intervention_answer(intervention)
                if missing_env:
                    append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({
                        "event": "fixture.intervention.missing_answer_env",
                        "source": fixture["source"],
                        "playbookID": fixture["playbookID"],
                        "playbookVersion": fixture["playbookVersion"],
                        "playbookStepID": step_id,
                        "answerEnv": missing_env,
                    }))
                    exit_reason = "fixture_answer_env_missing"
                    unanswered.append({"source": fixture["source"], "playbookStepID": step_id, "reason": "answer_env_missing", "answerEnv": missing_env})
                    break
                append_jsonl(run_dir / "intervention-events.jsonl", sanitize_payload({
                    "event": "fixture.intervention.applied",
                    "source": fixture["source"],
                    "playbookID": fixture["playbookID"],
                    "playbookVersion": fixture["playbookVersion"],
                    "playbookStepID": step_id,
                    "matcherResult": "matched",
                    "answerSource": "fixture",
                    "approval": intervention.get("approval"),
                }))
                applied_steps.add(step_id)
                message = answer

            summary = run_summary(args, fixture, run_dir, state_path, ok, exit_reason, applied_steps, unanswered, openclaw_agent, openclaw_session_key, hermes_session, hermes_resume_count, openclaw_isolation, preflight_results=preflight_results)
            write_json_sanitized(run_dir / "run-summary.json", summary)
            return summary
        finally:
            stop_openclaw_gateway(openclaw_gateway_process)
            stop_openclaw_source_config_watcher(args, run_dir, openclaw_config_watcher)

    def run_summary(args, fixture, run_dir, state_path, ok, exit_reason, applied_steps, unanswered, openclaw_agent, openclaw_session_key, hermes_session, hermes_resume_count, openclaw_isolation=None, preflight_results=None):
        summary = {
            "ok": ok,
            "command": "run",
            "runtime": args.runtime,
            "source": fixture["source"],
            "playbookID": fixture["playbookID"],
            "playbookVersion": fixture["playbookVersion"],
            "exitReason": exit_reason,
            "interventionCount": len(applied_steps),
            "unansweredInterventions": unanswered,
            "runDirectory": str(run_dir),
            "statePath": str(state_path),
            "sanitizer": {"redactedCount": sanitizer_state["redactedCount"]},
            "preflight": {
                "ok": all(item.get("ok") for item in (preflight_results or [])),
                "commands": preflight_results or [],
            },
        }
        if args.runtime == "openclaw":
            summary["openClaw"] = {
                "agentID": openclaw_agent,
                "sessionKey": openclaw_session_key,
                "workspace": str(run_dir),
            }
            if openclaw_isolation:
                summary["openClaw"]["isolatedHome"] = str(openclaw_isolation["isolatedHome"])
                summary["openClaw"]["configPath"] = str(openclaw_isolation["configPath"])
                summary["openClaw"]["stateDir"] = str(openclaw_isolation["stateDir"])
                summary["openClaw"]["gatewayPort"] = openclaw_isolation["gatewayPort"]
        else:
            summary["hermes"] = {
                "sessionID": hermes_session,
                "resumeCount": hermes_resume_count,
            }
        return summary

    def probe_openclaw(args, run_dir):
        executable = args.openclaw_executable
        agent = args.openclaw_agent or ("zebra-source-replay-" + args.run_id.lower().replace("_", "-"))
        session_key = f"agent:{agent}:{args.run_id}"
        env = replay_env(args, run_dir)
        watcher = start_openclaw_source_config_watcher(args, run_dir)
        isolation = prepare_openclaw_isolation(args, run_dir, env)
        gateway_process = start_openclaw_gateway(args, run_dir, env, isolation)
        try:
            add_argv = [executable, "agents", "add", agent, "--workspace", str(run_dir), "--non-interactive", "--json"]
            audit_openclaw_config(args, run_dir, "openclaw.probe.agents.add.starting", argv=add_argv, envConfigPath=env.get("OPENCLAW_CONFIG_PATH"))
            add_result = run_process(
                add_argv,
                cwd=run_dir,
                env=env,
                timeout=args.timeout,
            )
            append_jsonl(run_dir / "helper-events.jsonl", sanitize_payload({"event": "openclaw.agents.add", "result": add_result}))
            audit_openclaw_config(args, run_dir, "openclaw.probe.agents.add.finished", exitCode=add_result.get("exitCode"), envConfigPath=env.get("OPENCLAW_CONFIG_PATH"), processSnapshot=process_snapshot())
            if add_result["exitCode"] != 0 and "already" not in (add_result["stdout"] + add_result["stderr"]).lower():
                return {"ok": False, "reason": "openclaw_agent_add_failed", "result": sanitize_payload(add_result)}

            turn1_message = (
                "Runtime replay probe turn 1. Do not modify files. Use available tools if needed. "
                "Report current working directory and contents of ./probe.txt. "
                "Then end with exactly: QUESTION: What color should I record?"
            )
            turn1_argv = [executable, "agent", "--agent", agent, "--session-key", session_key, "--message", turn1_message, "--json", "--timeout", str(args.timeout)]
            audit_openclaw_config(args, run_dir, "openclaw.probe.turn.starting", turn="turn1", argv=turn1_argv[:7] + ["<message>", *turn1_argv[8:]], envConfigPath=env.get("OPENCLAW_CONFIG_PATH"))
            turn1 = run_process(
                turn1_argv,
                cwd=run_dir,
                env=env,
                timeout=args.timeout + 30,
            )
            audit_openclaw_config(args, run_dir, "openclaw.probe.turn.finished", turn="turn1", exitCode=turn1.get("exitCode"), envConfigPath=env.get("OPENCLAW_CONFIG_PATH"), processSnapshot=process_snapshot())
            text1 = openclaw_text(turn1["stdout"])
            record_turn(run_dir, "openclaw", "turn1", turn1, text1)

            turn2_message = (
                "The color is blue. Runtime replay probe turn 2. Reply with exactly two lines: "
                "RECORDED_COLOR=<color> and REMEMBERED_PREVIOUS_QUESTION=<yes-or-no>."
            )
            turn2_argv = [executable, "agent", "--agent", agent, "--session-key", session_key, "--message", turn2_message, "--json", "--timeout", str(args.timeout)]
            audit_openclaw_config(args, run_dir, "openclaw.probe.turn.starting", turn="turn2", argv=turn2_argv[:7] + ["<message>", *turn2_argv[8:]], envConfigPath=env.get("OPENCLAW_CONFIG_PATH"))
            turn2 = run_process(
                turn2_argv,
                cwd=run_dir,
                env=env,
                timeout=args.timeout + 30,
            )
            audit_openclaw_config(args, run_dir, "openclaw.probe.turn.finished", turn="turn2", exitCode=turn2.get("exitCode"), envConfigPath=env.get("OPENCLAW_CONFIG_PATH"), processSnapshot=process_snapshot())
            text2 = openclaw_text(turn2["stdout"])
            record_turn(run_dir, "openclaw", "turn2", turn2, text2)

            turn3_message = (
                "Runtime replay probe turn 3. Run this exact helper command from the workspace: "
                "ZEBRA_REPLAY_HELPER_MARKER=openclaw-helper ./probe-helper openclaw-arg. "
                "Reply with only the helper output lines."
            )
            turn3_argv = [executable, "agent", "--agent", agent, "--session-key", session_key, "--message", turn3_message, "--json", "--timeout", str(args.timeout)]
            audit_openclaw_config(args, run_dir, "openclaw.probe.turn.starting", turn="turn3", argv=turn3_argv[:7] + ["<message>", *turn3_argv[8:]], envConfigPath=env.get("OPENCLAW_CONFIG_PATH"))
            turn3 = run_process(
                turn3_argv,
                cwd=run_dir,
                env=env,
                timeout=args.timeout + 30,
            )
            audit_openclaw_config(args, run_dir, "openclaw.probe.turn.finished", turn="turn3", exitCode=turn3.get("exitCode"), envConfigPath=env.get("OPENCLAW_CONFIG_PATH"), processSnapshot=process_snapshot())
            text3 = openclaw_text(turn3["stdout"])
            record_turn(run_dir, "openclaw", "turn3", turn3, text3)

            checks = {
                "promptInjection": turn1["exitCode"] == 0,
                "workspaceFileRead": "probe_file=ok" in text1,
                "questionObserved": "QUESTION: What color should I record?" in text1,
                "multiTurnMemory": "RECORDED_COLOR=blue" in text2 and "REMEMBERED_PREVIOUS_QUESTION=yes" in text2,
                "helperCommand": "HELPER_ARG=openclaw-arg" in text3,
                "helperCommandEnv": "HELPER_MARKER=openclaw-helper" in text3,
            }
            return {
                "ok": all(checks.values()),
                "runtime": "openclaw",
                "agent": agent,
                "sessionKey": session_key,
                "isolatedHome": str(isolation["isolatedHome"]),
                "configPath": str(isolation["configPath"]),
                "stateDir": str(isolation["stateDir"]),
                "gatewayPort": isolation["gatewayPort"],
                "checks": checks,
            }
        finally:
            stop_openclaw_gateway(gateway_process)
            stop_openclaw_source_config_watcher(args, run_dir, watcher)

    def probe_hermes(args, run_dir):
        executable = args.hermes_executable
        env = os.environ.copy()
        env["ZEBRA_REPLAY_PROBE_TOKEN"] = "hermes-token"
        turn1_message = (
            "Runtime replay probe turn 1. Do not modify files. Use terminal tools if needed. "
            "Report current working directory, value of env var ZEBRA_REPLAY_PROBE_TOKEN, "
            "and contents of ./probe.txt. Then end with exactly: QUESTION: What color should I record?"
        )
        turn1 = run_process(
            [executable, "chat", "-q", turn1_message, "--quiet"],
            cwd=run_dir,
            env=env,
            timeout=args.timeout + 30,
        )
        text1 = without_session_line(turn1["stdout"])
        session_id = hermes_session_id(turn1["stdout"] + "\\n" + turn1["stderr"])
        record_turn(run_dir, "hermes", "turn1", turn1, text1)
        if not session_id:
            return {"ok": False, "reason": "hermes_session_id_missing", "result": turn1}

        turn2_message = (
            "The color is blue. Runtime replay probe turn 2. Reply with exactly two lines: "
            "RECORDED_COLOR=<color> and REMEMBERED_PREVIOUS_QUESTION=<yes-or-no>."
        )
        turn2 = run_process(
            [executable, "chat", "--resume", session_id, "-q", turn2_message, "--quiet"],
            cwd=run_dir,
            timeout=args.timeout + 30,
        )
        text2 = without_session_line(turn2["stdout"])
        record_turn(run_dir, "hermes", "turn2", turn2, text2)

        turn3_message = (
            "Runtime replay probe turn 3. Run this exact helper command from the current directory: "
            "ZEBRA_REPLAY_HELPER_MARKER=hermes-helper ./probe-helper hermes-arg. "
            "Reply with only the helper output lines."
        )
        turn3 = run_process(
            [executable, "chat", "--resume", session_id, "-q", turn3_message, "--quiet"],
            cwd=run_dir,
            timeout=args.timeout + 30,
        )
        text3 = without_session_line(turn3["stdout"])
        record_turn(run_dir, "hermes", "turn3", turn3, text3)

        checks = {
            "promptInjection": turn1["exitCode"] == 0,
            "cwd": str(run_dir) in text1 or str(run_dir).replace("/tmp/", "/private/tmp/") in text1,
            "workspaceFileRead": "probe_file=ok" in text1,
            "questionObserved": "QUESTION: What color should I record?" in text1,
            "multiTurnMemory": "RECORDED_COLOR=blue" in text2 and "REMEMBERED_PREVIOUS_QUESTION=yes" in text2,
            "helperCommand": "HELPER_ARG=hermes-arg" in text3,
            "helperCommandEnv": "HELPER_MARKER=hermes-helper" in text3,
        }
        return {
            "ok": all(checks.values()),
            "runtime": "hermes",
            "sessionID": session_id,
            "checks": checks,
        }

    def command_probe(argv):
        parser = argparse.ArgumentParser(prog="zebra-source-replay probe")
        parser.add_argument("--runtime", choices=["openclaw", "hermes"], required=True)
        parser.add_argument("--root", default="/tmp/zebra-source-replay")
        parser.add_argument("--batch-id", default="probe")
        parser.add_argument("--run-id", default=None)
        parser.add_argument("--timeout", type=int, default=180)
        parser.add_argument("--openclaw-agent", default="")
        parser.add_argument("--openclaw-executable", default="openclaw")
        parser.add_argument("--openclaw-home", default="")
        parser.add_argument("--openclaw-gateway-port", type=int, default=0)
        parser.add_argument("--openclaw-skip-gateway", action="store_true")
        parser.add_argument("--hermes-executable", default="hermes")
        args = parser.parse_args(argv)
        args.run_id = args.run_id or ("run-" + uuid.uuid4().hex[:12])
        run_dir = make_run_dir(args.root, args.runtime, args.batch_id, args.run_id)
        write_probe_files(run_dir)
        manifest = {
            "schemaVersion": 1,
            "kind": "runtime-probe",
            "runtime": args.runtime,
            "batchID": args.batch_id,
            "runID": args.run_id,
            "runDirectory": str(run_dir),
        }
        write_json(run_dir / "replay-manifest.json", manifest)
        if args.runtime == "openclaw":
            summary = probe_openclaw(args, run_dir)
        else:
            summary = probe_hermes(args, run_dir)
        summary["runDirectory"] = str(run_dir)
        write_json(run_dir / "run-summary.json", summary)
        print(json.dumps(summary, indent=2, sort_keys=True))
        return 0 if summary.get("ok") else 1

    def add_run_arguments(parser):
        parser.add_argument("--runtime", choices=["openclaw", "hermes"], required=True)
        parser.add_argument("--root", default="/tmp/zebra-source-replay")
        parser.add_argument("--batch-id", default="manual")
        parser.add_argument("--run-id", default=None)
        parser.add_argument("--fixture", required=True)
        parser.add_argument("--prompt-file", default="")
        parser.add_argument("--prompt", default="")
        parser.add_argument("--state-path", default="")
        parser.add_argument("--timeout", type=int, default=180)
        parser.add_argument("--max-turns", type=int, default=8)
        parser.add_argument("--openclaw-agent", default="")
        parser.add_argument("--openclaw-executable", default="openclaw")
        parser.add_argument("--openclaw-home", default="")
        parser.add_argument("--openclaw-gateway-port", type=int, default=0)
        parser.add_argument("--openclaw-skip-gateway", action="store_true")
        parser.add_argument("--hermes-executable", default="hermes")

    def command_run(argv):
        parser = argparse.ArgumentParser(prog="zebra-source-replay run")
        add_run_arguments(parser)
        args = parser.parse_args(argv)
        summary = execute_run(args)
        print(json.dumps(sanitize_payload(summary), indent=2, sort_keys=True))
        return 0 if summary.get("ok") else 1

    def command_batch(argv):
        parser = argparse.ArgumentParser(prog="zebra-source-replay batch")
        add_run_arguments(parser)
        parser.add_argument("--run-count", type=int, default=3)
        args = parser.parse_args(argv)
        batch_dir = Path(args.root).expanduser() / "batch" / args.batch_id
        batch_dir.mkdir(parents=True, exist_ok=True)
        runs = []
        ok = True
        for index in range(1, args.run_count + 1):
            child_args = argparse.Namespace(**vars(args))
            child_args.run_id = args.run_id or f"{args.batch_id}-run-{index:02d}"
            summary = execute_run(child_args)
            runs.append(summary)
            ok = ok and bool(summary.get("ok"))
        batch_summary = {
            "ok": ok,
            "command": "batch",
            "runtime": args.runtime,
            "batchID": args.batch_id,
            "batchDirectory": str(batch_dir),
            "runCount": len(runs),
            "completedCount": len([run for run in runs if run.get("ok")]),
            "failedCount": len([run for run in runs if not run.get("ok")]),
            "runs": [
                {
                    "runDirectory": run.get("runDirectory"),
                    "ok": run.get("ok"),
                    "exitReason": run.get("exitReason"),
                    "interventionCount": run.get("interventionCount"),
                    "unansweredInterventions": run.get("unansweredInterventions"),
                }
                for run in runs
            ],
        }
        write_json_sanitized(batch_dir / "batch-summary.json", batch_summary)
        print(json.dumps(sanitize_payload(batch_summary), indent=2, sort_keys=True))
        return 0 if ok else 1

    def command_test(argv):
        parser = argparse.ArgumentParser(prog="zebra-source-replay test")
        parser.add_argument("scenario_id")
        parser.add_argument("--runtime", choices=["openclaw", "hermes"], default="")
        parser.add_argument("--root", default="/tmp/zebra-source-replay")
        parser.add_argument("--batch-id", default="")
        parser.add_argument("--run-id", default=None)
        parser.add_argument("--state-path", default="")
        parser.add_argument("--timeout", type=int, default=0)
        parser.add_argument("--max-turns", type=int, default=0)
        parser.add_argument("--input", action="append", default=[])
        parser.add_argument("--vault", default="")
        parser.add_argument("--runtime-state-path", default="")
        parser.add_argument("--openclaw-agent", default="")
        parser.add_argument("--openclaw-executable", default="")
        parser.add_argument("--openclaw-home", default="")
        parser.add_argument("--openclaw-gateway-port", type=int, default=0)
        parser.add_argument("--openclaw-skip-gateway", action="store_true")
        parser.add_argument("--hermes-executable", default="")
        args = parser.parse_args(argv)

        scenario, scenario_error, scenario_path = load_scenario(args.scenario_id)
        if scenario_error:
            report = {
                "ok": False,
                "command": "test",
                "scenarioID": args.scenario_id,
                "reason": scenario_error,
                "scenarioPath": str(scenario_path) if scenario_path else None,
            }
            print(json.dumps(report, indent=2, sort_keys=True))
            return 1

        fixture_path = resolve_fixture_path(scenario)
        if not fixture_path:
            report = {
                "ok": False,
                "command": "test",
                "scenarioID": args.scenario_id,
                "reason": "fixture_missing",
                "scenarioPath": str(scenario_path),
                "fixture": scenario.get("fixture"),
            }
            print(json.dumps(report, indent=2, sort_keys=True))
            return 1

        inputs = parse_key_value_inputs(args.input)
        if args.vault:
            inputs["vault"] = args.vault
        required_inputs = scenario.get("requiredInputs") if isinstance(scenario.get("requiredInputs"), list) else []
        missing_inputs = [key for key in required_inputs if not inputs.get(key)]
        if missing_inputs:
            report = {
                "ok": False,
                "command": "test",
                "scenarioID": args.scenario_id,
                "reason": "missing_required_input",
                "missingInputs": missing_inputs,
            }
            print(json.dumps(report, indent=2, sort_keys=True))
            return 1

        runtime_info, runtime_error = resolve_test_runtime(args)
        if runtime_error:
            report = {
                "ok": False,
                "command": "test",
                "scenarioID": args.scenario_id,
                **runtime_error,
            }
            print(json.dumps(report, indent=2, sort_keys=True))
            return 1

        runtime = runtime_info["runtime"]
        run_args = argparse.Namespace(
            runtime=runtime,
            root=args.root,
            batch_id=args.batch_id or scenario.get("defaultBatchID") or args.scenario_id.replace(".", "-"),
            run_id=args.run_id or ("run-" + uuid.uuid4().hex[:12]),
            fixture=str(fixture_path),
            prompt_file="",
            prompt=scenario.get("initialPrompt") or "",
            state_path=args.state_path,
            timeout=args.timeout or int(scenario.get("defaultTimeout") or 180),
            max_turns=args.max_turns or int(scenario.get("defaultMaxTurns") or 8),
            openclaw_agent=args.openclaw_agent,
            openclaw_executable=args.openclaw_executable or (runtime_info["executablePath"] if runtime == "openclaw" else "openclaw"),
            openclaw_home=args.openclaw_home,
            openclaw_gateway_port=args.openclaw_gateway_port,
            openclaw_skip_gateway=args.openclaw_skip_gateway,
            hermes_executable=args.hermes_executable or (runtime_info["executablePath"] if runtime == "hermes" else "hermes"),
            preflight_commands=scenario.get("preflightCommands") if isinstance(scenario.get("preflightCommands"), list) else [],
        )

        input_env = scenario.get("inputEnv") if isinstance(scenario.get("inputEnv"), dict) else {}
        previous_env = {}
        for key, env_name in input_env.items():
            if key not in inputs or not isinstance(env_name, str) or not env_name:
                continue
            previous_env[env_name] = os.environ.get(env_name)
            os.environ[env_name] = inputs[key]

        openclaw_before = None
        openclaw_after = None
        if runtime == "openclaw":
            before = openclaw_original_config_metadata(run_args)
            openclaw_before = before["metadata"]

        try:
            run_summary_payload = execute_run(run_args)
        finally:
            for env_name, value in previous_env.items():
                if value is None:
                    os.environ.pop(env_name, None)
                else:
                    os.environ[env_name] = value

        if runtime == "openclaw":
            after = openclaw_original_config_metadata(run_args)
            openclaw_after = after["metadata"]
            openclaw_config = {
                "path": before["path"],
                "before": openclaw_before,
                "after": openclaw_after,
                "unchanged": openclaw_before == openclaw_after,
            }
        else:
            openclaw_config = None

        excluded_roots = []
        openclaw_summary = run_summary_payload.get("openClaw") if isinstance(run_summary_payload.get("openClaw"), dict) else {}
        if openclaw_summary.get("isolatedHome"):
            excluded_roots.append(openclaw_summary["isolatedHome"])
        artifact_scan = scan_artifacts(
            run_summary_payload.get("runDirectory"),
            raw_inputs=list(inputs.values()),
            excluded_roots=excluded_roots,
        )
        summary_path = str(Path(run_summary_payload.get("runDirectory")) / "run-summary.json") if run_summary_payload.get("runDirectory") else None
        blocker = None
        if not run_summary_payload.get("ok"):
            blocker = {
                "reason": run_summary_payload.get("exitReason"),
                "unansweredInterventions": run_summary_payload.get("unansweredInterventions"),
            }
        ok = bool(run_summary_payload.get("ok")) and artifact_scan.get("ok") and (openclaw_config is None or openclaw_config.get("unchanged"))
        report = {
            "ok": ok,
            "command": "test",
            "scenarioID": args.scenario_id,
            "scenarioPath": str(scenario_path),
            "fixturePath": str(fixture_path),
            "runtime": runtime,
            "selectedRuntimeReceiptPath": runtime_info.get("statePath"),
            "runDirectory": run_summary_payload.get("runDirectory"),
            "summaryPath": summary_path,
            "runSummary": run_summary_payload,
            "openClawOriginalConfig": openclaw_config,
            "artifactScan": artifact_scan,
            "blocker": blocker,
            "nextAction": "inspect_run_artifacts",
        }
        write_json_sanitized(Path(run_summary_payload.get("runDirectory")) / "test-report.json", report)
        print(json.dumps(sanitize_payload(report), indent=2, sort_keys=True))
        return 0 if ok else 1

    def print_top_level_usage(stream=sys.stdout):
        print("usage: zebra-source-replay <probe|run|batch|test> ...", file=stream)
        print("", file=stream)
        print("commands:", file=stream)
        print("  probe   Run a runtime capability probe", file=stream)
        print("  run     Replay one source onboarding fixture", file=stream)
        print("  batch   Replay a fixture multiple times and summarize the batch", file=stream)
        print("  test    Replay a named source onboarding scenario", file=stream)

    def main():
        if len(sys.argv) < 2:
            print_top_level_usage(sys.stderr)
            return 2
        command = sys.argv[1]
        if command in ("--help", "-h", "help"):
            print_top_level_usage(sys.stdout)
            return 0
        if command == "probe":
            return command_probe(sys.argv[2:])
        if command == "run":
            return command_run(sys.argv[2:])
        if command == "batch":
            return command_batch(sys.argv[2:])
        if command == "test":
            return command_test(sys.argv[2:])
        print_top_level_usage(sys.stderr)
        return 2

    sys.exit(main())
    PY
    """
}
