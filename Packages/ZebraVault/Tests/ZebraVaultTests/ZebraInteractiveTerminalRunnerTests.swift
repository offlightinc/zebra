import Foundation
import XCTest
@testable import ZebraVault

final class ZebraInteractiveTerminalRunnerTests: XCTestCase {
    private struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zebra-interactive-terminal-runner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]
    ) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func installedRunner(in root: URL) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        return try XCTUnwrap(ZebraInteractiveTerminalRunner.install(in: bin))
    }

    private func startEnvironment(root: URL, fakeCLI: URL) -> [String: String] {
        [
            "ZEBRA_INTERACTIVE_TERMINAL_RUNNER_STATE_DIR": root.appendingPathComponent("state").path,
            "CMUX_BUNDLED_CLI_PATH": fakeCLI.path,
            "CMUX_SOCKET_PATH": root.appendingPathComponent("zebra.sock").path,
            "CMUX_WORKSPACE_ID": "workspace-1",
            "CMUX_PANE_ID": "pane-1",
            "ZEBRA_INTERACTIVE_TERMINAL_RUNNER_WAIT": "0",
        ]
    }

    private func makeFakeCLI(in root: URL) throws -> (url: URL, calls: URL) {
        let calls = root.appendingPathComponent("cmux-calls.txt")
        let cli = root.appendingPathComponent("fake-cmux")
        try writeExecutable(
            """
            #!/bin/sh
            printf '%s\n' "$*" >> '\(calls.path)'
            printf '%s\n' '{"surface_id":"surface-task-1","workspace_id":"workspace-1"}'
            """,
            to: cli
        )
        return (cli, calls)
    }

    func testStartCreatesTypedRequestAndCmuxSurfaceOnce() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let fake = try makeFakeCLI(in: root)
        let environment = startEnvironment(root: root, fakeCLI: fake.url)
        let arguments = ["start", "--task", "fixture-success", "--run-id", "run-1"]

        let first = try run(runner, arguments, environment: environment)
        XCTAssertEqual(first.status, 0, first.stderr)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(first.stdout.utf8)) as? [String: Any]
        )
        let request = try XCTUnwrap(payload["request"] as? [String: Any])
        let requestID = try XCTUnwrap(request["id"] as? String)
        XCTAssertEqual(request["kind"] as? String, "fixture-success")
        XCTAssertEqual(request["payload"] as? [String: String], [:])

        let callsAfterFirst = try String(contentsOf: fake.calls, encoding: .utf8)
        XCTAssertTrue(callsAfterFirst.contains("rpc surface.create"), callsAfterFirst)
        XCTAssertTrue(callsAfterFirst.contains("workspace-1"), callsAfterFirst)
        XCTAssertTrue(callsAfterFirst.contains("pane-1"), callsAfterFirst)
        XCTAssertTrue(callsAfterFirst.contains("execute --request"), callsAfterFirst)
        XCTAssertTrue(callsAfterFirst.contains(requestID), callsAfterFirst)

        let second = try run(runner, arguments, environment: environment)
        XCTAssertEqual(second.status, 0, second.stderr)
        let duplicate = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(second.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(duplicate["duplicate"] as? Bool, true)
        XCTAssertEqual(try String(contentsOf: fake.calls, encoding: .utf8), callsAfterFirst)
    }

    func testSuccessAndFailureFixturesWriteExecutableReceipts() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let fake = try makeFakeCLI(in: root)
        var environment = startEnvironment(root: root, fakeCLI: fake.url)
        environment["ZEBRA_INTERACTIVE_TERMINAL_RUNNER_KEEP_SHELL"] = "0"

        for (task, runID, expectedExit, expectedStatus) in [
            ("fixture-success", "success-run", Int32(0), "succeeded"),
            ("fixture-failure", "failure-run", Int32(42), "failed"),
            ("fixture-cancel", "cancel-run", Int32(130), "canceled"),
        ] {
            let started = try run(
                runner,
                ["start", "--task", task, "--run-id", runID],
                environment: environment
            )
            XCTAssertEqual(started.status, 0, started.stderr)
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(started.stdout.utf8)) as? [String: Any]
            )
            let request = try XCTUnwrap(payload["request"] as? [String: Any])
            let requestID = try XCTUnwrap(request["id"] as? String)

            let executed = try run(
                runner,
                ["execute", "--request", requestID],
                environment: environment.merging(["CMUX_SURFACE_ID": "surface-(task)"]) { _, new in new }
            )
            XCTAssertEqual(executed.status, expectedExit, executed.stderr)

            let status = try run(runner, ["status", "--request", requestID], environment: environment)
            XCTAssertEqual(status.status, 0, status.stderr)
            let statusPayload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(status.stdout.utf8)) as? [String: Any]
            )
            let receipt = try XCTUnwrap(statusPayload["receipt"] as? [String: Any])
            XCTAssertEqual(receipt["status"] as? String, expectedStatus)
            XCTAssertEqual((receipt["exitCode"] as? NSNumber)?.int32Value, expectedExit)
        }
    }

    func testLaunchFailureCanRetryTheSameLogicalRequest() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let calls = root.appendingPathComponent("retry-calls.txt")
        let fakeCLI = root.appendingPathComponent("retry-cmux")
        try writeExecutable(
            """
            #!/bin/sh
            printf 'call\n' >> '\(calls.path)'
            count="$(/usr/bin/wc -l < '\(calls.path)' | /usr/bin/tr -d ' ')"
            if [ "$count" = "1" ]; then exit 1; fi
            printf '%s\n' '{"surface_id":"surface-retry","workspace_id":"workspace-1"}'
            """,
            to: fakeCLI
        )
        let environment = startEnvironment(root: root, fakeCLI: fakeCLI)
        let arguments = ["start", "--task", "fixture-success", "--run-id", "retry-run"]

        let first = try run(runner, arguments, environment: environment)
        XCTAssertNotEqual(first.status, 0)
        let second = try run(runner, arguments, environment: environment)
        XCTAssertEqual(second.status, 0, second.stderr)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(second.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(payload["duplicate"] as? Bool, true)
        XCTAssertEqual(try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").count, 2)
    }

    func testStaleRunningReceiptCanRetryTheSameLogicalRequest() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let fake = try makeFakeCLI(in: root)
        var environment = startEnvironment(root: root, fakeCLI: fake.url)
        let arguments = ["start", "--task", "fixture-success", "--run-id", "stale-run"]
        let first = try run(runner, arguments, environment: environment)
        XCTAssertEqual(first.status, 0, first.stderr)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(first.stdout.utf8)) as? [String: Any]
        )
        let request = try XCTUnwrap(payload["request"] as? [String: Any])
        let requestID = try XCTUnwrap(request["id"] as? String)
        let receiptURL = root.appendingPathComponent("state/receipts/\(requestID).json")
        let staleReceipt: [String: Any] = [
            "schemaVersion": 1,
            "requestID": requestID,
            "status": "running",
            "updatedAt": "2000-01-01T00:00:00+00:00",
        ]
        try JSONSerialization.data(withJSONObject: staleReceipt).write(to: receiptURL, options: .atomic)
        environment["ZEBRA_INTERACTIVE_TERMINAL_RUNNER_STALE_SECONDS"] = "1"

        let retried = try run(runner, arguments, environment: environment)
        XCTAssertEqual(retried.status, 0, retried.stderr)
        XCTAssertEqual(try String(contentsOf: fake.calls, encoding: .utf8).split(separator: "\n").count, 2)
    }

    func testStartWaitsForFastChildCompletionWithoutDowngradingReceipt() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let fakeCLI = root.appendingPathComponent("executing-cmux")
        try writeExecutable(
            """
            #!/bin/sh
            json="$3"
            command="$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1])["initial_command"])' "$json")"
            /bin/sh -c "$command" >/dev/null
            printf '%s\n' '{"surface_id":"surface-fast","workspace_id":"workspace-1"}'
            """,
            to: fakeCLI
        )
        var environment = startEnvironment(root: root, fakeCLI: fakeCLI)
        environment.removeValue(forKey: "ZEBRA_INTERACTIVE_TERMINAL_RUNNER_WAIT")
        environment["ZEBRA_INTERACTIVE_TERMINAL_RUNNER_WAIT_TIMEOUT"] = "5"

        let result = try run(
            runner,
            ["start", "--task", "fixture-success", "--run-id", "fast-run"],
            environment: environment
        )
        XCTAssertEqual(result.status, 0, result.stderr)
        let finalLine = try XCTUnwrap(result.stdout.split(separator: "\n").last)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(finalLine.utf8)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(payload["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["status"] as? String, "succeeded")
        XCTAssertEqual(receipt["surfaceID"] as? String, "surface-fast")
    }

    func testSuccessfulChildRestoresTheOriginSurface() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let calls = root.appendingPathComponent("focus-calls.txt")
        let fakeCLI = root.appendingPathComponent("focus-cmux")
        try writeExecutable(
            """
            #!/bin/sh
            printf '%s\n' "$*" >> '\(calls.path)'
            if [ "$2" = "surface.create" ]; then
              json="$3"
              command="$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1])["initial_command"])' "$json")"
              /bin/sh -c "$command" >/dev/null
              printf '%s\n' '{"surface_id":"surface-task","workspace_id":"workspace-1"}'
            else
              printf '%s\n' '{"ok":true}'
            fi
            """,
            to: fakeCLI
        )
        var environment = startEnvironment(root: root, fakeCLI: fakeCLI)
        environment.removeValue(forKey: "ZEBRA_INTERACTIVE_TERMINAL_RUNNER_WAIT")
        environment["ZEBRA_INTERACTIVE_TERMINAL_RUNNER_WAIT_TIMEOUT"] = "5"
        environment["CMUX_SURFACE_ID"] = "surface-origin"

        let result = try run(
            runner,
            ["start", "--task", "fixture-success", "--run-id", "focus-run"],
            environment: environment
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let recorded = try String(contentsOf: calls, encoding: .utf8)
        XCTAssertTrue(recorded.contains("rpc surface.focus"), recorded)
        XCTAssertTrue(recorded.contains("surface-origin"), recorded)
        let finalLine = try XCTUnwrap(result.stdout.split(separator: "\n").last)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(finalLine.utf8)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(payload["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["originFocusStatus"] as? String, "focused")
    }

    func testFailedChildPrintsRecoveryInstructionsBeforeShellHandoff() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let fake = try makeFakeCLI(in: root)
        var environment = startEnvironment(root: root, fakeCLI: fake.url)
        environment["ZEBRA_INTERACTIVE_TERMINAL_RUNNER_KEEP_SHELL"] = "0"
        environment["ZEBRA_ONBOARDING_LANGUAGE"] = "en"
        let started = try run(
            runner,
            ["start", "--task", "fixture-failure", "--run-id", "failure-help"],
            environment: environment
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(started.stdout.utf8)) as? [String: Any]
        )
        let request = try XCTUnwrap(payload["request"] as? [String: Any])
        let requestID = try XCTUnwrap(request["id"] as? String)

        let failed = try run(
            runner,
            ["execute", "--request", requestID],
            environment: environment
        )

        XCTAssertEqual(failed.status, 42)
        XCTAssertTrue(failed.stderr.contains("Task failed"), failed.stderr)
        XCTAssertTrue(failed.stderr.contains("status --request \(requestID)"), failed.stderr)
        XCTAssertTrue(failed.stderr.contains("exit"), failed.stderr)
    }

    func testRejectsArbitraryCommandsSecretsAndUnsupportedSourcesBeforeLaunch() throws {
        let root = try temporaryDirectory()
        let runner = try installedRunner(in: root)
        let fake = try makeFakeCLI(in: root)
        let environment = startEnvironment(root: root, fakeCLI: fake.url)

        let secretSentinel = "super-secret-sentinel-93841"
        let attempts = [
            ["start", "--task", "fixture-success", "--run-id", "run", "--command", "sudo whoami"],
            ["start", "--task", "fixture-success", "--run-id", "run", "--secret", secretSentinel],
            ["start", "--task", "fixture-success", "--run-id", "secret value"],
            ["start", "--task", "source-onboarding-homebrew-install", "--source", "unknown", "--run-id", "run"],
        ]
        for arguments in attempts {
            let result = try run(runner, arguments, environment: environment)
            XCTAssertNotEqual(result.status, 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fake.calls.path))
        let stateRoot = root.appendingPathComponent("state")
        if let enumerator = FileManager.default.enumerator(at: stateRoot, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator where !file.hasDirectoryPath {
                let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                XCTAssertFalse(contents.contains(secretSentinel), file.path)
            }
        }
    }
}
