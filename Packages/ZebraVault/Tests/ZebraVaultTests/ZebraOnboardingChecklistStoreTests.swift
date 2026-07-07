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
        XCTAssertTrue(line.contains("GBrain write target path (not an Obsidian source vault)"), line)
        XCTAssertTrue(line.contains("GBrain target context"), line)
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
        XCTAssertTrue(line.contains("Gmail, Obsidian, iMessage, and Notion runners"), line)
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
        XCTAssertTrue(line.contains("audit-openclaw-config --event 'openclaw.source_onboarding.launch.starting' --executable '/tmp/openclaw'"), line)
        XCTAssertTrue(line.contains("'/tmp/openclaw' tui --message \"$ZEBRA_SOURCE_ONBOARDING_PROMPT\""), line)
        XCTAssertTrue(line.contains("audit-openclaw-config --event 'openclaw.source_onboarding.launch.finished' --executable '/tmp/openclaw'"), line)
        XCTAssertTrue(line.contains("exit $_ZEBRA_SOURCE_ONBOARDING_OPENCLAW_STATUS"), line)
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

    func testSourceOnboardingRuntimeLaunchPlanExposesReplayMetadataForOpenClaw() throws {
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

        let plan = try XCTUnwrap(ZebraSourceOnboardingRuntimeLaunchPlan.make(
            launch: launch,
            runtime: runtime,
            prompt: "source onboarding prompt",
            language: .en,
            runID: "Source Replay Run 001"
        ))

        XCTAssertEqual(plan.runtime, .openclaw)
        XCTAssertEqual(plan.openClawAgentWorkspace, launch.launchDirectory)
        XCTAssertEqual(plan.openClawAgentID, "zebra-source-replay-source-replay-run-001")
        XCTAssertEqual(
            plan.openClawSessionKey,
            "agent:zebra-source-replay-source-replay-run-001:Source Replay Run 001"
        )
        XCTAssertNil(plan.hermesSessionID)
        XCTAssertTrue(plan.terminalStartupLine.contains("audit-openclaw-config --event 'openclaw.source_onboarding.launch.starting' --executable '/tmp/openclaw'"), plan.terminalStartupLine)
        XCTAssertTrue(plan.terminalStartupLine.contains("'/tmp/openclaw' tui --message \"$ZEBRA_SOURCE_ONBOARDING_PROMPT\""), plan.terminalStartupLine)
        XCTAssertTrue(plan.terminalStartupLine.contains("audit-openclaw-config --event 'openclaw.source_onboarding.launch.finished' --executable '/tmp/openclaw'"), plan.terminalStartupLine)
        XCTAssertFalse(plan.terminalStartupLine.contains("--local"), plan.terminalStartupLine)
        XCTAssertFalse(plan.terminalStartupLine.contains("--session"), plan.terminalStartupLine)
        XCTAssertFalse(plan.terminalStartupLine.contains("source onboarding prompt"), plan.terminalStartupLine)
        let prompt = try String(contentsOfFile: plan.promptPath, encoding: .utf8)
        XCTAssertTrue(prompt.contains("source onboarding prompt"), prompt)
    }

    func testSourceOnboardingPrepareLaunchInstallsReplayHelper() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("source-onboarding-state.json", isDirectory: false)
        let helper = ZebraSourceOnboardingHelper(
            stateURL: stateURL,
            gbrainOnboardingStateURL: root.appendingPathComponent("gbrain.json"),
            gbrainAdapterOnboardingStateURL: root.appendingPathComponent("adapter.json"),
            homeDirectoryPath: root.path
        )

        let launch = try XCTUnwrap(helper.prepareLaunch(selectedVaultPath: nil))
        let replayHelper = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("bin/zebra-source-replay", isDirectory: false)

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: replayHelper.path))
        XCTAssertTrue(launch.shellEnvironmentPrefix.contains("ZEBRA_SOURCE_ONBOARDING_STATE"))
    }

    func testSourceOnboardingHelperAuditsOpenClawConfigWithoutSecrets() throws {
        let root = try makeTemporaryDirectory()
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("source-onboarding-state.json", isDirectory: false)
        let openClawHome = root.appendingPathComponent(".openclaw", isDirectory: true)
        try FileManager.default.createDirectory(at: openClawHome, withIntermediateDirectories: true)
        try """
        {
          "gateway": {
            "mode": "local",
            "auth": {
              "token": "secret-token-123"
            }
          },
          "agents": []
        }
        """.write(
            to: openClawHome.appendingPathComponent("openclaw.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: root.appendingPathComponent("gbrain.json"),
                gbrainAdapterOnboardingStateURL: root.appendingPathComponent("adapter.json"),
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: nil)
        )
        let helperURL = URL(fileURLWithPath: launch.helperPath)

        let result = try runProcess(
            executableURL: helperURL,
            arguments: [
                "audit-openclaw-config",
                "--event", "unit.openclaw.audit",
                "--executable", "/tmp/openclaw",
            ],
            environment: [
                "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            ]
        )
        let payload = try jsonObject(from: result.stdout)
        let logURL = stateURL.deletingLastPathComponent().appendingPathComponent("openclaw-config-audit.jsonl", isDirectory: false)
        let audit = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["event"] as? String, "unit.openclaw.audit")
        XCTAssertEqual(payload["logPath"] as? String, logURL.path)
        XCTAssertTrue(audit.contains("\"event\": \"unit.openclaw.audit\""), audit)
        XCTAssertTrue(audit.contains("\"gatewayPresent\": true"), audit)
        XCTAssertTrue(audit.contains("\"gatewayMode\": \"local\""), audit)
        XCTAssertTrue(audit.contains("\"gatewayTokenPresent\": true"), audit)
        XCTAssertFalse(audit.contains("secret-token-123"), audit)
    }

    func testSourceReplayHelperTopLevelHelpExitsSuccessfully() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())

        for arguments in [["--help"], ["-h"], ["help"]] {
            let result = try runProcess(
                executableURL: helper,
                arguments: arguments,
                environment: [:]
            )

            XCTAssertEqual(result.status, 0, "arguments: \(arguments)\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
            XCTAssertTrue(result.stdout.contains("usage: zebra-source-replay <probe|run|batch|test>"), result.stdout)
            XCTAssertTrue(result.stdout.contains("commands:"), result.stdout)
            XCTAssertTrue(result.stderr.isEmpty, result.stderr)
        }
    }

    func testSourceReplayHelperUnknownTopLevelCommandFails() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())

        let result = try runProcess(
            executableURL: helper,
            arguments: ["unknown-command"],
            environment: [:]
        )

        XCTAssertEqual(result.status, 2, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertTrue(result.stderr.contains("usage: zebra-source-replay <probe|run|batch|test>"), result.stderr)
    }

    func testSourceReplayHelperRunWritesOpenClawArtifactsAndRedactsSecrets() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeOpenClaw = try installFakeSourceReplayRuntime(root: root, name: "openclaw")
        let fakeOpenClawHome = try makeFakeOpenClawHome(root: root)
        let fixture = root.appendingPathComponent("fixture.json", isDirectory: false)
        try """
        {
          "schemaVersion": 1,
          "source": "obsidian",
          "playbookID": "obsidian.direct-markdown",
          "playbookVersion": "v1",
          "interventions": [
            {
              "playbookStepId": "confirm_vault_if_needed",
              "matcher": {
                "type": "contains",
                "text": "vault path"
              },
              "answer": "/Users/hanwool/TestVault token sk-test-1234567890",
              "approval": "storable",
              "secretPolicy": "forbid_raw_secret"
            }
          ]
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "run",
                "--runtime", "openclaw",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "openclaw-success",
                "--fixture", fixture.path,
                "--openclaw-executable", fakeOpenClaw.path,
                "--openclaw-home", fakeOpenClawHome.path,
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)
        let runDirectory = URL(fileURLWithPath: try XCTUnwrap(payload["runDirectory"] as? String), isDirectory: true)
        let summary = try jsonObject(at: runDirectory.appendingPathComponent("run-summary.json", isDirectory: false))
        let openClaw = try XCTUnwrap(summary["openClaw"] as? [String: Any])

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(summary["ok"] as? Bool, true)
        XCTAssertEqual(summary["command"] as? String, "run")
        XCTAssertEqual(summary["source"] as? String, "obsidian")
        XCTAssertEqual(summary["playbookID"] as? String, "obsidian.direct-markdown")
        XCTAssertEqual(summary["playbookVersion"] as? String, "v1")
        XCTAssertEqual(summary["exitReason"] as? String, "completed")
        XCTAssertEqual(summary["interventionCount"] as? Int, 1)
        XCTAssertEqual((summary["unansweredInterventions"] as? [[String: Any]])?.count, 0)
        XCTAssertTrue((openClaw["agentID"] as? String)?.hasPrefix("zebra-source-replay-") == true)
        XCTAssertTrue((openClaw["sessionKey"] as? String)?.hasPrefix("agent:") == true)
        XCTAssertEqual(openClaw["workspace"] as? String, runDirectory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("replay-manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("fixture.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("prompt.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("transcript.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("intervention-events.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("openclaw-config-audit.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("helper-output/turn-001-stdout.txt").path))
        let events = try String(contentsOf: runDirectory.appendingPathComponent("intervention-events.jsonl"), encoding: .utf8)
        XCTAssertTrue(events.contains("\"event\": \"playbook.step.observed\""), events)
        XCTAssertTrue(events.contains("\"sourceOfTruth\": \"state+helper_stdout_next_prompt\""), events)
        XCTAssertTrue(events.contains("\"event\": \"fixture.intervention.applied\""), events)
        XCTAssertTrue(events.contains("\"playbookStepID\": \"confirm_vault_if_needed\""), events)
        XCTAssertTrue(events.contains("\"matcherResult\": \"matched\""), events)
        let audit = try String(contentsOf: runDirectory.appendingPathComponent("openclaw-config-audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"event\": \"openclaw.source_config.watch_started\""), audit)
        XCTAssertTrue(audit.contains("\"event\": \"openclaw.agents.add.starting\""), audit)
        XCTAssertTrue(audit.contains("\"event\": \"openclaw.agent.turn.finished\""), audit)
        let sanitizer = try XCTUnwrap(summary["sanitizer"] as? [String: Any])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sanitizer["redactedCount"] as? Int), 1)
        XCTAssertFalse(try directory(runDirectory, contains: "sk-test-1234567890"))
        XCTAssertFalse(try directory(runDirectory, contains: "refresh_token"))
        XCTAssertFalse(try directory(runDirectory, contains: "authorization_code"))
    }

    func testSourceReplayHelperRunUsesIsolatedOpenClawHomeCopy() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeOpenClaw = try installFakeSourceReplayRuntime(root: root, name: "openclaw")
        let sourceOpenClawHome = root.appendingPathComponent("source-openclaw", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceOpenClawHome, withIntermediateDirectories: true)
        let sourceConfig = sourceOpenClawHome.appendingPathComponent("openclaw.json", isDirectory: false)
        let sourceConfigContent = """
        {
          "gateway": {
            "auth": {
              "mode": "token",
              "token": "raw-replay-token-should-stay-out-of-artifacts"
            },
            "mode": "local",
            "port": 18789
          },
          "models": {
            "default": "openai/gpt-5.5"
          }
        }
        """
        try sourceConfigContent.write(to: sourceConfig, atomically: true, encoding: .utf8)
        let fixture = root.appendingPathComponent("fixture.json", isDirectory: false)
        try """
        {
          "schemaVersion": 1,
          "source": "obsidian",
          "playbookID": "obsidian.direct-markdown",
          "playbookVersion": "v1",
          "interventions": [
            {
              "playbookStepId": "confirm_vault_if_needed",
              "matcher": {
                "type": "contains",
                "text": "vault path"
              },
              "answer": "sample",
              "approval": "storable"
            }
          ]
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "run",
                "--runtime", "openclaw",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "openclaw-isolated-home",
                "--fixture", fixture.path,
                "--openclaw-executable", fakeOpenClaw.path,
                "--openclaw-home", sourceOpenClawHome.path,
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)
        let runDirectory = URL(fileURLWithPath: try XCTUnwrap(payload["runDirectory"] as? String), isDirectory: true)
        let summary = try jsonObject(at: runDirectory.appendingPathComponent("run-summary.json", isDirectory: false))
        let openClaw = try XCTUnwrap(summary["openClaw"] as? [String: Any])
        let isolatedHome = URL(fileURLWithPath: try XCTUnwrap(openClaw["isolatedHome"] as? String), isDirectory: true)
        let isolatedConfig = URL(fileURLWithPath: try XCTUnwrap(openClaw["configPath"] as? String), isDirectory: false)
        let stateDir = URL(fileURLWithPath: try XCTUnwrap(openClaw["stateDir"] as? String), isDirectory: true)
        let envLog = try String(contentsOf: runDirectory.appendingPathComponent("openclaw-env.jsonl"), encoding: .utf8)

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(summary["ok"] as? Bool, true)
        XCTAssertEqual(try String(contentsOf: sourceConfig, encoding: .utf8), sourceConfigContent)
        XCTAssertNotEqual(isolatedHome.path, sourceOpenClawHome.path)
        XCTAssertTrue(isolatedHome.path.contains("/replay/openclaw-home/unit/openclaw-isolated-home"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolatedConfig.path))
        XCTAssertEqual(stateDir.path, isolatedHome.path)
        XCTAssertTrue(envLog.contains("OPENCLAW_HOME"))
        XCTAssertTrue(envLog.contains(isolatedHome.path), envLog)
        XCTAssertTrue(envLog.contains(isolatedConfig.path), envLog)
        XCTAssertFalse(envLog.contains(sourceOpenClawHome.path), envLog)
        XCTAssertTrue(envLog.contains(#""hasGatewayToken": true"#), envLog)
        let audit = try String(contentsOf: runDirectory.appendingPathComponent("openclaw-config-audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"gatewayTokenPresent\": true"), audit)
        XCTAssertTrue(audit.contains("\"event\": \"openclaw.isolation.prepared\""), audit)
        XCTAssertFalse(try directory(runDirectory, contains: "raw-replay-token-should-stay-out-of-artifacts"))
    }

    func testSourceReplayHelperRunUsesBundledObsidianBaselineFixtureAnswerEnv() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeOpenClaw = try installFakeSourceReplayRuntime(root: root, name: "openclaw")
        let fakeOpenClawHome = try makeFakeOpenClawHome(root: root)
        let fixture = sourceReplayFixtureURL("obsidian.direct-markdown.baseline.v1.json")
        let vaultPath = root.appendingPathComponent("TestVault", isDirectory: true).path

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "run",
                "--runtime", "openclaw",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "obsidian-baseline-env",
                "--fixture", fixture.path,
                "--openclaw-executable", fakeOpenClaw.path,
                "--openclaw-home", fakeOpenClawHome.path,
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [
                "ZEBRA_REPLAY_OBSIDIAN_VAULT_PATH": vaultPath,
            ]
        )
        let payload = try jsonObject(from: result.stdout)
        let runDirectory = URL(fileURLWithPath: try XCTUnwrap(payload["runDirectory"] as? String), isDirectory: true)
        let fixtureArtifact = try String(contentsOf: runDirectory.appendingPathComponent("fixture.json"), encoding: .utf8)

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["source"] as? String, "obsidian")
        XCTAssertEqual(payload["playbookID"] as? String, "obsidian.direct-markdown")
        XCTAssertEqual(payload["playbookVersion"] as? String, "v1")
        XCTAssertTrue(fixtureArtifact.contains("ZEBRA_REPLAY_OBSIDIAN_VAULT_PATH"), fixtureArtifact)
        XCTAssertFalse(fixtureArtifact.contains(vaultPath), fixtureArtifact)
    }

    func testSourceReplayHelperRunStopsWhenFixtureAnswerEnvIsMissing() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeOpenClaw = try installFakeSourceReplayRuntime(root: root, name: "openclaw")
        let fakeOpenClawHome = try makeFakeOpenClawHome(root: root)
        let fixture = sourceReplayFixtureURL("obsidian.direct-markdown.baseline.v1.json")

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "run",
                "--runtime", "openclaw",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "obsidian-baseline-missing-env",
                "--fixture", fixture.path,
                "--openclaw-executable", fakeOpenClaw.path,
                "--openclaw-home", fakeOpenClawHome.path,
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)
        let runDirectory = URL(fileURLWithPath: try XCTUnwrap(payload["runDirectory"] as? String), isDirectory: true)
        let events = try String(contentsOf: runDirectory.appendingPathComponent("intervention-events.jsonl"), encoding: .utf8)
        let unanswered = try XCTUnwrap(payload["unansweredInterventions"] as? [[String: Any]])

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["exitReason"] as? String, "fixture_answer_env_missing")
        XCTAssertEqual(unanswered.first?["playbookStepID"] as? String, "confirm_vault_if_needed")
        XCTAssertEqual(unanswered.first?["answerEnv"] as? String, "ZEBRA_REPLAY_OBSIDIAN_VAULT_PATH")
        XCTAssertTrue(events.contains("\"event\": \"fixture.intervention.missing_answer_env\""), events)
        XCTAssertFalse(events.contains("\"event\": \"fixture.intervention.applied\""), events)
    }

    func testSourceReplayHelperTestUsesSelectedHermesRuntimeForAppleNotesScenario() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeHermes = try installFakeSourceReplayRuntime(
            root: root,
            name: "hermes",
            firstStep: "choose_ingest_scope",
            source: "apple-notes",
            playbookID: "apple-notes.memo-cli"
        )
        let fakeMemo = try installFakeMemo(root: root)
        try writeSelectedRuntimeReceipt(root: root, runtime: "hermes", executable: fakeHermes)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "test",
                "apple-notes.memo-cli.baseline",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "apple-notes-hermes",
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [
                "PATH": fakeMemo.deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
            ]
        )
        let payload = try jsonObject(from: result.stdout)
        let runSummary = try XCTUnwrap(payload["runSummary"] as? [String: Any])
        let artifactScan = try XCTUnwrap(payload["artifactScan"] as? [String: Any])

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["command"] as? String, "test")
        XCTAssertEqual(payload["scenarioID"] as? String, "apple-notes.memo-cli.baseline")
        XCTAssertEqual(payload["runtime"] as? String, "hermes")
        XCTAssertEqual(runSummary["source"] as? String, "apple-notes")
        XCTAssertEqual(runSummary["playbookID"] as? String, "apple-notes.memo-cli")
        XCTAssertEqual(runSummary["interventionCount"] as? Int, 2)
        XCTAssertEqual(artifactScan["ok"] as? Bool, true)
        XCTAssertNotNil(payload["summaryPath"] as? String)
    }

    func testSourceReplayHelperTestUsesSelectedOpenClawRuntimeForAppleNotesScenario() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeOpenClaw = try installFakeSourceReplayRuntime(
            root: root,
            name: "openclaw",
            firstStep: "choose_ingest_scope",
            source: "apple-notes",
            playbookID: "apple-notes.memo-cli"
        )
        let fakeOpenClawHome = try makeFakeOpenClawHome(root: root)
        let fakeMemo = try installFakeMemo(root: root)
        let sourceConfig = fakeOpenClawHome.appendingPathComponent("openclaw.json", isDirectory: false)
        let sourceConfigContent = try String(contentsOf: sourceConfig, encoding: .utf8)
        try writeSelectedRuntimeReceipt(root: root, runtime: "openclaw", executable: fakeOpenClaw)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "test",
                "apple-notes.memo-cli.baseline",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "apple-notes-openclaw",
                "--openclaw-home", fakeOpenClawHome.path,
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [
                "PATH": fakeMemo.deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
            ]
        )
        let payload = try jsonObject(from: result.stdout)
        let runSummary = try XCTUnwrap(payload["runSummary"] as? [String: Any])
        let runDirectory = URL(fileURLWithPath: try XCTUnwrap(runSummary["runDirectory"] as? String), isDirectory: true)
        let openClawConfig = try XCTUnwrap(payload["openClawOriginalConfig"] as? [String: Any])
        let events = try String(contentsOf: runDirectory.appendingPathComponent("intervention-events.jsonl"), encoding: .utf8)

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["runtime"] as? String, "openclaw")
        XCTAssertEqual(openClawConfig["unchanged"] as? Bool, true)
        XCTAssertTrue(events.contains("\"event\": \"source.preflight.command\""), events)
        XCTAssertTrue(events.contains("\"id\": \"apple-notes.memo-automation-access\""), events)
        XCTAssertEqual(try String(contentsOf: sourceConfig, encoding: .utf8), sourceConfigContent)
    }

    func testSourceReplayHelperTestStopsBeforeRuntimeWhenSourcePreflightFails() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeHermes = try installFakeSourceReplayRuntime(
            root: root,
            name: "hermes",
            firstStep: "choose_ingest_scope",
            source: "apple-notes",
            playbookID: "apple-notes.memo-cli"
        )
        let fakeMemo = try installFakeMemo(root: root, mode: "fail")
        try writeSelectedRuntimeReceipt(root: root, runtime: "hermes", executable: fakeHermes)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "test",
                "apple-notes.memo-cli.baseline",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "apple-notes-preflight-fails",
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [
                "PATH": fakeMemo.deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
            ]
        )
        let payload = try jsonObject(from: result.stdout)
        let runSummary = try XCTUnwrap(payload["runSummary"] as? [String: Any])
        let preflight = try XCTUnwrap(runSummary["preflight"] as? [String: Any])
        let commands = try XCTUnwrap(preflight["commands"] as? [[String: Any]])

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(runSummary["exitReason"] as? String, "notes_automation_permission_required")
        XCTAssertEqual(preflight["ok"] as? Bool, false)
        XCTAssertEqual(commands.first?["id"] as? String, "apple-notes.memo-automation-access")
        XCTAssertEqual(commands.first?["exitCode"] as? Int, 13)
    }

    func testSourceReplayHelperTestFailsWhenSelectedRuntimeReceiptIsMissing() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "test",
                "apple-notes.memo-cli.baseline",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["reason"] as? String, "selected_runtime_missing")
        XCTAssertEqual(payload["scenarioID"] as? String, "apple-notes.memo-cli.baseline")
    }

    func testSourceReplayHelperTestFailsForUnknownScenario() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())

        let result = try runProcess(
            executableURL: helper,
            arguments: ["test", "missing.scenario"],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["reason"] as? String, "unknown_scenario")
    }

    func testSourceReplayHelperRunWritesHermesResumeArtifacts() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeHermes = try installFakeSourceReplayRuntime(root: root, name: "hermes")
        let fixture = root.appendingPathComponent("fixture.json", isDirectory: false)
        try """
        {
          "schemaVersion": 1,
          "source": "obsidian",
          "playbookID": "obsidian.direct-markdown",
          "playbookVersion": "v1",
          "interventions": [
            {
              "playbookStepId": "confirm_vault_if_needed",
              "matcher": {
                "type": "contains",
                "text": "vault path"
              },
              "answer": "sample",
              "approval": "storable"
            }
          ]
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "run",
                "--runtime", "hermes",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "hermes-success",
                "--fixture", fixture.path,
                "--hermes-executable", fakeHermes.path,
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)
        let hermes = try XCTUnwrap(payload["hermes"] as? [String: Any])

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["runtime"] as? String, "hermes")
        XCTAssertEqual(payload["exitReason"] as? String, "completed")
        XCTAssertEqual(hermes["sessionID"] as? String, "fake-hermes-session")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(hermes["resumeCount"] as? Int), 1)
    }

    func testSourceReplayHelperRunStopsWhenFixtureDoesNotCoverObservedStep() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeOpenClaw = try installFakeSourceReplayRuntime(root: root, name: "openclaw", firstStep: "choose_ingest_scope")
        let fakeOpenClawHome = try makeFakeOpenClawHome(root: root)
        let fixture = root.appendingPathComponent("fixture.json", isDirectory: false)
        try """
        {
          "schemaVersion": 1,
          "source": "obsidian",
          "playbookID": "obsidian.direct-markdown",
          "playbookVersion": "v1",
          "interventions": [
            {
              "playbookStepId": "confirm_vault_if_needed",
              "matcher": {
                "type": "contains",
                "text": "vault path"
              },
              "answer": "/Users/hanwool/TestVault",
              "approval": "storable"
            }
          ]
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "run",
                "--runtime", "openclaw",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "openclaw-needs-human",
                "--fixture", fixture.path,
                "--openclaw-executable", fakeOpenClaw.path,
                "--openclaw-home", fakeOpenClawHome.path,
                "--timeout", "5",
                "--max-turns", "4",
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)
        let unanswered = try XCTUnwrap(payload["unansweredInterventions"] as? [[String: Any]])

        XCTAssertEqual(result.status, 1, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["exitReason"] as? String, "needs_human_intervention")
        XCTAssertEqual(unanswered.first?["source"] as? String, "obsidian")
        XCTAssertEqual(unanswered.first?["playbookStepID"] as? String, "choose_ingest_scope")
    }

    func testSourceReplayHelperBatchWritesSummaryForMultipleRuns() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeHermes = try installFakeSourceReplayRuntime(root: root, name: "hermes")
        let fixture = root.appendingPathComponent("fixture.json", isDirectory: false)
        try """
        {
          "schemaVersion": 1,
          "source": "obsidian",
          "playbookID": "obsidian.direct-markdown",
          "playbookVersion": "v1",
          "interventions": [
            {
              "playbookStepId": "confirm_vault_if_needed",
              "matcher": {
                "type": "contains",
                "text": "vault path"
              },
              "answer": "sample",
              "approval": "storable"
            }
          ]
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)

        let rootReplay = root.appendingPathComponent("replay", isDirectory: true)
        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "batch",
                "--runtime", "hermes",
                "--root", rootReplay.path,
                "--batch-id", "batch-unit",
                "--fixture", fixture.path,
                "--hermes-executable", fakeHermes.path,
                "--timeout", "5",
                "--max-turns", "4",
                "--run-count", "2",
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)
        let summaryURL = rootReplay
            .appendingPathComponent("batch", isDirectory: true)
            .appendingPathComponent("batch-unit", isDirectory: true)
            .appendingPathComponent("batch-summary.json", isDirectory: false)
        let summary = try jsonObject(at: summaryURL)

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(summary["command"] as? String, "batch")
        XCTAssertEqual(summary["runCount"] as? Int, 2)
        XCTAssertEqual(summary["completedCount"] as? Int, 2)
        XCTAssertEqual(summary["failedCount"] as? Int, 0)
    }

    func testSourceReplayHelperHermesProbeReadsSessionIDFromStderr() throws {
        let root = try makeTemporaryDirectory()
        let helper = try XCTUnwrap(ZebraSourceReplayRunner(onboardingDirectory: root).installHelperScript())
        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let fakeHermes = fakeBin.appendingPathComponent("hermes", isDirectory: false)
        let script = """
        #!/bin/sh
        if [ "$1" = "chat" ]; then
          case "$*" in
            *"--resume 20260706_fake"*"The color is blue"*)
              echo 'RECORDED_COLOR=blue'
              echo 'REMEMBERED_PREVIOUS_QUESTION=yes'
              exit 0
              ;;
            *"--resume 20260706_fake"*)
              echo 'HELPER_CWD='"$(pwd)"
              echo 'HELPER_MARKER=hermes-helper'
              echo 'HELPER_ARG=hermes-arg'
              exit 0
              ;;
            *)
              echo 'session_id: 20260706_fake' >&2
              echo 'Current working directory: '"$(pwd)"
              echo 'ZEBRA_REPLAY_PROBE_TOKEN: '"${ZEBRA_REPLAY_PROBE_TOKEN:-missing}"
              cat probe.txt
              echo 'QUESTION: What color should I record?'
              exit 0
              ;;
          esac
        fi
        exit 1
        """
        try script.write(to: fakeHermes, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHermes.path)

        let result = try runProcess(
            executableURL: helper,
            arguments: [
                "probe",
                "--runtime", "hermes",
                "--root", root.appendingPathComponent("replay", isDirectory: true).path,
                "--batch-id", "unit",
                "--run-id", "hermes-stderr",
                "--timeout", "5",
                "--hermes-executable", fakeHermes.path,
            ],
            environment: [:]
        )
        let payload = try jsonObject(from: result.stdout)

        XCTAssertEqual(result.status, 0, "stdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertEqual(payload["runtime"] as? String, "hermes")
        XCTAssertEqual(payload["sessionID"] as? String, "20260706_fake")
        let checks = try XCTUnwrap(payload["checks"] as? [String: Bool])
        XCTAssertEqual(checks["helperCommandEnv"], true)
        XCTAssertEqual(checks["multiTurnMemory"], true)
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
            rawSourceInput: "gmail, slack, apple notes, 애플 리마인더, obsidian"
        )

        XCTAssertEqual(result.normalizedSourceList, ["gmail", "obsidian"])
        XCTAssertEqual(
            result.uncatalogedSources.map(\.normalizedValue),
            ["slack", "apple-notes", "apple-reminders"]
        )
        XCTAssertEqual(
            Set(result.uncatalogedSources.map(\.reason)),
            ["not_in_current_catalog"]
        )
        XCTAssertEqual(result.confirmationPrompt, "Gmail, Slack, Apple Notes, Apple Reminders, Obsidian로 이해했습니다. 맞나요?")
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
            "지메일, 옵시디언, 슬랙도 있어",
            now: recordedAt
        )
        let persisted = try readSourceOnboardingState(at: stateURL)

        XCTAssertEqual(recorded, persisted)
        XCTAssertEqual(persisted.status, .attention)
        XCTAssertEqual(persisted.sourceReadiness.gmail.status, .ready)
        XCTAssertEqual(persisted.progress.rawSourceInput, "지메일, 옵시디언, 슬랙도 있어")
        XCTAssertEqual(persisted.progress.normalizedSourceList, ["gmail", "obsidian"])
        XCTAssertEqual(persisted.progress.uncatalogedSources.map(\.normalizedValue), ["slack"])
        XCTAssertEqual(persisted.progress.sourceConfirmation?.prompt, "Gmail, Obsidian, Slack로 이해했습니다. 맞나요?")
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
        XCTAssertEqual(persistedConfirmation.status, .attention)
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
                "--raw", "옵시디언, 지메일 슬랙",
                "--candidate", "obsidian=옵시디언",
                "--candidate", "gmail=지메일",
                "--uncataloged", "slack=슬랙",
            ],
            environment: environment
        )
        XCTAssertEqual(intake.status, 0, "stdout:\n\(intake.stdout)\nstderr:\n\(intake.stderr)")
        let intakePayload = try jsonObject(from: intake.stdout)
        XCTAssertEqual(intakePayload["normalizedSourceList"] as? [String], ["obsidian", "gmail"])
        XCTAssertEqual(intakePayload["uncatalogedSources"] as? [String], ["slack"])
        XCTAssertNil(intakePayload["unsupportedInputs"])
        XCTAssertEqual(intakePayload["sourceConfirmationStatus"] as? String, "pending")
        XCTAssertEqual(intakePayload["confirmationPrompt"] as? String, "Obsidian, Gmail, Slack로 이해했습니다. 맞나요?")

        let store = makeChecklistStore(homeURL: root)
        let loaded = try XCTUnwrap(store.loadSourceOnboardingState())
        XCTAssertEqual(loaded.status, .attention)
        XCTAssertEqual(loaded.progress.rawSourceInput, "옵시디언, 지메일 슬랙")
        XCTAssertEqual(loaded.progress.normalizedSourceList, ["obsidian", "gmail"])
        XCTAssertEqual(loaded.progress.uncatalogedSources.map(\.normalizedValue), ["slack"])
        XCTAssertEqual(loaded.progress.uncatalogedSources.first?.rawValue, "슬랙")
        XCTAssertEqual(loaded.progress.uncatalogedSources.first?.reason, "not_in_current_catalog")
        XCTAssertEqual(loaded.progress.sourceRows["obsidian"]?.selectionState, "pending_confirmation")
        XCTAssertEqual(loaded.progress.sourceRows["gmail"]?.selectionState, "pending_confirmation")
        XCTAssertNil(loaded.progress.sourceRows["slack"])
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
        XCTAssertEqual(uncataloged.first?["rawValue"] as? String, "슬랙")
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
        let slackSubstep = try XCTUnwrap(sourceSubsteps.first { $0.id == "uncataloged-source-slack" })
        XCTAssertNil(sourceSubsteps.first { $0.id == "gmail-readiness" })

        XCTAssertEqual(obsidianSubstep.title, "Obsidian")
        XCTAssertNil(obsidianSubstep.detail)
        XCTAssertFalse(obsidianSubstep.isCompleted)
        XCTAssertEqual(gmailSubstep.title, "Gmail")
        XCTAssertNil(gmailSubstep.detail)
        XCTAssertEqual(slackSubstep.title, "Slack")
        XCTAssertNil(slackSubstep.detail)
        XCTAssertTrue(slackSubstep.isAttention)

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
    func testSourceOnboardingHelperStatusRefreshesStaleAdapterReadiness() throws {
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
        try writeInstalledAdapterFiles(vault)
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
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staleState: [String: Any] = [
            "schemaVersion": 1,
            "status": "ready",
            "entryContext": [
                "onboardingLanguageCode": "ko",
                "gbrainTargetPath": vault.path,
                "gbrainTargetKey": "vault:\(vault.path)",
                "adapterReady": false,
                "adapterReadinessReasons": [],
            ],
            "progress": [
                "rawSourceInput": NSNull(),
                "normalizedSourceList": [],
                "uncatalogedSources": [],
                "sourceConfirmation": NSNull(),
                "executionOrder": NSNull(),
                "activeSourceID": NSNull(),
                "sourceRows": [:],
                "pendingQuestion": NSNull(),
            ],
            "updatedAt": "2026-06-04T00:00:00Z",
        ]
        let staleData = try JSONSerialization.data(withJSONObject: staleState, options: [.prettyPrinted, .sortedKeys])
        try staleData.write(to: stateURL, options: .atomic)

        let launch = try XCTUnwrap(
            ZebraSourceOnboardingHelper(
                stateURL: stateURL,
                gbrainOnboardingStateURL: gbrainStateURL,
                gbrainAdapterOnboardingStateURL: adapterStateURL,
                homeDirectoryPath: root.path
            ).prepareLaunch(selectedVaultPath: vault.path)
        )
        let status = try runProcess(
            executableURL: URL(fileURLWithPath: launch.helperPath),
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
        let state = try XCTUnwrap(payload["state"] as? [String: Any])
        let entryContext = try XCTUnwrap(state["entryContext"] as? [String: Any])
        XCTAssertEqual(entryContext["adapterReady"] as? Bool, true)
        XCTAssertEqual(entryContext["adapterReadinessReasons"] as? [String], [])
        let persisted = try jsonObject(at: stateURL)
        let persistedEntry = try XCTUnwrap(persisted["entryContext"] as? [String: Any])
        XCTAssertEqual(persistedEntry["adapterReady"] as? Bool, true)
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
        XCTAssertEqual(payload["nextPlaybookStepID"] as? String, "choose_scope")
        let nextPrompt = try XCTUnwrap(payload["nextPrompt"] as? String)
        XCTAssertTrue(nextPrompt.contains("Notion에서 GBrain에 가져올 대상을 정해주세요."), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("4. URL/ID를 모르면 Notion workspace 후보 찾기"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("5. Notion workspace 전체 가져오기"), nextPrompt)
        XCTAssertTrue(nextPrompt.contains("6. Notion 건너뛰기"), nextPrompt)

        let loaded = try readSourceOnboardingState(at: stateURL)
        XCTAssertEqual(loaded.progress.executionOrder, ["notion"])
        XCTAssertEqual(loaded.progress.activeSourceID, "notion")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.status, "running")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.phase, "preflight")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookID, "notion.ntn-cli")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookVersion, "v1")
        XCTAssertEqual(loaded.progress.sourceRows["notion"]?.playbookStepID, "choose_scope")
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
        let reportPrompt = try XCTUnwrap(reportPayload["nextPrompt"] as? String)
        XCTAssertPrompt(
            reportPrompt,
            contains: "Notion Source Onboarding is complete.",
            before: "Zebra Source Onboarding: Obsidian is the active source."
        )

        let activeAfterReport = try readSourceOnboardingState(at: stateURL).progress
        XCTAssertEqual(activeAfterReport.sourceRows["notion"]?.status, "checked")
        XCTAssertEqual(activeAfterReport.activeSourceID, "obsidian")

        let duplicateReport = try runProcess(
            executableURL: helperURL,
            arguments: ["report", "--status", "completed", "--source", "notion"],
            environment: environment
        )
        XCTAssertEqual(duplicateReport.status, 1, "stdout:\n\(duplicateReport.stdout)\nstderr:\n\(duplicateReport.stderr)")
        XCTAssertEqual(try jsonObject(from: duplicateReport.stdout)["reason"] as? String, "source_not_active")
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
        XCTAssertTrue(pendingPrompt.contains("zebra-source-onboarding report --status completed --source obsidian"), pendingPrompt)

        let pendingResume = try runProcess(
            executableURL: helperURL,
            arguments: ["next"],
            environment: environment
        )
        XCTAssertEqual(pendingResume.status, 0, "stdout:\n\(pendingResume.stdout)\nstderr:\n\(pendingResume.stderr)")
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
        XCTAssertTrue(reportPrompt.contains("Source Onboarding is complete"), reportPrompt)

        loaded = try readSourceOnboardingState(at: stateURL)
        row = try XCTUnwrap(loaded.progress.sourceRows["obsidian"])
        XCTAssertEqual(row.status, "checked")
        XCTAssertEqual(row.phase, "complete")
        XCTAssertEqual(row.playbookStepID, "complete")
        XCTAssertEqual(row.playbookID, "obsidian.direct-markdown")
        XCTAssertNotNil(row.resultSummary)
        XCTAssertNotNil(row.runStatePath)
        XCTAssertFalse(try String(contentsOf: stateURL, encoding: .utf8).contains("First note\\nBody"))
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

    private func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func directory(_ url: URL, contains needle: String) throws -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return false
        }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if text.contains(needle) {
                return true
            }
        }
        return false
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

    private func installFakeMemo(root: URL, mode: String = "ok") throws -> URL {
        let directory = root.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("memo", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "memo, version 0.6.0"
          exit 0
        fi
        if [ "\(mode)" = "fail" ]; then
          echo "memo automation denied" >&2
          exit 13
        fi
        if [ "$1" = "notes" ]; then
          echo "001. Replay fixture note"
          exit 0
        fi
        echo "unexpected memo args: $*" >&2
        exit 1
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func installFakeSourceReplayRuntime(
        root: URL,
        name: String,
        firstStep: String = "confirm_vault_if_needed",
        source: String = "obsidian",
        playbookID: String = "obsidian.direct-markdown"
    ) throws -> URL {
        let directory = root.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(name, isDirectory: false)
        let scriptContent = """
        #!/usr/bin/env python3
        import json
        import os
        import sys

        runtime = "\(name)"
        first_step = "\(firstStep)"
        source = "\(source)"
        playbook_id = "\(playbookID)"
        playbook_version = "v1"

        def prompt_for(step):
            if step == "confirm_vault_if_needed":
                return "Please provide the Obsidian vault path."
            if step == "choose_ingest_scope":
                return "Choose the ingest scope: folder, search query, selected note, small sample, or skip."
            if step == "confirm_ingest_plan":
                return "Confirm the ingest plan with explicit approval."
            if step == "complete":
                return "Source Onboarding is complete."
            return "Continue Source Onboarding."

        def write_state(step):
            path = os.environ.get("ZEBRA_SOURCE_ONBOARDING_STATE")
            if not path:
                return
            os.makedirs(os.path.dirname(path), exist_ok=True)
            state = {
                "progress": {
                    "sourceRows": {
                        source: {
                            "playbookID": playbook_id,
                            "playbookVersion": playbook_version,
                            "playbookStepID": step,
                            "status": "checked" if step == "complete" else "attention"
                        }
                    }
                }
            }
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(state, handle, sort_keys=True)

        def payload(step):
            return {
                "nextSourceID": source,
                "nextPlaybookID": playbook_id,
                "nextPlaybookVersion": playbook_version,
                "nextPlaybookStepID": step,
                "nextPrompt": prompt_for(step),
                "nextPromptPath": os.path.join(os.environ.get("ZEBRA_SOURCE_REPLAY_RUN_DIR", ""), "next-prompt.txt")
            }

        def record_openclaw_environment():
            if runtime != "openclaw":
                return
            run_dir = os.environ.get("ZEBRA_SOURCE_REPLAY_RUN_DIR")
            if not run_dir:
                return
            os.makedirs(run_dir, exist_ok=True)
            entry = {
                "command": " ".join(sys.argv[1:3]),
                "OPENCLAW_HOME": os.environ.get("OPENCLAW_HOME"),
                "OPENCLAW_CONFIG_PATH": os.environ.get("OPENCLAW_CONFIG_PATH"),
                "OPENCLAW_STATE_DIR": os.environ.get("OPENCLAW_STATE_DIR"),
                "hasGatewayToken": bool(os.environ.get("OPENCLAW_GATEWAY_TOKEN")),
            }
            with open(os.path.join(run_dir, "openclaw-env.jsonl"), "a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, sort_keys=True) + "\\n")

        def message_from_args():
            args = sys.argv
            if "--message" in args:
                return args[args.index("--message") + 1]
            if "-q" in args:
                return args[args.index("-q") + 1]
            return " ".join(args[1:])

        record_openclaw_environment()

        if runtime == "openclaw" and len(sys.argv) > 2 and sys.argv[1] == "agents" and sys.argv[2] == "add":
            print(json.dumps({"ok": True}))
            sys.exit(0)

        message = message_from_args()
        if source == "apple-notes":
            lowered = message.lower()
            if lowered.strip() in {"yes", "y"}:
                step = "complete"
            elif "sample" in lowered:
                step = "confirm_ingest_plan"
            else:
                step = first_step
        else:
            step = "complete" if ("TestVault" in message or "sample" in message or "sk-test" in message) else first_step
        write_state(step)
        current_payload = payload(step)

        if runtime == "openclaw":
            print(json.dumps({"result": {"payloads": [{"text": json.dumps(current_payload, sort_keys=True)}]}}))
        else:
            if "--resume" not in sys.argv:
                print("session_id: fake-hermes-session", file=sys.stderr)
            print(json.dumps(current_payload, sort_keys=True))
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func makeFakeOpenClawHome(root: URL, token: String = "fake-openclaw-gateway-token") throws -> URL {
        let home = root.appendingPathComponent("fake-openclaw-home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        {
          "gateway": {
            "auth": {
              "mode": "token",
              "token": "\(token)"
            },
            "mode": "local",
            "port": 18789
          },
          "models": {
            "default": "openai/gpt-5.5"
          }
        }
        """.write(to: home.appendingPathComponent("openclaw.json", isDirectory: false), atomically: true, encoding: .utf8)
        return home
    }

    private func writeSelectedRuntimeReceipt(root: URL, runtime: String, executable: URL) throws {
        try """
        {
          "schemaVersion": 1,
          "receipt": {
            "complete": true,
            "runtime": "\(runtime)",
            "executablePath": "\(executable.path)",
            "provider": "test",
            "keySource": "test",
            "checks": {
              "credentials": true,
              "runtimeConfigCommand": true,
              "llmCall": true
            }
          }
        }
        """.write(
            to: root.appendingPathComponent("gbrain-runtime-state.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
    }

    private func sourceReplayFixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ZebraVault/Resources/SourceReplayFixtures", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
            .standardizedFileURL
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
