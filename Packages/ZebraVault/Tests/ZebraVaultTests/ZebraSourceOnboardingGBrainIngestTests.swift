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

        let diagnosticEvents = try fixture.events()
        XCTAssertEqual(result["complete"] as? Bool, true, "result: \(result), events: \(diagnosticEvents)")
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
        let manifestEvent = try XCTUnwrap(events.first { $0["command"] as? String == "staging-manifest" })
        let manifest = try XCTUnwrap(manifestEvent["manifest"] as? [String: Any])
        let manifestRecords = try XCTUnwrap(manifest["records"] as? [[String: Any]])
        XCTAssertEqual(manifestRecords.compactMap { $0["relativePath"] as? String }, ["obsidian/one.md", "obsidian/two.md"])
        XCTAssertEqual(manifestRecords.compactMap { $0["slug"] as? String }, ["sources/obsidian/one", "sources/obsidian/two"])
        XCTAssertTrue(manifestRecords.allSatisfy { ($0["identityDigest"] as? String)?.count == 64 })
        let privateRoot = fixture.root.appendingPathComponent("private-staging", isDirectory: true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: privateRoot.path).allSatisfy {
            !$0.hasPrefix("zebra-gbrain-ingest-")
        })
    }

    func testCommonFailuresBlockCompletion() throws {
        let cases: [(scenario: String, failure: String)] = [
            ("import-exit", "importProcessFailed"),
            ("malformed-json", "importResultMalformed"),
            ("numeric-errors", "importCountMismatch"),
            ("count-mismatch", "importCountMismatch"),
            ("missing-runtime", "gbrainRuntimeMissing"),
            ("wrong-target", "targetBindingMismatch"),
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
            let privateRoot = fixture.root.appendingPathComponent("private-staging", isDirectory: true)
            if FileManager.default.fileExists(atPath: privateRoot.path) {
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: privateRoot.path).allSatisfy {
                    !$0.hasPrefix("zebra-gbrain-ingest-")
                }, item.scenario)
            }
        }

        let duplicate = try Fixture()
        let duplicateRecord = duplicate.record(id: "same", body: "body")
        let stagingFailure = try duplicate.run(records: [duplicateRecord, duplicateRecord])
        XCTAssertEqual(stagingFailure["complete"] as? Bool, false)
        XCTAssertEqual(stagingFailure["failure"] as? String, "stagingFailed")
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

    func testAcquisitionCountsDiagnosticsAndCancellationAreReconciledCentrally() throws {
        let cases: [([String: Any], String)] = [
            (["failedCount": 1], "acquisitionIncomplete"),
            (["diagnosticCount": 1], "acquisitionIncomplete"),
            (["normalizedCount": 0], "acquisitionIncomplete"),
            (["selectedCount": 2, "discoveredCount": 1], "acquisitionIncomplete"),
            (["cancelled": true], "cancelled"),
        ]
        for (override, expectedFailure) in cases {
            let fixture = try Fixture()
            let result = try fixture.run(
                records: [fixture.record(id: "one", body: "body")],
                acquisitionOverride: override
            )
            XCTAssertEqual(result["complete"] as? Bool, false, "\(override)")
            XCTAssertEqual(result["failure"] as? String, expectedFailure, "\(override)")
            XCTAssertTrue(try fixture.events().isEmpty, "\(override)")
        }
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

    func testEveryCommonFailureBlocksInstalledCLICompletionReport() throws {
        let failures = [
            "acquisitionIncomplete", "stagingFailed", "gbrainRuntimeMissing",
            "targetBindingMismatch", "sourceRoutingMismatch", "importProcessFailed",
            "importResultMalformed", "importCountMismatch", "readbackMissing",
            "readbackIdentityMismatch", "writeThroughFailed", "cancelled",
        ]
        for failure in failures {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ZebraSourceOnboardingCompletionGateTests-\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: root) }
            let stateURL = root.appendingPathComponent("onboarding/source-onboarding-state.json")
            let helper = ZebraSourceOnboardingHelper(stateURL: stateURL, homeDirectoryPath: root.path)
            let launch = try helper.prepareLaunchResult(selectedVaultPath: nil).get()
            let runStateURL = stateURL.deletingLastPathComponent()
                .appendingPathComponent("source-run-state/obsidian.json")
            try FileManager.default.createDirectory(at: runStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let acquisitionComplete = failure != "acquisitionIncomplete" && failure != "cancelled"
            let acquisition: [String: Any] = [
                "discoveredCount": 1, "selectedCount": 1,
                "normalizedCount": acquisitionComplete ? 1 : 0,
                "failedCount": acquisitionComplete ? 0 : 1,
                "diagnosticCount": 0, "cancelled": failure == "cancelled",
                "complete": acquisitionComplete,
            ]
            let runState: [String: Any] = [
                "acquisitionReceipt": acquisition,
                "ingestReceipt": [
                    "complete": false, "failure": failure,
                    "expectedRecordCount": 1, "verifiedRecordCount": 0,
                ],
                "completionReportPending": true,
                "completionDisposition": "checked",
            ]
            try JSONSerialization.data(withJSONObject: runState, options: [.sortedKeys])
                .write(to: runStateURL, options: .atomic)
            let state: [String: Any] = [
                "schemaVersion": 1,
                "status": "running",
                "progress": [
                    "normalizedSourceList": ["obsidian"],
                    "confirmedSourceList": ["obsidian"],
                    "executionOrder": ["obsidian"],
                    "activeSourceID": "obsidian",
                    "sourceRows": [
                        "obsidian": [
                            "sourceID": "obsidian", "displayName": "Obsidian",
                            "status": "running", "phase": "complete",
                            "selectionState": "confirmed",
                            "playbookID": "obsidian.direct-markdown",
                            "playbookVersion": "v1", "playbookStepID": "complete",
                            "runStatePath": runStateURL.path,
                        ],
                    ],
                ],
            ]
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
                .write(to: stateURL, options: .atomic)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: launch.helperPath)
            process.arguments = ["report", "--status", "completed", "--source", "obsidian"]
            process.environment = ProcessInfo.processInfo.environment.merging([
                "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            ]) { _, replacement in replacement }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            XCTAssertEqual(process.terminationStatus, 1, failure)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
            XCTAssertEqual(payload["reason"] as? String, failure, failure)
            let persisted = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
            )
            let progress = try XCTUnwrap(persisted["progress"] as? [String: Any])
            let rows = try XCTUnwrap(progress["sourceRows"] as? [String: Any])
            let row = try XCTUnwrap(rows["obsidian"] as? [String: Any])
            XCTAssertEqual(row["status"] as? String, "running", failure)
        }
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
            log = root.appendingPathComponent("events.jsonl", isDirectory: false)
            store = root.appendingPathComponent("fake-gbrain-pages", isDirectory: true)
            self.scenario = scenario
            executable = try SourceOnboardingFakeGBrain.install(
                root: root,
                sourcePath: root.path,
                log: root.appendingPathComponent("commands.log", isDirectory: false),
                eventLog: log,
                sourceID: "verified-brain"
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: launch.helperPath))
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func record(id: String, body: String) -> [String: Any] {
            return [
                "connectorID": "obsidian",
                "logicalRecordID": id,
                "slug": "sources/obsidian/\(id)",
                "markdown": body,
                "originURI": "obsidian://\(id)",
            ]
        }

        func run(
            records: [[String: Any]],
            acquisitionComplete: Bool = true,
            acquisitionOverride: [String: Any] = [:]
        ) throws -> [String: Any] {
            let request = request(
                records: records,
                acquisitionComplete: acquisitionComplete,
                acquisitionOverride: acquisitionOverride
            )
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
                request(records: records, acquisitionComplete: true, acquisitionOverride: [:]),
                request(records: records, acquisitionComplete: true, acquisitionOverride: [:]),
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

        private func request(
            records: [[String: Any]],
            acquisitionComplete: Bool,
            acquisitionOverride: [String: Any]
        ) -> [String: Any] {
            var acquisition: [String: Any] = [
                "discoveredCount": records.count,
                "selectedCount": records.count,
                "normalizedCount": records.count,
                "failedCount": acquisitionComplete ? 0 : 1,
                "diagnosticCount": 0,
                "cancelled": false,
                "complete": acquisitionComplete,
            ]
            acquisition.merge(acquisitionOverride) { _, replacement in replacement }
            return [
                "attemptID": UUID().uuidString,
                "binding": [
                    "executable": scenario == "missing-runtime"
                        ? root.appendingPathComponent("missing-gbrain").path
                        : executable.path,
                    "workingDirectory": root.path,
                    "sourceID": "verified-brain",
                    "environment": [
                        "FAKE_GBRAIN_SCENARIO": scenario,
                        "GBRAIN_HOME": root.appendingPathComponent("gbrain-home", isDirectory: true).path,
                    ],
                ],
                "privateRoot": root.appendingPathComponent("private-staging", isDirectory: true).path,
                "acquisition": acquisition,
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
    }
}
