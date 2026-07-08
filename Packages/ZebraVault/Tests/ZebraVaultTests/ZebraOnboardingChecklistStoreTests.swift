import XCTest
import Combine
@testable import ZebraVault

final class ZebraOnboardingChecklistStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(
            forKey: "ZebraOnboardingChecklistStore.developmentCompletedStepIDs"
        )
        UserDefaults.standard.removeObject(
            forKey: "ZebraOnboardingChecklistStore.developmentIncompleteStepIDs"
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
            [.agent, .gbrainRuntime, .gbrain, .adapter, .sourceOnboarding]
        )
        XCTAssertEqual(store.snapshots.map { $0.number }, [1, 2, 3, 4, 5])
    }

    @MainActor
    func testAdapterIsActiveImmediatelyAfterGBrainCompletion() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let onboardingDirectory = root.appendingPathComponent("onboarding", isDirectory: true)
        let agentStateURL = onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        let agentPreferenceURL = root
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
        let runtimeStateURL = onboardingDirectory.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = onboardingDirectory.appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let executable = try installFakeRuntime(root: root, name: "hermes")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try writeAgentReadinessState(onboardingDirectory: onboardingDirectory, agent: "codex", method: "path")
        try writeAgentPreferences(agentPreferenceURL)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path
        )
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            executablePath: executable.path
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            agentOnboardingStateURL: agentStateURL,
            agentPreferenceURL: agentPreferenceURL,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path)

        let adapter = try XCTUnwrap(store.snapshots.first { $0.id == .adapter })
        let sourceOnboarding = try XCTUnwrap(store.snapshots.first { $0.id == .sourceOnboarding })

        XCTAssertTrue(store.completedStepIDs.contains(.agent))
        XCTAssertTrue(store.completedStepIDs.contains(.gbrainRuntime))
        XCTAssertTrue(store.completedStepIDs.contains(.gbrain))
        XCTAssertFalse(store.completedStepIDs.contains(.adapter))
        XCTAssertFalse(store.completedStepIDs.contains(.sourceOnboarding))
        XCTAssertTrue(adapter.isActive)
        XCTAssertTrue(adapter.showsStart)
        XCTAssertFalse(sourceOnboarding.isActive)
        XCTAssertFalse(sourceOnboarding.showsStart)
    }

    @MainActor
    func testSourceOnboardingIsActiveAfterAdapterCompletion() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let sourceRepo = root
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: true)
        let adapterRepo = sourceRepo
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-adapter", isDirectory: true)
        let onboardingDirectory = root.appendingPathComponent("onboarding", isDirectory: true)
        let agentStateURL = onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        let agentPreferenceURL = root
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
        let runtimeStateURL = onboardingDirectory.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = onboardingDirectory.appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = onboardingDirectory.appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let executable = try installFakeRuntime(root: root, name: "hermes")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapterRepo, withIntermediateDirectories: true)
        try writeInstalledAdapterFiles(vault)
        try writeAgentReadinessState(onboardingDirectory: onboardingDirectory, agent: "codex", method: "path")
        try writeAgentPreferences(agentPreferenceURL)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path
        )
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            executablePath: executable.path,
            sourceRepoPath: sourceRepo.path
        )
        try writeCompletedAdapterState(
            stateURL: adapterStateURL,
            targetVaultPath: vault.path,
            adapterRepoPath: adapterRepo.path
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            agentOnboardingStateURL: agentStateURL,
            agentPreferenceURL: agentPreferenceURL,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL,
            gbrainAdapterOnboardingStateURL: adapterStateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path)

        let sourceOnboarding = try XCTUnwrap(store.snapshots.first { $0.id == .sourceOnboarding })

        XCTAssertTrue(store.completedStepIDs.contains(.adapter))
        XCTAssertFalse(store.completedStepIDs.contains(.sourceOnboarding))
        XCTAssertTrue(sourceOnboarding.isActive)
        XCTAssertTrue(sourceOnboarding.showsStart)
    }

    @MainActor
    func testAutomaticStepStartRequiresCurrentSessionAgentLaunchLatch() {
        XCTAssertNil(
            ZebraOnboardingChecklistStore.automaticStepToStart(
                previousCompletedStepIDs: [],
                currentCompletedStepIDs: [.agent],
                didStartAgentStepInCurrentSession: false
            )
        )

        XCTAssertEqual(
            ZebraOnboardingChecklistStore.automaticStepToStart(
                previousCompletedStepIDs: [],
                currentCompletedStepIDs: [.agent],
                didStartAgentStepInCurrentSession: true
            ),
            .gbrainRuntime
        )
    }

    @MainActor
    func testAutomaticStepStartDoesNotRepeatWhenRuntimeIsAlreadyComplete() {
        XCTAssertNil(
            ZebraOnboardingChecklistStore.automaticStepToStart(
                previousCompletedStepIDs: [],
                currentCompletedStepIDs: [.agent, .gbrainRuntime],
                didStartAgentStepInCurrentSession: true
            )
        )
        XCTAssertNil(
            ZebraOnboardingChecklistStore.automaticStepToStart(
                previousCompletedStepIDs: [.agent],
                currentCompletedStepIDs: [.agent],
                didStartAgentStepInCurrentSession: true
            )
        )
    }

    @MainActor
    func testChainedRuntimeHandoffMovesRunningStateToRuntimeWithoutCompletingIt() throws {
        let root = try makeTemporaryDirectory()
        let store = makeChecklistStore(homeURL: root)

        store.beginLaunch(stepID: .agent)
        let shouldHandoff = ZebraOnboardingChecklistStore.shouldBeginChainedRuntimeHandoff(
            previousCompletedStepIDs: [],
            currentCompletedStepIDs: [.agent],
            didLaunchRuntimeInAgentTerminal: true
        )

        XCTAssertTrue(shouldHandoff)
        if shouldHandoff {
            store.beginLaunch(stepID: .gbrainRuntime)
        }

        XCTAssertEqual(store.runningStepID, .gbrainRuntime)
        XCTAssertFalse(store.completedStepIDs.contains(.gbrainRuntime))
        XCTAssertFalse(try XCTUnwrap(store.snapshots.first { $0.id == .agent }).isRunning)
        XCTAssertTrue(try XCTUnwrap(store.snapshots.first { $0.id == .gbrainRuntime }).isRunning)
    }

    @MainActor
    func testChainedRuntimeHandoffDoesNotBeginWithoutAgentCompletionOrWhenRuntimeComplete() {
        XCTAssertFalse(
            ZebraOnboardingChecklistStore.shouldBeginChainedRuntimeHandoff(
                previousCompletedStepIDs: [],
                currentCompletedStepIDs: [.agent],
                didLaunchRuntimeInAgentTerminal: false
            )
        )
        XCTAssertFalse(
            ZebraOnboardingChecklistStore.shouldBeginChainedRuntimeHandoff(
                previousCompletedStepIDs: [.agent],
                currentCompletedStepIDs: [.agent],
                didLaunchRuntimeInAgentTerminal: true
            )
        )
        XCTAssertFalse(
            ZebraOnboardingChecklistStore.shouldBeginChainedRuntimeHandoff(
                previousCompletedStepIDs: [],
                currentCompletedStepIDs: [.agent, .gbrainRuntime],
                didLaunchRuntimeInAgentTerminal: true
            )
        )
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
    func testStoredDevelopmentCompletedOverrideDoesNotCompleteRuntimeStep() throws {
        let root = try makeTemporaryDirectory()
        let runtimeStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)

        UserDefaults.standard.set(
            [ZebraOnboardingChecklistStepID.gbrainRuntime.rawValue],
            forKey: "ZebraOnboardingChecklistStore.developmentCompletedStepIDs"
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )

        XCTAssertFalse(store.completedStepIDs.contains(.gbrainRuntime))
        XCTAssertFalse(try XCTUnwrap(store.snapshots.first { $0.id == .gbrainRuntime }).isDevelopmentCompleted)
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

    @MainActor
    func testCompletedRuntimeStepStaysCompletedDuringGBrainRefreshWhenRuntimeProbeIsTemporarilyUnavailable() throws {
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

        try FileManager.default.removeItem(at: executable)
        store.beginLaunch(stepID: .gbrain)
        store.refreshDetectedCompletion()

        XCTAssertTrue(
            store.completedStepIDs.contains(.gbrainRuntime),
            "A previously completed runtime step should survive transient executable availability during later setup refreshes."
        )
    }

    @MainActor
    func testGBrainStateWatcherRefreshDoesNotReevaluateCompletedRuntimeStep() throws {
        let root = try makeTemporaryDirectory()
        let executable = try installFakeRuntime(root: root, name: "hermes")
        let onboardingDirectory = root.appendingPathComponent("onboarding", isDirectory: true)
        let runtimeStateURL = onboardingDirectory.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = onboardingDirectory.appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
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

        try writeGBrainPrepareAbortState(stateURL: gbrainStateURL)
        try writeIncompleteRuntimeState(
            stateURL: runtimeStateURL,
            reason: "llm_call_verification_failed"
        )
        store.refreshDetectedCompletion(for: .gbrain)

        XCTAssertTrue(
            store.completedStepIDs.contains(.gbrainRuntime),
            "A gbrain-state watcher refresh should only evaluate the gbrain step, not demote the completed runtime step."
        )

        store.refreshDetectedCompletion(for: .gbrainRuntime)

        XCTAssertFalse(
            store.completedStepIDs.contains(.gbrainRuntime),
            "The runtime step may be demoted when its own state records an explicit failed receipt."
        )
    }

    @MainActor
    func testRuntimeStepRefreshDemotesCompletedRuntimeWhenRuntimeReceiptIsMissing() throws {
        let root = try makeTemporaryDirectory()
        let executable = try installFakeRuntime(root: root, name: "hermes")
        let onboardingDirectory = root.appendingPathComponent("onboarding", isDirectory: true)
        let runtimeStateURL = onboardingDirectory.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = onboardingDirectory.appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
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

        try FileManager.default.removeItem(at: runtimeStateURL)
        store.refreshDetectedCompletion(for: .gbrainRuntime)

        XCTAssertFalse(
            store.completedStepIDs.contains(.gbrainRuntime),
            "The runtime step should be demoted when its own state file is removed and the receipt is missing."
        )
    }

    func testGBrainStartupLinePreparesSourceRepoBeforeRuntimeLaunch() throws {
        let launch = ZebraGBrainOnboardingStore.LaunchContext(
            launchDirectory: "/tmp/zebra-gbrain-work",
            startupPrompt: "setup prompt",
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
        XCTAssertTrue(line.contains("zebra-gbrain-onboarding write-runtime-launcher --runtime 'hermes'"), line)
        XCTAssertTrue(line.contains("--executable '/tmp/hermes'"), line)
        XCTAssertTrue(line.contains("&& \"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\""), line)
        XCTAssertFalse(line.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\" && '/tmp/hermes' chat"), line)
        XCTAssertFalse(line.contains("--query 'setup prompt'"), line)
        XCTAssertFalse(line.contains("setup prompt"), line)
        XCTAssertFalse(line.contains(" codex"), line)
        let prepareRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding prepare-source-repo"))
        let envRange = try XCTUnwrap(line.range(of: "eval \"$(zebra-gbrain-onboarding active-source-env)\""))
        let launcherRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding write-runtime-launcher"))
        let launchRange = try XCTUnwrap(line.range(of: "\"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\""))
        XCTAssertLessThan(prepareRange.lowerBound, envRange.lowerBound)
        XCTAssertLessThan(envRange.lowerBound, launcherRange.lowerBound)
        XCTAssertLessThan(launcherRange.lowerBound, launchRange.lowerBound)
    }

    func testGBrainStartupLineExecutesSelectedHermesRuntimeAfterSourceRepoSelection() throws {
        let root = try makeTemporaryDirectory()
        let sourceRepo = try writeFakeGBrainSourceRepo(root: root)
        let runtimeLog = root.appendingPathComponent("hermes.log", isDirectory: false)
        let executable = try installFakeRuntimeLogger(root: root, name: "hermes", log: runtimeLog)
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let store = ZebraGBrainOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            environment: ["ZEBRA_GBRAIN_DOCS_REMOTE_DISABLED": "1"],
            appPreferredLocalizations: ["en"],
            preferredLanguages: ["en-US"]
        )
        let launch = try XCTUnwrap(store.prepareLaunch(selectedVaultPath: nil, selectedAgent: .codex))
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "hermes",
            executablePath: executable.path
        )
        let line = ZebraOnboardingChecklistCommand.gbrainSetupRuntimeStartupLine(
            launch: launch,
            runtime: runtime,
            language: .en
        )

        let command = String(line.dropLast())
        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-lc", command],
            environment: [
                "HOME": root.path,
                "ZEBRA_GBRAIN_SOURCE_REPO": sourceRepo.path,
            ]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Preparing the GBrain source repo..."), result.stdout)
        XCTAssertTrue(result.stdout.contains("Preparing the selected runtime launcher..."), result.stdout)
        XCTAssertTrue(result.stdout.contains("Starting Hermes for Zebra GBrain setup..."), result.stdout)
        let log = try String(contentsOf: runtimeLog, encoding: .utf8)
        XCTAssertTrue(log.contains("chat --tui --source zebra-gbrain-onboarding --query"), log)
        XCTAssertTrue(log.contains("Zebra GBrain setup is starting."), log)
    }

    func testGBrainStartupLineUsesOpenClawRuntimeWhenSelected() throws {
        let launch = ZebraGBrainOnboardingStore.LaunchContext(
            launchDirectory: "/tmp/zebra-gbrain-work",
            startupPrompt: "setup prompt",
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
            line.contains("zebra-gbrain-onboarding write-runtime-launcher --runtime 'openclaw' --executable '/tmp/openclaw'"),
            line
        )
        XCTAssertTrue(line.contains("--agent-id 'zebra-gbrain-setup-12-3456-7890'"), line)
        XCTAssertTrue(line.contains("--session 'agent:zebra-gbrain-setup-12-3456-7890:gbrain-ABCDEF12-3456-7890'"), line)
        XCTAssertTrue(line.contains("&& \"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\""), line)
        XCTAssertFalse(line.contains("cd \"$ZEBRA_GBRAIN_SOURCE_REPO\" && '/tmp/openclaw' tui"), line)
        XCTAssertFalse(line.contains("--local"), line)
        XCTAssertFalse(line.contains("--message 'setup prompt'"), line)
        XCTAssertFalse(line.contains("setup prompt"), line)
        XCTAssertFalse(line.contains("agents list --json"), line)
        XCTAssertFalse(line.contains("agents add"), line)
        XCTAssertFalse(line.contains("--session zebra-gbrain-setup"), line)
        XCTAssertFalse(line.contains(" codex"), line)
        let prepareRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding prepare-source-repo"))
        let envRange = try XCTUnwrap(line.range(of: "eval \"$(zebra-gbrain-onboarding active-source-env)\""))
        let launcherRange = try XCTUnwrap(line.range(of: "zebra-gbrain-onboarding write-runtime-launcher"))
        let launchRange = try XCTUnwrap(line.range(of: "\"$ZEBRA_GBRAIN_RUNTIME_LAUNCHER\""))
        XCTAssertLessThan(prepareRange.lowerBound, envRange.lowerBound)
        XCTAssertLessThan(envRange.lowerBound, launcherRange.lowerBound)
        XCTAssertLessThan(launcherRange.lowerBound, launchRange.lowerBound)
    }

    func testGBrainStartupLineDoesNotInjectRuntimePromptIntoTerminal() throws {
        let launch = ZebraGBrainOnboardingStore.LaunchContext(
            launchDirectory: "/tmp/zebra-gbrain-work",
            startupPrompt: "line one\n\nline two\r\nline three\rline four",
            runId: "gbrain-test-run",
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

        XCTAssertTrue(line.hasSuffix("\r"), line)
        let commandBeforeReturn = String(line.dropLast())
        XCTAssertFalse(commandBeforeReturn.contains("\n"), line)
        XCTAssertFalse(commandBeforeReturn.contains("\r"), line)
        XCTAssertFalse(line.contains("line one"), line)
        XCTAssertFalse(line.contains("line two"), line)
        XCTAssertFalse(line.contains("--message"), line)
        XCTAssertTrue(line.contains("zebra-gbrain-onboarding write-runtime-launcher"), line)
    }

    func testSourceOnboardingLaunchPlanStartsFirstSliceOnly() throws {
        let selectedVaultPath = "/tmp/zebra-brain"
        let launch = try XCTUnwrap(
            ZebraOnboardingChecklistCommand.launchPlan(
                for: .sourceOnboarding,
                selectedVaultPath: selectedVaultPath,
                useSelectedRuntimeForSourceOnboarding: false
            )
        )
        let line = launch.startupLine

        XCTAssertTrue(line.contains("Source Onboarding"), line)
        XCTAssertTrue(line.contains("source-onboarding-state.json"), line)
        XCTAssertTrue(line.contains(selectedVaultPath), line)
        XCTAssertTrue(line.contains("Brain write target path (selected brain repo; not an Obsidian source vault)"), line)
        XCTAssertTrue(line.contains("Brain target context"), line)
        XCTAssertFalse(line.contains("Selected vault path"), line)
        XCTAssertTrue(line.contains("Step 3 GBrain setup receipt"), line)
        XCTAssertTrue(line.contains("Source Onboarding is Step 5"), line)
        XCTAssertTrue(line.contains("after Step 4 gbrain-adapter is installed"), line)
        XCTAssertTrue(line.contains("entryContext.adapterReady"), line)
        XCTAssertTrue(line.contains("injecting approved user source data into the active brain"), line)
        XCTAssertTrue(line.contains("selected agent runtime"), line)
        XCTAssertTrue(line.contains("runtime-specific"), line)
        XCTAssertTrue(line.contains("Hermes vault access still needs separate verification"), line)
        XCTAssertTrue(line.contains("ZEBRA_SOURCE_ONBOARDING_STATE"), line)
        XCTAssertTrue(line.contains("zebra-source-onboarding"), line)
        XCTAssertTrue(line.contains("zebra-source-onboarding intake"), line)
        XCTAssertTrue(line.contains("zebra-source-onboarding confirm --answer yes"), line)
        XCTAssertTrue(line.contains("zebra-source-onboarding status --json"), line)
        XCTAssertTrue(line.contains("zebra-source-onboarding next"), line)
        XCTAssertTrue(line.contains("status --json first"), line)
        XCTAssertTrue(line.contains("pending source confirmation"), line)
        XCTAssertTrue(line.contains("which sources Zebra should understand for this first source intake"), line)
        XCTAssertTrue(line.contains("Normalize source aliases into source candidates"), line)
        XCTAssertTrue(line.contains("uncataloged sources"), line)
        XCTAssertTrue(line.contains("must include every source the user named"), line)
        XCTAssertTrue(line.contains("Gmail, Obsidian, iMessage, Notion, and Apple Notes runners"), line)
        XCTAssertFalse(line.contains("Do not implement or start Notion runners"), line)
        XCTAssertTrue(line.contains("report --status completed --source <source-id>"), line)
        XCTAssertTrue(line.contains("nextPromptPath"), line)
        XCTAssertFalse(line.contains("unsupported inputs"), line)
        XCTAssertFalse(line.contains("--unsupported"), line)
        XCTAssertTrue(line.contains("saved state path"), line)
        XCTAssertTrue(line.contains("--timeout=3600s"), line)
        XCTAssertTrue(line.contains("Prefer the Step 3 receipt"), line)
        XCTAssertFalse(line.contains("v1 catalog"), line)
        XCTAssertFalse(line.contains("supported v1"), line)
        XCTAssertFalse(line.contains("gmail, obsidian, imessage, notion"), line)
        XCTAssertFalse(line.contains("Gmail, Obsidian, iMessage, or Notion"), line)
        XCTAssertFalse(line.contains("Use only these top-level keys"), line)
        XCTAssertFalse(line.contains("progress.rawSourceInput"), line)
        XCTAssertFalse(line.contains("progress.sourceRows"), line)
        XCTAssertFalse(line.contains("which sources they want to onboard first"), line)
        XCTAssertFalse(line.contains("Do not ask for importance order"), line)
        XCTAssertFalse(line.contains("final ingest execution order"), line)
        XCTAssertFalse(line.contains("Do not write progress.importanceOrder"), line)
        XCTAssertFalse(line.contains("Do not run recovery"), line)
        XCTAssertFalse(line.contains("ingest commands"), line)
        XCTAssertFalse(line.contains("Do not start source interviews"), line)
        XCTAssertFalse(line.contains("run a limited initial ingest"), line)
        XCTAssertFalse(line.contains("zebra-source-onboarding gmail verify-connection"), line)
    }

    func testSourceOnboardingRuntimeStartupLineUsesOpenClawRuntime() throws {
        let root = try makeTemporaryDirectory()
        let promptDirectory = root.appendingPathComponent("source-runtime-prompts", isDirectory: true)
        let launch = ZebraSourceOnboardingHelper.LaunchContext(
            helperPath: root.appendingPathComponent("bin/zebra-source-onboarding").path,
            launchDirectory: root.appendingPathComponent("source-onboarding-work", isDirectory: true).path,
            runtimePromptDirectory: promptDirectory.path,
            shellEnvironmentPrefix: "export ZEBRA_SOURCE_ONBOARDING_STATE='\(root.path)/state.json' && "
        )
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "openclaw",
            executablePath: "/tmp/openclaw"
        )

        let line = ZebraOnboardingChecklistCommand.sourceOnboardingRuntimeStartupLine(
            launch: launch,
            runtime: runtime,
            prompt: "source onboarding prompt",
            language: .en
        )
        let promptFiles = try FileManager.default.contentsOfDirectory(
            at: promptDirectory,
            includingPropertiesForKeys: nil
        )

        XCTAssertTrue(line.contains("ZEBRA_SOURCE_ONBOARDING_PROMPT=$(cat "), line)
        XCTAssertTrue(line.contains("Starting OpenClaw for Zebra Source Onboarding..."), line)
        XCTAssertTrue(line.contains("cd '\(launch.launchDirectory)'"), line)
        XCTAssertTrue(line.contains("'/tmp/openclaw' tui --message \"$ZEBRA_SOURCE_ONBOARDING_PROMPT\""), line)
        XCTAssertTrue(line.contains("audit-openclaw-config --event 'openclaw.source_onboarding.launch.finished'"), line)
        XCTAssertFalse(line.contains("--local"), line)
        XCTAssertFalse(line.contains("--session"), line)
        XCTAssertTrue(line.contains("--message \"$ZEBRA_SOURCE_ONBOARDING_PROMPT\""), line)
        XCTAssertTrue(line.contains("ZEBRA_SOURCE_ONBOARDING_STATE"), line)
        XCTAssertFalse(line.contains("source onboarding prompt"), line)
        XCTAssertEqual(promptFiles.count, 1)
        let prompt = try String(contentsOf: try XCTUnwrap(promptFiles.first), encoding: .utf8)
        XCTAssertTrue(prompt.contains("source onboarding prompt"), prompt)
        XCTAssertTrue(prompt.contains("Use Zebra's app language"), prompt)
    }

    func testSourceOnboardingRuntimeStartupLineUsesHermesRuntime() throws {
        let root = try makeTemporaryDirectory()
        let promptDirectory = root.appendingPathComponent("source-runtime-prompts", isDirectory: true)
        let launch = ZebraSourceOnboardingHelper.LaunchContext(
            helperPath: root.appendingPathComponent("bin/zebra-source-onboarding").path,
            launchDirectory: root.appendingPathComponent("source-onboarding-work", isDirectory: true).path,
            runtimePromptDirectory: promptDirectory.path,
            shellEnvironmentPrefix: "export ZEBRA_SOURCE_ONBOARDING_STATE='\(root.path)/state.json' && "
        )
        let runtime = ZebraGBrainRuntimeOnboardingStore.SelectedRuntime(
            runtime: "hermes",
            executablePath: "/tmp/hermes"
        )

        let line = ZebraOnboardingChecklistCommand.sourceOnboardingRuntimeStartupLine(
            launch: launch,
            runtime: runtime,
            prompt: "source onboarding prompt",
            language: .en
        )

        XCTAssertTrue(line.contains("Starting Hermes for Zebra Source Onboarding..."), line)
        XCTAssertTrue(line.contains("exec '/tmp/hermes' chat --tui --source zebra-source-onboarding --query \"$ZEBRA_SOURCE_ONBOARDING_PROMPT\""), line)
        XCTAssertFalse(line.contains("source onboarding prompt"), line)
    }

    func testSourceOnboardingCatalogNormalizesFreeTextAliasesInMentionOrder() {
        let result = ZebraSourceOnboardingCatalog.normalize(
            rawSourceInput: "노션이랑 지메일 먼저 보고, 아이메세지도 있어"
        )

        XCTAssertEqual(result.normalizedSourceList, ["notion", "gmail", "imessage"])
        XCTAssertTrue(result.uncatalogedSources.isEmpty)
        XCTAssertEqual(result.sourceRows["notion"]?.displayName, "Notion")
        XCTAssertEqual(result.sourceRows["gmail"]?.type, "email")
        XCTAssertEqual(result.sourceRows["imessage"]?.selectionState, "pending_confirmation")
    }

    func testSourceOnboardingCatalogRecordsUncatalogedKnownSources() {
        let result = ZebraSourceOnboardingCatalog.normalize(
            rawSourceInput: "gmail, apple notes, 애플 리마인더, obsidian"
        )

        XCTAssertEqual(result.normalizedSourceList, ["gmail", "apple-notes", "apple-reminders", "obsidian"])
        XCTAssertEqual(result.sourceRows["apple-notes"]?.displayName, "Apple Notes")
        XCTAssertEqual(result.sourceRows["apple-notes"]?.type, "notes")
        XCTAssertEqual(result.sourceRows["apple-reminders"]?.displayName, "Apple Reminders")
        XCTAssertEqual(result.sourceRows["apple-reminders"]?.type, "tasks")
        XCTAssertTrue(result.uncatalogedSources.isEmpty)
        XCTAssertEqual(result.confirmationPrompt, "Gmail, Apple Notes, Apple Reminders, Obsidian로 이해했습니다. 맞나요?")
    }

    func testSourceOnboardingCatalogRecognizesKoreanAppleNotesAliasInMentionOrder() {
        let result = ZebraSourceOnboardingCatalog.normalize(
            rawSourceInput: "애플노트 지메일 노션"
        )

        XCTAssertEqual(result.normalizedSourceList, ["apple-notes", "gmail", "notion"])
        XCTAssertTrue(result.uncatalogedSources.isEmpty)
        XCTAssertEqual(result.confirmationPrompt, "Apple Notes, Gmail, Notion로 이해했습니다. 맞나요?")
    }

    func testSourceOnboardingCatalogRecognizesKoreanAppleRemindersAliasesInMentionOrder() {
        let result = ZebraSourceOnboardingCatalog.normalize(
            rawSourceInput: "애플리마인더 지메일 미리 알림 노션"
        )

        XCTAssertEqual(result.normalizedSourceList, ["apple-reminders", "gmail", "notion"])
        XCTAssertTrue(result.uncatalogedSources.isEmpty)
        XCTAssertEqual(result.confirmationPrompt, "Apple Reminders, Gmail, Notion로 이해했습니다. 맞나요?")
    }

    @MainActor
    func testSourceOnboardingInputPersistenceRecordsConfirmationStateAndRows() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_TASK_ID=task_test
            """,
            homeURL: root
        )
        let store = makeChecklistStore(homeURL: root)
        store.syncExternalState(
            selectedVaultPath: nil,
            emailConnectionVerified: true
        )
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let recordedAt = Date(timeIntervalSince1970: 1_800_000_100)

        let recorded = try store.recordSourceOnboardingInput(
            "지메일, 옵시디언",
            now: recordedAt
        )
        let persisted = try readSourceOnboardingState(at: stateURL)

        XCTAssertEqual(recorded, persisted)
        XCTAssertEqual(persisted.status, .running)
        XCTAssertEqual(persisted.sourceReadiness.gmail.status, .ready)
        XCTAssertEqual(persisted.progress.rawSourceInput, "지메일, 옵시디언")
        XCTAssertEqual(persisted.progress.normalizedSourceList, ["gmail", "obsidian"])
        XCTAssertTrue(persisted.progress.uncatalogedSources.isEmpty)
        XCTAssertEqual(persisted.progress.sourceConfirmation?.prompt, "Gmail, Obsidian로 이해했습니다. 맞나요?")
        XCTAssertEqual(persisted.progress.sourceConfirmation?.status, .pending)
        XCTAssertEqual(persisted.progress.sourceConfirmation?.sourceIDs, ["gmail", "obsidian"])
        XCTAssertEqual(persisted.progress.pendingQuestion?.status, "pending_source_confirmation")
        XCTAssertEqual(persisted.progress.sourceRows["gmail"]?.phase, "intake")
        XCTAssertEqual(persisted.progress.sourceRows["gmail"]?.status, "unchecked")
        XCTAssertEqual(persisted.progress.sourceRows["gmail"]?.selectionState, "pending_confirmation")

        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_200)
        let confirmed = try store.confirmSourceOnboardingSources(now: confirmedAt)
        let persistedConfirmation = try readSourceOnboardingState(at: stateURL)

        XCTAssertEqual(confirmed, persistedConfirmation)
        XCTAssertEqual(persistedConfirmation.status, .ready)
        XCTAssertNil(persistedConfirmation.progress.pendingQuestion)
        XCTAssertEqual(persistedConfirmation.progress.sourceConfirmation?.status, .confirmed)
        XCTAssertEqual(persistedConfirmation.progress.sourceConfirmation?.confirmedAt, confirmedAt)
        XCTAssertEqual(persistedConfirmation.progress.sourceRows["gmail"]?.selectionState, "confirmed")
        XCTAssertEqual(persistedConfirmation.progress.sourceRows["obsidian"]?.selectionState, "confirmed")
    }

    @MainActor
    func testSourceOnboardingHelperWritesStateThatStoreCanRead() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let emailArtifact = root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("email.sqlite", isDirectory: false)
        try FileManager.default.createDirectory(
            at: emailArtifact.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: emailArtifact)

        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("ZEBRA_ONBOARDING_LANGUAGE"), launch.shellEnvironmentPrefix)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        let intake = try runProcess(
            executableURL: helperURL,
            arguments: [
                "intake",
                "--raw", "옵시디언, 지메일 사용자소스",
                "--candidate", "obsidian=옵시디언",
                "--candidate", "gmail=지메일",
                "--uncataloged", "custom-source=사용자소스",
            ],
            environment: environment
        )
        XCTAssertEqual(intake.status, 0, "stdout:\n\(intake.stdout)\nstderr:\n\(intake.stderr)")
        let intakePayload = try jsonObject(from: intake.stdout)
        XCTAssertEqual(intakePayload["normalizedSourceList"] as? [String], ["obsidian", "gmail"])
        XCTAssertEqual(intakePayload["uncatalogedSources"] as? [String], ["custom-source"])
        XCTAssertNil(intakePayload["unsupportedInputs"])
        XCTAssertEqual(intakePayload["sourceConfirmationStatus"] as? String, "pending")
        XCTAssertEqual(intakePayload["confirmationPrompt"] as? String, "Obsidian, Gmail, 사용자소스로 이해했습니다. 맞나요?")

        let store = makeChecklistStore(homeURL: root)
        let loaded = try XCTUnwrap(store.loadSourceOnboardingState())
        XCTAssertEqual(loaded.status, .attention)
        XCTAssertEqual(loaded.progress.rawSourceInput, "옵시디언, 지메일 사용자소스")
        XCTAssertEqual(loaded.progress.normalizedSourceList, ["obsidian", "gmail"])
        XCTAssertEqual(loaded.progress.uncatalogedSources.map(\.normalizedValue), ["custom-source"])
        XCTAssertEqual(loaded.progress.uncatalogedSources.first?.rawValue, "사용자소스")
        XCTAssertEqual(loaded.progress.uncatalogedSources.first?.reason, "not_in_current_catalog")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.selectionState, "pending_confirmation")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.selectionState, "pending_confirmation")
        XCTAssertNil(loaded.progress.sourceRows["custom-source"])
        XCTAssertEqual(loaded.sourceReadiness.gmail.localArtifact?.path, emailArtifact.path)
        XCTAssertNotEqual(loaded.sourceReadiness.gmail.connectionPath, emailArtifact.path)

        let rawState = try stateObject(in: stateURL)
        let sourceReadiness = try XCTUnwrap(rawState["sourceReadiness"] as? [String: Any])
        XCTAssertNil(sourceReadiness["obsidian"])
        let progress = try XCTUnwrap(rawState["progress"] as? [String: Any])
        XCTAssertNil(progress["step"])
        XCTAssertTrue(progress["sourceRows"] is [String: Any])
        XCTAssertFalse(progress["sourceRows"] is [[String: Any]])
        XCTAssertNil(progress["unsupportedInputs"])
        let uncataloged = try XCTUnwrap(progress["uncatalogedSources"] as? [[String: Any]])
        XCTAssertEqual(uncataloged.first?["rawValue"] as? String, "사용자소스")
        XCTAssertEqual(uncataloged.first?["reason"] as? String, "not_in_current_catalog")
        XCTAssertNil(uncataloged.first?["supportedCatalog"])
        let gmail = try XCTUnwrap((sourceReadiness["gmail"] as? [String: Any]))
        XCTAssertNotEqual(gmail["status"] as? String, "candidate")
        XCTAssertNotEqual(gmail["connectionPath"] as? String, emailArtifact.path)

        let confirm = try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        )
        XCTAssertEqual(confirm.status, 0, "stdout:\n\(confirm.stdout)\nstderr:\n\(confirm.stderr)")
        let confirmed = try XCTUnwrap(store.loadSourceOnboardingState())
        XCTAssertNotEqual(confirmed.status, .completed)
        XCTAssertEqual(confirmed.status, .attention)
        XCTAssertEqual(confirmed.progress.sourceConfirmation?.status, .confirmed)
        XCTAssertNil(confirmed.progress.pendingQuestion)
        XCTAssertEqual(confirmed.progress.sourceRows["obsidian"]?.selectionState, "confirmed")
        XCTAssertEqual(confirmed.progress.sourceRows["gmail"]?.selectionState, "confirmed")

        let sourceSnapshot = try XCTUnwrap(store.snapshots.first { $0.id == .sourceOnboarding })
        let sourceSubsteps = sourceSnapshot.substeps
        XCTAssertNil(sourceSubsteps.first { $0.id == "source-confirmation" })
        let obsidianSubstep = try XCTUnwrap(sourceSubsteps.first { $0.id == "source-row-obsidian" })
        let gmailSubstep = try XCTUnwrap(sourceSubsteps.first { $0.id == "source-row-gmail" })
        let customSourceSubstep = try XCTUnwrap(sourceSubsteps.first { $0.id == "uncataloged-source-custom-source" })
        XCTAssertNil(sourceSubsteps.first { $0.id == "gmail-readiness" })

        XCTAssertEqual(obsidianSubstep.title, "Obsidian")
        XCTAssertNil(obsidianSubstep.detail)
        XCTAssertFalse(obsidianSubstep.isCompleted)
        XCTAssertEqual(gmailSubstep.title, "Gmail")
        XCTAssertNil(gmailSubstep.detail)
        XCTAssertEqual(customSourceSubstep.title, "사용자소스")
        XCTAssertNil(customSourceSubstep.detail)
        XCTAssertTrue(customSourceSubstep.isAttention)

        let status = try runProcess(
            executableURL: helperURL,
            arguments: ["status", "--json"],
            environment: environment
        )
        XCTAssertEqual(status.status, 0, "stdout:\n\(status.stdout)\nstderr:\n\(status.stderr)")
        let statusPayload = try jsonObject(from: status.stdout)
        XCTAssertEqual(statusPayload["statePath"] as? String, stateURL.path)
        XCTAssertEqual(statusPayload["sourceConfirmationStatus"] as? String, "confirmed")
    }

    @MainActor
    func testSourceOnboardingPrepareLaunchOverwritesStaleRuntimePlaybooks() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let playbookDirectory = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("source-playbooks", isDirectory: true)
        let stalePlaybooks = [
            "obsidian.direct-markdown.v1.md",
            "imessage.imsg-cli.v1.md",
            "notion.ntn-cli.v1.md",
            "apple-notes.memo-cli.v1.md",
            "apple-reminders.remindctl.v1.md",
        ]
        try FileManager.default.createDirectory(at: playbookDirectory, withIntermediateDirectories: true)
        for filename in stalePlaybooks {
            try "STALE RUNTIME PLAYBOOK: \(filename)\n".write(
                to: playbookDirectory.appendingPathComponent(filename, isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
        }

        _ = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )

        let expectedMarkers = [
            "obsidian.direct-markdown.v1.md": "GBrain write target path",
            "imessage.imsg-cli.v1.md": "Full Disk Access",
            "notion.ntn-cli.v1.md": "curl -fsSL https://ntn.dev | bash",
            "apple-notes.memo-cli.v1.md": "brew tap antoniorodr/memo && brew install antoniorodr/memo/memo",
            "apple-reminders.remindctl.v1.md": "brew install steipete/tap/remindctl",
        ]
        for (filename, marker) in expectedMarkers {
            let text = try String(
                contentsOf: playbookDirectory.appendingPathComponent(filename, isDirectory: false),
                encoding: .utf8
            )
            XCTAssertFalse(text.contains("STALE RUNTIME PLAYBOOK"), "\(filename) was not overwritten")
            XCTAssertTrue(text.contains(marker), "\(filename) missing latest marker \(marker):\n\(text)")
        }
    }

    @MainActor
    func testSourceOnboardingHelperStatusCreatesBaselineBeforeAskingSources() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        let status = try runProcess(
            executableURL: helperURL,
            arguments: ["status", "--json"],
            environment: environment
        )

        XCTAssertEqual(status.status, 0, "stdout:\n\(status.stdout)\nstderr:\n\(status.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        let store = makeChecklistStore(homeURL: root)
        let loaded = try XCTUnwrap(store.loadSourceOnboardingState())
        XCTAssertEqual(loaded.progress.normalizedSourceList, [])
        XCTAssertTrue(loaded.progress.sourceRows.isEmpty)
        XCTAssertNil(loaded.progress.pendingQuestion)
        let payload = try jsonObject(from: status.stdout)
        XCTAssertEqual(payload["statePath"] as? String, stateURL.path)
        XCTAssertEqual(payload["normalizedSourceList"] as? [String], [])
    }

    func testSourceOnboardingHelperOffersAgentMemoryOnlyWhenImportableContentExists() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let onboardingDirectory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: onboardingDirectory, withIntermediateDirectories: true)
        try writeJSONObject(
            [
                "schemaVersion": 1,
                "phase": "complete",
                "selectedAgent": "codex",
                "candidates": [
                    [
                        "id": "codex",
                        "displayName": "Codex",
                        "installState": "installed",
                        "terminalLaunchable": true,
                    ],
                ],
            ],
            to: onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        )
        let codexDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try """
        # Personal Codex Instructions

        Prefer concise source summaries for Zebra import tests.
        """.write(
            to: codexDirectory.appendingPathComponent("AGENTS.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]
        let status = try runProcess(
            executableURL: helperURL,
            arguments: ["status", "--json"],
            environment: environment
        )
        XCTAssertEqual(status.status, 0, "stdout:\n\(status.stdout)\nstderr:\n\(status.stderr)")
        let payload = try jsonObject(from: status.stdout)
        XCTAssertTrue((payload["sourceInputPrompt"] as? String)?.contains("기존 agent memory") == true)
        let suggestion = try XCTUnwrap(payload["agentMemorySuggestion"] as? [String: Any])
        XCTAssertEqual(suggestion["available"] as? Bool, true)
        XCTAssertEqual(suggestion["importableUnitCount"] as? Int, 1)

        let intake = try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "기존 agent memory"],
            environment: environment
        )
        XCTAssertEqual(intake.status, 0, "stdout:\n\(intake.stdout)\nstderr:\n\(intake.stderr)")
        let intakePayload = try jsonObject(from: intake.stdout)
        XCTAssertEqual(intakePayload["normalizedSourceList"] as? [String], ["agent-memory"])
        XCTAssertEqual(intakePayload["confirmationPrompt"] as? String, "기존 agent memory로 이해했습니다. 맞나요?")
        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["agent-memory"]?.displayName, "기존 agent memory")
        XCTAssertEqual(loaded.progress.sourceRows["agent-memory"]?.type, "agent-memory")
    }

    func testSourceOnboardingHelperDoesNotOfferEmptyAgentMemory() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let onboardingDirectory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: onboardingDirectory, withIntermediateDirectories: true)
        try writeJSONObject(
            [
                "schemaVersion": 1,
                "phase": "complete",
                "selectedAgent": "codex",
                "candidates": [
                    [
                        "id": "codex",
                        "displayName": "Codex",
                        "installState": "installed",
                        "terminalLaunchable": true,
                    ],
                ],
            ],
            to: onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        )
        let codexDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try "   \n".write(
            to: codexDirectory.appendingPathComponent("AGENTS.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let status = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["status", "--json"],
            environment: [
                "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
                "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
                "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            ]
        )

        XCTAssertEqual(status.status, 0, "stdout:\n\(status.stdout)\nstderr:\n\(status.stderr)")
        let payload = try jsonObject(from: status.stdout)
        XCTAssertFalse((payload["sourceInputPrompt"] as? String)?.contains("기존 agent memory") == true)
        let suggestion = try XCTUnwrap(payload["agentMemorySuggestion"] as? [String: Any])
        XCTAssertEqual(suggestion["available"] as? Bool, false)
        XCTAssertEqual(suggestion["importableUnitCount"] as? Int, 0)
    }

    func testSourceOnboardingHelperBlocksAgentMemoryIngestBeforeApproval() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let onboardingDirectory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: onboardingDirectory, withIntermediateDirectories: true)
        try writeJSONObject(
            [
                "schemaVersion": 1,
                "phase": "complete",
                "selectedAgent": "codex",
                "candidates": [
                    [
                        "id": "codex",
                        "displayName": "Codex",
                        "installState": "installed",
                        "terminalLaunchable": true,
                    ],
                ],
            ],
            to: onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        )
        let codexDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try "Do not ingest before explicit approval.\n".write(
            to: codexDirectory.appendingPathComponent("AGENTS.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        XCTAssertEqual(try runProcess(executableURL: helperURL, arguments: ["intake", "--raw", "기존 agent memory"], environment: environment).status, 0)
        XCTAssertEqual(try runProcess(executableURL: helperURL, arguments: ["confirm", "--answer", "yes"], environment: environment).status, 0)
        XCTAssertEqual(try runProcess(executableURL: helperURL, arguments: ["next"], environment: environment).status, 0)
        XCTAssertEqual(try runProcess(executableURL: helperURL, arguments: ["agent-memory", "choose-scope", "--scope", "sample"], environment: environment).status, 0)

        let blocked = try runProcess(
            executableURL: helperURL,
            arguments: ["agent-memory", "ingest"],
            environment: environment
        )

        XCTAssertEqual(blocked.status, 1, "stdout:\n\(blocked.stdout)\nstderr:\n\(blocked.stderr)")
        let payload = try jsonObject(from: blocked.stdout)
        XCTAssertEqual(payload["reason"] as? String, "ingest_plan_unconfirmed")
        let artifact = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("source-ingest-artifacts", isDirectory: true)
            .appendingPathComponent("agent-memory-knowledge.md", isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path))
    }

    func testSourceOnboardingHelperRunsAgentMemorySourceToCompletion() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let onboardingDirectory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: onboardingDirectory, withIntermediateDirectories: true)
        try writeJSONObject(
            [
                "schemaVersion": 1,
                "phase": "complete",
                "selectedAgent": "codex",
                "candidates": [
                    [
                        "id": "codex",
                        "displayName": "Codex",
                        "installState": "installed",
                        "terminalLaunchable": true,
                    ],
                ],
            ],
            to: onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        )
        let codexDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try "Remember Zebra import behavior tests.\n".write(
            to: codexDirectory.appendingPathComponent("AGENTS.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        _ = try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "기존 agent memory"],
            environment: environment
        )
        _ = try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        )
        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        XCTAssertEqual(try jsonObject(from: next.stdout)["nextPlaybookStepID"] as? String, "review_found_agents")

        _ = try runProcess(
            executableURL: helperURL,
            arguments: ["agent-memory", "choose-scope", "--scope", "sample"],
            environment: environment
        )
        _ = try runProcess(
            executableURL: helperURL,
            arguments: ["agent-memory", "confirm-plan", "--answer", "yes"],
            environment: environment
        )
        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["agent-memory", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let ingestPayload = try jsonObject(from: ingest.stdout)
        let artifactPath = try XCTUnwrap(ingestPayload["artifactPath"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactPath))
        let artifact = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifact.contains("source: agent-memory"))
        XCTAssertTrue(artifact.contains("Remember Zebra import behavior tests."))

        let verify = try runProcess(
            executableURL: helperURL,
            arguments: ["agent-memory", "verify-readback"],
            environment: environment
        )
        XCTAssertEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")
        XCTAssertEqual(try jsonObject(from: verify.stdout)["nextPlaybookStepID"] as? String, "complete")

        let blockedAfterVerify = try runProcess(
            executableURL: helperURL,
            arguments: ["agent-memory", "choose-scope", "--scope", "all"],
            environment: environment
        )
        XCTAssertEqual(blockedAfterVerify.status, 1, "stdout:\n\(blockedAfterVerify.stdout)\nstderr:\n\(blockedAfterVerify.stderr)")
        let blockedPayload = try jsonObject(from: blockedAfterVerify.stdout)
        XCTAssertEqual(blockedPayload["reason"] as? String, "source_completion_report_required")
        XCTAssertEqual(blockedPayload["pendingSourceID"] as? String, "agent-memory")

        let report = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "agent-memory"],
            environment: environment
        )
        XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["agent-memory"]?.status, "checked")
    }

    @MainActor
    func testSourceOnboardingHelperStatusRejectsStaleAdapterReceipt() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let sourceRepo = root
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: true)
        let adapterRepo = sourceRepo
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-adapter", isDirectory: true)
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let executable = try installFakeRuntime(root: root, name: "hermes")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapterRepo, withIntermediateDirectories: true)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            executablePath: executable.path,
            sourceRepoPath: sourceRepo.path
        )
        try writeCompletedAdapterState(
            stateURL: adapterStateURL,
            targetVaultPath: vault.path,
            adapterRepoPath: adapterRepo.path
        )

        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: vault.path)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let status = try runProcess(
            executableURL: helperURL,
            arguments: ["status", "--json"],
            environment: [
                "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
                "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
                "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
                "ZEBRA_GBRAIN_WRITE_TARGET_PATH": vault.path,
            ]
        )

        XCTAssertEqual(status.status, 0, "stdout:\n\(status.stdout)\nstderr:\n\(status.stderr)")
        let payload = try jsonObject(from: status.stdout)
        XCTAssertEqual(payload["status"] as? String, "attention")
        let state = try XCTUnwrap(payload["state"] as? [String: Any])
        let entryContext = try XCTUnwrap(state["entryContext"] as? [String: Any])
        XCTAssertEqual(entryContext["adapterReady"] as? Bool, false)
        let reasons = try XCTUnwrap(entryContext["adapterReadinessReasons"] as? [String])
        XCTAssertTrue(reasons.contains("missing:adapterSkillRouter"), reasons.joined(separator: ","))
    }

    @MainActor
    func testSourceOnboardingHelperNextStartsGmailRunnerAndWritesPromptPath() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        let intake = try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "지메일", "--candidate", "gmail=지메일"],
            environment: environment
        )
        XCTAssertEqual(intake.status, 0, "stdout:\n\(intake.stdout)\nstderr:\n\(intake.stderr)")
        let confirm = try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        )
        XCTAssertEqual(confirm.status, 0, "stdout:\n\(confirm.stdout)\nstderr:\n\(confirm.stderr)")

        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )

        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let payload = try jsonObject(from: next.stdout)
        XCTAssertEqual(payload["nextSourceID"] as? String, "gmail")
        XCTAssertEqual(payload["nextPlaybookID"] as? String, "gmail.clawvisor-gbrain")
        XCTAssertEqual(payload["nextPlaybookVersion"] as? String, "v1")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "connect_clawvisor")
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        let nextPromptPath = try XCTUnwrap(payload["nextPromptPath"] as? String)
        let promptFile = try String(contentsOfFile: nextPromptPath, encoding: .utf8)
        XCTAssertEqual(promptFile.trimmingCharacters(in: .whitespacesAndNewlines), nextPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(nextPrompt.contains("Do not start Notion, Obsidian, iMessage"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Zebra는 Clawvisor를 통해 Gmail, Calendar, Contacts 접근 권한을 안전하게 연결합니다."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("아래 순서대로 진행하세요."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("1. https://app.clawvisor.com/register 을 열고 Google로 sign up 또는 sign in 하세요."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("2. Clawvisor에서 왼쪽 sidebar의 Agents를 열고 GBrain을 선택한 뒤 Create GBrain agent를 클릭하세요."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("3. Google service authorization과 task approval을 이어서 진행하세요."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. 마지막 Env vars step에 도달하면 세 줄의 export env lines를 이 터미널에 그대로 붙여넣으세요."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("zebra-source-onboarding gmail verify-env"), nextPrompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.status, .running)
        XCTAssertEqual(loaded.progress.executionOrder, ["gmail"])
        XCTAssertEqual(loaded.progress.activeSourceID, "gmail")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.status, "running")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.phase, "connect")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.playbookID, "gmail.clawvisor-gbrain")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.playbookVersion, "v1")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.playbookStepID, "connect_clawvisor")

        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let sourceRepo = root
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: true)
        let adapterRepo = sourceRepo
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-adapter", isDirectory: true)
        let agentStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("agent-cli-state.json", isDirectory: false)
        let agentPreferenceURL = root
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
        let runtimeStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let executable = try installFakeRuntime(root: root, name: "hermes")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapterRepo, withIntermediateDirectories: true)
        try writeInstalledAdapterFiles(vault)
        try writeAgentReadinessState(onboardingDirectory: root.appendingPathComponent("onboarding", isDirectory: true), agent: "codex", method: "path")
        try writeAgentPreferences(agentPreferenceURL)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path
        )
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            executablePath: executable.path,
            sourceRepoPath: sourceRepo.path
        )
        try writeCompletedAdapterState(
            stateURL: adapterStateURL,
            targetVaultPath: vault.path,
            adapterRepoPath: adapterRepo.path
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            agentOnboardingStateURL: agentStateURL,
            agentPreferenceURL: agentPreferenceURL,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL,
            gbrainAdapterOnboardingStateURL: adapterStateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path)

        var sourceSnapshot = try XCTUnwrap(store.snapshots.first { $0.id == .sourceOnboarding })
        var gmailSubstep = try XCTUnwrap(sourceSnapshot.substeps.first { $0.id == "source-row-gmail" })
        XCTAssertTrue(sourceSnapshot.isActive)
        XCTAssertFalse(sourceSnapshot.isRunning)
        XCTAssertTrue(gmailSubstep.isActive)
        XCTAssertFalse(gmailSubstep.isRunning)
        XCTAssertTrue(gmailSubstep.showsStart)
        XCTAssertTrue(gmailSubstep.wasStartedBefore)

        store.beginLaunch(stepID: .sourceOnboarding)

        sourceSnapshot = try XCTUnwrap(store.snapshots.first { $0.id == .sourceOnboarding })
        gmailSubstep = try XCTUnwrap(sourceSnapshot.substeps.first { $0.id == "source-row-gmail" })
        XCTAssertTrue(sourceSnapshot.isRunning)
        XCTAssertTrue(gmailSubstep.isActive)
        XCTAssertTrue(gmailSubstep.isRunning)
        XCTAssertFalse(gmailSubstep.showsStart)
    }

    @MainActor
    func testSourceOnboardingHelperNextStartsObsidianRunnerFromVendoredPlaybook() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )

        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let payload = try jsonObject(from: next.stdout)
        XCTAssertEqual(payload["nextSourceID"] as? String, "obsidian")
        XCTAssertEqual(payload["nextPlaybookID"] as? String, "obsidian.direct-markdown")
        XCTAssertEqual(payload["nextPlaybookVersion"] as? String, "v1")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "discover_vault")
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        let nextPromptPath = try XCTUnwrap(payload["nextPromptPath"] as? String)
        let promptFile = try String(contentsOfFile: nextPromptPath, encoding: .utf8)
        XCTAssertEqual(promptFile.trimmingCharacters(in: .whitespacesAndNewlines), nextPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(nextPrompt.contains("Playbook: obsidian.direct-markdown v1"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("zebra-source-onboarding obsidian verify-vault"), nextPrompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.status, .running)
        XCTAssertEqual(loaded.progress.executionOrder, ["obsidian"])
        XCTAssertEqual(loaded.progress.activeSourceID, "obsidian")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.status, "running")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.phase, "preflight")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.playbookID, "obsidian.direct-markdown")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.playbookVersion, "v1")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.playbookStepID, "discover_vault")
    }

    @MainActor
    func testSourceOnboardingHelperNextStartsNotionRunnerWithStateLanguageFallback() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "노션", "--candidate", "notion=노션"],
            environment: environment
        ).status, 0)
        var state = try stateObject(in: stateURL)
        var entryContext = state["entryContext"] as? [String: Any] ?? [:]
        entryContext["onboardingLanguageCode"] = "ko"
        state["entryContext"] = entryContext
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: stateURL, options: .atomic)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )

        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let payload = try jsonObject(from: next.stdout)
        XCTAssertEqual(payload["nextSourceID"] as? String, "notion")
        XCTAssertEqual(payload["nextPlaybookID"] as? String, "notion.ntn-cli")
        XCTAssertEqual(payload["nextPlaybookVersion"] as? String, "v1")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "check_ntn_cli")
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertTrue(nextPrompt.contains("zebra-source-onboarding notion check-cli"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("curl -fsSL https://ntn.dev | bash"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("npm install --global ntn"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("Do not install anything unless the user explicitly asks."), nextPrompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.executionOrder, ["notion"])
        XCTAssertEqual(loaded.progress.activeSourceID, "notion")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.status, "running")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.phase, "preflight")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookID, "notion.ntn-cli")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookVersion, "v1")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookStepID, "check_ntn_cli")
    }

    @MainActor
    func testSourceOnboardingNotionMissingCLIWritesAttentionBeforeScopeCommands() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fakeBin.appendingPathComponent("python3", isDirectory: false),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3")
        )
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "PATH": fakeBin.path,
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "노션", "--candidate", "notion=노션"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)

        let checkCLI = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "check-cli"],
            environment: environment
        )
        XCTAssertEqual(checkCLI.status, 1, "stdout:\n\(checkCLI.stdout)\nstderr:\n\(checkCLI.stderr)")
        let payload = try jsonObject(from: checkCLI.stdout)
        XCTAssertEqual(payload["reason"] as? String, "ntn_cli_missing")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "check_ntn_cli")
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertTrue(nextPrompt.contains("curl -fsSL https://ntn.dev | bash"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("npm install --global ntn"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("ntn login"), nextPrompt)

        let choose = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "choose-scope", "--scope", "workspace-search"],
            environment: environment
        )
        XCTAssertEqual(choose.status, 1, "stdout:\n\(choose.stdout)\nstderr:\n\(choose.stderr)")
        XCTAssertEqual(try jsonObject(from: choose.stdout)["reason"] as? String, "ntn_cli_missing")

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.status, "attention")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.attentionReason, "ntn_cli_missing")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookStepID, "check_ntn_cli")
    }

    @MainActor
    func testSourceOnboardingNotionChooseScopeAppliesAfterImplicitCLIPreflight() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let ntnLog = root.appendingPathComponent("ntn.log", isDirectory: false)
        _ = try installFakeNotionCLI(fakeBin: fakeBin, logURL: ntnLog)
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "PATH": "\(fakeBin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "노션", "--candidate", "notion=노션"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)

        let choose = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "choose-scope", "--scope", "page", "--target", "page123"],
            environment: environment
        )
        XCTAssertEqual(choose.status, 0, "stdout:\n\(choose.stdout)\nstderr:\n\(choose.stderr)")
        let payload = try jsonObject(from: choose.stdout)
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "ingest_notion")
        XCTAssertEqual(payload["scope"] as? String, "page")
        XCTAssertEqual(payload["targetID"] as? String, "page123")

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.status, "running")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookStepID, "ingest_notion")
        let runStatePath = try XCTUnwrap(loaded.progress.sourceRows["notion"]?.runStatePath)
        let runState = try jsonObject(from: String(contentsOfFile: runStatePath, encoding: .utf8))
        XCTAssertEqual(runState["cliStatus"] as? String, "passed")
        XCTAssertEqual(runState["scope"] as? String, "page")
        XCTAssertEqual(runState["targetID"] as? String, "page123")
    }

    @MainActor
    func testSourceOnboardingAppleNotesRunnerMissingCLIHappyPathAndBrainArtifact() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let memoLog = root.appendingPathComponent("memo.log", isDirectory: false)
        let brain = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: brain, withIntermediateDirectories: true)

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: brain.path,
            executablePath: "/usr/bin/true"
        )
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: brain.path)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let baseEnvironment = [
            "PATH": "/usr/bin:/bin",
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_GBRAIN_WRITE_TARGET_PATH": brain.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "맥북 메모", "--candidate", "apple-notes=맥북 메모"],
            environment: baseEnvironment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: baseEnvironment
        ).status, 0)

        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: baseEnvironment
        )
        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let nextPayload = try jsonObject(from: next.stdout)
        XCTAssertEqual(nextPayload["nextSourceID"] as? String, "apple-notes")
        XCTAssertEqual(nextPayload["nextPlaybookID"] as? String, "apple-notes.memo-cli")
        XCTAssertEqual(nextPayload["nextPlaybookVersion"] as? String, "v1")
        XCTAssertEqual(nextPayload["nextPlaybookStepID"] as? String, "check_memo_cli")
        XCTAssertTrue(try XCTUnwrap(nextPayload["nextPrompt"] as? String).contains("zebra-source-onboarding apple-notes check-cli"))

        let missingCLI = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-cli"],
            environment: baseEnvironment
        )
        XCTAssertEqual(missingCLI.status, 1, "stdout:\n\(missingCLI.stdout)\nstderr:\n\(missingCLI.stderr)")
        let missingCLIPayload = try jsonObject(from: missingCLI.stdout)
        XCTAssertEqual(missingCLIPayload["reason"] as? String, "memo_cli_missing")
        let missingCLIPrompt = try XCTUnwrap(missingCLIPayload["nextPrompt"] as? String)
        XCTAssertTrue(missingCLIPrompt.contains("brew tap antoniorodr/memo && brew install antoniorodr/memo/memo"), missingCLIPrompt)
        XCTAssertTrue(missingCLIPrompt.contains("Apple Notes ingest requires the memo CLI. Install it now with Homebrew? (yes/no)"), missingCLIPrompt)
        XCTAssertTrue(missingCLIPrompt.contains("Do not install anything unless the user explicitly answers yes."), missingCLIPrompt)

        let koreanMissingCLI = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-cli"],
            environment: baseEnvironment.merging(["ZEBRA_ONBOARDING_LANGUAGE": "ko"]) { _, new in new }
        )
        XCTAssertEqual(koreanMissingCLI.status, 1, "stdout:\n\(koreanMissingCLI.stdout)\nstderr:\n\(koreanMissingCLI.stderr)")
        let koreanMissingCLIPrompt = try XCTUnwrap(jsonObject(from: koreanMissingCLI.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(koreanMissingCLIPrompt.contains("Apple Notes ingest에는 memo CLI가 필요합니다. Homebrew로 지금 설치할까요? (yes/no)"), koreanMissingCLIPrompt)
        XCTAssertTrue(koreanMissingCLIPrompt.contains("사용자가 명시적으로 yes라고 답하기 전에는 아무것도 설치하지 마세요."), koreanMissingCLIPrompt)
        XCTAssertFalse(koreanMissingCLIPrompt.contains("Install it now with Homebrew?"), koreanMissingCLIPrompt)

        let japaneseMissingCLI = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-cli"],
            environment: baseEnvironment.merging(["ZEBRA_ONBOARDING_LANGUAGE": "ja"]) { _, new in new }
        )
        XCTAssertEqual(japaneseMissingCLI.status, 1, "stdout:\n\(japaneseMissingCLI.stdout)\nstderr:\n\(japaneseMissingCLI.stderr)")
        let japaneseMissingCLIPrompt = try XCTUnwrap(jsonObject(from: japaneseMissingCLI.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(japaneseMissingCLIPrompt.contains("Apple Notes ingest には memo CLI が必要です。Homebrew で今インストールしますか？ (yes/no)"), japaneseMissingCLIPrompt)
        XCTAssertTrue(japaneseMissingCLIPrompt.contains("ユーザーが明示的に yes と答えるまで、何もインストールしないでください。"), japaneseMissingCLIPrompt)
        XCTAssertFalse(japaneseMissingCLIPrompt.contains("Install it now with Homebrew?"), japaneseMissingCLIPrompt)

        _ = try installFakeMemoCLI(fakeBin: fakeBin, logURL: memoLog)
        let environment = baseEnvironment.merging([
            "PATH": "\(fakeBin.path):/usr/bin:/bin",
        ]) { _, new in new }

        let checkCLI = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-cli"],
            environment: environment
        )
        XCTAssertEqual(checkCLI.status, 0, "stdout:\n\(checkCLI.stdout)\nstderr:\n\(checkCLI.stderr)")
        XCTAssertEqual(try jsonObject(from: checkCLI.stdout)["nextPlaybookStepID"] as? String, "check_notes_automation")

        let checkAccess = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-access"],
            environment: environment
        )
        XCTAssertEqual(checkAccess.status, 0, "stdout:\n\(checkAccess.stdout)\nstderr:\n\(checkAccess.stderr)")
        XCTAssertEqual(try jsonObject(from: checkAccess.stdout)["nextPlaybookStepID"] as? String, "smoke_list_notes")

        let smoke = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "smoke-list"],
            environment: environment
        )
        XCTAssertEqual(smoke.status, 0, "stdout:\n\(smoke.stdout)\nstderr:\n\(smoke.stderr)")
        XCTAssertEqual(try jsonObject(from: smoke.stdout)["nextPlaybookStepID"] as? String, "choose_ingest_scope")

        let scope = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "choose-scope", "--scope", "selected-notes", "--note-id", "7"],
            environment: environment
        )
        XCTAssertEqual(scope.status, 0, "stdout:\n\(scope.stdout)\nstderr:\n\(scope.stderr)")
        XCTAssertEqual(try jsonObject(from: scope.stdout)["nextPlaybookStepID"] as? String, "confirm_ingest_plan")

        let blockedIngest = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "ingest"],
            environment: environment
        )
        XCTAssertEqual(blockedIngest.status, 1, "stdout:\n\(blockedIngest.stdout)\nstderr:\n\(blockedIngest.stderr)")
        XCTAssertEqual(try jsonObject(from: blockedIngest.stdout)["reason"] as? String, "ingest_plan_unconfirmed")

        let confirm = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "confirm-plan", "--answer", "yes"],
            environment: environment
        )
        XCTAssertEqual(confirm.status, 0, "stdout:\n\(confirm.stdout)\nstderr:\n\(confirm.stderr)")
        XCTAssertEqual(try jsonObject(from: confirm.stdout)["nextPlaybookStepID"] as? String, "ingest_notes")

        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let ingestPayload = try jsonObject(from: ingest.stdout)
        XCTAssertEqual(ingestPayload["nextPlaybookStepID"] as? String, "verify_readback")
        let artifactPath = try XCTUnwrap(ingestPayload["artifactPath"] as? String)
        let expectedArtifact = brain
            .appendingPathComponent("sources/apple-notes-memo-cli.md")
            .standardizedFileURL
            .path
        XCTAssertEqual(
            URL(fileURLWithPath: artifactPath).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: expectedArtifact).resolvingSymlinksInPath().path
        )
        let artifact = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifact.contains("source: apple-notes"), artifact)
        XCTAssertTrue(artifact.contains("playbook: apple-notes.memo-cli.v1"), artifact)
        XCTAssertTrue(artifact.contains("KakaoVentures VC framework"), artifact)

        let verify = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "verify-readback"],
            environment: environment
        )
        XCTAssertEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")
        let verifyPayload = try jsonObject(from: verify.stdout)
        XCTAssertEqual(verifyPayload["nextPlaybookStepID"] as? String, "complete")
        XCTAssertTrue(try XCTUnwrap(verifyPayload["nextPrompt"] as? String).contains("report --status completed --source apple-notes"))

        var loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["apple-notes"]?.status, "running")

        let report = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "apple-notes"],
            environment: environment
        )
        XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.status, .completed)
        XCTAssertEqual(loaded.progress.sourceRows["apple-notes"]?.status, "checked")
    }

    @MainActor
    func testSourceOnboardingHelperRecognizesKoreanAppleNotesAliasWithoutAgentCandidate() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        let intake = try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "애플노트 지메일 노션"],
            environment: environment
        )

        XCTAssertEqual(intake.status, 0, "stdout:\n\(intake.stdout)\nstderr:\n\(intake.stderr)")
        let payload = try jsonObject(from: intake.stdout)
        XCTAssertEqual(payload["normalizedSourceList"] as? [String], ["apple-notes", "gmail", "notion"])
        XCTAssertEqual(payload["uncatalogedSources"] as? [String], [])
        XCTAssertEqual(payload["confirmationPrompt"] as? String, "Apple Notes, Gmail, Notion로 이해했습니다. 맞나요?")
    }

    @MainActor
    func testSourceOnboardingHelperRecognizesKoreanAppleRemindersAliasWithoutAgentCandidate() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        let intake = try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "애플리마인더 지메일 미리 알림 노션"],
            environment: environment
        )

        XCTAssertEqual(intake.status, 0, "stdout:\n\(intake.stdout)\nstderr:\n\(intake.stderr)")
        let payload = try jsonObject(from: intake.stdout)
        XCTAssertEqual(payload["normalizedSourceList"] as? [String], ["apple-reminders", "gmail", "notion"])
        XCTAssertEqual(payload["uncatalogedSources"] as? [String], [])
        XCTAssertEqual(payload["confirmationPrompt"] as? String, "Apple Reminders, Gmail, Notion로 이해했습니다. 맞나요?")
    }

    @MainActor
    func testSourceOnboardingAppleRemindersInstallConsentAndPermissionAttention() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fakeBin.appendingPathComponent("python3", isDirectory: false),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3")
        )

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let baseEnvironment = [
            "PATH": fakeBin.path,
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "미리알림", "--candidate", "apple-reminders=미리알림"],
            environment: baseEnvironment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: baseEnvironment
        ).status, 0)
        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: baseEnvironment
        )
        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let nextPayload = try jsonObject(from: next.stdout)
        XCTAssertEqual(nextPayload["nextSourceID"] as? String, "apple-reminders")
        XCTAssertEqual(nextPayload["nextPlaybookID"] as? String, "apple-reminders.remindctl")
        XCTAssertEqual(nextPayload["nextPlaybookStepID"] as? String, "check_remindctl_cli")

        let missingBrew = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "check-cli"],
            environment: baseEnvironment
        )
        XCTAssertEqual(missingBrew.status, 1, "stdout:\n\(missingBrew.stdout)\nstderr:\n\(missingBrew.stderr)")
        XCTAssertEqual(try jsonObject(from: missingBrew.stdout)["reason"] as? String, "homebrew_install_consent_required")
        var loaded = try readSourceOnboardingState(at: stateURL)
        var row = try XCTUnwrap(loaded.progress.sourceRows["apple-reminders"])
        var runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["homebrewInstallAsked"] as? Bool, true)
        XCTAssertEqual(runState["installCommandRun"] as? Bool, false)

        let declinedBrew = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "check-cli", "--homebrew-install-answer", "no"],
            environment: baseEnvironment
        )
        XCTAssertEqual(declinedBrew.status, 1, "stdout:\n\(declinedBrew.stdout)\nstderr:\n\(declinedBrew.stderr)")
        XCTAssertEqual(try jsonObject(from: declinedBrew.stdout)["reason"] as? String, "homebrew_install_declined")
        loaded = try readSourceOnboardingState(at: stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["apple-reminders"])
        runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["homebrewInstallAnswer"] as? String, "no")
        XCTAssertEqual((runState["homebrewInstallResult"] as? [String: Any])?["status"] as? String, "user_declined")

        let brewLog = root.appendingPathComponent("brew.log", isDirectory: false)
        try installFakeCommand(
            directory: fakeBin,
            name: "brew",
            content: """
            #!/bin/sh
            printf '%s\\n' "$*" >> '\(shellSingleQuoted(brewLog.path))'
            if [ "$1" = "install" ] && [ "$2" = "steipete/tap/remindctl" ]; then
              /bin/cat > '\(shellSingleQuoted(fakeBin.appendingPathComponent("remindctl", isDirectory: false).path))' <<'EOS'
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "remindctl 0.3.2"
              exit 0
            fi
            if [ "$1" = "status" ]; then
              echo '{"status":"denied"}'
              exit 0
            fi
            if [ "$1" = "doctor" ]; then
              echo 'Reminders permission required'
              exit 0
            fi
            if [ "$1" = "authorize" ]; then
              exit 0
            fi
            exit 1
            EOS
              /bin/chmod +x '\(shellSingleQuoted(fakeBin.appendingPathComponent("remindctl", isDirectory: false).path))'
              exit 0
            fi
            exit 1
            """
        )
        let installRemindctl = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "check-cli", "--remindctl-install-answer", "yes"],
            environment: baseEnvironment
        )
        XCTAssertEqual(installRemindctl.status, 0, "stdout:\n\(installRemindctl.stdout)\nstderr:\n\(installRemindctl.stderr)")
        loaded = try readSourceOnboardingState(at: stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["apple-reminders"])
        runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["remindctlInstallAsked"] as? Bool, true)
        XCTAssertEqual(runState["remindctlInstallAnswer"] as? String, "yes")
        XCTAssertEqual((runState["remindctlInstallResult"] as? [String: Any])?["status"] as? String, "succeeded")
        XCTAssertEqual(runState["installCommandRun"] as? Bool, true)

        let denied = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "check-access"],
            environment: baseEnvironment
        )
        XCTAssertEqual(denied.status, 1, "stdout:\n\(denied.stdout)\nstderr:\n\(denied.stderr)")
        XCTAssertEqual(try jsonObject(from: denied.stdout)["reason"] as? String, "reminders_permission_attention")
        XCTAssertTrue(try XCTUnwrap(jsonObject(from: denied.stdout)["nextPrompt"] as? String).contains("System Settings > Privacy & Security > Reminders"))
    }

    @MainActor
    func testSourceOnboardingAppleRemindersRunnerHappyPathUsesOpenListCommand() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let remindctlLog = root.appendingPathComponent("remindctl.log", isDirectory: false)
        let brain = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: brain, withIntermediateDirectories: true)
        _ = try installFakeRemindctlCLI(fakeBin: fakeBin, logURL: remindctlLog)

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: brain.path,
            executablePath: "/usr/bin/true"
        )
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: brain.path)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "PATH": "\(fakeBin.path):/usr/bin:/bin",
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_GBRAIN_WRITE_TARGET_PATH": brain.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: [
                "intake",
                "--raw", "apple reminders, apple notes",
                "--candidate", "apple-reminders=apple reminders",
                "--candidate", "apple-notes=apple notes",
            ],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(executableURL: helperURL, arguments: ["next"], environment: environment).status, 0)
        XCTAssertEqual(try runProcess(executableURL: helperURL, arguments: ["apple-reminders", "check-cli"], environment: environment).status, 0)
        XCTAssertEqual(try runProcess(executableURL: helperURL, arguments: ["apple-reminders", "check-access"], environment: environment).status, 0)

        let smoke = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "smoke-list"],
            environment: environment
        )
        XCTAssertEqual(smoke.status, 0, "stdout:\n\(smoke.stdout)\nstderr:\n\(smoke.stderr)")
        let smokePayload = try jsonObject(from: smoke.stdout)
        XCTAssertEqual(smokePayload["openReminderCount"] as? Int, 2)
        let scopePrompt = try XCTUnwrap(smokePayload["nextPrompt"] as? String)
        XCTAssertTrue(scopePrompt.contains("1. All open reminders"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("5. Skip Apple Reminders for now"), scopePrompt)

        let koreanScope = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment.merging(["ZEBRA_ONBOARDING_LANGUAGE": "ko"]) { _, new in new }
        )
        XCTAssertEqual(koreanScope.status, 0, "stdout:\n\(koreanScope.stdout)\nstderr:\n\(koreanScope.stderr)")
        let koreanScopePrompt = try XCTUnwrap(jsonObject(from: koreanScope.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(koreanScopePrompt.contains("1. 열려 있는 모든 미리알림"), koreanScopePrompt)
        XCTAssertTrue(koreanScopePrompt.contains("5. 지금은 Apple Reminders 건너뛰기"), koreanScopePrompt)
        XCTAssertFalse(koreanScopePrompt.contains("1. All open reminders"), koreanScopePrompt)
        XCTAssertFalse(koreanScopePrompt.contains("5. Skip Apple Reminders for now"), koreanScopePrompt)

        let japaneseScope = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment.merging(["ZEBRA_ONBOARDING_LANGUAGE": "ja"]) { _, new in new }
        )
        XCTAssertEqual(japaneseScope.status, 0, "stdout:\n\(japaneseScope.stdout)\nstderr:\n\(japaneseScope.stderr)")
        let japaneseScopePrompt = try XCTUnwrap(jsonObject(from: japaneseScope.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(japaneseScopePrompt.contains("1. 未完了のすべてのリマインダー"), japaneseScopePrompt)
        XCTAssertTrue(japaneseScopePrompt.contains("5. 今回はApple Remindersをスキップ"), japaneseScopePrompt)
        XCTAssertFalse(japaneseScopePrompt.contains("1. All open reminders"), japaneseScopePrompt)
        XCTAssertFalse(japaneseScopePrompt.contains("5. Skip Apple Reminders for now"), japaneseScopePrompt)

        let scope = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "choose-scope", "--scope", "one-list", "--list", "Work"],
            environment: environment
        )
        XCTAssertEqual(scope.status, 0, "stdout:\n\(scope.stdout)\nstderr:\n\(scope.stderr)")
        XCTAssertEqual(try jsonObject(from: scope.stdout)["nextPlaybookStepID"] as? String, "confirm_ingest_plan")
        XCTAssertEqual(try jsonObject(from: scope.stdout)["expectedCount"] as? Int, 2)

        let blockedIngest = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "ingest"],
            environment: environment
        )
        XCTAssertEqual(blockedIngest.status, 1, "stdout:\n\(blockedIngest.stdout)\nstderr:\n\(blockedIngest.stderr)")
        XCTAssertEqual(try jsonObject(from: blockedIngest.stdout)["reason"] as? String, "ingest_plan_unconfirmed")

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "confirm-plan", "--answer", "yes"],
            environment: environment
        ).status, 0)
        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let artifactPath = try XCTUnwrap(jsonObject(from: ingest.stdout)["artifactPath"] as? String)
        let artifact = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifact.contains("source: apple-reminders"), artifact)
        XCTAssertTrue(artifact.contains("playbook: apple-reminders.remindctl.v1"), artifact)
        XCTAssertTrue(artifact.contains("Investor update"), artifact)
        XCTAssertTrue(artifact.contains("[Source: Apple Reminders list \"Work\","), artifact)
        XCTAssertFalse(artifact.contains("\"reminders\":"), artifact)

        let commandLog = try String(contentsOf: remindctlLog, encoding: .utf8)
        XCTAssertTrue(commandLog.contains("open --list Work --json"), commandLog)
        XCTAssertFalse(commandLog.split(whereSeparator: \.isNewline).contains("list Work --json"), commandLog)

        let verify = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-reminders", "verify-readback"],
            environment: environment
        )
        XCTAssertEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")
        let verifyPayload = try jsonObject(from: verify.stdout)
        XCTAssertEqual(verifyPayload["nextPlaybookStepID"] as? String, "complete")
        let pendingPrompt = try XCTUnwrap(verifyPayload["nextPrompt"] as? String)
        XCTAssertTrue(pendingPrompt.contains("Apple Reminders completion report is required"), pendingPrompt)
        XCTAssertTrue(pendingPrompt.contains("zebra-source-onboarding report --status completed --source apple-reminders"), pendingPrompt)
        XCTAssertFalse(pendingPrompt.contains("Zebra Source Onboarding: Apple Notes is the active source."), pendingPrompt)

        let blockedNext = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(blockedNext.status, 1, "stdout:\n\(blockedNext.stdout)\nstderr:\n\(blockedNext.stderr)")
        let blockedNextPayload = try jsonObject(from: blockedNext.stdout)
        XCTAssertEqual(blockedNextPayload["reason"] as? String, "source_completion_report_required")
        XCTAssertEqual(blockedNextPayload["pendingSourceID"] as? String, "apple-reminders")
        XCTAssertEqual(blockedNextPayload["blockedSourceID"] as? String, "next")
        XCTAssertEqual(blockedNextPayload["nextSourceID"] as? String, "apple-reminders")
        XCTAssertEqual(blockedNextPayload["nextPlaybookStepID"] as? String, "complete")
        XCTAssertTrue(try XCTUnwrap(blockedNextPayload["nextPrompt"] as? String).contains("zebra-source-onboarding report --status completed --source apple-reminders"))
        var loadedWhilePending = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loadedWhilePending.progress.activeSourceID, "apple-reminders")
        XCTAssertNil(loadedWhilePending.progress.sourceRows["apple-notes"]?.playbookStepID)

        let blockedNextSource = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-cli"],
            environment: environment
        )
        XCTAssertEqual(blockedNextSource.status, 1, "stdout:\n\(blockedNextSource.stdout)\nstderr:\n\(blockedNextSource.stderr)")
        let blockedNextSourcePayload = try jsonObject(from: blockedNextSource.stdout)
        XCTAssertEqual(blockedNextSourcePayload["reason"] as? String, "source_completion_report_required")
        XCTAssertEqual(blockedNextSourcePayload["pendingSourceID"] as? String, "apple-reminders")
        XCTAssertEqual(blockedNextSourcePayload["blockedSourceID"] as? String, "apple-notes")

        let report = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "apple-reminders"],
            environment: environment
        )
        XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        let reportPayload = try jsonObject(from: report.stdout)
        XCTAssertEqual(reportPayload["completedSourceID"] as? String, "apple-reminders")
        XCTAssertEqual(reportPayload["nextSourceID"] as? String, "apple-notes")
        XCTAssertNil(reportPayload["nextCommand"])
        XCTAssertEqual(reportPayload["complete"] as? Bool, false)
        let reportPrompt = try XCTUnwrap(reportPayload["nextPrompt"] as? String)
        XCTAssertTrue(reportPrompt.contains("# Completed Source Result"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("# Continuation Contract"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("# Next Source Prompt"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("Apple Reminders Source Onboarding is complete."), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Reminders ingested: 2"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Scope: open reminders from list `Work`"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Artifact: `"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("Zebra Source Onboarding: Apple Notes is the active source."), reportPrompt)
        XCTAssertFalse(reportPrompt.contains("zebra-source-onboarding next"), reportPrompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["apple-reminders"]?.status, "checked")
        XCTAssertEqual(loaded.progress.activeSourceID, "apple-notes")
        XCTAssertEqual(loaded.progress.sourceRows["apple-notes"]?.playbookStepID, "check_memo_cli")
        let runStatePath = try XCTUnwrap(loaded.progress.sourceRows["apple-reminders"]?.runStatePath)
        let runState = try stateObject(in: URL(fileURLWithPath: runStatePath))
        XCTAssertNil(runState["rawJSON"])
        XCTAssertNil(runState["items"])
        XCTAssertEqual(runState["ingestedReminderCount"] as? Int, 2)
        XCTAssertEqual(runState["completionReportPending"] as? Bool, false)
        XCTAssertNotNil(runState["completionReportedAt"] as? String)

        let nextAfterReport = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(nextAfterReport.status, 0, "stdout:\n\(nextAfterReport.stdout)\nstderr:\n\(nextAfterReport.stderr)")
        let nextAfterReportPayload = try jsonObject(from: nextAfterReport.stdout)
        XCTAssertEqual(nextAfterReportPayload["nextSourceID"] as? String, "apple-notes")
        let nextAfterReportPrompt = try XCTUnwrap(nextAfterReportPayload["nextPrompt"] as? String)
        XCTAssertTrue(nextAfterReportPrompt.contains("Zebra Source Onboarding: Apple Notes is the active source."), nextAfterReportPrompt)
        loadedWhilePending = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loadedWhilePending.progress.activeSourceID, "apple-notes")
    }

    @MainActor
    func testSourceOnboardingAppleNotesFolderScopeIngestsAllResolvedNotes() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let memoLog = root.appendingPathComponent("memo.log", isDirectory: false)
        _ = try installFakeMemoCLI(fakeBin: fakeBin, logURL: memoLog)
        let brain = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: brain, withIntermediateDirectories: true)

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: brain.path,
            executablePath: "/usr/bin/true"
        )
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: brain.path)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "PATH": "\(fakeBin.path):/usr/bin:/bin",
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_GBRAIN_WRITE_TARGET_PATH": brain.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "apple notes", "--candidate", "apple-notes=apple notes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-cli"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "check-access"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "smoke-list"],
            environment: environment
        ).status, 0)

        let scope = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "choose-scope", "--scope", "folder", "--folder", "Overflow"],
            environment: environment
        )
        XCTAssertEqual(scope.status, 0, "stdout:\n\(scope.stdout)\nstderr:\n\(scope.stderr)")
        XCTAssertEqual(try jsonObject(from: scope.stdout)["estimatedNoteCount"] as? Int, 25)

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "confirm-plan", "--answer", "yes"],
            environment: environment
        ).status, 0)
        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["apple-notes", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        XCTAssertEqual(try jsonObject(from: ingest.stdout)["ingestedNoteCount"] as? Int, 25)

        let artifactPath = try XCTUnwrap(jsonObject(from: ingest.stdout)["artifactPath"] as? String)
        let artifact = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifact.contains("note_count: 25"), artifact)
        XCTAssertTrue(artifact.contains("Generated overflow note 25"), artifact)
    }

    @MainActor
    func testSourceOnboardingNotionRedactsQuotedCredentialFieldsBeforeArtifactWrite() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let ntnLog = root.appendingPathComponent("ntn.log", isDirectory: false)
        _ = try installFakeNotionCLI(fakeBin: fakeBin, logURL: ntnLog)
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "PATH": "\(fakeBin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "노션", "--candidate", "notion=노션"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)
        let checkCLI = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "check-cli"],
            environment: environment
        )
        XCTAssertEqual(checkCLI.status, 0, "stdout:\n\(checkCLI.stdout)\nstderr:\n\(checkCLI.stderr)")
        XCTAssertEqual(try jsonObject(from: checkCLI.stdout)["nextPlaybookStepID"] as? String, "choose_scope")
        let choose = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "choose-scope", "--scope", "page", "--target", "page123"],
            environment: environment
        )
        XCTAssertEqual(choose.status, 0, "stdout:\n\(choose.stdout)\nstderr:\n\(choose.stderr)")
        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let artifactPath = try XCTUnwrap(jsonObject(from: ingest.stdout)["artifactPath"] as? String)
        let artifact = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifact.contains("\"oauth_code\":\"REDACTED\""), artifact)
        XCTAssertTrue(artifact.contains("\"code\":\"REDACTED\""), artifact)
        XCTAssertFalse(artifact.contains("ABCDEFGH"), artifact)
        XCTAssertFalse(artifact.contains("12345678"), artifact)
    }

    @MainActor
    func testSourceOnboardingReportCompletedAdvancesFromNotionToObsidianWithCompletionBoundary() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let ntnLog = root.appendingPathComponent("ntn.log", isDirectory: false)
        _ = try installFakeNotionCLI(fakeBin: fakeBin, logURL: ntnLog)
        let vault = root.appendingPathComponent("Obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian", isDirectory: true), withIntermediateDirectories: true)
        try "# Obsidian note\nBody".write(
            to: vault.appendingPathComponent("note.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "PATH": "\(fakeBin.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "노션 옵시디언", "--candidate", "notion=노션", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "check-cli"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "choose-scope", "--scope", "page", "--target", "page123"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "ingest"],
            environment: environment
        ).status, 0)

        let verify = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "verify-readback"],
            environment: environment
        )
        XCTAssertEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")
        let verifyPayload = try jsonObject(from: verify.stdout)
        XCTAssertEqual(verifyPayload["nextSourceID"] as? String, "notion")
        XCTAssertEqual(verifyPayload["nextPlaybookStepID"] as? String, "complete")
        let pendingPrompt = try XCTUnwrap(verifyPayload["nextPrompt"] as? String)
        XCTAssertTrue(pendingPrompt.contains("zebra-source-onboarding report --status completed --source notion"), pendingPrompt)
        XCTAssertFalse(pendingPrompt.contains("Zebra Source Onboarding: Obsidian is the active source."), pendingPrompt)

        let activeBeforeReport = try readSourceOnboardingState(at: stateURL).progress
        XCTAssertEqual(activeBeforeReport.activeSourceID, "notion")
        XCTAssertEqual(activeBeforeReport.sourceRows["notion"]?.status, "running")

        let outOfOrderSourceCommand = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "verify-vault", "--path", root.path],
            environment: environment
        )
        XCTAssertEqual(outOfOrderSourceCommand.status, 1, "stdout:\n\(outOfOrderSourceCommand.stdout)\nstderr:\n\(outOfOrderSourceCommand.stderr)")
        let outOfOrderPayload = try jsonObject(from: outOfOrderSourceCommand.stdout)
        XCTAssertEqual(outOfOrderPayload["reason"] as? String, "source_completion_report_required")
        XCTAssertEqual(outOfOrderPayload["pendingSourceID"] as? String, "notion")
        XCTAssertEqual(outOfOrderPayload["blockedSourceID"] as? String, "obsidian")
        XCTAssertTrue(try XCTUnwrap(outOfOrderPayload["nextPrompt"] as? String).contains("report --status completed --source notion"))
        let activeAfterOutOfOrderCommand = try readSourceOnboardingState(at: stateURL).progress
        XCTAssertEqual(activeAfterOutOfOrderCommand.activeSourceID, "notion")
        XCTAssertEqual(activeAfterOutOfOrderCommand.sourceRows["notion"]?.status, "running")
        XCTAssertNil(activeAfterOutOfOrderCommand.sourceRows["obsidian"]?.playbookStepID)

        let blockedNext = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(blockedNext.status, 1, "stdout:\n\(blockedNext.stdout)\nstderr:\n\(blockedNext.stderr)")
        let blockedNextPayload = try jsonObject(from: blockedNext.stdout)
        XCTAssertEqual(blockedNextPayload["reason"] as? String, "source_completion_report_required")
        XCTAssertEqual(blockedNextPayload["pendingSourceID"] as? String, "notion")
        XCTAssertEqual(blockedNextPayload["blockedSourceID"] as? String, "next")
        XCTAssertEqual(blockedNextPayload["nextSourceID"] as? String, "notion")
        XCTAssertEqual(blockedNextPayload["nextPlaybookStepID"] as? String, "complete")
        XCTAssertTrue(try XCTUnwrap(blockedNextPayload["nextPrompt"] as? String).contains("report --status completed --source notion"))
        let activeAfterBlockedNext = try readSourceOnboardingState(at: stateURL).progress
        XCTAssertEqual(activeAfterBlockedNext.activeSourceID, "notion")
        XCTAssertNil(activeAfterBlockedNext.sourceRows["obsidian"]?.playbookStepID)

        let wrongReport = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "obsidian"],
            environment: environment
        )
        XCTAssertEqual(wrongReport.status, 1, "stdout:\n\(wrongReport.stdout)\nstderr:\n\(wrongReport.stderr)")
        XCTAssertEqual(try jsonObject(from: wrongReport.stdout)["reason"] as? String, "source_not_active")

        let report = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "notion"],
            environment: environment
        )
        XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        let reportPayload = try jsonObject(from: report.stdout)
        XCTAssertEqual(reportPayload["completedSourceID"] as? String, "notion")
        XCTAssertEqual(reportPayload["nextSourceID"] as? String, "obsidian")
        XCTAssertNil(reportPayload["nextCommand"])
        XCTAssertEqual(reportPayload["complete"] as? Bool, false)
        XCTAssertTrue(try XCTUnwrap(reportPayload["completedSourceResultBlock"] as? String).contains("Notion Source Onboarding is complete."))
        let reportPrompt = try XCTUnwrap(reportPayload["nextPrompt"] as? String)
        XCTAssertTrue(reportPrompt.contains("# Completed Source Result"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("# Continuation Contract"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("# Next Source Prompt"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("Notion Source Onboarding is complete."), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Result:"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Artifact:"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Readback: passed"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Verified at:"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("Before running any command from the Next Source Prompt"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("Do not treat a brief progress update or commentary as satisfying this requirement"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("Zebra Source Onboarding: Obsidian is the active source."), reportPrompt)
        XCTAssertFalse(reportPrompt.contains("zebra-source-onboarding next"), reportPrompt)
        XCTAssertFalse(reportPrompt.contains("continue?"), reportPrompt)
        XCTAssertFalse(reportPrompt.contains("계속 진행할까요?"), reportPrompt)
        XCTAssertFalse(reportPrompt.contains("다음 source로 넘어갈까요?"), reportPrompt)

        let activeAfterReport = try readSourceOnboardingState(at: stateURL).progress
        XCTAssertEqual(activeAfterReport.sourceRows["notion"]?.status, "checked")
        XCTAssertEqual(activeAfterReport.activeSourceID, "obsidian")
        let notionRunStatePath = try XCTUnwrap(activeAfterReport.sourceRows["notion"]?.runStatePath)
        let notionRunState = try stateObject(in: URL(fileURLWithPath: notionRunStatePath))
        XCTAssertEqual(notionRunState["completionReportPending"] as? Bool, false)
        XCTAssertNotNil(notionRunState["completionReportedAt"] as? String)

        let nextAfterReport = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(nextAfterReport.status, 0, "stdout:\n\(nextAfterReport.stdout)\nstderr:\n\(nextAfterReport.stderr)")
        let nextAfterReportPayload = try jsonObject(from: nextAfterReport.stdout)
        XCTAssertEqual(nextAfterReportPayload["nextSourceID"] as? String, "obsidian")
        let nextAfterReportPrompt = try XCTUnwrap(nextAfterReportPayload["nextPrompt"] as? String)
        XCTAssertTrue(nextAfterReportPrompt.contains("Zebra Source Onboarding: Obsidian is the active source."), nextAfterReportPrompt)
        let activeAfterNext = try readSourceOnboardingState(at: stateURL).progress
        XCTAssertEqual(activeAfterNext.activeSourceID, "obsidian")

        let duplicateReport = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "notion"],
            environment: environment
        )
        XCTAssertEqual(duplicateReport.status, 1, "stdout:\n\(duplicateReport.stdout)\nstderr:\n\(duplicateReport.stderr)")
        XCTAssertEqual(try jsonObject(from: duplicateReport.stdout)["reason"] as? String, "source_not_active")
    }

    @MainActor
    func testSourceOnboardingReportCompletionHandoffIsLocalizedForKoreanAndJapanese() throws {
        for fixture in [
            (
                language: "ko",
                required: [
                    "# Completed Source Result",
                    "# Continuation Contract",
                    "# Next Source Prompt",
                    "다음 source command를 실행하기 전에 반드시 위 Completed Source Result를 사용자에게 먼저 보여주세요.",
                    "짧은 진행상황 업데이트나 commentary는 이 요구사항을 충족하지 않습니다.",
                    "사용자에게 계속 진행할지 묻지 마세요.",
                ]
            ),
            (
                language: "ja",
                required: [
                    "# Completed Source Result",
                    "# Continuation Contract",
                    "# Next Source Prompt",
                    "次の source command を実行する前に、必ず上の Completed Source Result を先にユーザーへ表示してください。",
                    "短い進捗更新や commentary だけでは、この要件を満たしません。",
                    "ユーザーに続行許可を求めないでください。",
                ]
            ),
        ] {
            let root = try makeTemporaryDirectory()
            let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
            let gbrainStateURL = root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
            let adapterStateURL = root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
            let launch = try XCTUnwrap(
                ZebraSourceOnboardingHelper(
                    stateURL: stateURL,
                    gbrainOnboardingStateURL: gbrainStateURL,
                    gbrainAdapterOnboardingStateURL: adapterStateURL,
                    homeDirectoryPath: root.path
                ).prepareLaunch(selectedVaultPath: nil)
            )
            let helperURL = URL(fileURLWithPath: launch.helperPath)
            let runStateDirectory = stateURL
                .deletingLastPathComponent()
                .appendingPathComponent("source-run-state", isDirectory: true)
            try FileManager.default.createDirectory(at: runStateDirectory, withIntermediateDirectories: true)
            try writeJSONObject(
                [
                    "status": "running",
                    "entryContext": ["onboardingLanguageCode": fixture.language],
                    "sourceReadiness": [:],
                    "progress": [
                        "rawSourceInput": "notion obsidian",
                        "normalizedSourceList": ["notion", "obsidian"],
                        "executionOrder": ["notion", "obsidian"],
                        "activeSourceID": "notion",
                        "uncatalogedSources": [],
                        "sourceConfirmation": [
                            "sourceIDs": ["notion", "obsidian"],
                            "status": "confirmed",
                        ],
                        "sourceRows": [
                            "notion": [
                                "id": "notion",
                                "displayName": "Notion",
                                "type": "workspace",
                                "phase": "complete",
                                "status": "running",
                                "selectionState": "confirmed",
                                "playbookID": "notion.ntn-cli",
                                "playbookVersion": "v1",
                                "playbookStepID": "complete",
                                "resultSummary": "Notion ingest readback verified for target page123.",
                            ],
                            "obsidian": [
                                "id": "obsidian",
                                "displayName": "Obsidian",
                                "type": "vault",
                                "phase": "intake",
                                "status": "unchecked",
                                "selectionState": "confirmed",
                            ],
                        ],
                    ],
                ],
                to: stateURL
            )
            try writeJSONObject(
                [
                    "completionDisposition": "checked",
                    "completionSummary": "Notion ingest readback verified for target page123.",
                    "artifactPath": root.appendingPathComponent("sources/notion-ntn-cli.md").path,
                    "readbackStatus": "passed",
                    "verifiedAt": "2026-07-07T06:49:51Z",
                ],
                to: runStateDirectory.appendingPathComponent("notion.json", isDirectory: false)
            )

            let report = try runProcess(
                executableURL: helperURL,
                arguments: ["report", "--status", "completed", "--source", "notion"],
                environment: [
                    "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                    "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
                    "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
                    "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
                    "ZEBRA_ONBOARDING_LANGUAGE": fixture.language,
                ]
            )

            XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
            let prompt = try XCTUnwrap(jsonObject(from: report.stdout)["nextPrompt"] as? String)
            for text in fixture.required {
                XCTAssertTrue(prompt.contains(text), "\(fixture.language): \(text)\n\(prompt)")
            }
            if fixture.language == "ko" {
                XCTAssertTrue(prompt.contains("Notion Source Onboarding이 완료됐습니다."), prompt)
                XCTAssertFalse(prompt.contains("Notion Source Onboarding is complete."), prompt)
                XCTAssertFalse(prompt.contains("계속 진행할까요?"), prompt)
                XCTAssertFalse(prompt.contains("다음 source로 넘어갈까요?"), prompt)
            } else {
                XCTAssertTrue(prompt.contains("Notion Source Onboarding が完了しました。"), prompt)
                XCTAssertFalse(prompt.contains("Notion Source Onboarding is complete."), prompt)
            }
            XCTAssertTrue(prompt.contains("Zebra Source Onboarding: Obsidian is the active source."), prompt)
        }
    }

    @MainActor
    func testSourceOnboardingSkipRequiresReportBeforeCompletion() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "노션", "--candidate", "notion=노션"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)

        let skip = try runProcess(
            executableURL: helperURL,
            arguments: ["notion", "choose-scope", "--scope", "skip"],
            environment: environment
        )
        XCTAssertEqual(skip.status, 0, "stdout:\n\(skip.stdout)\nstderr:\n\(skip.stderr)")
        let skipPayload = try jsonObject(from: skip.stdout)
        XCTAssertEqual(skipPayload["nextSourceID"] as? String, "notion")
        XCTAssertEqual(skipPayload["nextPlaybookStepID"] as? String, "complete")
        XCTAssertTrue(try XCTUnwrap(skipPayload["nextPrompt"] as? String).contains("report --status completed --source notion"))

        var loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.status, .running)
        XCTAssertEqual(loaded.progress.activeSourceID, "notion")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.status, "running")

        let report = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "notion"],
            environment: environment
        )
        XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        let reportPayload = try jsonObject(from: report.stdout)
        XCTAssertEqual(reportPayload["completedSourceDisposition"] as? String, "skipped")
        XCTAssertEqual(reportPayload["complete"] as? Bool, true)

        loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.status, .completed)
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.status, "skipped")
    }

    @MainActor
    func testSourceOnboardingObsidianDiscoveryUsesAppRegistryBeforeICloudListing() throws {
        let root = try makeTemporaryDirectory()
        let vault = root
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents", isDirectory: true)
            .appendingPathComponent("Han", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Registry note\nBody".write(
            to: vault.appendingPathComponent("note.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let registry = root
            .appendingPathComponent("Library/Application Support/obsidian", isDirectory: true)
            .appendingPathComponent("obsidian.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: registry.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let registryData = try JSONSerialization.data(withJSONObject: [
            "vaults": [
                "test": [
                    "path": vault.path,
                    "open": true,
                ],
            ],
        ])
        try registryData.write(to: registry, options: .atomic)
        let expectedVaultPath = pythonResolvedPath(vault)

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )

        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let payload = try jsonObject(from: next.stdout)
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "smoke_read")
        let prompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertTrue(prompt.contains(expectedVaultPath), prompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        let row = try XCTUnwrap(loaded.progress.sourceRows["obsidian"])
        XCTAssertEqual(row.status, "running")
        XCTAssertEqual(row.phase, "smoke")
        XCTAssertEqual(row.playbookStepID, "smoke_read")
        let runStatePath = try XCTUnwrap(row.runStatePath)
        let runState = try stateObject(in: URL(fileURLWithPath: runStatePath))
        XCTAssertEqual(runState["selectedVaultPath"] as? String, expectedVaultPath)
        XCTAssertEqual(runState["discoveryMethod"] as? String, "obsidian_registry")
    }

    @MainActor
    func testSourceOnboardingObsidianRegistryMultipleVaultsAskUserToChoose() throws {
        let root = try makeTemporaryDirectory()
        let firstVault = root
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents", isDirectory: true)
            .appendingPathComponent("Han", isDirectory: true)
        let secondVault = root
            .appendingPathComponent("Obsidian", isDirectory: true)
            .appendingPathComponent("Work", isDirectory: true)
        for vault in [firstVault, secondVault] {
            try FileManager.default.createDirectory(
                at: vault.appendingPathComponent(".obsidian", isDirectory: true),
                withIntermediateDirectories: true
            )
            try "# Note\nBody".write(
                to: vault.appendingPathComponent("note.md", isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
        }
        let registry = root
            .appendingPathComponent("Library/Application Support/obsidian", isDirectory: true)
            .appendingPathComponent("obsidian.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: registry.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let registryData = try JSONSerialization.data(withJSONObject: [
            "vaults": [
                "first": [
                    "path": firstVault.path,
                    "open": true,
                ],
                "second": [
                    "path": secondVault.path,
                    "open": false,
                ],
            ],
        ])
        try registryData.write(to: registry, options: .atomic)
        let expectedFirstVaultPath = pythonResolvedPath(firstVault)
        let expectedSecondVaultPath = pythonResolvedPath(secondVault)

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )

        XCTAssertEqual(next.status, 1, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        XCTAssertFalse(next.stdout.isEmpty, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let payload = try jsonObject(from: next.stdout)
        XCTAssertEqual(payload["reason"] as? String, "multiple_obsidian_vault_candidates")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "confirm_vault_if_needed")
        let prompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertTrue(prompt.contains(expectedFirstVaultPath), prompt)
        XCTAssertTrue(prompt.contains(expectedSecondVaultPath), prompt)
        XCTAssertTrue(prompt.contains("which one to use"), prompt)
        XCTAssertTrue(prompt.contains("obsidian_registry"), prompt)

        var koreanEnvironment = environment
        koreanEnvironment["ZEBRA_ONBOARDING_LANGUAGE"] = "ko"
        let koreanNext = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: koreanEnvironment
        )
        XCTAssertEqual(koreanNext.status, 0, "stdout:\n\(koreanNext.stdout)\nstderr:\n\(koreanNext.stderr)")
        let koreanPrompt = try XCTUnwrap(jsonObject(from: koreanNext.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(koreanPrompt.contains("여러 `.obsidian/` vault 후보"), koreanPrompt)
        XCTAssertTrue(koreanPrompt.contains("후보:"), koreanPrompt)
        XCTAssertTrue(koreanPrompt.contains(expectedFirstVaultPath), koreanPrompt)
        XCTAssertFalse(koreanPrompt.contains("which one to use"), koreanPrompt)
        XCTAssertFalse(koreanPrompt.contains("Zebra found multiple `.obsidian/` vault candidates"), koreanPrompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        let row = try XCTUnwrap(loaded.progress.sourceRows["obsidian"])
        XCTAssertEqual(row.status, "attention")
        XCTAssertEqual(row.attentionReason, "multiple_obsidian_vault_candidates")
        let runStatePath = try XCTUnwrap(row.runStatePath)
        let runState = try stateObject(in: URL(fileURLWithPath: runStatePath))
        XCTAssertEqual(
            Set(runState["candidateVaultPaths"] as? [String] ?? []),
            Set([expectedFirstVaultPath, expectedSecondVaultPath])
        )
        XCTAssertEqual(runState["discoveryMethod"] as? String, "obsidian_registry")
    }

    @MainActor
    func testSourceOnboardingObsidianInvalidVaultPathWritesAttentionAndRepairPrompt() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "verify-vault", "--path", root.appendingPathComponent("missing-vault").path],
            environment: environment
        )

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let payload = try jsonObject(from: result.stdout)
        XCTAssertEqual(payload["nextSourceID"] as? String, "obsidian")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "confirm_vault_if_needed")
        XCTAssertEqual(payload["reason"] as? String, "invalid_vault_path")
        let promptPath = try XCTUnwrap(payload["nextPromptPath"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: promptPath))

        let loaded = try readSourceOnboardingState(at: stateURL)
        let row = try XCTUnwrap(loaded.progress.sourceRows["obsidian"])
        XCTAssertEqual(row.status, "attention")
        XCTAssertEqual(row.phase, "preflight")
        XCTAssertEqual(row.playbookStepID, "confirm_vault_if_needed")
        XCTAssertEqual(row.attentionReason, "invalid_vault_path")
        XCTAssertNotNil(row.runStatePath)

        let resumed = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumed.status, 0, "stdout:\n\(resumed.stdout)\nstderr:\n\(resumed.stderr)")
        XCTAssertEqual(try jsonObject(from: resumed.stdout)["nextPlaybookStepID"] as? String, "confirm_vault_if_needed")

        var koreanEnvironment = environment
        koreanEnvironment["ZEBRA_ONBOARDING_LANGUAGE"] = "ko"
        let koreanResumed = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: koreanEnvironment
        )
        XCTAssertEqual(koreanResumed.status, 0, "stdout:\n\(koreanResumed.stdout)\nstderr:\n\(koreanResumed.stderr)")
        let koreanPrompt = try XCTUnwrap(jsonObject(from: koreanResumed.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(koreanPrompt.contains("Obsidian vault 후보"), koreanPrompt)
        XCTAssertFalse(koreanPrompt.contains("Ask the user to confirm whether this is the Obsidian vault to use"), koreanPrompt)
    }

    @MainActor
    func testSourceOnboardingObsidianDoesNotTreatSelectedGBrainPathAsSourceVault() throws {
        let root = try makeTemporaryDirectory()
        let brainRepo = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(
            at: brainRepo.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Brain file\nNot an Obsidian vault".write(
            to: brainRepo.appendingPathComponent("README.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: brainRepo.path)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_GBRAIN_WRITE_TARGET_PATH": brainRepo.path,
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let next = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )

        XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
        let payload = try jsonObject(from: next.stdout)
        XCTAssertEqual(payload["nextSourceID"] as? String, "obsidian")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "discover_vault")
        let prompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertFalse(prompt.contains(brainRepo.path), prompt)
        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.status, "running")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.phase, "preflight")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.playbookStepID, "discover_vault")
        XCTAssertNil(loaded.progress.sourceRows["obsidian"]?.runStatePath)

        let rejected = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "verify-vault", "--path", brainRepo.path],
            environment: environment
        )
        XCTAssertEqual(rejected.status, 1, "stdout:\n\(rejected.stdout)\nstderr:\n\(rejected.stderr)")
        let rejectedPayload = try jsonObject(from: rejected.stdout)
        XCTAssertEqual(rejectedPayload["ok"] as? Bool, false)
        XCTAssertEqual(rejectedPayload["reason"] as? String, "gbrain_target_is_not_obsidian_source_vault")
        XCTAssertEqual(rejectedPayload["nextPlaybookStepID"] as? String, "confirm_vault_if_needed")
    }

    @MainActor
    func testSourceOnboardingObsidianDiscoveryUsesOnlyExactKnownFallbackPaths() throws {
        do {
            let root = try makeTemporaryDirectory()
            let vault = root
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Obsidian", isDirectory: true)
            try FileManager.default.createDirectory(
                at: vault.appendingPathComponent(".obsidian", isDirectory: true),
                withIntermediateDirectories: true
            )
            try "# Exact fallback note\nBody".write(
                to: vault.appendingPathComponent("note.md", isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
            let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
            let gbrainStateURL = root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
            let adapterStateURL = root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
            let launch = try XCTUnwrap(
                ZebraSourceOnboardingHelper(
                    stateURL: stateURL,
                    gbrainOnboardingStateURL: gbrainStateURL,
                    gbrainAdapterOnboardingStateURL: adapterStateURL,
                    homeDirectoryPath: root.path
                ).prepareLaunch(selectedVaultPath: nil)
            )
            let helperURL = URL(fileURLWithPath: launch.helperPath)
            let environment = [
                "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
                "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
                "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            ]
            XCTAssertEqual(try runProcess(
                executableURL: helperURL,
                arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
                environment: environment
            ).status, 0)
            XCTAssertEqual(try runProcess(
                executableURL: helperURL,
                arguments: ["confirm", "--answer", "yes"],
                environment: environment
            ).status, 0)

            let next = try runProcess(
                executableURL: helperURL,
                arguments: ["next"],
                environment: environment
            )

            XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
            let payload = try jsonObject(from: next.stdout)
            XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "smoke_read")
            let prompt = try XCTUnwrap(payload["nextPrompt"] as? String)
            XCTAssertTrue(prompt.contains(vault.path), prompt)
        }

        do {
            let root = try makeTemporaryDirectory()
            let nestedVault = root
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Obsidian", isDirectory: true)
                .appendingPathComponent("NestedVault", isDirectory: true)
            try FileManager.default.createDirectory(
                at: nestedVault.appendingPathComponent(".obsidian", isDirectory: true),
                withIntermediateDirectories: true
            )
            try "# Nested fallback note\nBody".write(
                to: nestedVault.appendingPathComponent("note.md", isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
            let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
            let gbrainStateURL = root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
            let adapterStateURL = root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
            let launch = try XCTUnwrap(
                ZebraSourceOnboardingHelper(
                    stateURL: stateURL,
                    gbrainOnboardingStateURL: gbrainStateURL,
                    gbrainAdapterOnboardingStateURL: adapterStateURL,
                    homeDirectoryPath: root.path
                ).prepareLaunch(selectedVaultPath: nil)
            )
            let helperURL = URL(fileURLWithPath: launch.helperPath)
            let environment = [
                "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
                "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
                "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            ]
            XCTAssertEqual(try runProcess(
                executableURL: helperURL,
                arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
                environment: environment
            ).status, 0)
            XCTAssertEqual(try runProcess(
                executableURL: helperURL,
                arguments: ["confirm", "--answer", "yes"],
                environment: environment
            ).status, 0)

            let next = try runProcess(
                executableURL: helperURL,
                arguments: ["next"],
                environment: environment
            )

            XCTAssertEqual(next.status, 0, "stdout:\n\(next.stdout)\nstderr:\n\(next.stderr)")
            let payload = try jsonObject(from: next.stdout)
            XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "discover_vault")
            let prompt = try XCTUnwrap(payload["nextPrompt"] as? String)
            XCTAssertFalse(prompt.contains(nestedVault.path), prompt)
        }
    }

    @MainActor
    func testSourceOnboardingObsidianScopeConfirmationIngestReadbackAndResume() throws {
        let root = try makeTemporaryDirectory()
        let vault = root
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents", isDirectory: true)
            .appendingPathComponent("ObsidianVault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# First note\nBody".write(
            to: vault.appendingPathComponent("first.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "# Second note\nBody".write(
            to: vault.appendingPathComponent("second.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let started = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(started.status, 0, "stdout:\n\(started.stdout)\nstderr:\n\(started.stderr)")
        let startedPayload = try jsonObject(from: started.stdout)
        XCTAssertEqual(startedPayload["nextPlaybookStepID"] as? String, "smoke_read")
        let startedPrompt = try XCTUnwrap(startedPayload["nextPrompt"] as? String)
        XCTAssertTrue(startedPrompt.contains(vault.path), startedPrompt)

        let resumedSmoke = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumedSmoke.status, 0, "stdout:\n\(resumedSmoke.stdout)\nstderr:\n\(resumedSmoke.stderr)")
        XCTAssertEqual(try jsonObject(from: resumedSmoke.stdout)["nextPlaybookStepID"] as? String, "smoke_read")

        let smoke = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "smoke-read"],
            environment: environment
        )
        XCTAssertEqual(smoke.status, 0, "stdout:\n\(smoke.stdout)\nstderr:\n\(smoke.stderr)")
        XCTAssertEqual(try jsonObject(from: smoke.stdout)["nextPlaybookStepID"] as? String, "choose_ingest_scope")

        let resumed = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumed.status, 0, "stdout:\n\(resumed.stdout)\nstderr:\n\(resumed.stderr)")
        XCTAssertEqual(try jsonObject(from: resumed.stdout)["nextPlaybookStepID"] as? String, "choose_ingest_scope")

        let scope = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "choose-scope", "--scope", "sample"],
            environment: environment
        )
        XCTAssertEqual(scope.status, 0, "stdout:\n\(scope.stdout)\nstderr:\n\(scope.stderr)")
        let scopePayload = try jsonObject(from: scope.stdout)
        XCTAssertEqual(scopePayload["nextPlaybookStepID"] as? String, "confirm_ingest_plan")
        let confirmPrompt = try XCTUnwrap(scopePayload["nextPrompt"] as? String)
        XCTAssertTrue(confirmPrompt.contains("Resolved Obsidian ingest plan:"), confirmPrompt)
        XCTAssertTrue(confirmPrompt.contains("Selected scope: `recent/sample subset: up to 5 Markdown files`"), confirmPrompt)
        XCTAssertTrue(confirmPrompt.contains("Excluded paths/policies: `.obsidian/`, hidden directories, `__MACOSX`, non-Markdown files, and paths outside the selected vault."), confirmPrompt)
        XCTAssertTrue(confirmPrompt.contains("Ingest mode: direct Markdown filesystem ingest into a Zebra source artifact."), confirmPrompt)
        XCTAssertTrue(confirmPrompt.contains("Verification plan: read back the generated Obsidian source artifact"), confirmPrompt)

        var koreanEnvironment = environment
        koreanEnvironment["ZEBRA_ONBOARDING_LANGUAGE"] = "ko"
        let koreanPlan = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: koreanEnvironment
        )
        XCTAssertEqual(koreanPlan.status, 0, "stdout:\n\(koreanPlan.stdout)\nstderr:\n\(koreanPlan.stderr)")
        let koreanPlanPrompt = try XCTUnwrap(jsonObject(from: koreanPlan.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(koreanPlanPrompt.contains("선택된 Obsidian ingest plan입니다."), koreanPlanPrompt)
        XCTAssertTrue(koreanPlanPrompt.contains("선택한 범위: `최근/샘플 일부: 최대 5개 Markdown 파일`"), koreanPlanPrompt)
        XCTAssertTrue(koreanPlanPrompt.contains("제외 경로/정책"), koreanPlanPrompt)
        XCTAssertTrue(koreanPlanPrompt.contains("검증 계획"), koreanPlanPrompt)
        XCTAssertFalse(koreanPlanPrompt.contains("Resolved Obsidian ingest plan:"), koreanPlanPrompt)
        XCTAssertFalse(koreanPlanPrompt.contains("Selected scope: `recent/sample subset: up to 5 Markdown files`"), koreanPlanPrompt)

        let resumedPlan = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumedPlan.status, 0, "stdout:\n\(resumedPlan.stdout)\nstderr:\n\(resumedPlan.stderr)")
        XCTAssertEqual(try jsonObject(from: resumedPlan.stdout)["nextPlaybookStepID"] as? String, "confirm_ingest_plan")

        let blockedIngest = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "ingest"],
            environment: environment
        )
        XCTAssertEqual(blockedIngest.status, 1, "stdout:\n\(blockedIngest.stdout)\nstderr:\n\(blockedIngest.stderr)")
        XCTAssertEqual(try jsonObject(from: blockedIngest.stdout)["nextPlaybookStepID"] as? String, "confirm_ingest_plan")

        let confirm = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "confirm-plan", "--answer", "yes"],
            environment: environment
        )
        XCTAssertEqual(confirm.status, 0, "stdout:\n\(confirm.stdout)\nstderr:\n\(confirm.stderr)")
        XCTAssertEqual(try jsonObject(from: confirm.stdout)["nextPlaybookStepID"] as? String, "ingest_markdown")

        let resumedIngest = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumedIngest.status, 0, "stdout:\n\(resumedIngest.stdout)\nstderr:\n\(resumedIngest.stderr)")
        XCTAssertEqual(try jsonObject(from: resumedIngest.stdout)["nextPlaybookStepID"] as? String, "ingest_markdown")

        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let ingestPayload = try jsonObject(from: ingest.stdout)
        XCTAssertEqual(ingestPayload["nextPlaybookStepID"] as? String, "verify_readback")
        let artifactPath = try XCTUnwrap(ingestPayload["artifactPath"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactPath))

        let resumedVerify = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumedVerify.status, 0, "stdout:\n\(resumedVerify.stdout)\nstderr:\n\(resumedVerify.stderr)")
        XCTAssertEqual(try jsonObject(from: resumedVerify.stdout)["nextPlaybookStepID"] as? String, "verify_readback")

        let verify = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "verify-readback"],
            environment: environment
        )
        XCTAssertEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")
        let verifyPayload = try jsonObject(from: verify.stdout)
        XCTAssertEqual(verifyPayload["nextPlaybookStepID"] as? String, "complete")
        let pendingPrompt = try XCTUnwrap(verifyPayload["nextPrompt"] as? String)
        XCTAssertTrue(pendingPrompt.contains("completion report is required"), pendingPrompt)
        XCTAssertTrue(pendingPrompt.contains("# User-Facing Output"), pendingPrompt)
        XCTAssertTrue(pendingPrompt.contains("Do not send a user-facing Obsidian completion message yet"), pendingPrompt)
        XCTAssertTrue(pendingPrompt.contains("Your next action is not a user-facing message"), pendingPrompt)
        XCTAssertTrue(pendingPrompt.contains("zebra-source-onboarding report --status completed --source obsidian"), pendingPrompt)

        let pendingResume = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(pendingResume.status, 1, "stdout:\n\(pendingResume.stdout)\nstderr:\n\(pendingResume.stderr)")
        XCTAssertEqual(try jsonObject(from: pendingResume.stdout)["reason"] as? String, "source_completion_report_required")
        XCTAssertEqual(try jsonObject(from: pendingResume.stdout)["pendingSourceID"] as? String, "obsidian")
        XCTAssertEqual(try jsonObject(from: pendingResume.stdout)["blockedSourceID"] as? String, "next")
        XCTAssertEqual(try jsonObject(from: pendingResume.stdout)["nextPlaybookStepID"] as? String, "complete")

        var loaded = try readSourceOnboardingState(at: stateURL)
        var row = try XCTUnwrap(loaded.progress.sourceRows["obsidian"])
        XCTAssertEqual(row.status, "running")
        XCTAssertEqual(row.phase, "complete")
        XCTAssertEqual(row.playbookStepID, "complete")

        let report = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "obsidian"],
            environment: environment
        )
        XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        let reportPayload = try jsonObject(from: report.stdout)
        XCTAssertEqual(reportPayload["completedSourceID"] as? String, "obsidian")
        XCTAssertEqual(reportPayload["complete"] as? Bool, true)
        let reportPrompt = try XCTUnwrap(reportPayload["nextPrompt"] as? String)
        XCTAssertTrue(reportPrompt.contains("Obsidian Source Onboarding is complete."), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("You must first show the user the exact completion result below."), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Markdown files ingested: 2"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("- Artifact: `"), reportPrompt)
        XCTAssertTrue(reportPrompt.contains("Source Onboarding is complete"), reportPrompt)

        loaded = try readSourceOnboardingState(at: stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["obsidian"])
        XCTAssertEqual(row.status, "checked")
        XCTAssertEqual(row.phase, "complete")
        XCTAssertEqual(row.playbookStepID, "complete")
        XCTAssertEqual(row.playbookID, "obsidian.direct-markdown")
        XCTAssertNotNil(row.resultSummary)
        XCTAssertNotNil(row.runStatePath)
        XCTAssertNil(loaded.progress.activeSourceID)
        let runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["completionReportPending"] as? Bool, false)
        XCTAssertNotNil(runState["completionReportedAt"] as? String)
        XCTAssertFalse(try String(contentsOf: stateURL, encoding: .utf8).contains("First note\\nBody"))
    }

    @MainActor
    func testSourceOnboardingObsidianKoreanScopePromptAndSingleFileIngest() throws {
        let root = try makeTemporaryDirectory()
        let vault = root
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents", isDirectory: true)
            .appendingPathComponent("ObsidianVault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".obsidian", isDirectory: true),
            withIntermediateDirectories: true
        )
        let notes = vault.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try "# Alpha\nOnly this note".write(
            to: notes.appendingPathComponent("A.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "# Beta\nDo not ingest".write(
            to: notes.appendingPathComponent("B.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try "not markdown".write(
            to: notes.appendingPathComponent("raw.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "ko",
        ]

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "옵시디언", "--candidate", "obsidian=옵시디언"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)

        let smoke = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "smoke-read"],
            environment: environment
        )
        XCTAssertEqual(smoke.status, 0, "stdout:\n\(smoke.stdout)\nstderr:\n\(smoke.stderr)")
        let smokePrompt = try XCTUnwrap(jsonObject(from: smoke.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(smokePrompt.contains("사용자에게 아래 다섯 가지 선택지만 보여주세요"), smokePrompt)
        XCTAssertTrue(smokePrompt.contains("3. 특정 note 파일"), smokePrompt)
        XCTAssertTrue(smokePrompt.contains("--scope file --file"), smokePrompt)
        XCTAssertFalse(smokePrompt.contains("whole vault"), smokePrompt)
        XCTAssertFalse(smokePrompt.contains("selected folders"), smokePrompt)
        XCTAssertFalse(smokePrompt.contains("recent/sample subset"), smokePrompt)
        XCTAssertFalse(smokePrompt.contains("skip Obsidian for now"), smokePrompt)

        let rejectedOutsidePath = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "choose-scope", "--scope", "file", "--file", "../outside.md"],
            environment: environment
        )
        XCTAssertEqual(rejectedOutsidePath.status, 2, "stdout:\n\(rejectedOutsidePath.stdout)\nstderr:\n\(rejectedOutsidePath.stderr)")
        XCTAssertTrue(rejectedOutsidePath.stderr.contains("file_path_outside_vault"), rejectedOutsidePath.stderr)

        let rejectedDirectory = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "choose-scope", "--scope", "file", "--file", "Notes"],
            environment: environment
        )
        XCTAssertEqual(rejectedDirectory.status, 2, "stdout:\n\(rejectedDirectory.stdout)\nstderr:\n\(rejectedDirectory.stderr)")
        XCTAssertTrue(rejectedDirectory.stderr.contains("file_path_not_file"), rejectedDirectory.stderr)

        let rejectedNonMarkdown = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "choose-scope", "--scope", "file", "--file", "Notes/raw.txt"],
            environment: environment
        )
        XCTAssertEqual(rejectedNonMarkdown.status, 2, "stdout:\n\(rejectedNonMarkdown.stdout)\nstderr:\n\(rejectedNonMarkdown.stderr)")
        XCTAssertTrue(rejectedNonMarkdown.stderr.contains("file_path_not_markdown"), rejectedNonMarkdown.stderr)

        let scope = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "choose-scope", "--scope", "file", "--file", "Notes/A"],
            environment: environment
        )
        XCTAssertEqual(scope.status, 0, "stdout:\n\(scope.stdout)\nstderr:\n\(scope.stderr)")
        let scopePayload = try jsonObject(from: scope.stdout)
        XCTAssertEqual(scopePayload["nextPlaybookStepID"] as? String, "confirm_ingest_plan")
        XCTAssertEqual(scopePayload["scope"] as? String, "file")
        XCTAssertEqual(scopePayload["estimatedFileCount"] as? Int, 1)
        let planPrompt = try XCTUnwrap(scopePayload["nextPrompt"] as? String)
        XCTAssertTrue(planPrompt.contains("선택한 범위: `특정 note 파일: Notes/A.md`"), planPrompt)
        XCTAssertTrue(planPrompt.contains("예상 Markdown 파일 수: `1`"), planPrompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        let runStatePath = try XCTUnwrap(loaded.progress.sourceRows["obsidian"]?.runStatePath)
        let runState = try jsonObject(from: String(contentsOfFile: runStatePath, encoding: .utf8))
        XCTAssertEqual(runState["scope"] as? String, "file")
        XCTAssertEqual(runState["files"] as? [String], ["Notes/A.md"])

        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "confirm-plan", "--answer", "yes"],
            environment: environment
        ).status, 0)
        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["obsidian", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let artifactPath = try XCTUnwrap(jsonObject(from: ingest.stdout)["artifactPath"] as? String)
        let artifact = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifact.contains("scope: file"), artifact)
        XCTAssertTrue(artifact.contains("- Notes/A.md"), artifact)
        XCTAssertTrue(artifact.contains("### Notes/A.md"), artifact)
        XCTAssertTrue(artifact.contains("Only this note"), artifact)
        XCTAssertFalse(artifact.contains("Notes/B.md"), artifact)
        XCTAssertFalse(artifact.contains("Do not ingest"), artifact)
    }

    @MainActor
    func testSourceOnboardingIMessageScopeConfirmationIngestReadbackAndResume() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        try installFakeIMsg(in: fakeBin)

        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "PATH": fakeBin.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "아이메시지", "--candidate", "imessage=아이메시지"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)

        let started = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(started.status, 0, "stdout:\n\(started.stdout)\nstderr:\n\(started.stderr)")
        let startedPayload = try jsonObject(from: started.stdout)
        XCTAssertEqual(startedPayload["nextSourceID"] as? String, "imessage")
        XCTAssertEqual(startedPayload["nextPlaybookID"] as? String, "imessage.imsg-cli")
        XCTAssertEqual(startedPayload["nextPlaybookVersion"] as? String, "v1")
        XCTAssertEqual(startedPayload["nextPlaybookStepID"] as? String, "check_imsg_cli")
        let nextPrompt = try XCTUnwrap(startedPayload["nextPrompt"] as? String)
        let nextPromptPath = try XCTUnwrap(startedPayload["nextPromptPath"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nextPromptPath))
        XCTAssertTrue(nextPrompt.contains("Playbook: imessage.imsg-cli v1"), nextPrompt)

        let checkCLI = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "check-cli"],
            environment: environment
        )
        XCTAssertEqual(checkCLI.status, 0, "stdout:\n\(checkCLI.stdout)\nstderr:\n\(checkCLI.stderr)")
        XCTAssertEqual(try jsonObject(from: checkCLI.stdout)["nextPlaybookStepID"] as? String, "check_full_disk_access")

        let checkAccess = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "check-access"],
            environment: environment
        )
        XCTAssertEqual(checkAccess.status, 0, "stdout:\n\(checkAccess.stdout)\nstderr:\n\(checkAccess.stderr)")
        XCTAssertEqual(try jsonObject(from: checkAccess.stdout)["nextPlaybookStepID"] as? String, "smoke_history")

        let smoke = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "smoke-history"],
            environment: environment
        )
        XCTAssertEqual(smoke.status, 0, "stdout:\n\(smoke.stdout)\nstderr:\n\(smoke.stderr)")
        let smokePayload = try jsonObject(from: smoke.stdout)
        XCTAssertEqual(smokePayload["nextPlaybookStepID"] as? String, "choose_ingest_scope")
        let scopePrompt = try XCTUnwrap(smokePayload["nextPrompt"] as? String)
        XCTAssertTrue(scopePrompt.contains("1. 최근 날짜 이후 업데이트된 대화방"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("2. 특정 대화방"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("3. 대화방 전체"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("4. 지금은 iMessage 건너뛰기"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("Alpha (+82 10-4330-0841)"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("SMS - Direct - 2026-07-02 12:00 - chat_id chat-alpha"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("4. No Handle"), scopePrompt)
        XCTAssertTrue(scopePrompt.contains("iMessage - Direct - 2026-06-30 12:00 - chat_id chat-name-only"), scopePrompt)
        XCTAssertFalse(scopePrompt.contains("No Handle (chat-name-only)"), scopePrompt)
        XCTAssertFalse(scopePrompt.contains("chat_id=chat-alpha"), scopePrompt)
        XCTAssertFalse(scopePrompt.contains("최근 N개 메시지"), scopePrompt)

        var koreanScopeEnvironment = environment
        koreanScopeEnvironment["ZEBRA_ONBOARDING_LANGUAGE"] = "ko"
        let koreanScope = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: koreanScopeEnvironment
        )
        XCTAssertEqual(koreanScope.status, 0, "stdout:\n\(koreanScope.stdout)\nstderr:\n\(koreanScope.stderr)")
        let koreanScopePrompt = try XCTUnwrap(jsonObject(from: koreanScope.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(koreanScopePrompt.contains("옵션 2에서 사용할 최근 iMessage 대화방 후보:"), koreanScopePrompt)
        XCTAssertTrue(koreanScopePrompt.contains("SMS · 개인 대화 · 2026-07-02 12:00 · chat_id chat-alpha"), koreanScopePrompt)
        XCTAssertTrue(koreanScopePrompt.contains("4. No Handle"), koreanScopePrompt)
        XCTAssertTrue(koreanScopePrompt.contains("iMessage · 개인 대화 · 2026-06-30 12:00 · chat_id chat-name-only"), koreanScopePrompt)
        XCTAssertFalse(koreanScopePrompt.contains("No Handle (chat-name-only)"), koreanScopePrompt)
        XCTAssertFalse(koreanScopePrompt.contains("Recent conversation candidates for option 2:"), koreanScopePrompt)
        XCTAssertFalse(koreanScopePrompt.contains("Use the candidate list below"), koreanScopePrompt)
        XCTAssertFalse(koreanScopePrompt.contains("SMS - Direct - 2026-07-02 12:00 - chat_id chat-alpha"), koreanScopePrompt)

        let resumedScope = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumedScope.status, 0, "stdout:\n\(resumedScope.stdout)\nstderr:\n\(resumedScope.stderr)")
        XCTAssertEqual(try jsonObject(from: resumedScope.stdout)["nextPlaybookStepID"] as? String, "choose_ingest_scope")

        let blockedBeforeScope = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "ingest"],
            environment: environment
        )
        XCTAssertEqual(blockedBeforeScope.status, 1, "stdout:\n\(blockedBeforeScope.stdout)\nstderr:\n\(blockedBeforeScope.stderr)")
        XCTAssertEqual(try jsonObject(from: blockedBeforeScope.stdout)["reason"] as? String, "ingest_scope_required")

        let invalidScope = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "updated-since"],
            environment: environment
        )
        XCTAssertEqual(invalidScope.status, 2)

        let scope = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "updated-since", "--since", "2026-07-01"],
            environment: environment
        )
        XCTAssertEqual(scope.status, 0, "stdout:\n\(scope.stdout)\nstderr:\n\(scope.stderr)")
        let scopePayload = try jsonObject(from: scope.stdout)
        XCTAssertEqual(scopePayload["nextPlaybookStepID"] as? String, "confirm_ingest_plan")
        let confirmPrompt = try XCTUnwrap(scopePayload["nextPrompt"] as? String)
        XCTAssertTrue(confirmPrompt.contains("Resolved iMessage ingest plan:"), confirmPrompt)
        XCTAssertTrue(confirmPrompt.contains("recently updated conversations since 2026-07-01"), confirmPrompt)
        XCTAssertTrue(confirmPrompt.contains("up to `200` messages per conversation and up to `50` conversations"), confirmPrompt)
        XCTAssertTrue(confirmPrompt.contains("Sensitive data notice"), confirmPrompt)

        var koreanEnvironment = environment
        koreanEnvironment["ZEBRA_ONBOARDING_LANGUAGE"] = "ko"
        let koreanPlan = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: koreanEnvironment
        )
        XCTAssertEqual(koreanPlan.status, 0, "stdout:\n\(koreanPlan.stdout)\nstderr:\n\(koreanPlan.stderr)")
        let koreanPlanPrompt = try XCTUnwrap(jsonObject(from: koreanPlan.stdout)["nextPrompt"] as? String)
        XCTAssertTrue(koreanPlanPrompt.contains("선택된 iMessage ingest plan입니다."), koreanPlanPrompt)
        XCTAssertTrue(koreanPlanPrompt.contains("선택한 범위: `2026-07-01 이후 업데이트된 대화방`"), koreanPlanPrompt)
        XCTAssertTrue(koreanPlanPrompt.contains("민감정보 안내"), koreanPlanPrompt)

        let blockedBeforePlan = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "ingest"],
            environment: environment
        )
        XCTAssertEqual(blockedBeforePlan.status, 1, "stdout:\n\(blockedBeforePlan.stdout)\nstderr:\n\(blockedBeforePlan.stderr)")
        XCTAssertEqual(try jsonObject(from: blockedBeforePlan.stdout)["reason"] as? String, "ingest_plan_unconfirmed")

        let confirm = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "confirm-plan", "--answer", "yes"],
            environment: environment
        )
        XCTAssertEqual(confirm.status, 0, "stdout:\n\(confirm.stdout)\nstderr:\n\(confirm.stderr)")
        XCTAssertEqual(try jsonObject(from: confirm.stdout)["nextPlaybookStepID"] as? String, "ingest_messages")

        let resumedIngest = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumedIngest.status, 0, "stdout:\n\(resumedIngest.stdout)\nstderr:\n\(resumedIngest.stderr)")
        XCTAssertEqual(try jsonObject(from: resumedIngest.stdout)["nextPlaybookStepID"] as? String, "ingest_messages")

        let ingest = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "ingest"],
            environment: environment
        )
        XCTAssertEqual(ingest.status, 0, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let ingestPayload = try jsonObject(from: ingest.stdout)
        XCTAssertEqual(ingestPayload["nextPlaybookStepID"] as? String, "verify_readback")
        XCTAssertEqual(ingestPayload["ingestedThreadCount"] as? Int, 1)
        let artifactPath = try XCTUnwrap(ingestPayload["artifactPath"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactPath))
        let artifactBody = try String(contentsOfFile: artifactPath, encoding: .utf8)
        XCTAssertTrue(artifactBody.contains("fixture raw message body"))
        XCTAssertTrue(artifactBody.contains("chat-alpha"))
        XCTAssertFalse(artifactBody.contains("chat-old"))

        let verify = try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "verify-readback"],
            environment: environment
        )
        XCTAssertEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")
        let verifyPayload = try jsonObject(from: verify.stdout)
        XCTAssertEqual(verifyPayload["nextPlaybookStepID"] as? String, "complete")
        let pendingPrompt = try XCTUnwrap(verifyPayload["nextPrompt"] as? String)
        XCTAssertTrue(pendingPrompt.contains("completion report is required"), pendingPrompt)
        XCTAssertTrue(pendingPrompt.contains("zebra-source-onboarding report --status completed --source imessage"), pendingPrompt)

        var loaded = try readSourceOnboardingState(at: stateURL)
        var row = try XCTUnwrap(loaded.progress.sourceRows["imessage"])
        XCTAssertEqual(row.status, "running")
        XCTAssertEqual(row.phase, "complete")

        let report = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "imessage"],
            environment: environment
        )
        XCTAssertEqual(report.status, 0, "stdout:\n\(report.stdout)\nstderr:\n\(report.stderr)")
        let reportPayload = try jsonObject(from: report.stdout)
        XCTAssertEqual(reportPayload["completedSourceID"] as? String, "imessage")
        XCTAssertEqual(reportPayload["complete"] as? Bool, true)

        loaded = try readSourceOnboardingState(at: stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["imessage"])
        XCTAssertEqual(row.status, "checked")
        XCTAssertEqual(row.phase, "complete")
        XCTAssertEqual(row.playbookID, "imessage.imsg-cli")
        XCTAssertEqual(row.playbookStepID, "complete")
        let runStatePath = try XCTUnwrap(row.runStatePath)
        let runState = try stateObject(in: URL(fileURLWithPath: runStatePath))
        XCTAssertEqual(runState["scope"] as? String, "updated-since")
        XCTAssertEqual(runState["since"] as? String, "2026-07-01")
        XCTAssertEqual(runState["resolvedThreadListLimit"] as? Int, 50)
        XCTAssertEqual(runState["sensitiveNoticeConfirmed"] as? Bool, true)
        XCTAssertEqual(runState["ingestedThreadCount"] as? Int, 1)
        XCTAssertEqual(runState["readbackStatus"] as? String, "passed")
        let stateBody = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertFalse(stateBody.contains("fixture raw message body"))
        XCTAssertFalse(try String(contentsOfFile: runStatePath, encoding: .utf8).contains("fixture raw message body"))
    }

    @MainActor
    func testSourceOnboardingIMessageMissingCLIWritesAttention() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fakeBin.appendingPathComponent("python3", isDirectory: false),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3")
        )
        let prepared = try prepareIMessageSourceOnboarding(
            root: root,
            pathPrefix: fakeBin,
            includeAmbientPath: false
        )

        XCTAssertEqual(try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["next"],
            environment: prepared.environment
        ).status, 0)

        let checkCLI = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "check-cli"],
            environment: prepared.environment
        )

        XCTAssertEqual(checkCLI.status, 1, "stdout:\n\(checkCLI.stdout)\nstderr:\n\(checkCLI.stderr)")
        let payload = try jsonObject(from: checkCLI.stdout)
        XCTAssertEqual(payload["reason"] as? String, "imsg_cli_missing")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "check_imsg_cli")
        let loaded = try readSourceOnboardingState(at: prepared.stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["imessage"]?.status, "attention")
        XCTAssertEqual(loaded.progress.sourceRows["imessage"]?.attentionReason, "imsg_cli_missing")
    }

    @MainActor
    func testSourceOnboardingIMessageScopeVariantsAndSkip() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        try installFakeIMsg(in: fakeBin)
        let prepared = try prepareIMessageSourceOnboarding(root: root, pathPrefix: fakeBin)
        try runIMessageToScopeSelection(helperURL: prepared.helperURL, environment: prepared.environment)

        let missingChat = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "selected-threads"],
            environment: prepared.environment
        )
        XCTAssertEqual(missingChat.status, 2)

        let selected = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "selected-threads", "--chat-id", "chat-alpha"],
            environment: prepared.environment
        )
        XCTAssertEqual(selected.status, 0, "stdout:\n\(selected.stdout)\nstderr:\n\(selected.stderr)")
        var loaded = try readSourceOnboardingState(at: prepared.stateURL)
        var row = try XCTUnwrap(loaded.progress.sourceRows["imessage"])
        var runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["scope"] as? String, "selected-threads")
        XCTAssertEqual(runState["selectedThreadIDs"] as? [String], ["chat-alpha"])

        let allThreads = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "all-threads"],
            environment: prepared.environment
        )
        XCTAssertEqual(allThreads.status, 0, "stdout:\n\(allThreads.stdout)\nstderr:\n\(allThreads.stderr)")
        loaded = try readSourceOnboardingState(at: prepared.stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["imessage"])
        runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["scope"] as? String, "all-threads")
        XCTAssertEqual((runState["internalWindow"] as? [String: Any])?["threadListLimit"] as? Int, 50)

        let narrowed = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "updated-since", "--since", "2026-07-01"],
            environment: prepared.environment
        )
        XCTAssertEqual(narrowed.status, 0, "stdout:\n\(narrowed.stdout)\nstderr:\n\(narrowed.stderr)")
        loaded = try readSourceOnboardingState(at: prepared.stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["imessage"])
        runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["scope"] as? String, "updated-since")
        XCTAssertEqual(runState["since"] as? String, "2026-07-01")
        XCTAssertEqual(runState["resolvedThreadIDs"] as? [String], ["chat-alpha"])
        XCTAssertEqual(runState["estimatedThreadCount"] as? Int, 1)
        XCTAssertEqual(runState["resolvedThreadListLimit"] as? Int, 50)

        let skip = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "skip"],
            environment: prepared.environment
        )
        XCTAssertEqual(skip.status, 0, "stdout:\n\(skip.stdout)\nstderr:\n\(skip.stderr)")
        loaded = try readSourceOnboardingState(at: prepared.stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["imessage"])
        XCTAssertEqual(row.status, "running")
        XCTAssertEqual(row.playbookStepID, "complete")
        let skipPayload = try jsonObject(from: skip.stdout)
        let skipPrompt = try XCTUnwrap(skipPayload["nextPrompt"] as? String)
        XCTAssertTrue(skipPrompt.contains("zebra-source-onboarding report --status completed --source imessage"), skipPrompt)
    }

    @MainActor
    func testSourceOnboardingIMessageKoreanPlanFallsBackToStateLanguageForSelectedThread() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        try installFakeIMsg(in: fakeBin)
        let prepared = try prepareIMessageSourceOnboarding(
            root: root,
            pathPrefix: fakeBin,
            extraEnvironment: ["ZEBRA_ONBOARDING_LANGUAGE": "ko"]
        )
        try runIMessageToScopeSelection(helperURL: prepared.helperURL, environment: prepared.environment)

        var gatewayLikeEnvironment = prepared.environment
        gatewayLikeEnvironment.removeValue(forKey: "ZEBRA_ONBOARDING_LANGUAGE")
        let selected = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "selected-threads", "--chat-id", "1318"],
            environment: gatewayLikeEnvironment
        )

        XCTAssertEqual(selected.status, 0, "stdout:\n\(selected.stdout)\nstderr:\n\(selected.stderr)")
        let payload = try jsonObject(from: selected.stdout)
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "confirm_ingest_plan")
        let prompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertTrue(prompt.contains("선택된 iMessage ingest plan입니다."), prompt)
        XCTAssertTrue(prompt.contains("선택한 범위: `선택한 대화방:"), prompt)
        XCTAssertTrue(prompt.contains("+82 10-4330-0841"), prompt)
        XCTAssertTrue(prompt.contains("민감정보 안내"), prompt)
        XCTAssertFalse(prompt.contains("Resolved iMessage ingest plan:"), prompt)
        XCTAssertFalse(prompt.contains("Selected scope:"), prompt)
        XCTAssertFalse(prompt.contains("Sensitive data notice"), prompt)
        XCTAssertFalse(prompt.contains("selected conversations: 1318"), prompt)

        let loaded = try readSourceOnboardingState(at: prepared.stateURL)
        XCTAssertEqual(loaded.entryContext.onboardingLanguageCode, "ko")
        let row = try XCTUnwrap(loaded.progress.sourceRows["imessage"])
        let runState = try stateObject(in: URL(fileURLWithPath: try XCTUnwrap(row.runStatePath)))
        XCTAssertEqual(runState["selectedThreadIDs"] as? [String], ["1318"])
        let summaries = try XCTUnwrap(runState["selectedThreadSummaries"] as? [[String: Any]])
        XCTAssertEqual(summaries.first?["chatID"] as? String, "1318")
        XCTAssertTrue((summaries.first?["summary"] as? String ?? "").contains("+82 10-4330-0841"))
    }

    @MainActor
    func testSourceOnboardingIMessageHistoryFailureUsesHistoryReason() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        try installFakeIMsg(in: fakeBin)
        let prepared = try prepareIMessageSourceOnboarding(
            root: root,
            pathPrefix: fakeBin,
            extraEnvironment: ["IMSG_FIXTURE_MODE": "history-fails"]
        )
        _ = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["next"],
            environment: prepared.environment
        )
        _ = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "check-cli"],
            environment: prepared.environment
        )
        _ = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "check-access"],
            environment: prepared.environment
        )

        let smoke = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "smoke-history"],
            environment: prepared.environment
        )

        XCTAssertEqual(smoke.status, 1, "stdout:\n\(smoke.stdout)\nstderr:\n\(smoke.stderr)")
        let payload = try jsonObject(from: smoke.stdout)
        XCTAssertEqual(payload["reason"] as? String, "history_read_failed")
        let loaded = try readSourceOnboardingState(at: prepared.stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["imessage"]?.attentionReason, "history_read_failed")
    }

    @MainActor
    func testSourceOnboardingIMessageEmptyApprovedScopeDoesNotComplete() throws {
        let root = try makeTemporaryDirectory()
        let fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        try installFakeIMsg(in: fakeBin)
        let prepared = try prepareIMessageSourceOnboarding(root: root, pathPrefix: fakeBin)
        try runIMessageToScopeSelection(helperURL: prepared.helperURL, environment: prepared.environment)

        XCTAssertEqual(try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "choose-scope", "--scope", "updated-since", "--since", "2027-01-01"],
            environment: prepared.environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "confirm-plan", "--answer", "yes"],
            environment: prepared.environment
        ).status, 0)

        let ingest = try runProcess(
            executableURL: prepared.helperURL,
            arguments: ["imessage", "ingest"],
            environment: prepared.environment
        )

        XCTAssertEqual(ingest.status, 1, "stdout:\n\(ingest.stdout)\nstderr:\n\(ingest.stderr)")
        let payload = try jsonObject(from: ingest.stdout)
        XCTAssertEqual(payload["reason"] as? String, "no_threads_in_approved_scope")
        let loaded = try readSourceOnboardingState(at: prepared.stateURL)
        XCTAssertEqual(loaded.progress.sourceRows["imessage"]?.status, "attention")
        XCTAssertEqual(loaded.progress.sourceRows["imessage"]?.attentionReason, "no_threads_in_approved_scope")
    }

    @MainActor
    func testSourceOnboardingGmailVerifyEnvAdvancesRunnerToVerifyConnection() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_TASK_ID=task_test
            """,
            homeURL: root
        )
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "지메일", "--candidate", "gmail=지메일"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["gmail", "verify-env"],
            environment: environment
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let payload = try jsonObject(from: result.stdout)
        XCTAssertEqual(payload["nextSourceID"] as? String, "gmail")
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "verify_connection")
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        let nextPromptPath = try XCTUnwrap(payload["nextPromptPath"] as? String)
        XCTAssertTrue(nextPrompt.contains("zebra-source-onboarding gmail verify-connection"), nextPrompt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nextPromptPath))

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.sourceReadiness.gmail.status, .unverified)
        XCTAssertEqual(loaded.progress.activeSourceID, "gmail")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.status, "running")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.phase, "smoke")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.playbookStepID, "verify_connection")

        let resumed = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(resumed.status, 0, "stdout:\n\(resumed.stdout)\nstderr:\n\(resumed.stderr)")
        let resumedPayload = try jsonObject(from: resumed.stdout)
        XCTAssertEqual(resumedPayload["nextSourceID"] as? String, "gmail")
        XCTAssertEqual(resumedPayload["nextPlaybookStepID"] as? String, "verify_connection")
        let resumedState = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(resumedState.progress.sourceRows["gmail"]?.phase, "smoke")
        XCTAssertEqual(resumedState.progress.sourceRows["gmail"]?.playbookStepID, "verify_connection")
    }

    @MainActor
    func testSourceOnboardingGmailHelperVerifyEnvWritesMissingState() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["gmail", "verify-env"],
            environment: environment
        )

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.sourceReadiness.gmail.status, .missingEnv)
        XCTAssertEqual(
            Set(loaded.sourceReadiness.gmail.reasons),
            Set(["missing:CLAWVISOR_URL,CLAWVISOR_AGENT_TOKEN,CLAWVISOR_TASK_ID"])
        )
        XCTAssertTrue(loaded.sourceReadiness.gmail.envPath.hasSuffix(".gbrain/.env"))
    }

    @MainActor
    func testSourceOnboardingGmailHelperIgnoresAmbientEnvWithoutPersistedEnv() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "CLAWVISOR_URL": "https://app.clawvisor.com",
            "CLAWVISOR_AGENT_TOKEN": "ambient_token",
            "CLAWVISOR_TASK_ID": "ambient_task",
        ]

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["gmail", "verify-env"],
            environment: environment
        )

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.sourceReadiness.gmail.status, .missingEnv)
    }

    @MainActor
    func testSourceOnboardingGmailHelperVerifyEnvWritesUnverifiedState() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            export CLAWVISOR_URL="https://app.clawvisor.com"
            export CLAWVISOR_AGENT_TOKEN="cvis_test"
            export CLAWVISOR_TASK_ID="task_test"
            """,
            homeURL: root
        )
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["gmail", "verify-env"],
            environment: environment
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.sourceReadiness.gmail.status, .unverified)
        XCTAssertEqual(loaded.sourceReadiness.gmail.connectionPath, "clawvisor_env_available")
        XCTAssertEqual(loaded.sourceReadiness.gmail.reasons, ["email_connection_unverified"])
    }

    @MainActor
    func testSourceOnboardingGmailHelperVerifyConnectionWritesAttentionForBadURL() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=not a valid url
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_TASK_ID=task_test
            """,
            homeURL: root
        )
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "지메일", "--candidate", "gmail=지메일"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)

        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["gmail", "verify-connection"],
            environment: environment
        )

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertFalse(result.stderr.contains("Traceback"), result.stderr)
        let payload = try jsonObject(from: result.stdout)
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "verify_connection")
        XCTAssertNotNil(payload["nextPromptPath"])
        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.sourceReadiness.gmail.status, .attention)
        XCTAssertEqual(loaded.sourceReadiness.gmail.repairKind, "task_request_failed")
        XCTAssertTrue(loaded.sourceReadiness.gmail.reasons.first?.hasPrefix("task_request_failed:") == true)
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.status, "attention")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.phase, "smoke")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.playbookStepID, "verify_connection")
    }

    @MainActor
    func testSourceOnboardingHelperRejectedConfirmationStaysRunning() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
        ]

        let intake = try runProcess(
            executableURL: helperURL,
            arguments: [
                "intake",
                "--raw", "지메일",
                "--candidate", "gmail=지메일",
            ],
            environment: environment
        )
        XCTAssertEqual(intake.status, 0, "stdout:\n\(intake.stdout)\nstderr:\n\(intake.stderr)")

        let rejected = try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "no"],
            environment: environment
        )
        XCTAssertEqual(rejected.status, 0, "stdout:\n\(rejected.stdout)\nstderr:\n\(rejected.stderr)")

        let store = makeChecklistStore(homeURL: root)
        let loaded = try XCTUnwrap(store.loadSourceOnboardingState())
        XCTAssertEqual(loaded.status, .running)
        XCTAssertNotEqual(loaded.status, .ready)
        XCTAssertNotEqual(loaded.status, .completed)
        XCTAssertEqual(loaded.progress.sourceConfirmation?.status, .rejected)
        XCTAssertEqual(loaded.progress.pendingQuestion?.status, "source_confirmation_rejected")
        let payload = try jsonObject(from: rejected.stdout)
        XCTAssertEqual(payload["status"] as? String, "running")
        XCTAssertEqual(payload["sourceConfirmationStatus"] as? String, "rejected")
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
    func testGBrainSnapshotIncludesInlineSubstepsForCurrentSection() throws {
        let root = try makeTemporaryDirectory()
        let onboardingDirectory = root.appendingPathComponent("onboarding", isDirectory: true)
        let agentStateURL = onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        let agentPreferenceURL = root
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
        let runtimeStateURL = onboardingDirectory.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = onboardingDirectory.appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let executable = try installFakeRuntime(root: root, name: "hermes")
        try writeAgentReadinessState(onboardingDirectory: onboardingDirectory, agent: "codex", method: "path")
        try writeAgentPreferences(agentPreferenceURL)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path
        )
        try writeGBrainProgressState(
            stateURL: gbrainStateURL,
            completedSections: ["Step 1: Install GBrain"],
            nextSection: "Step 2: API Keys"
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            agentOnboardingStateURL: agentStateURL,
            agentPreferenceURL: agentPreferenceURL,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )
        let beforeStart = try XCTUnwrap(store.snapshots.first { $0.id == .gbrain })

        XCTAssertTrue(beforeStart.isActive)
        XCTAssertTrue(beforeStart.showsStart)
        XCTAssertEqual(beforeStart.substeps, [])

        store.beginLaunch(stepID: .gbrain)
        store.cancelRunning(stepID: .gbrain)

        let gbrain = try XCTUnwrap(store.snapshots.first { $0.id == .gbrain })
        let prepare = try XCTUnwrap(gbrain.substeps.first { $0.title == "Check and clone GBrain repo" })
        let install = try XCTUnwrap(gbrain.substeps.first { $0.title == "Step 1: Install GBrain" })
        let credentials = try XCTUnwrap(gbrain.substeps.first { $0.title == "Step 2: API Keys" })
        let future = try XCTUnwrap(gbrain.substeps.first { $0.title == "Step 3: Create the Brain" })

        XCTAssertTrue(gbrain.isActive)
        XCTAssertTrue(gbrain.showsStart)
        XCTAssertEqual(gbrain.substeps.map(\.title), [
            "Check and clone GBrain repo",
            "Step 1: Install GBrain",
            "Step 2: API Keys",
            "Step 3: Create the Brain",
        ])
        XCTAssertTrue(prepare.isCompleted)
        XCTAssertFalse(prepare.showsStart)
        XCTAssertTrue(install.isCompleted)
        XCTAssertFalse(install.showsStart)
        XCTAssertTrue(credentials.isActive)
        XCTAssertTrue(credentials.showsStart)
        XCTAssertFalse(future.isCompleted)
        XCTAssertFalse(future.isActive)
        XCTAssertFalse(future.showsStart)
    }

    @MainActor
    func testGBrainRefreshPublishesWhenOnlySubstepProgressChanges() throws {
        let root = try makeTemporaryDirectory()
        let onboardingDirectory = root.appendingPathComponent("onboarding", isDirectory: true)
        let agentStateURL = onboardingDirectory.appendingPathComponent("agent-cli-state.json", isDirectory: false)
        let agentPreferenceURL = root
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
        let runtimeStateURL = onboardingDirectory.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let gbrainStateURL = onboardingDirectory.appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let executable = try installFakeRuntime(root: root, name: "hermes")
        try writeAgentReadinessState(onboardingDirectory: onboardingDirectory, agent: "codex", method: "path")
        try writeAgentPreferences(agentPreferenceURL)
        try writeCompletedRuntimeState(
            stateURL: runtimeStateURL,
            runtime: "hermes",
            executablePath: executable.path
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            agentOnboardingStateURL: agentStateURL,
            agentPreferenceURL: agentPreferenceURL,
            gbrainRuntimeOnboardingStateURL: runtimeStateURL,
            gbrainOnboardingStateURL: gbrainStateURL
        )
        store.beginLaunch(stepID: .gbrain)
        store.cancelRunning(stepID: .gbrain)

        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }

        try writeGBrainProgressState(
            stateURL: gbrainStateURL,
            completedSections: ["Step 1: Install GBrain"],
            nextSection: "Step 2: API Keys"
        )
        store.refreshDetectedCompletion(for: .gbrain)

        XCTAssertGreaterThan(
            publishCount,
            0,
            "GBrain progress changes should redraw substeps even when top-level completion stays unchanged."
        )
        let gbrain = try XCTUnwrap(store.snapshots.first { $0.id == .gbrain })
        XCTAssertEqual(gbrain.substeps.map(\.title), [
            "Check and clone GBrain repo",
            "Step 1: Install GBrain",
            "Step 2: API Keys",
            "Step 3: Create the Brain",
        ])
        XCTAssertFalse(store.completedStepIDs.contains(.gbrain))
        cancellable.cancel()
    }

    @MainActor
    func testGBrainRecurringJobsCompletionPublishesDedicatedRevisionOnlyOnTransition() throws {
        let root = try makeTemporaryDirectory()
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainOnboardingStateURL: gbrainStateURL
        )

        XCTAssertEqual(store.gbrainRecurringJobsCompletionRevision, 0)

        try writeGBrainRecurringJobsProgressState(
            stateURL: gbrainStateURL,
            completedSections: ["Step 4: Import and index"],
            nextSection: "Step 7: Recurring jobs"
        )
        store.refreshDetectedCompletion(for: .gbrain)

        XCTAssertEqual(
            store.gbrainRecurringJobsCompletionRevision,
            0,
            "Non-recurring GBrain progress should not refresh Save UI."
        )

        try writeGBrainRecurringJobsProgressState(
            stateURL: gbrainStateURL,
            completedSections: ["Step 4: Import and index", "Step 7: Recurring jobs"],
            nextSection: "Step 9: Verify"
        )
        store.refreshDetectedCompletion(for: .gbrain)

        XCTAssertEqual(store.gbrainRecurringJobsCompletionRevision, 1)

        store.refreshDetectedCompletion(for: .gbrain)

        XCTAssertEqual(
            store.gbrainRecurringJobsCompletionRevision,
            1,
            "A recurring_jobs completion that is already known should not emit another Save UI refresh signal."
        )

        try writeGBrainRecurringJobsProgressState(
            stateURL: gbrainStateURL,
            completedSections: ["Step 4: Import and index"],
            nextSection: "Step 7: Recurring jobs"
        )
        store.refreshDetectedCompletion(for: .gbrain)

        XCTAssertEqual(store.gbrainRecurringJobsCompletionRevision, 1)

        try writeGBrainRecurringJobsProgressState(
            stateURL: gbrainStateURL,
            completedSections: ["Step 4: Import and index", "Step 7: Recurring jobs"],
            nextSection: "Step 9: Verify"
        )
        store.refreshDetectedCompletion(for: .gbrain)

        XCTAssertEqual(store.gbrainRecurringJobsCompletionRevision, 2)
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

    func testRuntimeLaunchInstallsFixedInstructionDocumentAndRunIsNonInteractive() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )

        let launch = try XCTUnwrap(store.prepareLaunch())
        XCTAssertTrue(FileManager.default.fileExists(atPath: launch.documentPath))
        let installedDocument = try String(
            contentsOf: URL(fileURLWithPath: launch.documentPath),
            encoding: .utf8
        )
        let sourceDocument = try String(
            contentsOf: Self.runtimeOnboardingDocumentURL(),
            encoding: .utf8
        )
        XCTAssertEqual(installedDocument, sourceDocument)
        XCTAssertTrue(launch.startupPrompt.contains(launch.documentPath))
        XCTAssertTrue(launch.startupPrompt.contains("status --json"))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("ZEBRA_GBRAIN_RUNTIME_DOC"))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("\(root.path)/.local/bin"))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("\(root.path)/.bun/bin"))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("/opt/homebrew/bin"))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("/usr/local/bin"))

        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let result = try runProcess(
            executableURL: helperURL,
            arguments: ["run"],
            environment: [
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
                "ZEBRA_GBRAIN_RUNTIME_DOC": launch.documentPath,
            ]
        )
        let payloadStart = try XCTUnwrap(result.stdout.firstIndex(of: "{"))
        let payloadText = String(result.stdout[payloadStart...])
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payloadText.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(payload["mode"] as? String, "agent_orchestrated")
        XCTAssertEqual(payload["documentPath"] as? String, launch.documentPath)
        XCTAssertFalse(result.stdout.contains("Select runtime"))
        XCTAssertFalse(result.stdout.contains("Select LLM connection"))
    }

    func testRuntimeHelperPreflightReportsCLTRequiredWithoutRequestingInstallWhenPython3IsMissing() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let noPythonBin = root.appendingPathComponent("no-python-bin", isDirectory: true)
        let xcodeSelectCallLog = root.appendingPathComponent("xcode-select-called", isDirectory: false)
        try FileManager.default.createDirectory(at: noPythonBin, withIntermediateDirectories: true)
        try installFakeCommand(
            directory: noPythonBin,
            name: "xcode-select",
            content: """
            #!/bin/sh
            echo "$*" >> '\(xcodeSelectCallLog.path)'
            exit 0
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["preflight", "--json"],
            environment: [
                "PATH": noPythonBin.path,
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["blockingReason"] as? String, "clt_install_required")
        XCTAssertEqual(payload["nextRecommendedCommand"] as? String, "recover-prerequisite clt")
        XCTAssertTrue((payload["userMessage"] as? String)?.contains("Command Line Tools") == true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: xcodeSelectCallLog.path),
            "preflight/status must not trigger xcode-select --install before the agent explains the CLT install prompt."
        )

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let lastFailure = try XCTUnwrap(progress["lastFailure"] as? [String: Any])
        let preflight = try XCTUnwrap(state["preflight"] as? [String: Any])
        let facts = try XCTUnwrap(preflight["facts"] as? [String: Any])
        let python3 = try XCTUnwrap(facts["python3"] as? [String: Any])

        XCTAssertEqual(progress["status"] as? String, "failed")
        XCTAssertNil(progress["waitingForUser"])
        XCTAssertEqual(lastFailure["reason"] as? String, "clt_install_required")
        XCTAssertNil(state["attempts"])
        XCTAssertEqual(python3["blockingNow"] as? Bool, true)
        XCTAssertEqual(python3["blockingReason"] as? String, "clt_install_required")
    }

    func testRuntimeHelperPreflightDoesNotRequestManualCLTInstallWhenPython3IsUnusableCLTShim() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let xcodeSelectCallLog = root.appendingPathComponent("xcode-select-called", isDirectory: false)
        try installFakeCommand(
            directory: fakeBin,
            name: "python3",
            content: """
            #!/bin/sh
            echo 'xcode-select: error: No developer tools were found and no install could be requested' >&2
            exit 1
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "xcode-select",
            content: """
            #!/bin/sh
            echo "$*" >> '\(xcodeSelectCallLog.path)'
            echo 'xcode-select: error: No developer tools were found and no install could be requested' >&2
            exit 1
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["preflight", "--json"],
            environment: [
                "PATH": fakeBin.path,
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["blockingReason"] as? String, "clt_install_required")
        XCTAssertEqual(payload["nextRecommendedCommand"] as? String, "recover-prerequisite clt")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: xcodeSelectCallLog.path),
            "preflight/status must not try xcode-select even when python3 is the CLT shim."
        )

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let lastFailure = try XCTUnwrap(progress["lastFailure"] as? [String: Any])
        let preflight = try XCTUnwrap(state["preflight"] as? [String: Any])
        let facts = try XCTUnwrap(preflight["facts"] as? [String: Any])
        let python3 = try XCTUnwrap(facts["python3"] as? [String: Any])

        XCTAssertEqual(progress["status"] as? String, "failed")
        XCTAssertNil(progress["waitingForUser"])
        XCTAssertEqual(lastFailure["reason"] as? String, "clt_install_required")
        XCTAssertNil(state["attempts"])
        XCTAssertEqual(python3["present"] as? Bool, true)
        XCTAssertEqual(python3["blockingReason"] as? String, "clt_install_required")
    }

    func testRuntimeHelperCLTRecoveryRequestsInstallWithoutUsablePython() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let xcodeSelectCallLog = root.appendingPathComponent("xcode-select-called", isDirectory: false)
        let pgrepCallLog = root.appendingPathComponent("pgrep-called", isDirectory: false)
        let osascriptCallLog = root.appendingPathComponent("osascript-called", isDirectory: false)
        try installFakeCommand(
            directory: fakeBin,
            name: "xcode-select",
            content: """
            #!/bin/sh
            echo "$*" >> '\(xcodeSelectCallLog.path)'
            exit 0
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "pgrep",
            content: """
            #!/bin/sh
            echo "$*" >> '\(pgrepCallLog.path)'
            exit 0
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "osascript",
            content: """
            #!/bin/sh
            echo "$*" >> '\(osascriptCallLog.path)'
            exit 0
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "clt"],
            environment: [
                "PATH": fakeBin.path,
                "ZEBRA_CLT_INSTALLER_FOREGROUND_ATTEMPTS": "1",
                "ZEBRA_CLT_INSTALLER_FOREGROUND_SLEEP": "0",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["requiresUserAction"] as? Bool, true)
        XCTAssertEqual(payload["blockingReason"] as? String, "clt_install_required")
        XCTAssertEqual(
            try String(contentsOf: xcodeSelectCallLog, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "--install"
        )
        XCTAssertTrue(
            try String(contentsOf: pgrepCallLog, encoding: .utf8).contains("com.apple.dt.CommandLineTools.installondemand")
        )
        XCTAssertEqual(
            try String(contentsOf: osascriptCallLog, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "-e tell application id \"com.apple.dt.CommandLineTools.installondemand\" to activate"
        )

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let waitingForUser = try XCTUnwrap(progress["waitingForUser"] as? [String: Any])
        let lastFailure = try XCTUnwrap(progress["lastFailure"] as? [String: Any])
        let attempts = try XCTUnwrap(state["attempts"] as? [[String: Any]])

        XCTAssertEqual(progress["status"] as? String, "waiting_for_user")
        XCTAssertEqual(waitingForUser["section"] as? String, "Install common prerequisites")
        XCTAssertEqual(lastFailure["reason"] as? String, "clt_install_required")
        XCTAssertEqual(attempts.first?["attemptedCommand"] as? String, "xcode-select --install")
    }

    func testRuntimeHelperCLTRecoveryForegroundsInstallerWithUsablePython() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let xcodeSelectCallLog = root.appendingPathComponent("xcode-select-called", isDirectory: false)
        let pgrepCallLog = root.appendingPathComponent("pgrep-called", isDirectory: false)
        let osascriptCallLog = root.appendingPathComponent("osascript-called", isDirectory: false)
        try installFakeCommand(
            directory: fakeBin,
            name: "xcode-select",
            content: """
            #!/bin/sh
            echo "$*" >> '\(xcodeSelectCallLog.path)'
            exit 0
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "pgrep",
            content: """
            #!/bin/sh
            echo "$*" >> '\(pgrepCallLog.path)'
            exit 0
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "osascript",
            content: """
            #!/bin/sh
            echo "$*" >> '\(osascriptCallLog.path)'
            exit 0
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "clt"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_CLT_INSTALLER_FOREGROUND_ATTEMPTS": "1",
                "ZEBRA_CLT_INSTALLER_FOREGROUND_SLEEP": "0",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["blockingReason"] as? String, "clt_install_required")
        XCTAssertEqual(
            try String(contentsOf: xcodeSelectCallLog, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "--install"
        )
        XCTAssertTrue(
            try String(contentsOf: pgrepCallLog, encoding: .utf8).contains("com.apple.dt.CommandLineTools.installondemand")
        )
        XCTAssertEqual(
            try String(contentsOf: osascriptCallLog, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "-e tell application id \"com.apple.dt.CommandLineTools.installondemand\" to activate"
        )
    }

    func testRuntimeHelperCLTRecoveryWritesStateWithoutUsablePython() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        try installFakeCommand(
            directory: fakeBin,
            name: "python3",
            content: """
            #!/bin/sh
            echo 'xcode-select: error: No developer tools were found and no install could be requested' >&2
            exit 1
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "xcode-select",
            content: """
            #!/bin/sh
            echo 'xcode-select: error: No developer tools were found and no install could be requested' >&2
            exit 1
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "clt"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("clt_manual_install_required"))
        XCTAssertTrue(result.stderr.contains("Install CLT manually"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let lastFailure = try XCTUnwrap(progress["lastFailure"] as? [String: Any])
        let attempts = try XCTUnwrap(state["attempts"] as? [[String: Any]])

        XCTAssertEqual(lastFailure["reason"] as? String, "clt_manual_install_required")
        XCTAssertEqual(attempts.first?["attemptedCommand"] as? String, "xcode-select --install")
    }

    func testRuntimeHelperPreflightFindsBunInHomeBunBinOutsidePath() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let bunBin = root
            .appendingPathComponent(".bun", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try installFakeCommand(
            directory: bunBin,
            name: "bun",
            content: """
            #!/bin/sh
            echo '1.3.14'
            exit 0
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["preflight", "--json"],
            environment: [
                "PATH": "/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let preflight = try XCTUnwrap(state["preflight"] as? [String: Any])
        let facts = try XCTUnwrap(preflight["facts"] as? [String: Any])
        let bun = try XCTUnwrap(facts["bun"] as? [String: Any])

        XCTAssertEqual(bun["ok"] as? Bool, true)
        XCTAssertEqual(bun["path"] as? String, bunBin.appendingPathComponent("bun").path)
        XCTAssertEqual(bun["version"] as? String, "1.3.14")
    }

    func testRuntimeHelperPreflightAndReportWriteProgressState() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let environment = [
            "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
            "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
        ]

        let started = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "started", "--section", "Baseline preflight"],
            environment: environment
        )
        XCTAssertEqual(started.status, 0)

        let preflight = try runProcess(
            executableURL: helperURL,
            arguments: ["preflight", "--json"],
            environment: environment
        )
        XCTAssertEqual(preflight.status, 0)

        let completed = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--section", "Baseline preflight"],
            environment: environment
        )
        XCTAssertEqual(completed.status, 0)

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let completedSections = try XCTUnwrap(progress["completedSections"] as? [String])
        let preflightState = try XCTUnwrap(state["preflight"] as? [String: Any])
        let facts = try XCTUnwrap(preflightState["facts"] as? [String: Any])
        let npm = try XCTUnwrap(facts["npm"] as? [String: Any])

        XCTAssertTrue(completedSections.contains("Baseline preflight"))
        XCTAssertEqual(npm["requiredFor"] as? [String], ["openclaw"])
        XCTAssertEqual(npm["blockingNow"] as? Bool, false)
    }

    func testRuntimeHelperNodeRecoveryReportsUserActionInsteadOfInstallCompletion() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let openLog = root.appendingPathComponent("open.log", isDirectory: false)
        try installFakeCommand(
            directory: fakeBin,
            name: "curl",
            content: """
            #!/bin/sh
            output=
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "-o" ]; then
                shift
                output="$1"
              fi
              shift || break
            done
            : > "$output"
            exit 0
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "open",
            content: """
            #!/bin/sh
            printf '%s\\n' "$*" > '\(shellSingleQuoted(openLog.path))'
            exit 0
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "node"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
                "ZEBRA_NODE_PKG_URL": "https://example.invalid/node.pkg",
            ]
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["requiresUserAction"] as? Bool, true)
        XCTAssertEqual(payload["blockingReason"] as? String, "node_pkg_install_required")
        XCTAssertTrue(FileManager.default.fileExists(atPath: openLog.path))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let waitingForUser = try XCTUnwrap(progress["waitingForUser"] as? [String: Any])
        XCTAssertEqual(waitingForUser["section"] as? String, "Install selected-runtime prerequisites")
    }

    func testRuntimeHelperNodeRecoveryDoesNotReopenInstallerWhileWaitingForUser() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let openLog = root.appendingPathComponent("open.log", isDirectory: false)
        try installFakeNodeInstallerCommands(fakeBin: fakeBin, openLog: openLog)

        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())
        let environment = [
            "PATH": "\(fakeBin.path):/usr/bin:/bin",
            "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
            "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            "ZEBRA_NODE_PKG_URL": "https://example.invalid/node.pkg",
        ]

        let first = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "node"],
            environment: environment
        )
        XCTAssertEqual(first.status, 0, "stdout:\n\(first.stdout)\nstderr:\n\(first.stderr)")
        XCTAssertEqual(try nodeInstallerOpenCount(openLog), 1)

        let second = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "node"],
            environment: environment
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(second.stdout.utf8)) as? [String: Any]
        )

        XCTAssertEqual(second.status, 0, "stdout:\n\(second.stdout)\nstderr:\n\(second.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["requiresUserAction"] as? Bool, true)
        XCTAssertEqual(payload["blockingReason"] as? String, "node_pkg_install_required")
        XCTAssertEqual(payload["alreadyRequested"] as? Bool, true)
        let userMessage = try XCTUnwrap(payload["userMessage"] as? String)
        XCTAssertTrue(userMessage.localizedCaseInsensitiveContains("install"))
        XCTAssertFalse(userMessage.localizedCaseInsensitiveContains("recover"))
        XCTAssertTrue(userMessage.localizedCaseInsensitiveContains("do not open the installer again"))
        XCTAssertTrue(userMessage.localizedCaseInsensitiveContains("re-check the environment"))
        XCTAssertEqual(try nodeInstallerOpenCount(openLog), 1)

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let waitingForUser = try XCTUnwrap(progress["waitingForUser"] as? [String: Any])
        XCTAssertEqual(waitingForUser["section"] as? String, "Install selected-runtime prerequisites")
    }

    func testRuntimeHelperNodeRecoveryClearsWaitingStateWhenNodeAndNpmAreNowAvailable() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let openLog = root.appendingPathComponent("open.log", isDirectory: false)
        try installFakeNodeInstallerCommands(fakeBin: fakeBin, openLog: openLog)

        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())
        let environment = [
            "PATH": "\(fakeBin.path):/usr/bin:/bin",
            "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
            "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            "ZEBRA_NODE_PKG_URL": "https://example.invalid/node.pkg",
        ]

        let first = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "node"],
            environment: environment
        )
        XCTAssertEqual(first.status, 0, "stdout:\n\(first.stdout)\nstderr:\n\(first.stderr)")
        XCTAssertEqual(try nodeInstallerOpenCount(openLog), 1)

        try installFakeCommand(
            directory: fakeBin,
            name: "node",
            content: """
            #!/bin/sh
            echo 'v22.0.0'
            exit 0
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "npm",
            content: """
            #!/bin/sh
            echo '10.0.0'
            exit 0
            """
        )

        let second = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["recover-prerequisite", "node"],
            environment: environment
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(second.stdout.utf8)) as? [String: Any]
        )

        XCTAssertEqual(second.status, 0, "stdout:\n\(second.stdout)\nstderr:\n\(second.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["alreadyInstalled"] as? Bool, true)
        XCTAssertEqual(try nodeInstallerOpenCount(openLog), 1)

        let preflight = try XCTUnwrap(payload["preflight"] as? [String: Any])
        let facts = try XCTUnwrap(preflight["facts"] as? [String: Any])
        let node = try XCTUnwrap(facts["node"] as? [String: Any])
        let npm = try XCTUnwrap(facts["npm"] as? [String: Any])
        XCTAssertEqual(node["ok"] as? Bool, true)
        XCTAssertEqual(npm["ok"] as? Bool, true)

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        XCTAssertNil(progress["waitingForUser"])
    }

    func testRuntimeHelperOpenClawInstallSetsUserNpmPrefixWhenGlobalPrefixIsNotWritable() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let log = root.appendingPathComponent("npm.log", isDirectory: false)
        let rootOwnedPrefix = root.appendingPathComponent("root-owned-prefix", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootOwnedPrefix.appendingPathComponent("lib", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rootOwnedPrefix.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rootOwnedPrefix.path)
        }
        try installFakeCommand(
            directory: fakeBin,
            name: "npm",
            content: """
            #!/bin/sh
            printf '%s\\n' "$*" >> '\(shellSingleQuoted(log.path))'
            if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "prefix" ]; then
              echo '\(shellSingleQuoted(rootOwnedPrefix.path))'
              exit 0
            fi
            if [ "$1" = "config" ] && [ "$2" = "set" ] && [ "$3" = "prefix" ]; then
              printf '%s\\n' "$4" > "$ZEBRA_GBRAIN_RUNTIME_HOME/.npm-prefix"
              exit 0
            fi
            if [ "$1" = "install" ] && [ "$2" = "-g" ] && [ "$3" = "openclaw" ]; then
              mkdir -p "$ZEBRA_GBRAIN_RUNTIME_HOME/.local/bin"
              openclaw="$ZEBRA_GBRAIN_RUNTIME_HOME/.local/bin/openclaw"
              printf '%s\\n' '#!/bin/sh' > "$openclaw"
              printf '%s\\n' 'if [ "$1" = "--version" ]; then echo "OpenClaw test"; exit 0; fi' >> "$openclaw"
              printf '%s\\n' 'exit 0' >> "$openclaw"
              chmod 755 "$openclaw"
              exit 0
            fi
            exit 1
            """
        )
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["install-runtime", "openclaw"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        let payloadStart = try XCTUnwrap(result.stdout.firstIndex(of: "{"))
        let payloadText = String(result.stdout[payloadStart...])
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payloadText.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        let detection = try XCTUnwrap(payload["detection"] as? [String: Any])
        XCTAssertEqual(detection["path"] as? String, root.appendingPathComponent(".local/bin/openclaw").path)

        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("config get prefix"))
        XCTAssertTrue(logText.contains("config set prefix \(root.path)/.local"))
        XCTAssertTrue(logText.contains("install -g openclaw"))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(".npm-prefix"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            root.appendingPathComponent(".local", isDirectory: true).path
        )

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let attempts = try XCTUnwrap(state["attempts"] as? [[String: Any]])
        XCTAssertTrue(attempts.contains { ($0["kind"] as? String) == "install-runtime:openclaw:npm-prefix" })
        XCTAssertTrue(attempts.contains { ($0["kind"] as? String) == "install-runtime:openclaw" })
    }

    func testRuntimeHelperOpenClawCodexOAuthWithoutTTYRequestsInteractiveAuth() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let log = root.appendingPathComponent("openclaw.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: log)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["configure-runtime", "openclaw", "--provider", "openai-codex"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let payloadStart = try XCTUnwrap(
            result.stdout.firstIndex(of: "{"),
            "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(result.stdout[payloadStart...]).utf8)) as? [String: Any]
        )

        XCTAssertEqual(payload["requiresInteractiveAuth"] as? Bool, true)
        XCTAssertEqual(payload["blockingReason"] as? String, "interactive_auth_required")

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let interactiveAuth = try XCTUnwrap(state["interactiveAuth"] as? [String: Any])
        XCTAssertEqual(interactiveAuth["status"] as? String, "required")
        XCTAssertEqual(interactiveAuth["runtime"] as? String, "openclaw")
        XCTAssertEqual(interactiveAuth["provider"] as? String, "openai-codex")
        XCTAssertTrue((interactiveAuth["command"] as? String ?? "").contains("interactive-auth openclaw --provider openai-codex"))

        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let waitingForUser = try XCTUnwrap(progress["waitingForUser"] as? [String: Any])
        XCTAssertEqual(waitingForUser["section"] as? String, "Configure selected runtime")

        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("models status"))
        XCTAssertFalse(logText.contains("models auth login"))
    }

    func testRuntimeHelperOpenClawClaudeAuthWithoutTTYRequestsInteractiveAuth() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let openClawLog = root.appendingPathComponent("openclaw.log", isDirectory: false)
        let claudeLog = root.appendingPathComponent("claude.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: openClawLog)
        _ = try installFakeClaudeRuntime(directory: fakeBin, log: claudeLog, loggedIn: false)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["configure-runtime", "openclaw", "--provider", "anthropic-claude-code"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let payloadStart = try XCTUnwrap(
            result.stdout.firstIndex(of: "{"),
            "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(result.stdout[payloadStart...]).utf8)) as? [String: Any]
        )

        XCTAssertEqual(payload["requiresInteractiveAuth"] as? Bool, true)

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let interactiveAuth = try XCTUnwrap(state["interactiveAuth"] as? [String: Any])
        XCTAssertEqual(interactiveAuth["status"] as? String, "required")
        XCTAssertEqual(interactiveAuth["runtime"] as? String, "openclaw")
        XCTAssertEqual(interactiveAuth["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(interactiveAuth["reason"] as? String, "claude_cli_auth_login_requires_tty")
        XCTAssertTrue((interactiveAuth["command"] as? String ?? "").contains("interactive-auth openclaw --provider anthropic-claude-code"))

        let claudeLogText = try String(contentsOf: claudeLog, encoding: .utf8)
        XCTAssertTrue(claudeLogText.contains("auth status"))
        XCTAssertFalse(claudeLogText.contains("auth login"))
    }

    func testRuntimeHelperOpenClawClaudeRegistrationWithoutTTYUsesRegistrationGuidance() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let openClawLog = root.appendingPathComponent("openclaw.log", isDirectory: false)
        let claudeLog = root.appendingPathComponent("claude.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: openClawLog)
        _ = try installFakeClaudeRuntime(directory: fakeBin, log: claudeLog, loggedIn: true)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["configure-runtime", "openclaw", "--provider", "anthropic-claude-code"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
                "ZEBRA_ONBOARDING_LANGUAGE": "ko",
            ]
        )
        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        let payloadStart = try XCTUnwrap(
            result.stdout.firstIndex(of: "{"),
            "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(result.stdout[payloadStart...]).utf8)) as? [String: Any]
        )

        XCTAssertEqual(payload["requiresInteractiveAuth"] as? Bool, true)

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let interactiveAuth = try XCTUnwrap(state["interactiveAuth"] as? [String: Any])
        XCTAssertEqual(interactiveAuth["status"] as? String, "required")
        XCTAssertEqual(interactiveAuth["runtime"] as? String, "openclaw")
        XCTAssertEqual(interactiveAuth["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(interactiveAuth["reason"] as? String, "openclaw_claude_cli_registration_requires_tty")

        let progress = try XCTUnwrap(state["progress"] as? [String: Any])
        let waitingForUser = try XCTUnwrap(progress["waitingForUser"] as? [String: Any])
        XCTAssertEqual(
            waitingForUser["note"] as? String,
            """
            OpenClaw가 Claude CLI 로그인을 재사용하도록 등록합니다.

            새 터미널이 열려 자동 등록을 진행하고, 성공하면 자동으로 닫힙니다.
            터미널이 닫히면 여기로 돌아와 완료됐다고 알려주세요.
            """
        )

        let claudeLogText = try String(contentsOf: claudeLog, encoding: .utf8)
        XCTAssertTrue(claudeLogText.contains("auth status"))
        XCTAssertFalse(claudeLogText.contains("auth login"))
        let openClawLogText = try String(contentsOf: openClawLog, encoding: .utf8)
        XCTAssertTrue(openClawLogText.contains("models status"))
        XCTAssertFalse(openClawLogText.contains("models auth login"))
    }

    func testRuntimeHelperReusesCompletedOpenClawClaudeConfigWithoutOpeningAuthAgain() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "selection": [
                    "selectedRuntime": "openclaw",
                    "selectedProvider": "anthropic-claude-code",
                    "runtimeProvider": "claude-cli",
                    "runtimeModel": "anthropic/claude-opus-4-8",
                    "credential": ["source": "agent-cli:claude-auth-status"],
                    "updatedAt": "2026-06-17T00:00:00Z",
                ],
                "interactiveAuth": [
                    "status": "completed",
                    "runtime": "openclaw",
                    "provider": "anthropic-claude-code",
                    "runtimeProvider": "claude-cli",
                    "completedAt": "2026-06-17T00:00:01Z",
                ],
                "runtimeConfig": [
                    "configuredAt": "2026-06-17T00:00:01Z",
                    "result": ["ok": true, "exitCode": 0, "stdoutTail": "", "stderrTail": ""],
                ],
                "receipt": [
                    "complete": false,
                    "verifiedAt": "2026-06-17T00:00:00Z",
                    "reasons": ["interactive_auth_required"],
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: stateURL, options: .atomic)

        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let openClawLog = root.appendingPathComponent("openclaw.log", isDirectory: false)
        let claudeLog = root.appendingPathComponent("claude.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: openClawLog)
        _ = try installFakeClaudeRuntime(directory: fakeBin, log: claudeLog, loggedIn: true)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let statusResult = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["status", "--json"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        XCTAssertEqual(statusResult.status, 0, "stdout:\n\(statusResult.stdout)\nstderr:\n\(statusResult.stderr)")
        let statusPayloadStart = try XCTUnwrap(statusResult.stdout.firstIndex(of: "{"))
        let statusPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(statusResult.stdout[statusPayloadStart...]).utf8)) as? [String: Any]
        )
        XCTAssertEqual(statusPayload["nextRecommendedCommand"] as? String, "verify-runtime openclaw")

        let configureResult = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
            arguments: ["configure-runtime", "openclaw", "--provider", "claude-code"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
                "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            ]
        )
        XCTAssertEqual(configureResult.status, 0, "stdout:\n\(configureResult.stdout)\nstderr:\n\(configureResult.stderr)")
        let configurePayloadStart = try XCTUnwrap(configureResult.stdout.firstIndex(of: "{"))
        let configurePayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(String(configureResult.stdout[configurePayloadStart...]).utf8)) as? [String: Any]
        )
        XCTAssertEqual(configurePayload["ok"] as? Bool, true)
        XCTAssertEqual(configurePayload["reusedCompletedInteractiveAuth"] as? Bool, true)
        XCTAssertEqual(configurePayload["nextRecommendedCommand"] as? String, "verify-runtime openclaw")

        let openClawLogText = try String(contentsOf: openClawLog, encoding: .utf8)
        XCTAssertTrue(openClawLogText.contains("--version"))
        XCTAssertFalse(openClawLogText.contains("models status"))
        XCTAssertFalse(openClawLogText.contains("models auth login"))
        let claudeLogText = (try? String(contentsOf: claudeLog, encoding: .utf8)) ?? ""
        XCTAssertFalse(claudeLogText.contains("auth status"))
        XCTAssertFalse(claudeLogText.contains("auth login"))
    }

    func testRuntimeHelperClearsInteractiveAuthRequiredReceiptAfterInteractiveAuthSuccess() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to provide a TTY to runtime helper interactive-auth")
        }

        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "selection": [
                    "selectedRuntime": "openclaw",
                    "selectedProvider": "anthropic-claude-code",
                    "runtimeProvider": "claude-cli",
                    "runtimeModel": "anthropic/claude-opus-4-8",
                    "credential": ["source": "agent-cli:claude-auth-status"],
                    "updatedAt": "2026-06-17T00:00:00Z",
                ],
                "interactiveAuth": [
                    "status": "required",
                    "runtime": "openclaw",
                    "provider": "anthropic-claude-code",
                    "runtimeProvider": "claude-cli",
                    "reason": "openclaw_claude_cli_registration_requires_tty",
                    "requestedAt": "2026-06-17T00:00:00Z",
                ],
                "runtimeConfig": [
                    "configuredAt": "2026-06-17T00:00:00Z",
                    "result": [
                        "ok": false,
                        "exitCode": 0,
                        "stdoutTail": "",
                        "stderrTail": "openclaw_claude_cli_registration_requires_tty",
                        "requiresInteractiveAuth": true,
                        "blockingReason": "interactive_auth_required",
                    ],
                ],
                "receipt": [
                    "complete": false,
                    "verifiedAt": "2026-06-17T00:00:00Z",
                    "reasons": ["interactive_auth_required"],
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: stateURL, options: .atomic)

        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        let openClawLog = root.appendingPathComponent("openclaw.log", isDirectory: false)
        let claudeLog = root.appendingPathComponent("claude.log", isDirectory: false)
        _ = try installFakeOpenClawRuntime(directory: fakeBin, log: openClawLog)
        _ = try installFakeClaudeRuntime(directory: fakeBin, log: claudeLog, loggedIn: true)
        let store = ZebraGBrainRuntimeOnboardingStore(
            stateURL: stateURL,
            homeDirectoryPath: root.path
        )
        let launch = try XCTUnwrap(store.prepareLaunch())

        let expectScript = root.appendingPathComponent("interactive-auth.expect", isDirectory: false)
        let expectContent = """
        set timeout 20
        spawn env PATH=\(fakeBin.path):/usr/bin:/bin ZEBRA_GBRAIN_RUNTIME_STATE=\(stateURL.path) ZEBRA_GBRAIN_RUNTIME_HOME=\(root.path) FAKE_OPENCLAW_AUTH_READY=claude-cli \(launch.helperPath) interactive-auth openclaw --provider anthropic-claude-code
        expect eof
        set result [wait]
        exit [lindex $result 3]
        """
        try expectContent.write(to: expectScript, atomically: true, encoding: .utf8)

        let result = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/expect"),
            arguments: [expectScript.path],
            environment: [:]
        )
        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        XCTAssertNil(state["receipt"])
        let interactiveAuth = try XCTUnwrap(state["interactiveAuth"] as? [String: Any])
        XCTAssertEqual(interactiveAuth["status"] as? String, "completed")
        let runtimeConfig = try XCTUnwrap(state["runtimeConfig"] as? [String: Any])
        let runtimeConfigResult = try XCTUnwrap(runtimeConfig["result"] as? [String: Any])
        XCTAssertEqual(runtimeConfigResult["ok"] as? Bool, true)
    }

    @MainActor
    func testChecklistStorePublishesPendingRuntimeInteractiveAuthRequest() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "interactiveAuth": [
                    "status": "required",
                    "runtime": "openclaw",
                    "provider": "openai-codex",
                    "command": "echo should-not-run",
                ],
            ],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: stateURL, options: .atomic)
        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: stateURL
        )

        store.syncExternalState(selectedVaultPath: nil)

        let request = try XCTUnwrap(store.pendingRuntimeInteractiveAuthRequest)
        XCTAssertEqual(request.id, "openclaw|openai-codex|pending")
        XCTAssertEqual(request.authKey, "openclaw|openai-codex")
        XCTAssertEqual(request.runtime, "openclaw")
        XCTAssertEqual(request.provider, "openai-codex")
        XCTAssertTrue(request.startupLine.contains("interactive-auth 'openclaw' --provider 'openai-codex'"))
        XCTAssertTrue(request.startupLine.contains("then exit; else"))
        XCTAssertFalse(request.startupLine.contains("should-not-run"))
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

    func testRuntimeHelperUsesOpenAICodexAccountLoginSelection() throws {
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "hermes",
            provider: "openai-codex",
            environment: ["OPENAI_API_KEY": "ambient-openai-key"]
        )
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("auth status openai-codex"))
        XCTAssertFalse(logText.contains("login --provider openai-codex"))
        XCTAssertFalse(logText.contains("auth add openai-codex"))
        XCTAssertTrue(logText.contains("config set model.provider openai-codex"))
        XCTAssertTrue(logText.contains("config set model.default gpt-5.5"))
        XCTAssertTrue(logText.contains("config set model.base_url https://chatgpt.com/backend-api/codex"))
        XCTAssertTrue(logText.contains("config set model.api_mode codex_responses"))
        XCTAssertTrue(logText.contains("chat -q Reply with OK. Do not use tools. --provider openai-codex --model gpt-5.5"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "gpt-5.5")
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "openclaw",
            provider: "openai-codex"
        )
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("models auth login --provider openai --method oauth --set-default"))
        XCTAssertTrue(logText.contains("models set openai/gpt-5.5"))
        XCTAssertFalse(logText.contains("onboard --non-interactive"))
        XCTAssertFalse(logText.contains("--auth-choice openai-codex"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "openai/gpt-5.5")
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "openclaw",
            provider: "openai-codex",
            environment: ["FAKE_OPENCLAW_AUTH_READY": "openai"]
        )
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("models status --json --probe-provider openai"))
        XCTAssertTrue(logText.contains("models set openai/gpt-5.5"))
        XCTAssertFalse(logText.contains("models auth login --provider openai"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "openai/gpt-5.5")
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "openclaw",
            provider: "openai-codex",
            environment: [
                "FAKE_OPENCLAW_LOGIN_HANGS_AFTER_READY": "openai",
                "ZEBRA_GBRAIN_RUNTIME_INTERACTIVE_GRACE_SECONDS": "0.1",
            ]
        )
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("models auth login --provider openai --method oauth --set-default"))
        XCTAssertTrue(logText.contains("models status --json --probe-provider openai"))
        XCTAssertTrue(logText.contains("models set openai/gpt-5.5"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "openai-codex")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "openai")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "openai/gpt-5.5")
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "openclaw",
            provider: "openai-codex",
            environment: [
                "OPENAI_API_KEY": "ambient-openai-key",
                "CODEX_API_KEY": "ambient-codex-key",
            ]
        )
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(logText.contains("models auth login --provider openai --method oauth --set-default"))
        XCTAssertTrue(logText.contains("models set openai/gpt-5.5"))
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "openclaw",
            provider: "anthropic-claude-code"
        )
        let openClawLogText = try String(contentsOf: openClawLog, encoding: .utf8)
        XCTAssertTrue(openClawLogText.contains("models auth login --provider anthropic --method cli --set-default"))
        XCTAssertTrue(openClawLogText.contains("models set anthropic/claude-opus-4-8"))
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
        XCTAssertEqual(receipt["runtimeModel"] as? String, "anthropic/claude-opus-4-8")
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "openclaw",
            provider: "anthropic-claude-code",
            environment: ["FAKE_OPENCLAW_AUTH_READY": "claude-cli"]
        )
        let openClawLogText = try String(contentsOf: openClawLog, encoding: .utf8)
        XCTAssertTrue(openClawLogText.contains("models status --json --probe-provider claude-cli"))
        XCTAssertTrue(openClawLogText.contains("models set anthropic/claude-opus-4-8"))
        XCTAssertFalse(openClawLogText.contains("models auth login --provider anthropic"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "claude-cli")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "anthropic/claude-opus-4-8")
        XCTAssertEqual(receipt["keySource"] as? String, "agent-cli:claude-auth-status")
    }

    func testRuntimeHelperAllowsClaudeCodeAccountLoginSelection() throws {
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "hermes",
            provider: "anthropic-claude-code",
            environment: ["ZEBRA_GBRAIN_RUNTIME_SKIP_CLAUDE_KEYCHAIN": "1"]
        )
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertFalse(logText.contains("login --provider openai-codex"))
        XCTAssertTrue(logText.contains("config set model.provider anthropic"))
        XCTAssertTrue(logText.contains("config set model.default claude-opus-4-8"))
        XCTAssertTrue(logText.contains("config set model.base_url https://api.anthropic.com"))
        XCTAssertTrue(logText.contains("config set model.api_mode anthropic_messages"))
        XCTAssertTrue(logText.contains("chat -q Reply with OK. Do not use tools. --provider anthropic --model claude-opus-4-8"))

        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "anthropic")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "claude-opus-4-8")
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "hermes",
            provider: "openai-api",
            environment: ["OPENAI_API_KEY": ""],
            secretPrompt: "Enter OpenAI API key",
            secretResponse: "entered-openai-key"
        )
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "hermes",
            provider: "anthropic-api",
            environment: [
                "ANTHROPIC_TOKEN": "test-anthropic-token",
                "ANTHROPIC_API_KEY": "",
                "CLAUDE_CODE_OAUTH_TOKEN": "",
            ]
        )
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "hermes",
            provider: "anthropic-claude-code",
            environment: [
                "ANTHROPIC_TOKEN": "",
                "ANTHROPIC_API_KEY": "",
                "CLAUDE_CODE_OAUTH_TOKEN": "",
                "ZEBRA_GBRAIN_RUNTIME_SKIP_CLAUDE_KEYCHAIN": "1",
            ]
        )
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        )
        let receipt = try XCTUnwrap(state["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["provider"] as? String, "anthropic-claude-code")
        XCTAssertEqual(receipt["runtimeProvider"] as? String, "anthropic")
        XCTAssertEqual(receipt["runtimeModel"] as? String, "claude-opus-4-8")
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
        _ = try runRuntimeHelperFlow(
            helperURL: helperURL,
            root: root,
            stateURL: stateURL,
            fakeBin: fakeBin,
            runtime: "hermes",
            provider: "openai-api",
            environment: ["OPENAI_API_KEY": "test-openai-key"],
            expectVerificationFailure: true
        )
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
        store.syncExternalState(selectedVaultPath: vault.path)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(store.completedStepIDs.contains(.gbrain))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: log.path),
            "Completed receipts should be trusted by the checklist without running gbrain doctor/current/list."
        )
    }

    @MainActor
    func testIncompleteGBrainReceiptDoesNotRunLiveProbeFromChecklist() async throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("gbrain-probe.log", isDirectory: false)
        let executable = try installFakeGBrain(root: root, sourcePath: vault.path, log: log)
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        try writeIncompleteGBrainState(stateURL: stateURL, vaultPath: vault.path, executablePath: executable.path)

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false),
            gbrainOnboardingStateURL: stateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(store.completedStepIDs.contains(.gbrain))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: log.path),
            "Incomplete receipts should remain incomplete until helper verify writes a complete receipt; the checklist must not run gbrain doctor/current/list."
        )
    }

    @MainActor
    func testGBrainStepRefreshDoesNotRunLiveProbeFromChecklist() async throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("gbrain-probe.log", isDirectory: false)
        let executable = try installFakeGBrain(root: root, sourcePath: vault.path, log: log)
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        try writeIncompleteGBrainState(stateURL: stateURL, vaultPath: vault.path, executablePath: executable.path)

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: root
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false),
            gbrainOnboardingStateURL: stateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path)
        store.refreshDetectedCompletion(for: .gbrain)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(store.completedStepIDs.contains(.gbrain))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: log.path),
            "A gbrain state-file refresh should not trigger app-side live verification."
        )
    }

    @MainActor
    func testCompletedAdapterReceiptCompletesAdapterStep() throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        let sourceRepo = root
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("gbrain", isDirectory: true)
        let adapterRepo = sourceRepo
            .deletingLastPathComponent()
            .appendingPathComponent("gbrain-adapter", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: adapterRepo, withIntermediateDirectories: true)
        let executable = try installFakeGBrain(
            root: root,
            sourcePath: vault.path,
            log: root.appendingPathComponent("gbrain-probe.log", isDirectory: false)
        )
        let onboardingDirectory = root.appendingPathComponent("onboarding", isDirectory: true)
        let gbrainStateURL = onboardingDirectory.appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = onboardingDirectory.appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        try writeCompletedGBrainState(
            stateURL: gbrainStateURL,
            vaultPath: vault.path,
            executablePath: executable.path,
            sourceRepoPath: sourceRepo.path
        )
        try writeInstalledAdapterFiles(vault)
        try writeCompletedAdapterState(
            stateURL: adapterStateURL,
            targetVaultPath: vault.path,
            adapterRepoPath: adapterRepo.path
        )

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainRuntimeOnboardingStateURL: onboardingDirectory.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false),
            gbrainOnboardingStateURL: gbrainStateURL,
            gbrainAdapterOnboardingStateURL: adapterStateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path)

        XCTAssertTrue(store.completedStepIDs.contains(.gbrain))
        XCTAssertTrue(store.completedStepIDs.contains(.adapter))
    }

    @MainActor
    func testStandaloneEmailAndIngestStepsAreNotEnabled() throws {
        let root = try makeTemporaryDirectory()
        let store = makeChecklistStore(homeURL: root)

        store.syncExternalState(selectedVaultPath: nil)

        XCTAssertFalse(store.snapshots.map(\.id.rawValue).contains("email"))
        XCTAssertFalse(store.snapshots.map(\.id.rawValue).contains("ingest"))
    }

    @MainActor
    func testGmailSourceReadinessIsUnverifiedFromClawvisorEnvBeforeVerifiedConnection() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_TASK_ID=task_test
            """,
            homeURL: root
        )

        let store = makeChecklistStore(homeURL: root)

        XCTAssertEqual(store.gmailSourceReadiness().status, .unverified)
        XCTAssertFalse(store.completedStepIDs.contains(.sourceOnboarding))
    }

    @MainActor
    func testGmailSourceReadinessIsReadyFromClawvisorEnvAfterVerifiedConnection() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_TASK_ID=task_test
            """,
            homeURL: root
        )

        let store = makeChecklistStore(homeURL: root)
        store.syncExternalState(
            selectedVaultPath: nil,
            emailConnectionVerified: true
        )

        XCTAssertEqual(store.gmailSourceReadiness().status, .ready)
        XCTAssertFalse(store.completedStepIDs.contains(.sourceOnboarding))
    }

    @MainActor
    func testSourceOnboardingPreviewStateIncludesGmailReadinessBoundary() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_TASK_ID=task_test
            """,
            homeURL: root
        )

        let store = makeChecklistStore(homeURL: root)
        store.syncExternalState(
            selectedVaultPath: nil,
            emailConnectionVerified: true
        )

        let state = store.sourceOnboardingPreviewState(now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(state.status, .attention)
        XCTAssertEqual(state.entryContext.gbrainTargetMissingReason, "gbrain_target_missing")
        XCTAssertEqual(state.entryContext.gbrainReceiptPath?.hasSuffix("gbrain-setup-state.json"), true)
        XCTAssertEqual(state.entryContext.liveProbe.ran, false)
        XCTAssertEqual(state.sourceReadiness.gmail.status, .ready)
        XCTAssertEqual(state.sourceReadiness.gmail.connectionPath, "existing_clawvisor_gmail_connection_path")
        XCTAssertTrue(state.sourceReadiness.gmail.envPath.hasSuffix(".gbrain/.env"))
        XCTAssertTrue(state.progress.normalizedSourceList.isEmpty)
        XCTAssertTrue(state.progress.sourceRows.isEmpty)
    }

    @MainActor
    func testGmailSourceReadinessIsReadyFromExportedClawvisorEnvAfterVerifiedConnection() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            export CLAWVISOR_URL="https://app.clawvisor.com"
            export CLAWVISOR_AGENT_TOKEN="cvis_test"
            export CLAWVISOR_TASK_ID="task_test"
            """,
            homeURL: root
        )

        let store = makeChecklistStore(homeURL: root)
        store.syncExternalState(
            selectedVaultPath: nil,
            emailConnectionVerified: true
        )

        XCTAssertEqual(store.gmailSourceReadiness().status, .ready)
        XCTAssertFalse(store.completedStepIDs.contains(.sourceOnboarding))
    }

    @MainActor
    func testGmailSourceReadinessNeedsAttentionWhenConnectionRepairIsActive() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_TASK_ID=task_test
            """,
            homeURL: root
        )
        let store = makeChecklistStore(homeURL: root)

        store.syncExternalState(
            selectedVaultPath: nil,
            emailConnectionRepairState: ZebraEmailConnectionRepairState(kind: .taskPendingApproval),
            emailConnectionVerified: true
        )

        let readiness = store.gmailSourceReadiness()
        XCTAssertEqual(readiness.status, .attention)
        XCTAssertEqual(readiness.repairKind, ZebraEmailConnectionRepairState.Kind.taskPendingApproval.rawValue)
        XCTAssertFalse(store.completedStepIDs.contains(.sourceOnboarding))
    }

    @MainActor
    func testGmailSourceReadinessIsMissingWhenClawvisorTaskIdIsMissing() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            """,
            homeURL: root
        )

        let store = makeChecklistStore(homeURL: root)

        XCTAssertEqual(store.gmailSourceReadiness().status, .missingEnv)
    }

    @MainActor
    func testGmailSourceReadinessIsMissingFromOldClawvisorGmailTaskEnvOnly() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            CLAWVISOR_GMAIL_TASK_ID=task_test
            ZEBRA_CLAWVISOR_GMAIL_ACCOUNT=test@example.com
            """,
            homeURL: root
        )

        let store = makeChecklistStore(homeURL: root)

        XCTAssertEqual(store.gmailSourceReadiness().status, .missingEnv)
    }

    @MainActor
    func testStoredDevelopmentCompletedOverrideDoesNotReviveEmailStep() throws {
        let root = try makeTemporaryDirectory()
        UserDefaults.standard.set(
            ["email"],
            forKey: "ZebraOnboardingChecklistStore.developmentCompletedStepIDs"
        )

        let store = makeChecklistStore(homeURL: root)

        XCTAssertFalse(store.snapshots.map(\.id.rawValue).contains("email"))
        XCTAssertFalse(store.completedStepIDs.contains(.sourceOnboarding))
    }

