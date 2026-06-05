import XCTest
@testable import ZebraVault

final class ZebraOnboardingChecklistStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(
            forKey: "ZebraOnboardingChecklistStore.developmentCompletedStepIDs"
        )
    }

    @MainActor
    func testChecklistInsertsRuntimeSetupBeforeGBrainAndShiftsNumbers() throws {
        let root = try makeTemporaryDirectory()
        let runtimeStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )

        XCTAssertEqual(
            store.snapshots.map { $0.id },
            [.agent, .gbrainRuntime, .gbrain, .adapter, .email, .ingest, .goals]
        )
        XCTAssertEqual(store.snapshots.map { $0.number }, [1, 2, 3, 4, 5, 6, 7])
    }

    @MainActor
    func testCompletedRuntimeReceiptCompletesRuntimeStepOnly() throws {
        let root = try makeTemporaryDirectory()
        let executable = try installFakeRuntime(root: root, name: "hermes")
        let runtimeStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )

        XCTAssertTrue(store.completedStepIDs.contains(.gbrainRuntime))
        XCTAssertFalse(store.completedStepIDs.contains(.gbrain))
    }

    @MainActor
    func testRuntimeReceiptWithoutLLMCallCheckDoesNotCompleteRuntimeStep() throws {
        let root = try makeTemporaryDirectory()
        let executable = try installFakeRuntime(root: root, name: "hermes")
        let runtimeStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path,
            llmCallVerified: false
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )

        XCTAssertFalse(store.completedStepIDs.contains(.gbrainRuntime))
    }

    @MainActor
    func testRuntimeReceiptWithoutRuntimeConfigCheckDoesNotCompleteRuntimeStep() throws {
        let root = try makeTemporaryDirectory()
        let executable = try installFakeRuntime(root: root, name: "hermes")
        let runtimeStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path,
            runtimeConfigVerified: false
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )

        XCTAssertFalse(store.completedStepIDs.contains(.gbrainRuntime))
    }

    func testRuntimeHelperStatusRuns() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )

        XCTAssertNotNil(store.prepareLaunch())
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["status"],
            environment: [
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("\"statePath\""))
    }

    func testRuntimeHelperStatusFindsHermesLauncherOutsidePath() throws {
        let root = try makeTemporaryDirectory()
        _ = try installFakeRuntime(
            directory: root
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true),
            name: "hermes"
        )
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )

        XCTAssertNotNil(store.prepareLaunch())
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["status"],
            environment: [
                "PATH": "/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        let status = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )
        let detection = try XCTUnwrap(status["detection"] as? [String: Any])
        let hermes = try XCTUnwrap(detection["hermes"] as? [String: Any])

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(hermes["installed"] as? Bool, true)
        XCTAssertEqual(
            hermes["path"] as? String,
            root
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("hermes", isDirectory: false)
                .path
        )
    }

    func testRuntimeHelperConfiguresHermesProviderModelAndBaseURLTogether() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let log = root.appendingPathComponent("hermes.log", isDirectory: false)
        _ = try installFakeHermesRuntime(directory: fakeBin, log: log)
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en-US"],
            currentLocaleIdentifier: "en_US"
        )

        XCTAssertNotNil(store.prepareLaunch())
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let expectScript = root.appendingPathComponent("run-helper.expect", isDirectory: false)
        let expectContent = """
        set timeout 20
        spawn env PATH=$env(TEST_PATH) ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en OPENAI_API_KEY=test-openai-key $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select API provider"
        send "2\\r"
        expect eof
        set result [wait]
        exit [lindex $result 3]
        """
        try expectContent.write(to: expectScript, atomically: true, encoding: .utf8)

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/expect"),
            arguments: [expectScript.path],
            environment: [
                "TEST_PATH": "\(fakeBin.path):/usr/bin:/bin",
                "TEST_STATE": stateURL.path,
                "TEST_HOME": root.path,
                "TEST_HELPER": helperURL.path,
            ]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("config set model.provider openai-api"))
        XCTAssertTrue(logText.contains("config set model.default gpt-5-mini"))
        XCTAssertTrue(logText.contains("config set model.base_url https://api.openai.com/v1"))
        XCTAssertTrue(logText.contains("config set model.api_mode codex_responses"))
        XCTAssertTrue(logText.contains("chat -q Reply with OK. Do not use tools. --provider openai-api --model gpt-5-mini"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai-api")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "gpt-5-mini")
        let envText = try String(
            contentsOf: root
                .appendingPathComponent(".hermes", isDirectory: true)
                .appendingPathComponent(".env", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(envText.contains("OPENAI_API_KEY=test-openai-key"))
    }

    func testRuntimeHelperRejectsHermesWarningOnlyVerification() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let log = root.appendingPathComponent("hermes.log", isDirectory: false)
        _ = try installFakeHermesRuntime(
            directory: fakeBin,
            log: log,
            chatBody: """
              echo 'warning only' >&2
              exit 0
            """
        )
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en-US"],
            currentLocaleIdentifier: "en_US"
        )

        XCTAssertNotNil(store.prepareLaunch())
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let expectScript = root.appendingPathComponent("run-helper.expect", isDirectory: false)
        let expectContent = """
        set timeout 20
        spawn env PATH=$env(TEST_PATH) ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en OPENAI_API_KEY=test-openai-key $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select API provider"
        send "2\\r"
        expect eof
        set result [wait]
        exit [lindex $result 3]
        """
        try expectContent.write(to: expectScript, atomically: true, encoding: .utf8)

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/expect"),
            arguments: [expectScript.path],
            environment: [
                "TEST_PATH": "\(fakeBin.path):/usr/bin:/bin",
                "TEST_STATE": stateURL.path,
                "TEST_HOME": root.path,
                "TEST_HELPER": helperURL.path,
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["complete"] as? Bool, false)
        XCTAssertEqual(receipt["reasons"] as? [String], ["llm_call_verification_failed"])
    }

    @MainActor
    func testCompletedGBrainReceiptDoesNotRunLiveProbeFromChecklist() async throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("gbrain-probe.log", isDirectory: false)
        let executable = try installFakeGBrain(root: root, sourcePath: vault.path, log: log)
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        try writeCompletedGBrainState(stateURL: stateURL, vaultPath: vault.path, executablePath: executable.path)

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false),
            gbrainOnboardingStateURL: stateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path, emailConnected: false)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(store.completedStepIDs.contains(.gbrain))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: log.path),
            "Completed receipts should be trusted by the checklist without running gbrain doctor/current/list."
        )
    }

    private func writeCompletedRuntimeState(
        stateURL: URL,
        runtime: String,
        executablePath: String,
        llmCallVerified: Bool = true,
        runtimeConfigVerified: Bool = true
    ) throws {
        let state: [String: Any] = [
            "schemaVersion": 1,
            "receipt": [
                "complete": true,
                "runtime": runtime,
                "executablePath": executablePath,
                "version": "\(runtime) test",
                "provider": "openai",
                "keySource": "env:OPENAI_API_KEY",
                "configPaths": [:],
                "verifiedAt": "2026-06-04T00:00:00Z",
                "checks": [
                    "executable": true,
                    "credentials": true,
                    "runtimeConfigCommand": runtimeConfigVerified,
                    "llmCall": llmCallVerified,
                ],
                "reasons": [],
            ],
        ]
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func writeCompletedGBrainState(
        stateURL: URL,
        vaultPath: String,
        executablePath: String
    ) throws {
        let targetKey = "vault:\(vaultPath)"
        let timestamp = "2026-06-04T00:00:00Z"
        let target: [String: Any] = [
            "vaultPath": vaultPath,
            "sourceId": "brain",
            "gbrainExecutablePath": executablePath,
            "doctorStatus": ["ok": true, "status": "ok"],
            "sourcesCurrentResult": [
                "ok": true,
                "sourceId": "brain",
                "localPath": vaultPath,
            ],
            "searchProbeResult": ["ok": true, "status": "not_run"],
            "verifiedAt": timestamp,
            "complete": true,
            "targetResolution": [
                "method": "user_created_repo",
                "confirmedAt": timestamp,
            ],
            "reasons": [],
        ]
        let state: [String: Any] = [
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
                "targets": [
                    targetKey: target,
                ],
            ],
        ]
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func installFakeGBrain(root: URL, sourcePath: String, log: URL) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        echo "$@" >> '\(shellSingleQuoted(log.path))'
        if [ "$1" = "doctor" ]; then
          echo '{"ok":true}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"brain"}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          echo '{"sources":[{"id":"brain","local_path":"\(jsonEscaped(sourcePath))"}]}'
          exit 0
        fi
        exit 0
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdoutText, stderrText)
    }

    private func installFakeRuntime(root: URL, name: String) throws -> URL {
        try installFakeRuntime(
            directory: root.appendingPathComponent("bin", isDirectory: true),
            name: name
        )
    }

    private func installFakeRuntime(directory: URL, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(name, isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo '\(name) test'
          exit 0
        fi
        exit 0
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func installFakeHermesRuntime(
        directory: URL,
        log: URL,
        chatBody: String = """
          echo 'OK'
          exit 0
        """
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("hermes", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(shellSingleQuoted(log.path))'
        if [ "$1" = "--version" ]; then
          echo 'hermes test'
          exit 0
        fi
        if [ "$1" = "config" ] && [ "$2" = "set" ]; then
          exit 0
        fi
        if [ "$1" = "chat" ]; then
        \(chatBody)
        fi
        exit 1
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func shellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraOnboardingChecklistStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
