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

    func testSelectedRuntimeForGBrainSetupReadsCompletedReceipt() throws {
        let root = try makeTemporaryDirectory()
        let executable = try installFakeRuntime(root: root, name: "openclaw")
        let runtimeStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "openclaw",
            executablePath: executable.path
        )

        let runtime = ZebraGBrainRuntimeOnboardingStore(
            stateURL: runtimeStateURL,
            homeDirectoryPath: root.path
        ).selectedRuntimeForGBrainSetup()

        XCTAssertEqual(runtime?.runtime, "openclaw")
        XCTAssertEqual(runtime?.executablePath, executable.path)
    }

    func testGBrainStartupLinePreparesSourceRepoBeforeRuntimeLaunch() throws {
        let launch = ZebraGBrainOnboardingStore.LaunchContext(
            launchDirectory: "/tmp/zebra-gbrain-work",
            startupPrompt: "setup prompt",
            setupPacketPath: "/tmp/zebra-gbrain-packet.md",
            runId: "gbrain-test-run",
            shellEnvironmentPrefix: "export ZEBRA_GBRAIN_STATE='/tmp/state.json' && ",
            allowTrustedAutomation: true,
            allowLaunchDirectoryTrust: false
        )
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "hermes",
            executablePath: "/tmp/hermes"
        )

        let line = ZebraOnboardingChecklistCommand.gbrainSetupRuntimeStartupLine(
            launch: launch,
            runtime: runtime
        )

        XCTAssertTrue(line.contains("zebra-gbrain-onboarding prepare-source-repo"), line)
        XCTAssertTrue(line.contains("eval \"$(zebra-gbrain-onboarding active-source-env)\""), line)
        XCTAssertTrue(line.contains("zebra-gbrain-onboarding write-setup-packet --path '/tmp/zebra-gbrain-packet.md'"), line)
        XCTAssertTrue(line.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\" && '/tmp/hermes' chat"), line)
        XCTAssertTrue(line.contains("--source zebra-gbrain-onboarding"), line)
        XCTAssertTrue(line.contains("--query 'setup prompt'"), line)
        XCTAssertFalse(line.contains(" codex"), line)
        let prepareRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding prepare-source-repo"))
        let envRange = try XCTUnwrap(line.range(of: "eval \"$(zebra-gbrain-onboarding active-source-env)\""))
        let packetRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding write-setup-packet"))
        let launchRange = try XCTUnwrap(line.range(of: "cd \"$ZEBRA_GBRAIN_SOURCE_REPO\" && '/tmp/hermes' chat"))
        XCTAssertLessThan(prepareRange.lowerBound, envRange.lowerBound)
        XCTAssertLessThan(envRange.lowerBound, packetRange.lowerBound)
        XCTAssertLessThan(packetRange.lowerBound, launchRange.lowerBound)
    }

    func testGBrainStartupLineUsesOpenClawRuntimeWhenSelected() throws {
        let launch = ZebraGBrainOnboardingStore.LaunchContext(
            launchDirectory: "/tmp/zebra-gbrain-work",
            startupPrompt: "setup prompt",
            setupPacketPath: "/tmp/zebra-gbrain-packet.md",
            runId: "gbrain-ABCDEF12-3456-7890",
            shellEnvironmentPrefix: "export ZEBRA_GBRAIN_STATE='/tmp/state.json' && ",
            allowTrustedAutomation: true,
            allowLaunchDirectoryTrust: false
        )
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "openclaw",
            executablePath: "/tmp/openclaw"
        )

        let line = ZebraOnboardingChecklistCommand.gbrainSetupRuntimeStartupLine(
            launch: launch,
            runtime: runtime
        )

        XCTAssertTrue(
            line.contains("zebra-gbrain-onboarding prepare-openclaw-agent --executable '/tmp/openclaw' --agent-id 'zebra-gbrain-setup-12-3456-7890'"),
            line
        )
        XCTAssertTrue(line.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\" && '/tmp/openclaw' tui"), line)
        XCTAssertTrue(line.contains("--session 'agent:zebra-gbrain-setup-12-3456-7890:gbrain-ABCDEF12-3456-7890'"), line)
        XCTAssertTrue(line.contains("--local"), line)
        XCTAssertTrue(line.contains("--message 'setup prompt'"), line)
        XCTAssertFalse(line.contains("agents list --json"), line)
        XCTAssertFalse(line.contains("agents add"), line)
        XCTAssertFalse(line.contains("--session zebra-gbrain-setup"), line)
        XCTAssertFalse(line.contains(" codex"), line)
        let prepareRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding prepare-source-repo"))
        let envRange = try XCTUnwrap(line.range(of: "eval \"$(zebra-gbrain-onboarding active-source-env)\""))
        let packetRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding write-setup-packet"))
        let agentRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding prepare-openclaw-agent"))
        let launchRange = try XCTUnwrap(line.range(of: "cd \"$ZEBRA_GBRAIN_SOURCE_REPO\" && '/tmp/openclaw' tui"))
        XCTAssertLessThan(prepareRange.lowerBound, envRange.lowerBound)
        XCTAssertLessThan(envRange.lowerBound, packetRange.lowerBound)
        XCTAssertLessThan(packetRange.lowerBound, agentRange.lowerBound)
        XCTAssertLessThan(agentRange.lowerBound, launchRange.lowerBound)
    }

    @MainActor
    func testGBrainPrepareAbortShowsStartAgain() throws {
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
        store.beginLaunch(stepID: .gbrain)

        XCTAssertEqual(store.runningStepID, .gbrain)
        XCTAssertEqual(store.snapshots.first { $0.id == .gbrain }?.isRunning, true)
        XCTAssertEqual(store.snapshots.first { $0.id == .gbrain }?.showsStart, false)

        try writeGBrainPrepareAbortState(stateURL: gbrainStateURL)
        store.refreshDetectedCompletion()

        XCTAssertNil(store.runningStepID)
        XCTAssertEqual(store.snapshots.first { $0.id == .gbrain }?.isRunning, false)
        XCTAssertEqual(store.snapshots.first { $0.id == .gbrain }?.showsStart, true)
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

    func testRuntimeHelperUsesOpenAICodexAccountLoginByDefault() throws {
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
        try writeAgentReadinessState(
            onboardingDirectory: stateURL.deletingLastPathComponent(),
            agent: "codex",
            method: "codex login status"
        )
        let codexDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try #"{"tokens":{"access_token":"test-codex-access-token","refresh_token":"test-codex-refresh-token"}}"#.write(
            to: codexDirectory.appendingPathComponent("auth.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let expectScript = root.appendingPathComponent("run-helper.expect", isDirectory: false)
        let expectContent = """
        set timeout 20
        spawn env PATH=$env(TEST_PATH) ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en OPENAI_API_KEY=ambient-openai-key $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        XCTAssertTrue(logText.contains("auth status openai-codex"))
        XCTAssertFalse(logText.contains("login --provider openai-codex"))
        XCTAssertFalse(logText.contains("auth add openai-codex"))
        XCTAssertTrue(logText.contains("config set model.provider openai-codex"))
        XCTAssertTrue(logText.contains("config set model.default gpt-5.4"))
        XCTAssertTrue(logText.contains("config set model.base_url https://chatgpt.com/backend-api/codex"))
        XCTAssertTrue(logText.contains("config set model.api_mode codex_responses"))
        XCTAssertTrue(logText.contains("chat -q Reply with OK. Do not use tools. --provider openai-codex --model gpt-5.4"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "gpt-5.4")
        XCTAssertEqual(receipt["keySource"] as? String, "agent-cli:codex-auth-status")
        XCTAssertEqual(receipt["keyEnvName"] as? String, "")
        XCTAssertEqual(receipt["keyPersistedEnvName"] as? String, "")
        let authStore = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: root
                        .appendingPathComponent(".hermes", isDirectory: true)
                        .appendingPathComponent("auth.json", isDirectory: false)
                )
            ) as? [String: Any]
        )
        let providers = try XCTUnwrap(authStore["providers"] as? [String: Any])
        XCTAssertNotNil(providers["openai-codex"])
        let credentialPool = try XCTUnwrap(authStore["credential_pool"] as? [String: Any])
        let codexPool = try XCTUnwrap(credentialPool["openai-codex"] as? [[String: Any]])
        XCTAssertEqual(codexPool.first?["source"] as? String, "device_code")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(".hermes", isDirectory: true)
                    .appendingPathComponent(".env", isDirectory: false)
                    .path
            )
        )
    }

    func testRuntimeHelperUsesOpenClawOpenAIAuthLoginInsteadOfNonInteractiveCodexOnboard() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let log = root.appendingPathComponent("openclaw.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: log)
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
        spawn env PATH=$env(TEST_PATH) ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        XCTAssertTrue(logText.contains("models auth login --provider openai --method oauth --set-default"))
        XCTAssertFalse(logText.contains("onboard --non-interactive"))
        XCTAssertFalse(logText.contains("--auth-choice openai-codex"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai")
        XCTAssertEqual(receipt["keySource"] as? String, "openai-codex:oauth")
    }

    func testRuntimeHelperSkipsOpenClawOpenAILoginWhenProfileAlreadyUsable() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let log = root.appendingPathComponent("openclaw.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: log)
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
        spawn env PATH=$env(TEST_PATH) FAKE_OPENCLAW_AUTH_READY=openai ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        XCTAssertTrue(logText.contains("models status --json --probe-provider openai"))
        XCTAssertFalse(logText.contains("models auth login --provider openai"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai")
        XCTAssertEqual(receipt["keySource"] as? String, "openai-codex:oauth")
    }

    func testRuntimeHelperWaitsBrieflyWhenOpenClawAuthLoginHangsAfterProfileBecomesUsable() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let log = root.appendingPathComponent("openclaw.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: log)
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
        spawn env PATH=$env(TEST_PATH) FAKE_OPENCLAW_LOGIN_HANGS_AFTER_READY=openai ZEBRA_GBRAIN_RUNTIME_INTERACTIVE_GRACE_SECONDS=0.1 ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        XCTAssertTrue(logText.contains("models auth login --provider openai --method oauth --set-default"))
        XCTAssertTrue(logText.contains("models status --json --probe-provider openai"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai")
        XCTAssertEqual(receipt["keySource"] as? String, "openai-codex:oauth")
    }

    func testRuntimeHelperDoesNotTreatOpenAIAPIKeyEnvAsOpenClawCodexLogin() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let log = root.appendingPathComponent("openclaw.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: log)
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
        spawn env PATH=$env(TEST_PATH) OPENAI_API_KEY=ambient-openai-key CODEX_API_KEY=ambient-codex-key ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        XCTAssertTrue(logText.contains("models auth login --provider openai --method oauth --set-default"))
        XCTAssertFalse(logText.contains("env OPENAI_API_KEY"))
        XCTAssertFalse(logText.contains("env CODEX_API_KEY"))
    }

    func testRuntimeHelperUsesOpenClawClaudeAuthLoginInsteadOfNonInteractiveAnthropicCliOnboard() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let openClawLog = root.appendingPathComponent("openclaw.log", isDirectory: false)
        let claudeLog = root.appendingPathComponent("claude.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: openClawLog)
        _ = try installFakeClaudeRuntime(directory: fakeBin, log: claudeLog, loggedIn: true)
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
        try writeAgentReadinessState(
            onboardingDirectory: stateURL.deletingLastPathComponent(),
            agent: "claude",
            method: "claude auth status --json"
        )
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let expectScript = root.appendingPathComponent("run-helper.expect", isDirectory: false)
        let expectContent = """
        set timeout 20
        spawn env PATH=$env(TEST_PATH) ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        let openClawLogText = try String(contentsOf: openClawLog, encoding: .utf8)
        XCTAssertTrue(openClawLogText.contains("models auth login --provider anthropic --method cli --set-default"))
        XCTAssertFalse(openClawLogText.contains("onboard --non-interactive"))
        XCTAssertFalse(openClawLogText.contains("--auth-choice anthropic-cli"))
        let claudeLogText = try String(contentsOf: claudeLog, encoding: .utf8)
        XCTAssertTrue(claudeLogText.contains("auth status --json"))
        XCTAssertFalse(claudeLogText.contains("auth login"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "claude-cli")
        XCTAssertEqual(receipt["keySource"] as? String, "agent-cli:claude-auth-status")
    }

    func testRuntimeHelperSkipsOpenClawClaudeLoginWhenProfileAlreadyUsable() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let openClawLog = root.appendingPathComponent("openclaw.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: openClawLog)
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
        try writeAgentReadinessState(
            onboardingDirectory: stateURL.deletingLastPathComponent(),
            agent: "claude",
            method: "claude auth status --json"
        )
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let expectScript = root.appendingPathComponent("run-helper.expect", isDirectory: false)
        let expectContent = """
        set timeout 20
        spawn env PATH=$env(TEST_PATH) FAKE_OPENCLAW_AUTH_READY=claude-cli ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        let openClawLogText = try String(contentsOf: openClawLog, encoding: .utf8)
        XCTAssertTrue(openClawLogText.contains("models status --json --probe-provider claude-cli"))
        XCTAssertFalse(openClawLogText.contains("models auth login --provider anthropic"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "claude-cli")
        XCTAssertEqual(receipt["keySource"] as? String, "agent-cli:claude-auth-status")
    }

    func testRuntimeHelperUsesClaudeCodeAccountLoginByDefault() throws {
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
        try writeAgentReadinessState(
            onboardingDirectory: stateURL.deletingLastPathComponent(),
            agent: "claude",
            method: "claude auth status --json"
        )
        let helperURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-onboarding", isDirectory: false)
        let expectScript = root.appendingPathComponent("run-helper.expect", isDirectory: false)
        let expectContent = """
        set timeout 20
        spawn env PATH=$env(TEST_PATH) ZEBRA_GBRAIN_RUNTIME_SKIP_CLAUDE_KEYCHAIN=1 ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "\\r"
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
        XCTAssertFalse(logText.contains("login --provider openai-codex"))
        XCTAssertTrue(logText.contains("config set model.provider anthropic"))
        XCTAssertTrue(logText.contains("config set model.default claude-sonnet-4-6"))
        XCTAssertTrue(logText.contains("config set model.base_url https://api.anthropic.com"))
        XCTAssertTrue(logText.contains("config set model.api_mode anthropic_messages"))
        XCTAssertTrue(logText.contains("chat -q Reply with OK. Do not use tools. --provider anthropic --model claude-sonnet-4-6"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "anthropic")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(receipt["keySource"] as? String, "agent-cli:claude-auth-status")
        XCTAssertEqual(receipt["keyEnvName"] as? String, "")
        XCTAssertEqual(receipt["keyPersistedEnvName"] as? String, "")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent(".hermes", isDirectory: true)
                    .appendingPathComponent(".env", isDirectory: false)
                    .path
            )
        )
    }

    func testRuntimeHelperPromptsForOpenAIWhenAmbientKeyIsMissing() throws {
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
        spawn env PATH=$env(TEST_PATH) OPENAI_API_KEY= ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "6\\r"
        expect "Enter OpenAI API key"
        send "entered-openai-key\\r"
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
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-api")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai-api")
        XCTAssertEqual(receipt["keySource"] as? String, "entered:OPENAI_API_KEY")
        XCTAssertEqual(receipt["keyEnvName"] as? String, "OPENAI_API_KEY")
        XCTAssertEqual(receipt["keyPersistedEnvName"] as? String, "OPENAI_API_KEY")
        let envText = try String(
            contentsOf: root
                .appendingPathComponent(".hermes", isDirectory: true)
                .appendingPathComponent(".env", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(envText.contains("OPENAI_API_KEY=entered-openai-key"))
    }

    func testRuntimeHelperUsesHermesAnthropicTokenSource() throws {
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
        spawn env PATH=$env(TEST_PATH) ANTHROPIC_TOKEN=test-anthropic-token ANTHROPIC_API_KEY= CLAUDE_CODE_OAUTH_TOKEN= ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
        send "4\\r"
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
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "anthropic")
        XCTAssertEqual(receipt["keySource"] as? String, "env:ANTHROPIC_TOKEN")
        XCTAssertEqual(receipt["keyEnvName"] as? String, "ANTHROPIC_TOKEN")
        XCTAssertEqual(receipt["keyPersistedEnvName"] as? String, "ANTHROPIC_TOKEN")
    }

    func testRuntimeHelperUsesClaudeCodeCredentialsForHermesAnthropic() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to drive the helper's /dev/tty prompts")
        }

        let root = try makeTemporaryDirectory()
        let fakeBin = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let log = root.appendingPathComponent("hermes.log", isDirectory: false)
        _ = try installFakeHermesRuntime(directory: fakeBin, log: log)
        let claudeDirectory = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let credentials = [
            "claudeAiOauth": [
                "accessToken": "test-claude-code-access-token",
                "refreshToken": "test-refresh-token",
                "expiresAt": 4_102_444_800_000,
            ],
        ]
        let credentialsData = try JSONSerialization.data(withJSONObject: credentials, options: [.prettyPrinted, .sortedKeys])
        try credentialsData.write(
            to: claudeDirectory.appendingPathComponent(".credentials.json", isDirectory: false),
            options: .atomic
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
        spawn env PATH=$env(TEST_PATH) ANTHROPIC_TOKEN= ANTHROPIC_API_KEY= CLAUDE_CODE_OAUTH_TOKEN= ZEBRA_GBRAIN_RUNTIME_SKIP_CLAUDE_KEYCHAIN=1 ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en $env(TEST_HELPER) run
        expect "Select runtime"
        send "1\\r"
        expect "Select LLM connection"
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
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "anthropic")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(receipt["keySource"] as? String, "claude-code-credentials-file")
        XCTAssertEqual(receipt["keyEnvName"] as? String, "")
        XCTAssertEqual(receipt["keyPersistedEnvName"] as? String, "")
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
        expect "Select LLM connection"
        send "6\\r"
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

    private func writeGBrainPrepareAbortState(stateURL: URL) throws {
        let state: [String: Any] = [
            "schemaVersion": 1,
            "progress": [
                "lastFailure": "source_repo_prepare_aborted",
                "updatedAt": "2026-06-08T00:00:00Z",
            ],
        ]
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func writeAgentReadinessState(
        onboardingDirectory: URL,
        agent: String,
        method: String
    ) throws {
        try FileManager.default.createDirectory(at: onboardingDirectory, withIntermediateDirectories: true)
        let state: [String: Any] = [
            "schemaVersion": 1,
            "phase": "complete",
            "selectedAgent": agent,
        ]
        let stateData = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        try stateData.write(
            to: onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false),
            options: .atomic
        )
        let event = """
        {"ts":"2026-06-05T00:00:00Z","runId":"test","event":"agent_readiness_probe_succeeded","agent":"\(agent)","method":"\(method)","exitCode":0,"timedOut":false}

        """
        try event.write(
            to: onboardingDirectory.appendingPathComponent("agent-cli-events.jsonl", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
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

    private func installFakeOpenClawRuntime(directory: URL, log: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("openclaw", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(shellSingleQuoted(log.path))'
        if [ "$1" = "--version" ]; then
          echo 'OpenClaw test'
          exit 0
        fi
        if [ "$1" = "onboard" ] && [ "$2" = "--help" ]; then
          echo '--skip-daemon --skip-ui --skip-skills --skip-health --skip-bootstrap --skip-channels --skip-search'
          exit 0
        fi
        if [ "$1" = "models" ] && [ "$2" = "auth" ] && [ "$3" = "login" ]; then
          if [ -n "${OPENAI_API_KEY:-}" ]; then
            printf '%s\\n' "env OPENAI_API_KEY" >> '\(shellSingleQuoted(log.path))'
          fi
          if [ -n "${CODEX_API_KEY:-}" ]; then
            printf '%s\\n' "env CODEX_API_KEY" >> '\(shellSingleQuoted(log.path))'
          fi
          if ! test -t 0; then
            echo 'models auth login requires an interactive TTY' >&2
            exit 9
          fi
          if [ "${FAKE_OPENCLAW_LOGIN_HANGS_AFTER_READY:-}" = "openai" ]; then
            : > "${ZEBRA_GBRAIN_RUNTIME_HOME:-.}/.fake-openclaw-openai-ready"
            sleep 60
            exit 0
          fi
          exit 0
        fi
        if [ "$1" = "models" ] && [ "$2" = "status" ]; then
          if [ -n "${OPENAI_API_KEY:-}" ]; then
            printf '%s\\n' "env OPENAI_API_KEY" >> '\(shellSingleQuoted(log.path))'
          fi
          if [ -n "${CODEX_API_KEY:-}" ]; then
            printf '%s\\n' "env CODEX_API_KEY" >> '\(shellSingleQuoted(log.path))'
          fi
          openai_ready_file="${ZEBRA_GBRAIN_RUNTIME_HOME:-}/.fake-openclaw-openai-ready"
          if [ "${FAKE_OPENCLAW_AUTH_READY:-}" = "openai" ] || { [ -n "${ZEBRA_GBRAIN_RUNTIME_HOME:-}" ] && [ -f "$openai_ready_file" ]; }; then
            echo '{"auth":{"providersWithOAuth":["openai (1)"],"oauth":{"profiles":[{"provider":"openai","status":"ok","type":"oauth"}],"providers":[{"provider":"openai","status":"ok"}]},"runtimeAuthRoutes":[{"provider":"openai","runtime":"codex","authProvider":"openai","status":"usable"}],"probes":{"results":[{"provider":"openai","status":"ok"},{"provider":"claude-cli","status":"ok"}]}}}'
            exit 0
          fi
          if [ "${FAKE_OPENCLAW_AUTH_READY:-}" = "claude-cli" ]; then
            echo '{"auth":{"runtimeAuthRoutes":[{"provider":"claude-cli","runtime":"claude-cli","authProvider":"anthropic","status":"usable"}],"probes":{"results":[{"provider":"openai","status":"ok"},{"provider":"claude-cli","status":"ok"}]}}}'
            exit 0
          fi
          if [ -n "${OPENAI_API_KEY:-}" ] || [ -n "${CODEX_API_KEY:-}" ]; then
            echo '{"auth":{"runtimeAuthRoutes":[{"provider":"openai","runtime":"codex","authProvider":"openai","status":"usable","effective":{"kind":"env"}}],"probes":{"results":[{"provider":"openai","status":"ok"},{"provider":"claude-cli","status":"ok"}]}}}'
            exit 0
          fi
          echo '{"auth":{"probes":{"results":[{"provider":"openai","status":"ok"},{"provider":"claude-cli","status":"ok"}]}}}'
          exit 0
        fi
        if [ "$1" = "onboard" ]; then
          exit 0
        fi
        exit 1
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func installFakeClaudeRuntime(directory: URL, log: URL, loggedIn: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("claude", isDirectory: false)
        let loggedInJson = loggedIn ? "true" : "false"
        let scriptContent = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(shellSingleQuoted(log.path))'
        if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
          echo '{"loggedIn":\(loggedInJson),"authMethod":"claude.ai","apiProvider":"firstParty"}'
          exit 0
        fi
        if [ "$1" = "auth" ] && [ "$2" = "login" ]; then
          exit 0
        fi
        exit 1
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
        if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
          if [ -n "${ZEBRA_GBRAIN_RUNTIME_HOME:-}" ] && [ -f "$ZEBRA_GBRAIN_RUNTIME_HOME/.hermes/auth.json" ] && grep -q '"openai-codex"' "$ZEBRA_GBRAIN_RUNTIME_HOME/.hermes/auth.json"; then
            echo 'openai-codex: logged in'
          else
            echo 'openai-codex: logged out'
          fi
          exit 0
        fi
        if [ "$1" = "auth" ] && [ "$2" = "add" ]; then
          exit 0
        fi
        if [ "$1" = "login" ]; then
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
