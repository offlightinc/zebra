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
            [.agent, .gbrainRuntime, .gbrain, .adapter, .email]
        )
        XCTAssertEqual(store.snapshots.map { $0.number }, [1, 2, 3, 4, 5])
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
    func testDevelopmentToggleCanForceCompletedRuntimeStepIncomplete() throws {
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

        store.developmentToggleStepCompleted(.gbrainRuntime)

        XCTAssertFalse(
            store.completedStepIDs.contains(.gbrainRuntime),
            "DEBUG manual toggle should be able to force a receipt-completed step back to incomplete."
        )

        store.developmentToggleStepCompleted(.gbrainRuntime)

        XCTAssertTrue(store.completedStepIDs.contains(.gbrainRuntime))
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
        XCTAssertEqual(beforeStart.gbrainSubsteps, [])

        store.beginLaunch(stepID: .gbrain)
        store.cancelRunning(stepID: .gbrain)

        let gbrain = try XCTUnwrap(store.snapshots.first { $0.id == .gbrain })
        let prepare = try XCTUnwrap(gbrain.gbrainSubsteps.first { $0.title == "Check and clone GBrain repo" })
        let install = try XCTUnwrap(gbrain.gbrainSubsteps.first { $0.title == "Step 1: Install GBrain" })
        let credentials = try XCTUnwrap(gbrain.gbrainSubsteps.first { $0.title == "Step 2: API Keys" })
        let future = try XCTUnwrap(gbrain.gbrainSubsteps.first { $0.title == "Step 3: Create the Brain" })

        XCTAssertTrue(gbrain.isActive)
        XCTAssertTrue(gbrain.showsStart)
        XCTAssertEqual(gbrain.gbrainSubsteps.map(\.title), [
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
        XCTAssertEqual(gbrain.gbrainSubsteps.map(\.title), [
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
        XCTAssertEqual(waitingForUser["section"] as? String, "Recover common prerequisites")
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
        XCTAssertEqual(waitingForUser["section"] as? String, "Recover selected-runtime prerequisites")
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
    func testEmailStepDoesNotCompleteFromExternalConnectedCache() throws {
        let root = try makeTemporaryDirectory()
        let store = makeChecklistStore(homeURL: root)

        store.syncExternalState(selectedVaultPath: nil)

        XCTAssertFalse(store.completedStepIDs.contains(.email))
    }

    @MainActor
    func testEmailStepDoesNotCompleteFromClawvisorEnvBeforeVerifiedConnection() throws {
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

        XCTAssertFalse(store.completedStepIDs.contains(.email))
    }

    @MainActor
    func testEmailStepCompletesFromClawvisorEnvAfterVerifiedConnection() throws {
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

        XCTAssertTrue(store.completedStepIDs.contains(.email))
    }

    @MainActor
    func testEmailStepCompletesFromExportedClawvisorEnvAfterVerifiedConnection() throws {
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

        XCTAssertTrue(store.completedStepIDs.contains(.email))
    }

    @MainActor
    func testEmailStepDoesNotCompleteWhenConnectionRepairIsActive() throws {
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

        XCTAssertFalse(store.completedStepIDs.contains(.email))
    }

    @MainActor
    func testEmailStepDoesNotCompleteWhenClawvisorTaskIdIsMissing() throws {
        let root = try makeTemporaryDirectory()
        try writeClawvisorEnv(
            """
            CLAWVISOR_URL=https://app.clawvisor.com
            CLAWVISOR_AGENT_TOKEN=cvis_test
            """,
            homeURL: root
        )

        let store = makeChecklistStore(homeURL: root)

        XCTAssertFalse(store.completedStepIDs.contains(.email))
    }

    @MainActor
    func testEmailStepDoesNotCompleteFromOldClawvisorGmailTaskEnvOnly() throws {
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

        XCTAssertFalse(store.completedStepIDs.contains(.email))
    }

#if DEBUG
    @MainActor
    func testEmailStepCannotBeCompletedByDevelopmentToggle() throws {
        let root = try makeTemporaryDirectory()
        let store = makeChecklistStore(homeURL: root)

        store.developmentToggleStepCompleted(.email)

        XCTAssertFalse(store.completedStepIDs.contains(.email))
    }
#endif

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

    private func installFakeCommand(directory: URL, name: String, content: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent(name, isDirectory: false)
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
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
