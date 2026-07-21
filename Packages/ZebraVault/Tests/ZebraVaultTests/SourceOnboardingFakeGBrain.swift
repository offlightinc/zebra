import Foundation

enum SourceOnboardingFakeGBrain {
    static func install(
        root: URL,
        sourcePath: String,
        log: URL,
        eventLog: URL? = nil,
        sourceID: String = "brain"
    ) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let pageStore = root.appendingPathComponent("fake-gbrain-pages", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pageStore, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        let content = """
        #!/usr/bin/python3
        import hashlib
        import json
        import os
        import pathlib
        import sys
        import time

        args = sys.argv[1:]
        command = args[0] if args else ""
        scenario = os.environ.get("FAKE_GBRAIN_SCENARIO", "success")
        source = os.environ.get("GBRAIN_SOURCE", "")
        expected_source = \(pythonLiteral(sourceID))
        source_path = \(pythonLiteral(sourcePath))
        command_log = pathlib.Path(\(pythonLiteral(log.path)))
        event_log_value = \(pythonLiteral(eventLog?.path ?? ""))
        event_log = pathlib.Path(event_log_value) if event_log_value else None
        store = pathlib.Path(\(pythonLiteral(pageStore.path)))
        store.mkdir(parents=True, exist_ok=True)

        with command_log.open("a", encoding="utf-8") as handle:
            handle.write(" ".join(args) + "\\n")

        def event(name, **values):
            if event_log is None:
                return
            payload = {"command": name, "arguments": args[1:], "source": source}
            payload.update(values)
            with event_log.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(payload, sort_keys=True) + "\\n")

        event(command)

        if command == "doctor":
            print(json.dumps({"ok": True}))
            raise SystemExit(0)

        if command == "sources" and len(args) > 1 and args[1] == "current":
            current = "wrong-brain" if scenario == "wrong-source" else expected_source
            current_path = source_path + "/wrong-target" if scenario == "wrong-target" else source_path
            print(json.dumps({"source_id": current, "local_path": current_path}))
            raise SystemExit(0)

        if command == "sources" and len(args) > 1 and args[1] == "list":
            print(json.dumps({"sources": [{"id": expected_source, "local_path": source_path}]}))
            raise SystemExit(0)

        if command == "import":
            if scenario == "import-exit":
                raise SystemExit(9)
            if scenario == "malformed-json":
                print("not json")
                raise SystemExit(0)
            staging = pathlib.Path(args[1])
            if scenario == "slow-import":
                time.sleep(3)
            manifest = json.loads((staging / "zebra-ingest-manifest.json").read_text(encoding="utf-8"))
            event("staging-manifest", manifest=manifest)
            overlap = store / "import-active"
            if scenario == "detect-overlap":
                try:
                    overlap.mkdir()
                except FileExistsError:
                    print("overlap", file=sys.stderr)
                    raise SystemExit(17)
                time.sleep(0.25)
            files = [path for path in staging.rglob("*.md")]
            files_to_write = files[:-1] if scenario == "partial-retry" else files
            for path in files_to_write:
                text = path.read_text(encoding="utf-8")
                slug = next(line.split(":", 1)[1].strip() for line in text.splitlines() if line.startswith("slug:"))
                key = hashlib.sha256(slug.encode()).hexdigest()
                (store / (key + ".md")).write_text(text, encoding="utf-8")
            errors = 1 if scenario in ("numeric-errors", "partial-retry") else 0
            imported = max(0, len(files) - 1) if scenario in ("count-mismatch", "partial-retry") else len(files)
            payload = {"status": "success", "imported": imported, "skipped": 0, "errors": errors}
            if scenario == "write-through":
                payload["writeThrough"] = {"ok": False}
            if overlap.exists():
                overlap.rmdir()
            print(json.dumps(payload))
            raise SystemExit(0)

        if command == "put":
            slug = args[1]
            text = sys.stdin.read()
            key = hashlib.sha256(slug.encode()).hexdigest()
            (store / (key + ".md")).write_text(text, encoding="utf-8")
            if scenario == "malformed-put":
                print("not json")
            elif scenario == "put-ok-false":
                print(json.dumps({"ok": False, "error": "rejected"}))
            else:
                print(json.dumps({"ok": True}))
            raise SystemExit(0)

        if command == "get":
            if scenario == "missing-readback":
                raise SystemExit(4)
            slug = args[1]
            key = hashlib.sha256(slug.encode()).hexdigest()
            path = store / (key + ".md")
            if not path.is_file():
                raise SystemExit(4)
            text = path.read_text(encoding="utf-8")
            if scenario == "identity-mismatch":
                text = text.replace("zebra_identity_digest:", "zebra_identity_digest: deadbeef #")
            print(text, end="")
            raise SystemExit(0)

        raise SystemExit(2)
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    static func writeCompletedState(
        to stateURL: URL,
        vaultPath: String,
        executablePath: String,
        sourceRepoPath: String? = nil
    ) throws {
        let targetKey = "vault:\(vaultPath)"
        let timestamp = "2026-06-04T00:00:00Z"
        let target: [String: Any] = [
            "vaultPath": vaultPath,
            "sourceId": "brain",
            "gbrainExecutablePath": executablePath,
            "doctorStatus": ["ok": true, "status": "ok"],
            "sourcesCurrentResult": ["ok": true, "sourceId": "brain", "localPath": vaultPath],
            "searchProbeResult": ["ok": true, "status": "not_run"],
            "verifiedAt": timestamp,
            "complete": true,
            "targetResolution": ["method": "user_created_repo", "confirmedAt": timestamp],
            "reasons": [],
        ]
        var state: [String: Any] = [
            "schemaVersion": 1,
            "progress": [
                "resolvedTargetKey": targetKey,
                "targetResolution": [
                    "status": "verified",
                    "method": "user_created_repo",
                    "confirmedAt": timestamp,
                ],
            ],
            "receipt": [
                "globalReadiness": [
                    "complete": true,
                    "gbrainExecutablePath": executablePath,
                    "doctorOk": true,
                    "verifiedAt": timestamp,
                ],
                "primaryTargetKey": targetKey,
                "targets": [targetKey: target],
            ],
        ]
        if let sourceRepoPath {
            state["activeGBrainBinding"] = [
                "sourceRepoPath": sourceRepoPath,
                "sourceRepoStatus": "existing",
                "gbrainHomePath": sourceRepoPath,
                "confirmedAt": timestamp,
            ]
        }
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: stateURL, options: .atomic)
    }

    private static func pythonLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return (data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\"")
            .replacingOccurrences(of: "\\/", with: "/")
    }
}
