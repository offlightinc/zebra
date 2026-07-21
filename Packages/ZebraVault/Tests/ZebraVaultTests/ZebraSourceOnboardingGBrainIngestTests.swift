import Foundation
import XCTest
@testable import ZebraVault

final class ZebraSourceOnboardingGBrainIngestTests: XCTestCase {
    func testBulkImportUsesExplicitVerifiedSourceAndExactReadback() throws {
        let fixture = try Fixture()
        let result = try fixture.run(records: [
            fixture.record(id: "one", body: "first body"),
            fixture.record(id: "two", body: "second body"),
        ])

        XCTAssertEqual(result["complete"] as? Bool, true)
        XCTAssertNil(result["failure"] as? String)
        XCTAssertEqual(result["verifiedRecordCount"] as? Int, 2)

        let events = try fixture.events()
        let importEvent = try XCTUnwrap(events.first { $0["command"] as? String == "import" })
        let arguments = try XCTUnwrap(importEvent["arguments"] as? [String])
        XCTAssertTrue(arguments.contains("--source-id"))
        XCTAssertTrue(arguments.contains("verified-brain"))
        XCTAssertTrue(arguments.contains("--fresh"))
        XCTAssertTrue(arguments.contains("--json"))
        XCTAssertEqual(events.filter { $0["command"] as? String == "get" }.count, 2)
        XCTAssertTrue(events.allSatisfy { $0["source"] as? String == "verified-brain" })
    }

    func testCommonFailuresBlockCompletion() throws {
        let cases: [(scenario: String, failure: String)] = [
            ("import-exit", "importProcessFailed"),
            ("malformed-json", "importResultMalformed"),
            ("numeric-errors", "importCountMismatch"),
            ("count-mismatch", "importCountMismatch"),
            ("wrong-source", "sourceRoutingMismatch"),
            ("missing-readback", "readbackMissing"),
            ("identity-mismatch", "readbackIdentityMismatch"),
            ("write-through", "writeThroughFailed"),
        ]

        for item in cases {
            let fixture = try Fixture(scenario: item.scenario)
            let result = try fixture.run(records: [
                fixture.record(id: "one", body: "first body"),
                fixture.record(id: "two", body: "second body"),
            ])
            XCTAssertEqual(result["complete"] as? Bool, false, item.scenario)
            XCTAssertEqual(result["failure"] as? String, item.failure, item.scenario)
        }
    }

    func testIncompleteAcquisitionBlocksWriteAndSingleRecordUsesPut() throws {
        let incomplete = try Fixture()
        let blocked = try incomplete.run(
            records: [incomplete.record(id: "one", body: "body")],
            acquisitionComplete: false
        )
        XCTAssertEqual(blocked["complete"] as? Bool, false)
        XCTAssertEqual(blocked["failure"] as? String, "acquisitionIncomplete")
        XCTAssertTrue(try incomplete.events().isEmpty)

        let single = try Fixture()
        let completed = try single.run(records: [single.record(id: "one", body: "body")])
        XCTAssertEqual(completed["complete"] as? Bool, true)
        let events = try single.events()
        XCTAssertEqual(events.filter { $0["command"] as? String == "put" }.count, 1)
        XCTAssertEqual(events.filter { $0["command"] as? String == "import" }.count, 0)
        XCTAssertEqual(events.filter { $0["command"] as? String == "get" }.count, 1)
    }

    func testSinglePutRequiresStructuredResultAndOversizedRecordUsesBulkImport() throws {
        let malformed = try Fixture(scenario: "malformed-put")
        let rejected = try malformed.run(records: [malformed.record(id: "one", body: "body")])
        XCTAssertEqual(rejected["complete"] as? Bool, false)
        XCTAssertEqual(rejected["failure"] as? String, "importResultMalformed")

        let oversized = try Fixture()
        let completed = try oversized.run(records: [
            oversized.record(id: "large", body: String(repeating: "x", count: 5_000_001)),
        ])
        XCTAssertEqual(completed["complete"] as? Bool, true)
        let events = try oversized.events()
        XCTAssertEqual(events.filter { $0["command"] as? String == "import" }.count, 1)
        XCTAssertEqual(events.filter { $0["command"] as? String == "put" }.count, 0)
    }

