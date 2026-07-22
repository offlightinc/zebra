import Foundation
import XCTest
@testable import ZebraVault

final class ZebraSourceOnboardingGBrainIngestTests: XCTestCase {
    func testBulkImportAcceptsNoisyJSONAndStagesAtPathAuthoritativeSlugs() throws {
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
        XCTAssertFalse(arguments.contains("--fresh"))
        XCTAssertTrue(arguments.contains("--json"))
        XCTAssertEqual(events.filter { $0["command"] as? String == "put" }.count, 0)
        XCTAssertEqual(events.filter { $0["command"] as? String == "get" }.count, 2)
        XCTAssertTrue(events.allSatisfy { $0["source"] as? String == "verified-brain" })
        let manifestEvent = try XCTUnwrap(events.first { $0["command"] as? String == "staging-manifest" })
        let manifest = try XCTUnwrap(manifestEvent["manifest"] as? [String: Any])
        let manifestRecords = try XCTUnwrap(manifest["records"] as? [[String: Any]])
        XCTAssertEqual(
            manifestRecords.compactMap { $0["relativePath"] as? String },
            ["sources/obsidian/one.md", "sources/obsidian/two.md"]
        )
        XCTAssertEqual(manifestRecords.compactMap { $0["slug"] as? String }, ["sources/obsidian/one", "sources/obsidian/two"])
        XCTAssertTrue(manifestRecords.allSatisfy { ($0["identityDigest"] as? String)?.count == 64 })
        let filesystem = try XCTUnwrap(result["filesystem"] as? [String: Any])
        XCTAssertEqual(filesystem["state"] as? String, "verified")
        let index = try XCTUnwrap(result["index"] as? [String: Any])
        XCTAssertEqual(index["fresh"] as? Bool, false)
        let operationReceiptPath = try XCTUnwrap(result["operationReceiptPath"] as? String)
        let durableReceipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: operationReceiptPath)))
                as? [String: Any]
        )
        XCTAssertEqual(durableReceipt["state"] as? String, "complete")
        XCTAssertEqual(durableReceipt["complete"] as? Bool, true)
        for record in manifestRecords {
            let relativePath = try XCTUnwrap(record["relativePath"] as? String)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(relativePath).path))
        }
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

    func testIncompleteAcquisitionBlocksWriteAndSingleRecordUsesFileImport() throws {
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
        XCTAssertEqual(events.filter { $0["command"] as? String == "put" }.count, 0)
        XCTAssertEqual(events.filter { $0["command"] as? String == "import" }.count, 1)
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

    func testSingleFileImportRequiresStructuredResultAndHandlesLargeRecord() throws {
        let malformed = try Fixture(scenario: "malformed-json")
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

    func testTransientImportRetriesTwiceThenSucceeds() throws {
        let retryFixture = try Fixture(scenario: "transient-import")
        let retried = try retryFixture.run(records: [
            retryFixture.record(id: "one", body: "body"),
        ])
        XCTAssertEqual(retried["complete"] as? Bool, true)
        let events = try retryFixture.events()
        XCTAssertEqual(events.filter { $0["command"] as? String == "import" }.count, 3)
        XCTAssertEqual(events.filter { $0["command"] as? String == "put" }.count, 0)
        let index = try XCTUnwrap(retried["index"] as? [String: Any])
        XCTAssertEqual(index["attemptCount"] as? Int, 3)
    }

    func testBulkFailureIsIsolatedAndRetriedWithFileImport() throws {
        let retryFixture = try Fixture(scenario: "partial-retry")
        let retried = try retryFixture.run(records: [
            retryFixture.record(id: "one", body: "first"),
            retryFixture.record(id: "two", body: "second"),
        ])
        XCTAssertEqual(retried["complete"] as? Bool, true)
        XCTAssertNil(retried["failure"] as? String)
        let events = try retryFixture.events()
        XCTAssertEqual(events.filter { $0["command"] as? String == "import" }.count, 2)
        XCTAssertEqual(events.filter { $0["command"] as? String == "put" }.count, 0)
        XCTAssertEqual(events.filter { $0["command"] as? String == "get" }.count, 3)
    }

    func testPersistentTransientFailureStopsAfterThreeAttemptsAndKeepsCanonicalFile() throws {
        let fixture = try Fixture(scenario: "import-exit")
        let result = try fixture.run(records: [fixture.record(id: "one", body: "body")])

        XCTAssertEqual(result["complete"] as? Bool, false)
        XCTAssertEqual(result["state"] as? String, "indexPending")
        XCTAssertEqual(result["retryable"] as? Bool, true)
        let index = try XCTUnwrap(result["index"] as? [String: Any])
        XCTAssertEqual(index["attemptCount"] as? Int, 3)
        let imports = try fixture.events().filter { $0["command"] as? String == "import" }
        XCTAssertEqual(imports.count, 3)
        let importRoots = imports.compactMap { ($0["arguments"] as? [String])?.first }
        XCTAssertEqual(Set(importRoots).count, 3)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("sources/obsidian/one.md").path
        ))
    }

    func testConfigurationFailureDoesNotAutomaticallyRetry() throws {
        let fixture = try Fixture(scenario: "configuration-error")
        let result = try fixture.run(records: [fixture.record(id: "one", body: "body")])

        XCTAssertEqual(result["complete"] as? Bool, false)
        XCTAssertEqual(result["failure"] as? String, "indexConfigurationFailed")
        XCTAssertEqual(result["retryable"] as? Bool, false)
        XCTAssertEqual(try fixture.events().filter { $0["command"] as? String == "import" }.count, 1)
    }

    func testUserModifiedCanonicalFileIsPreservedAndBlocksReimport() throws {
        let fixture = try Fixture()
        let original = fixture.record(id: "one", body: "first")
        XCTAssertEqual(try fixture.run(records: [original])["complete"] as? Bool, true)
        let canonical = fixture.root.appendingPathComponent("sources/obsidian/one.md")
        var edited = try String(contentsOf: canonical, encoding: .utf8)
        edited += "user note\n"
        try edited.write(to: canonical, atomically: true, encoding: .utf8)
        let importCountBefore = try fixture.events().filter { $0["command"] as? String == "import" }.count

        let result = try fixture.run(records: [fixture.record(id: "one", body: "updated source")])

        XCTAssertEqual(result["complete"] as? Bool, false)
        XCTAssertEqual(result["failure"] as? String, "filesystemConflict")
        XCTAssertEqual(try String(contentsOf: canonical, encoding: .utf8), edited)
        XCTAssertEqual(
            try fixture.events().filter { $0["command"] as? String == "import" }.count,
            importCountBefore
        )
    }

    func testCanonicalFileChangedDuringImportPreventsCompletion() throws {
        let fixture = try Fixture(scenario: "mutate-canonical")
        let result = try fixture.run(records: [fixture.record(id: "one", body: "body")])

        XCTAssertEqual(result["complete"] as? Bool, false)
        XCTAssertEqual(result["failure"] as? String, "filesystemConflict")
        XCTAssertEqual(result["state"] as? String, "conflict")
        let canonical = fixture.root.appendingPathComponent("sources/obsidian/one.md")
        XCTAssertTrue(try String(contentsOf: canonical, encoding: .utf8).hasSuffix("user edit\n"))
    }

    func testCancellationAfterRouteVerificationIsNotRetryable() throws {
        let fixture = try Fixture(scenario: "cancel-after-route")
        let result = try fixture.runCancelledAfterRoute(records: [fixture.record(id: "one", body: "body")])

        XCTAssertEqual(result["complete"] as? Bool, false)
        XCTAssertEqual(result["failure"] as? String, "cancelled")
        XCTAssertEqual(result["retryable"] as? Bool, false)
        XCTAssertTrue(try fixture.events().filter { $0["command"] as? String == "import" }.isEmpty)
    }

    func testConnectorCannotOverrideDeterministicSlug() throws {
        let fixture = try Fixture()
        var record = fixture.record(id: "one", body: "body")
        record["slug"] = "sources/another-source/attacker-selected"

        let result = try fixture.run(records: [record])

        XCTAssertEqual(result["complete"] as? Bool, false)
        XCTAssertEqual(result["failure"] as? String, "stagingFailed")
        XCTAssertTrue(try fixture.events().allSatisfy {
            !["put", "import", "get"].contains($0["command"] as? String ?? "")
        })
    }

    func testReconcilerRejectsInconsistentWrongScopedAndDuplicateReadbacks() throws {
        let fixture = try Fixture()
        let acquisition: [String: Any] = [
            "discoveredCount": 2, "selectedCount": 2, "normalizedCount": 2,
            "failedCount": 0, "diagnosticCount": 0, "cancelled": false, "complete": true,
        ]
        let write: [String: Any] = ["failure": NSNull(), "sourceID": "verified-brain"]
        let cases: [([[String: Any]], String)] = [
            ([
                ["slug": "sources/obsidian/one", "sourceID": "verified-brain", "identityMatch": false, "failure": NSNull()],
                ["slug": "sources/obsidian/two", "sourceID": "verified-brain", "identityMatch": true, "failure": NSNull()],
            ], "readbackIdentityMismatch"),
            ([
                ["slug": "sources/obsidian/wrong", "sourceID": "verified-brain", "identityMatch": true, "failure": NSNull()],
                ["slug": "sources/obsidian/two", "sourceID": "verified-brain", "identityMatch": true, "failure": NSNull()],
            ], "readbackIdentityMismatch"),
            ([
                ["slug": "sources/obsidian/one", "sourceID": "wrong-brain", "identityMatch": true, "failure": NSNull()],
                ["slug": "sources/obsidian/two", "sourceID": "verified-brain", "identityMatch": true, "failure": NSNull()],
            ], "sourceRoutingMismatch"),
            ([
                ["slug": "sources/obsidian/one", "sourceID": "verified-brain", "identityMatch": true, "failure": NSNull()],
                ["slug": "sources/obsidian/one", "sourceID": "verified-brain", "identityMatch": true, "failure": NSNull()],
            ], "readbackMissing"),
        ]
        let expected = ["sources/obsidian/one", "sources/obsidian/two"]
        for (readbacks, failure) in cases {
            let result = try fixture.reconcile(
                acquisition: acquisition,
                write: write,
                readbacks: readbacks,
                expectedSlugs: expected,
                expectedSourceID: "verified-brain"
            )
            XCTAssertEqual(result["complete"] as? Bool, false, "\(readbacks)")
            XCTAssertEqual(result["failure"] as? String, failure, "\(readbacks)")
        }
    }

    func testCancellationDuringBulkImportTerminatesAttempt() throws {
        let fixture = try Fixture(scenario: "slow-import")
        let started = Date()
        let result = try fixture.runCancellingDuringProcess(records: [
            fixture.record(id: "one", body: "first"),
            fixture.record(id: "two", body: "second"),
        ])

        XCTAssertEqual(result["complete"] as? Bool, false)
        XCTAssertEqual(result["failure"] as? String, "cancelled")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
        XCTAssertTrue(try fixture.events().filter { $0["command"] as? String == "get" }.isEmpty)
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
            "readbackIdentityMismatch", "writeThroughFailed", "filesystemPersistFailed",
            "filesystemConflict", "indexConfigurationFailed", "cancelled",
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

        func reconcile(
            acquisition: [String: Any],
            write: [String: Any],
            readbacks: [[String: Any]],
            expectedSlugs: [String],
            expectedSourceID: String
        ) throws -> [String: Any] {
            let input = try JSONSerialization.data(withJSONObject: [
                "acquisition": acquisition,
                "write": write,
                "readbacks": readbacks,
                "expectedSlugs": expectedSlugs,
                "expectedSourceID": expectedSourceID,
            ], options: [.sortedKeys])
            let harness = root.appendingPathComponent("reconcile-harness.py", isDirectory: false)
            let harnessText = """
            import json
            import sys
            sys.path.insert(0, \(String(reflecting: runtime.path)))
            from domain import reconciliation
            value = json.load(sys.stdin)
            print(json.dumps(reconciliation(
                value["acquisition"], value["write"], value["readbacks"],
                len(value["expectedSlugs"]), expected_slugs=value["expectedSlugs"],
                expected_source_id=value["expectedSourceID"]
            ), sort_keys=True))
            """
            try harnessText.write(to: harness, atomically: true, encoding: .utf8)
            return try runHarness(harness, input: input)
        }

        func runCancellingDuringProcess(records: [[String: Any]]) throws -> [String: Any] {
            let cancellation = root.appendingPathComponent("cancel-requested", isDirectory: false)
            var value = request(records: records, acquisitionComplete: true, acquisitionOverride: [:])
            value["cancellationPath"] = cancellation.path
            let input = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            let harness = root.appendingPathComponent("cancellation-harness.py", isDirectory: false)
            let harnessText = """
            import json
            import sys
            sys.path.insert(0, \(String(reflecting: runtime.path)))
            from gbrain_ingest import run_ingest
            print(json.dumps(run_ingest(json.load(sys.stdin)), sort_keys=True))
            """
            try harnessText.write(to: harness, atomically: true, encoding: .utf8)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                FileManager.default.createFile(atPath: cancellation.path, contents: Data())
            }
            return try runHarness(harness, input: input)
        }

        func runCancelledAfterRoute(records: [[String: Any]]) throws -> [String: Any] {
            let cancellation = root.appendingPathComponent("cancel-after-route", isDirectory: false)
            var value = request(records: records, acquisitionComplete: true, acquisitionOverride: [:])
            value["cancellationPath"] = cancellation.path
            var binding = try XCTUnwrap(value["binding"] as? [String: Any])
            var environment = try XCTUnwrap(binding["environment"] as? [String: String])
            environment["FAKE_GBRAIN_CANCELLATION_PATH"] = cancellation.path
            binding["environment"] = environment
            value["binding"] = binding
            let input = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            let harness = root.appendingPathComponent("cancel-after-route-harness.py", isDirectory: false)
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
            let value: [String: Any] = [
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
                "persistCanonical": true,
                "retryDelays": [0, 0],
                "acquisition": acquisition,
                "records": records,
            ]
            return value
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