#if os(macOS)
    @MainActor
    func testCompletionWatcherCreatesGbrainDirectoryWithPrivatePermissions() throws {
        let root = try makeTemporaryDirectory()

        let store = makeChecklistStore(homeURL: root)
        store.activateCompletionWatching()

        let gbrainURL = root.appendingPathComponent(".gbrain", isDirectory: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: gbrainURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(permissions & 0o777, 0o700)
    }
#endif

    @MainActor
    private func makeChecklistStore(homeURL: URL) -> ZebraOnboardingChecklistStore {
        ZebraOnboardingChecklistStore(
            homeDirectoryPath: homeURL.path,
            gbrainRuntimeOnboardingStateURL: homeURL
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-runtime-state.json", isDirectory: false),
            gbrainOnboardingStateURL: homeURL
                .appendingPathComponent("onboarding", isDirectory: true)
                .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        )
    }

    private func writeClawvisorEnv(_ raw: String, homeURL: URL) throws {
        let gbrainURL = homeURL.appendingPathComponent(".gbrain", isDirectory: true)
        try FileManager.default.createDirectory(at: gbrainURL, withIntermediateDirectories: true)
        try raw.write(
            to: gbrainURL.appendingPathComponent(".env", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
    }

    private func installFakeIMsg(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("imsg", isDirectory: false)
        let content = """
        #!/bin/sh
        MODE="${IMSG_FIXTURE_MODE:-ok}"
        if [ "$1" = "--version" ]; then
          echo "imsg fixture 1.0"
          exit 0
        fi
        if [ "$1" = "chats" ]; then
          echo '{"chat_id":"chat-alpha","display_name":"Alpha","identifier":"+821043300841","service":"SMS","is_group":false,"last_message_at":"2026-07-02T12:00:00Z","participants":["+821043300841"]}'
          echo '{"id":1318,"name":"","identifier":"+821043300841","service":"SMS","is_group":false,"last_message_at":"2026-06-30T12:30:00Z","participants":["+821043300841"]}'
          echo '{"chat_id":"chat-old","identifier":"+8215881688","service":"SMS","is_group":false,"last_message_at":"2026-06-01T12:00:00Z","participants":["+8215881688"]}'
          echo '{"chat_id":"chat-name-only","display_name":"No Handle","service":"iMessage","is_group":false,"last_message_at":"2026-06-30T12:00:00Z"}'
          exit 0
        fi
        if [ "$1" = "history" ]; then
          if [ "$MODE" = "history-fails" ]; then
            echo "history fixture denied" >&2
            exit 13
          fi
          echo '{"message_id":"message-1","text":"fixture raw message body","timestamp":"2026-07-02T12:01:00Z"}'
          exit 0
        fi
        echo "unknown imsg fixture command" >&2
        exit 1
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    private func prepareIMessageSourceOnboarding(
        root: URL,
        pathPrefix: URL,
        includeAmbientPath: Bool = true,
        extraEnvironment: [String: String] = [:]
    ) throws -> (
        helperURL: URL,
        stateURL: URL,
        environment: [String: String]
    ) {
        let stateURL = ZebraSourceOnboardingState.defaultStateURL(homeDirectoryPath: root.path)
        let gbrainStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        let adapterStateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-adapter-state.json", isDirectory: false)
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)
        let path = includeAmbientPath
            ? pathPrefix.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            : pathPrefix.path
        var environment = [
            "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
            "ZEBRA_GBRAIN_SETUP_STATE": gbrainStateURL.path,
            "ZEBRA_GBRAIN_ADAPTER_STATE": adapterStateURL.path,
            "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            "PATH": path,
        ]
        environment.merge(extraEnvironment) { _, new in new }
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["intake", "--raw", "아이메시지", "--candidate", "imessage=아이메시지"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["confirm", "--answer", "yes"],
            environment: environment
        ).status, 0)
        return (helperURL, stateURL, environment)
    }

    private func runIMessageToScopeSelection(
        helperURL: URL,
        environment: [String: String]
    ) throws {
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "check-cli"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "check-access"],
            environment: environment
        ).status, 0)
        XCTAssertEqual(try runProcess(
            executableURL: helperURL,
            arguments: ["imessage", "smoke-history"],
            environment: environment
        ).status, 0)
    }

    private func pythonResolvedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/var/") {
            return "/private" + path
        }
        return path
    }

    private func readSourceOnboardingState(at url: URL) throws -> ZebraSourceOnboardingState {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ZebraSourceOnboardingState.self, from: data)
    }

    private func stateObject(in url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func jsonObject(from stdout: String) throws -> [String: Any] {
        let data = try XCTUnwrap(stdout.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeJSONObject(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func XCTAssertPrompt(
        _ prompt: String,
        contains earlier: String,
        before later: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let earlierRange = prompt.range(of: earlier) else {
            XCTFail("Prompt did not contain expected text: \(earlier)", file: file, line: line)
            return
        }
        guard let laterRange = prompt.range(of: later) else {
            XCTFail("Prompt did not contain later text: \(later)", file: file, line: line)
            return
        }
        XCTAssertLessThan(
            earlierRange.lowerBound,
            laterRange.lowerBound,
            "Expected `\(earlier)` to appear before `\(later)` in prompt:\n\(prompt)",
            file: file,
            line: line
        )
    }

    private func writeAgentPreferences(_ url: URL) throws {
        let preferences: [String: Any] = [
            "schemaVersion": 1,
            "primaryAgent": "codex",
        ]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: preferences, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func writeGBrainProgressState(
        stateURL: URL,
        completedSections: [String],
        nextSection: String
    ) throws {
        let state: [String: Any] = [
            "schemaVersion": 1,
            "docsManifest": [
                "generatedAt": "2026-06-12T00:00:00Z",
                "sourceKind": "local",
                "sourceRef": "test",
                "files": [],
                "installForAgentsSections": [
                    [
                        "title": "Step 1: Install GBrain",
                        "hash": "step-1",
                    ],
                    [
                        "title": "Step 2: API Keys",
                        "hash": "step-2",
                    ],
                    [
                        "title": "Step 3: Create the Brain",
                        "hash": "step-3",
                    ],
                ],
            ],
            "progress": [
                "completedSections": completedSections,
                "nextSection": nextSection,
            ],
        ]
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func writeGBrainRecurringJobsProgressState(
        stateURL: URL,
        completedSections: [String],
        nextSection: String
    ) throws {
        let state: [String: Any] = [
            "schemaVersion": 1,
            "docsManifest": [
                "generatedAt": "2026-06-12T00:00:00Z",
                "sourceKind": "local",
                "sourceRef": "test",
                "files": [],
                "installForAgentsSections": [
                    [
                        "title": "Step 4: Import and index",
                        "hash": "step-4",
                    ],
                    [
                        "title": "Step 7: Recurring jobs",
                        "hash": "step-7",
                    ],
                    [
                        "title": "Step 9: Verify",
                        "hash": "step-9",
                    ],
                ],
            ],
            "sectionRoles": [
                "hash:step-4": [
                    "section": "Step 4: Import and index",
                    "sectionHash": "step-4",
                    "role": "import_index",
                    "roleSource": "exact_title",
                    "roleConfidence": "deterministic",
                    "roleEvidence": ["exact_title"],
                    "updatedAt": "2026-06-12T00:00:00Z",
                ],
                "hash:step-7": [
                    "section": "Step 7: Recurring jobs",
                    "sectionHash": "step-7",
                    "role": "recurring_jobs",
                    "roleSource": "recurring_jobs_title",
                    "roleConfidence": "deterministic",
                    "roleEvidence": ["recurring_jobs_title"],
                    "updatedAt": "2026-06-12T00:00:00Z",
                ],
            ],
            "progress": [
                "completedSections": completedSections,
                "nextSection": nextSection,
            ],
        ]
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
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

    private func writeIncompleteRuntimeState(stateURL: URL, reason: String) throws {
        let state: [String: Any] = [
            "schemaVersion": 1,
            "receipt": [
                "complete": false,
                "verifiedAt": "2026-06-04T00:00:00Z",
                "reasons": [reason],
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
                "targets": [
                    targetKey: target,
                ],
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
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func writeIncompleteGBrainState(
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
            "doctorStatus": ["ok": false, "status": "failed"],
            "sourcesCurrentResult": [
                "ok": false,
                "sourceId": "brain",
                "localPath": vaultPath,
                "status": "transient",
                "reason": "pglite_busy",
            ],
            "searchProbeResult": ["ok": false, "status": "blocked"],
            "verifiedAt": timestamp,
            "complete": false,
            "targetResolution": [
                "method": "user_created_repo",
                "confirmedAt": timestamp,
            ],
            "reasons": ["pglite_busy"],
        ]
        let state: [String: Any] = [
            "schemaVersion": 1,
            "progress": [
                "resolvedTargetKey": targetKey,
                "targetResolution": [
                    "status": "failed",
                    "method": "user_created_repo",
                    "confirmedAt": timestamp,
                ],
            ],
            "receipt": [
                "globalReadiness": [
                    "complete": false,
                    "gbrainExecutablePath": executablePath,
                    "doctorOk": false,
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

    private func writeCompletedAdapterState(
        stateURL: URL,
        targetVaultPath: String,
        adapterRepoPath: String
    ) throws {
        let targetKey = "vault:\(targetVaultPath)"
        let timestamp = "2026-06-04T00:00:00Z"
        let state: [String: Any] = [
            "schemaVersion": 1,
            "adapterSourceBinding": [
                "repoPath": adapterRepoPath,
                "remote": "test",
                "ref": "main",
                "commit": "test",
                "status": "cloned",
            ],
            "receipt": [
                "complete": true,
                "targetKey": targetKey,
                "targetVaultPath": targetVaultPath,
                "adapterRepoPath": adapterRepoPath,
                "adapterRemote": "test",
                "adapterRef": "main",
                "adapterCommit": "test",
                "installerPath": "\(adapterRepoPath)/scripts/install.sh",
                "installedAt": timestamp,
                "verifiedAt": timestamp,
                "checks": [
                    "adapterSkillRouter": true,
                    "adapterSkillDailyTaskManager": true,
                    "adapterSkillDailyTaskPrep": true,
                    "goalsReadme": true,
                    "tasksReadme": true,
                    "resolverBlock": true,
                    "schemaBlock": true,
                    "agentsBlock": true,
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

    private func writeInstalledAdapterFiles(_ vault: URL) throws {
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/router", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-manager", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-prep", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("goals", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("tasks", isDirectory: true), withIntermediateDirectories: true)
        try "router\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/router/SKILL.md"), atomically: true, encoding: .utf8)
        try "manager\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-manager/SKILL.md"), atomically: true, encoding: .utf8)
        try "prep\n".write(to: vault.appendingPathComponent(".gbrain-adapter/skills/daily-task-prep/SKILL.md"), atomically: true, encoding: .utf8)
        try "goals\n".write(to: vault.appendingPathComponent("goals/README.md"), atomically: true, encoding: .utf8)
        try "tasks\n".write(to: vault.appendingPathComponent("tasks/README.md"), atomically: true, encoding: .utf8)
        for file in ["RESOLVER.md", "schema.md", "AGENTS.md"] {
            try """
            # \(file)

            <!-- gbrain-adapter:begin goals-tasks -->
            installed
            <!-- gbrain-adapter:end goals-tasks -->
            """.write(to: vault.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
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

    @discardableResult
    private func runRuntimeHelperFlow(
        helperURL: URL,
        root: URL,
        stateURL: URL,
        fakeBin: URL,
        runtime: String,
        provider: String,
        environment extraEnvironment: [String: String] = [:],
        secretPrompt: String? = nil,
        secretResponse: String? = nil,
        expectVerificationFailure: Bool = false
    ) throws -> (
        configure: (status: Int32, stdout: String, stderr: String),
        verify: (status: Int32, stdout: String, stderr: String),
        receipt: (status: Int32, stdout: String, stderr: String)?
    ) {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/expect") else {
            throw XCTSkip("expect is required to provide a TTY to runtime helper configure commands")
        }

        let expectScript = root.appendingPathComponent("configure-runtime.expect", isDirectory: false)
        var processEnvironment: [String: String] = [
            "TEST_PATH": "\(fakeBin.path):/usr/bin:/bin",
            "TEST_STATE": stateURL.path,
            "TEST_HOME": root.path,
            "TEST_HELPER": helperURL.path,
            "TEST_RUNTIME": runtime,
            "TEST_PROVIDER": provider,
        ]
        var extraTokens: [String] = []
        for (index, key) in extraEnvironment.keys.sorted().enumerated() {
            let envKey = "TEST_EXTRA_\(index)"
            processEnvironment[envKey] = "\(key)=\(extraEnvironment[key] ?? "")"
            extraTokens.append("$env(\(envKey))")
        }
        let promptBlock: String
        if let secretPrompt, let secretResponse {
            promptBlock = """
            expect "\(secretPrompt)"
            send "\(secretResponse)\\r"
            """
        } else {
            promptBlock = ""
        }
        let expectContent = """
        set timeout 20
        spawn env PATH=$env(TEST_PATH) ZEBRA_GBRAIN_RUNTIME_STATE=$env(TEST_STATE) ZEBRA_GBRAIN_RUNTIME_HOME=$env(TEST_HOME) ZEBRA_ONBOARDING_LANGUAGE=en \(extraTokens.joined(separator: " ")) $env(TEST_HELPER) configure-runtime $env(TEST_RUNTIME) --provider $env(TEST_PROVIDER)
        \(promptBlock)
        expect eof
        set result [wait]
        exit [lindex $result 3]
        """
        try expectContent.write(to: expectScript, atomically: true, encoding: .utf8)

        let configure = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/expect"),
            arguments: [expectScript.path],
            environment: processEnvironment
        )
        XCTAssertEqual(configure.status, 0, "stdout:\n\(configure.stdout)\nstderr:\n\(configure.stderr)")

        let helperEnvironment = [
            "PATH": "\(fakeBin.path):/usr/bin:/bin",
            "ZEBRA_GBRAIN_RUNTIME_STATE": stateURL.path,
            "ZEBRA_GBRAIN_RUNTIME_HOME": root.path,
            "ZEBRA_ONBOARDING_LANGUAGE": "en",
        ].merging(extraEnvironment) { _, new in new }

        let verify = try runProcess(
            executableURL: helperURL,
            arguments: ["verify-runtime", runtime],
            environment: helperEnvironment
        )
        if expectVerificationFailure {
            XCTAssertNotEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")
            return (configure, verify, nil)
        }
        XCTAssertEqual(verify.status, 0, "stdout:\n\(verify.stdout)\nstderr:\n\(verify.stderr)")

        let receipt = try runProcess(
            executableURL: helperURL,
            arguments: ["write-receipt"],
            environment: helperEnvironment
        )
        XCTAssertEqual(receipt.status, 0, "stdout:\n\(receipt.stdout)\nstderr:\n\(receipt.stderr)")
        return (configure, verify, receipt)
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

    private func installFakeRuntimeLogger(root: URL, name: String, log: URL) throws -> URL {
        let directory = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(name, isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo '\(name) test'
          exit 0
        fi
        printf '%s\\n' "$*" >> '\(shellSingleQuoted(log.path))'
        exit 0
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func writeFakeGBrainSourceRepo(root: URL, name: String = "gbrain") throws -> URL {
        let repo = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        {"scripts":{"test":"true"}}
        """.write(
            to: repo.appendingPathComponent("package.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try """
        # INSTALL_FOR_AGENTS

        ## Step 1: Install GBrain
        Run setup.
        """.write(
            to: repo.appendingPathComponent("INSTALL_FOR_AGENTS.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("skills", isDirectory: true),
            withIntermediateDirectories: true
        )
        return repo
    }

    private func installFakeCommand(directory: URL, name: String, content: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(name, isDirectory: false)
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    private func installFakeNodeInstallerCommands(fakeBin: URL, openLog: URL) throws {
        try installFakeCommand(
            directory: fakeBin,
            name: "curl",
            content: """
            #!/bin/sh
            output=
            while [ "$#" -gt 0 ]; do
              if [ "$1" = "-o" ]; then
                shift
                output="$1"
              fi
              shift || break
            done
            : > "$output"
            exit 0
            """
        )
        try installFakeCommand(
            directory: fakeBin,
            name: "open",
            content: """
            #!/bin/sh
            printf '%s\\n' "$*" >> '\(shellSingleQuoted(openLog.path))'
            exit 0
            """
        )
    }

    private func nodeInstallerOpenCount(_ openLog: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: openLog.path) else { return 0 }
        return try String(contentsOf: openLog, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .count
    }

    private static func runtimeOnboardingDocumentURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("zebra-gbrain-runtime-agent-onboarding.md", isDirectory: false)
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
        if [ "$1" = "models" ] && [ "$2" = "set" ]; then
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

    private func installFakeNotionCLI(fakeBin: URL, logURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let script = fakeBin.appendingPathComponent("ntn", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(shellSingleQuoted(logURL.path))'
        if [ "$1" = "--version" ]; then
          echo "ntn 1.0.0"
          exit 0
        fi
        if [ "$1" = "pages" ] && [ "$2" = "get" ]; then
          echo '{"id":"page123","title":"Test Page","oauth_code":"ABCDEFGH","code":"12345678"}'
          exit 0
        fi
        if [ "$1" = "datasources" ] && [ "$2" = "query" ]; then
          echo '{"results":[{"id":"row1","title":"Row"}]}'
          exit 0
        fi
        if [ "$1" = "api" ] && [ "$2" = "v1/search" ]; then
          echo '{"results":[{"id":"page123","object":"page","title":"Test Page"}]}'
          exit 0
        fi
        exit 1
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func installFakeMemoCLI(fakeBin: URL, logURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let script = fakeBin.appendingPathComponent("memo", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(shellSingleQuoted(logURL.path))'
        if [ "$1" = "--version" ]; then
          echo "memo 0.5.2"
          exit 0
        fi
        if [ "$1" = "notes" ]; then
          args="$*"
          case "$args" in
            *"-v 7"*)
              printf '%s\\n' "KakaoVentures VC framework" "" "- Team quality" "- Market timing" "- Founder insight"
              exit 0
              ;;
            *"-v "*)
              note_id="${args##* -v }"
              echo "Generated overflow note $note_id"
              exit 0
              ;;
            *"-f Overflow"*)
              echo "Overflow"
              i=1
              while [ "$i" -le 25 ]; do
                echo "  $i. Generated overflow note $i"
                i=$((i + 1))
              done
              exit 0
              ;;
            *"-fl"*|*" -f "*|*" -s "*|"notes")
              printf '%s\\n' "Work" "  7. KakaoVentures VC framework" "  8. Zebra onboarding note" "Personal" "  9. Grocery memo"
              exit 0
              ;;
          esac
        fi
        echo "unsupported memo args: $*" >&2
        exit 1
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func installFakeRemindctlCLI(fakeBin: URL, logURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let script = fakeBin.appendingPathComponent("remindctl", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(shellSingleQuoted(logURL.path))'
        if [ "$1" = "--version" ]; then
          echo "remindctl 0.3.2"
          exit 0
        fi
        if [ "$1" = "status" ]; then
          echo '{"status":"full-access"}'
          exit 0
        fi
        if [ "$1" = "doctor" ]; then
          echo 'Reminders access OK'
          exit 0
        fi
        if [ "$1" = "authorize" ]; then
          exit 0
        fi
        if [ "$1" = "list" ] && [ "$2" = "--json" ]; then
          echo '[{"id":"list-work","title":"Work","reminderCount":3,"overdueCount":1},{"id":"list-home","title":"Home","reminderCount":0,"overdueCount":0}]'
          exit 0
        fi
        if [ "$1" = "list" ] && [ "$2" = "Work" ] && [ "$3" = "--json" ]; then
          echo '[{"id":"done-1","title":"Completed task","list":"Work","completed":true}]'
          exit 0
        fi
        if [ "$1" = "open" ] && [ "$2" = "--json" ]; then
          echo '[{"id":"r1","title":"Investor update","list":"Work","dueDate":"2026-07-08","completed":false},{"id":"r2","title":"Review metrics","list":"Work","completed":false}]'
          exit 0
        fi
        if [ "$1" = "open" ] && [ "$2" = "--list" ] && [ "$3" = "Work" ] && [ "$4" = "--json" ]; then
          echo '[{"id":"r1","title":"Investor update","list":"Work","dueDate":"2026-07-08","completed":false},{"id":"r2","title":"Review metrics","list":"Work","completed":false,"url":"https://example.com"}]'
          exit 0
        fi
        if [ "$1" = "today" ] || [ "$1" = "overdue" ] || [ "$1" = "week" ]; then
          echo '[]'
          exit 0
        fi
        echo "unsupported remindctl args: $*" >&2
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