    func testBulkAttemptsSharingGBrainHomeAreSerialized() throws {
        let fixture = try Fixture(scenario: "detect-overlap")
        let results = try fixture.runConcurrently(records: [
            fixture.record(id: "one", body: "first"),
            fixture.record(id: "two", body: "second"),
        ])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0["complete"] as? Bool == true })
        XCTAssertEqual(try fixture.events().filter { $0["command"] as? String == "import" }.count, 2)
    }
}

private extension ZebraSourceOnboardingGBrainIngestTests {
    final class Fixture {
        let root: URL
        let runtime: URL
        let executable: URL
        let log: URL
        let store: URL
        let scenario: String

        init(scenario: String = "success") throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ZebraSourceOnboardingGBrainIngestTests-\(UUID().uuidString)",
                isDirectory: true
            )
            let state = root.appendingPathComponent("onboarding/source-onboarding-state.json")
            let helper = ZebraSourceOnboardingHelper(
                stateURL: state,
                gbrainOnboardingStateURL: root.appendingPathComponent("gbrain.json"),
                gbrainAdapterOnboardingStateURL: root.appendingPathComponent("adapter.json"),
                homeDirectoryPath: root.path
            )
            guard let launch = helper.prepareLaunch(selectedVaultPath: nil) else {
                throw FixtureError.runtimeInstallFailed
            }
            runtime = state.deletingLastPathComponent().appendingPathComponent(
                "source-onboarding-runtime",
                isDirectory: true
            )
            executable = root.appendingPathComponent("fake-gbrain", isDirectory: false)
            log = root.appendingPathComponent("events.jsonl", isDirectory: false)
            store = root.appendingPathComponent("readback", isDirectory: true)
            self.scenario = scenario
            try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
            try Self.fakeGBrain.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: launch.helperPath))
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func record(id: String, body: String) -> [String: Any] {
            [
                "connectorID": "obsidian",
                "logicalRecordID": id,
                "slug": "sources/obsidian/\(id)",
                "markdown": body,
                "originURI": "obsidian://\(id)",
            ]
        }

        func run(records: [[String: Any]], acquisitionComplete: Bool = true) throws -> [String: Any] {
            let request = request(records: records, acquisitionComplete: acquisitionComplete)
            let input = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
            let harness = root.appendingPathComponent("harness.py", isDirectory: false)
            let harnessText = """
            import json
            import sys
            sys.path.insert(0, \(String(reflecting: runtime.path)))
            from gbrain_ingest import run_ingest
            print(json.dumps(run_ingest(json.load(sys.stdin)), sort_keys=True))
            """
            try harnessText.write(to: harness, atomically: true, encoding: .utf8)
            return try runHarness(harness, input: input)
        }

        func runConcurrently(records: [[String: Any]]) throws -> [[String: Any]] {
            let requests = [
                request(records: records, acquisitionComplete: true),
                request(records: records, acquisitionComplete: true),
            ]
            let input = try JSONSerialization.data(withJSONObject: requests, options: [.sortedKeys])
            let harness = root.appendingPathComponent("concurrent-harness.py", isDirectory: false)
            let harnessText = """
            import concurrent.futures
            import json
            import sys
            sys.path.insert(0, \(String(reflecting: runtime.path)))
            from gbrain_ingest import run_ingest
            requests = json.load(sys.stdin)
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(run_ingest, requests))
            print(json.dumps(results, sort_keys=True))
            """
            try harnessText.write(to: harness, atomically: true, encoding: .utf8)
            let result = try runHarness(harness, input: input)
            return try XCTUnwrap(result["results"] as? [[String: Any]])
        }

        private func request(records: [[String: Any]], acquisitionComplete: Bool) -> [String: Any] {
            [
                "attemptID": UUID().uuidString,
                "binding": [
                    "executable": executable.path,
                    "workingDirectory": root.path,
                    "sourceID": "verified-brain",
                    "environment": [
                        "FAKE_GBRAIN_LOG": log.path,
                        "FAKE_GBRAIN_STORE": store.path,
                        "FAKE_GBRAIN_SCENARIO": scenario,
                        "GBRAIN_HOME": root.appendingPathComponent("gbrain-home", isDirectory: true).path,
                    ],
                ],
                "acquisition": [
                    "discoveredCount": records.count,
                    "selectedCount": records.count,
                    "normalizedCount": records.count,
                    "failedCount": acquisitionComplete ? 0 : 1,
                    "diagnosticCount": 0,
                    "cancelled": false,
                    "complete": acquisitionComplete,
                ],
                "records": records,
            ]
        }

        private func runHarness(_ harness: URL, input: Data) throws -> [String: Any] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-I", harness.path]
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            stdin.fileHandleForWriting.write(input)
            stdin.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, error)
            let object = try JSONSerialization.jsonObject(with: output)
            if let dictionary = object as? [String: Any] { return dictionary }
            if let array = object as? [[String: Any]] { return ["results": array] }
            throw FixtureError.invalidHarnessOutput(error)
        }

        func events() throws -> [[String: Any]] {
            guard FileManager.default.fileExists(atPath: log.path) else { return [] }
            return try String(contentsOf: log, encoding: .utf8)
                .split(separator: "\n")
                .map { line in
                    try XCTUnwrap(
                        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                    )
                }
        }

        enum FixtureError: Error {
            case runtimeInstallFailed
            case invalidHarnessOutput(String)
        }

        static let fakeGBrain = #"""
        #!/usr/bin/python3
        import hashlib
        import json
        import os
        import pathlib
        import shutil
        import sys
        import time

        args = sys.argv[1:]
        command = args[0] if args else ""
        scenario = os.environ.get("FAKE_GBRAIN_SCENARIO", "success")
        source = os.environ.get("GBRAIN_SOURCE", "")
        log = pathlib.Path(os.environ["FAKE_GBRAIN_LOG"])
        store = pathlib.Path(os.environ["FAKE_GBRAIN_STORE"])
        store.mkdir(parents=True, exist_ok=True)
        with log.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"command": command, "arguments": args[1:], "source": source}) + "\n")

        if command == "sources":
            current = "wrong-brain" if scenario == "wrong-source" else "verified-brain"
            print(json.dumps({"sourceId": current, "localPath": os.getcwd()}))
            raise SystemExit(0)

        if command == "import":
            if scenario == "import-exit":
                raise SystemExit(9)
            if scenario == "malformed-json":
                print("not json")
                raise SystemExit(0)
            staging = pathlib.Path(args[1])
            overlap = store / "import-active"
            if scenario == "detect-overlap":
                try:
                    overlap.mkdir()
                except FileExistsError:
                    print("overlap", file=sys.stderr)
                    raise SystemExit(17)
                time.sleep(0.25)
            files = [path for path in staging.rglob("*.md")]
            for path in files:
                text = path.read_text(encoding="utf-8")
                slug = next(line.split(":", 1)[1].strip() for line in text.splitlines() if line.startswith("slug:"))
                (store / (hashlib.sha256(slug.encode()).hexdigest() + ".md")).write_text(text, encoding="utf-8")
            errors = 1 if scenario == "numeric-errors" else 0
            imported = max(0, len(files) - 1) if scenario == "count-mismatch" else len(files)
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
            (store / (hashlib.sha256(slug.encode()).hexdigest() + ".md")).write_text(text, encoding="utf-8")
            print("not json" if scenario == "malformed-put" else json.dumps({"ok": True}))
            raise SystemExit(0)

        if command == "get":
            if scenario == "missing-readback":
                raise SystemExit(4)
            slug = args[1]
            text = (store / (hashlib.sha256(slug.encode()).hexdigest() + ".md")).read_text(encoding="utf-8")
            if scenario == "identity-mismatch":
                text = text.replace("zebra_identity_digest:", "zebra_identity_digest: deadbeef #")
            print(text, end="")
            raise SystemExit(0)

        raise SystemExit(2)
        """#
    }
}
