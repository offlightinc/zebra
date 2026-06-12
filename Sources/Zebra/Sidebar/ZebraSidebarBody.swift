import Bonsplit
import Foundation
import SwiftUI
import ZebraVault

/// Zebra's plug for the sidebar composer slot.
///
/// Wraps the cmux `slots.workspaceList` inside a `ModeRail + mode layers +
/// Zebra footer` shell so the same workspace list is reused untouched when
/// the user is on the terminal rail mode.
struct ZebraSidebarBody: View {
    let slots: SidebarSlots

    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var sidebarSelectionState: SidebarSelectionState
    @EnvironmentObject var modeState: VerticalTabsSidebarModeState
    @EnvironmentObject var vaultState: VerticalTabsSidebarVaultState
    @EnvironmentObject var markdownFileListStore: MarkdownFileListStore
    @EnvironmentObject var goalFileListStore: GoalFileListStore
    @EnvironmentObject var taskFileListStore: TaskFileListStore
    @EnvironmentObject var goalsViewState: GoalsViewState
    @EnvironmentObject var emailListStore: ZebraEmailListStore
    @EnvironmentObject var emailDetailStore: ZebraEmailDetailStore
    @EnvironmentObject var brainSyncService: BrainSyncService
    @EnvironmentObject var onboardingChecklistStore: ZebraOnboardingChecklistStore
    @Environment(\.zebra) private var zebra
    @State private var observedOnboardingCompletedStepIDs: Set<ZebraOnboardingChecklistStepID>?
    @State private var pendingGBrainRuntimeStartAfterAgentLaunch = false
    @State private var pendingChainedGBrainRuntimeRunningAfterAgentLaunch = false
    @State private var launchedRuntimeInteractiveAuthRequestIDs: Set<String> = []
    @State private var lastRuntimeInteractiveAuthLaunchByKey: [String: Date] = [:]
    private static let runtimeInteractiveAuthAutoRetryInterval: TimeInterval = 120

    var body: some View {
        HStack(spacing: 0) {
            VerticalTabsSidebarModeRail(
                state: modeState,
                footer: AnyView(
                    // ?/⚙ 두 버튼. 디자인 spec — ModeRail 하단 spacer 아래.
                    // size 는 mode iconButton (36×36, icon 16pt) 과 동일하게 강제.
                    // SidebarHelpMenuButton / VerticalTabsSidebarSettingsButton 은
                    // cmux app module 의 internal struct (ContentView.swift) —
                    // 같은 module 이라 여기서 직접 instantiate.
                    VStack(spacing: 4) {
                        SidebarHelpMenuButton(
                            buttonSize: 36,
                            iconSize: 16,
                            onSendFeedback: slots.onSendFeedback
                        )
                        VerticalTabsSidebarSettingsButton(buttonSize: 36, iconSize: 16)
                    }
                )
            )
                .fixedSize(horizontal: true, vertical: false)
            contentColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            modeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .bottom) {
                    onboardingChecklistOverlay
                }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            onboardingChecklistStore.activateCompletionWatching()
            refreshOnboardingChecklist()
            startRuntimeInteractiveAuthIfNeeded(onboardingChecklistStore.pendingRuntimeInteractiveAuthRequest)
            observedOnboardingCompletedStepIDs = onboardingChecklistStore.completedStepIDs
        }
        .onDisappear {
            onboardingChecklistStore.deactivateCompletionWatching()
            observedOnboardingCompletedStepIDs = nil
            pendingGBrainRuntimeStartAfterAgentLaunch = false
            pendingChainedGBrainRuntimeRunningAfterAgentLaunch = false
            launchedRuntimeInteractiveAuthRequestIDs = []
            lastRuntimeInteractiveAuthLaunchByKey = [:]
        }
        .onChange(of: onboardingChecklistStore.completedStepIDs) { completedStepIDs in
            handleOnboardingCompletionChange(completedStepIDs)
        }
        .onChange(of: onboardingChecklistStore.pendingRuntimeInteractiveAuthRequest) { request in
            startRuntimeInteractiveAuthIfNeeded(request)
        }
        .onChange(of: vaultState.selectedVaultPath) { _ in
            refreshOnboardingChecklist()
        }
        .onChange(of: emailListStore.isConnected) { _ in
            refreshOnboardingChecklist()
        }
        .onChange(of: emailListStore.connectionRepairState) { _ in
            refreshOnboardingChecklist()
        }
    }

    private var onboardingChecklistOverlay: some View {
        ZebraOnboardingChecklistCard(
            store: onboardingChecklistStore,
            onStartStep: { stepID in
                startOnboardingChecklistStep(stepID)
            },
            onStopStep: { stepID in
                stopOnboardingChecklistStep(stepID)
            }
        )
        .padding(8)
        .zIndex(10)
    }

    private var footer: some View {
        VerticalTabsSidebarFooter(
            vaultState: vaultState,
            brainSync: brainSyncService,
            onSendFeedback: slots.onSendFeedback,
            onBrainSyncFailureAgent: { agent, failedAt, failure in
                startBrainSyncFailureAgent(agent: agent, failedAt: failedAt, failure: failure)
            }
        )
    }

    /// Sync failure reason 일 때 사용자가 Resolve with AI 를 누르면 호출.
    /// Brain sync 는 전용 agent picker 를 갖지 않고 primary agent CLI 를 실행한다.
    /// agent 의 첫 prompt 에는 `BrainSyncFailureContextPrefix`
    /// 가 인자로 들어가 reason/detail, git 상태, 최근 sync 로그, reason별
    /// recovery guidance 가 모두 주입된 상태. 사용자는 그 다음부터 agent 와
    /// 자연어로 대화하며 해결.
    ///
    /// `startClawvisorOnboardingAgent` 와 같은 결로, 그 패턴을 그대로 따라간다.
    private func startBrainSyncFailureAgent(
        agent: MarkdownPillAgent,
        failedAt: Date,
        failure: BrainSyncService.Failure
    ) {
        guard let workspace = tabManager.selectedWorkspace else { return }
        guard let vaultPath = vaultState.selectedVaultPath, !vaultPath.isEmpty else { return }
        // Claude 의 .claude.json trust 처리는 prep 단계에서 (codex/agy 는 no-op).
        _ = MarkdownChatPillCommand.prepareLaunchEnvironmentForBrainSyncFailure(
            agent: agent,
            vaultPath: vaultPath
        )
        let startupLine = MarkdownChatPillCommand.shellStartupLineForBrainSyncFailure(
            agent: agent,
            vaultPath: vaultPath,
            reason: failure.reason,
            rawReasonId: failure.rawReasonId,
            detail: failure.detail,
            failedAt: failedAt
        )
        guard let agentTerminals = zebra?.agentTerminals else { return }
        workspace.openZebraAgentTerminal(
            startupLine: startupLine,
            source: .brainSyncFailure,
            agent: agent,
            anchor: .focusAnchored,
            markedBy: agentTerminals
        )
    }

    private var modeContent: some View {
        Group {
            switch modeState.selectedMode {
            case .terminal:
                slots.workspaceList

            case .goals:
                if modeState.listVisible {
                    VerticalTabsSidebarGoalsContent(
                        state: modeState,
                        goalsStore: goalFileListStore,
                        viewState: goalsViewState,
                        onSelectFile: openMarkdownFile
                    )
                }

            case .tasks:
                if modeState.listVisible {
                    VerticalTabsSidebarTasksContent(
                        state: modeState,
                        taskStore: taskFileListStore,
                        onSelectFile: openMarkdownFile
                    )
                }

            case .email:
                if modeState.listVisible {
                    VerticalTabsSidebarEmailContent(
                        state: modeState,
                        threads: emailListStore.threads,
                        userLabels: emailListStore.userLabels,
                        isConnected: emailListStore.isConnected,
                        isLoading: emailListStore.isLoading,
                        isSyncing: emailListStore.isSyncing,
                        errorMessage: emailListStore.lastError,
                        connectionRepairState: emailListStore.connectionRepairState,
                        selectedThreadId: emailDetailStore.selectedThreadId,
                        onConnect: { startClawvisorOnboardingAgent() },
                        onRefresh: { Task { await emailListStore.refresh() } },
                        onSelectThread: openEmailThread,
                        onCreateLabel: { emailListStore.localLabel(named: $0) }
                    )
                    .task(id: modeState.selectedMode) {
                        await emailListStore.refreshIfNeeded()
                    }
                }

            case .documents:
                if modeState.listVisible {
                    VerticalTabsSidebarDocumentsContent(
                        state: modeState,
                        store: markdownFileListStore,
                        onSelectFile: openMarkdownFile
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: modeState.selectedMode)
        .animation(.easeOut(duration: 0.15), value: modeState.listVisible)
    }

    /// Launch a fresh terminal tab in the focused pane, drop the user into
    /// their primary agent, and seed a prompt that walks them through
    /// signing up at Clawvisor and writing `~/.gbrain/.env`. Replaces the
    /// previous direct-OAuth flow.
    private func startClawvisorOnboardingAgent() {
        guard let workspace = tabManager.selectedWorkspace else { return }
        guard let agentTerminals = zebra?.agentTerminals else { return }
        guard let agent = ZebraClawvisorOnboardingCommand.readyPrimaryAgent() else {
            startAgentOnboardingStep(in: workspace)
            return
        }
        let launchPlan = ZebraClawvisorOnboardingCommand.launchPlan(agent: agent)
        guard launchPlan.launchEnvironmentReady else {
            openClawvisorLaunchPreparationFailure(in: workspace, agent: launchPlan.agent)
            return
        }
        workspace.openZebraAgentTerminal(
            startupLine: launchPlan.startupLine,
            source: .clawvisorOnboarding,
            agent: launchPlan.agent,
            anchor: .focusAnchored,
            markedBy: agentTerminals
        )
    }

    private func stopOnboardingChecklistStep(_ stepID: ZebraOnboardingChecklistStepID) {
        guard let workspace = tabManager.selectedWorkspace,
              let agentTerminals = zebra?.agentTerminals else { return }
        let targetSource = ZebraAgentTerminalSource.onboardingChecklist(stepID)
        let terminalPanels = workspace.panels.values.compactMap { $0 as? TerminalPanel }
        for panel in terminalPanels {
            guard let reg = agentTerminals.registration(panelId: panel.id),
                  reg.source == targetSource else { continue }
            panel.sendInput("\u{03}")
            panel.surface.forceRefresh(reason: "zebra.onboarding.stop")
            break
        }
        onboardingChecklistStore.cancelRunning(stepID: stepID)
        if stepID == .agent {
            pendingGBrainRuntimeStartAfterAgentLaunch = false
            pendingChainedGBrainRuntimeRunningAfterAgentLaunch = false
        }
    }

    private func startOnboardingChecklistStep(_ stepID: ZebraOnboardingChecklistStepID) {
        guard onboardingChecklistStore.runningStepID != stepID else { return }
        guard let workspace = tabManager.selectedWorkspace else {
            return
        }
        if stepID == .email {
            startOnboardingChecklistEmailStep(in: workspace)
            return
        }
        guard let launchPlan = ZebraOnboardingChecklistCommand.launchPlan(
            for: stepID,
            selectedVaultPath: onboardingSelectedVaultPath,
            chainGBrainRuntimeAfterAgent: stepID == .agent
        ) else { return }
        let startupLine = launchPlan.startupLine
        var launchBegan = false
        func beginLaunchIfNeeded() {
            guard !launchBegan else { return }
            launchBegan = true
            onboardingChecklistStore.beginLaunch(stepID: stepID)
            if stepID == .agent {
                let launchesRuntimeInAgentTerminal = launchPlan.launchesGBrainRuntimeInAgentTerminal
                pendingGBrainRuntimeStartAfterAgentLaunch = !launchesRuntimeInAgentTerminal
                pendingChainedGBrainRuntimeRunningAfterAgentLaunch = launchesRuntimeInAgentTerminal
            } else if stepID == .gbrainRuntime {
                pendingChainedGBrainRuntimeRunningAfterAgentLaunch = false
            }
        }
        let agent = onboardingChecklistAgent(for: stepID)
        #if DEBUG
        cmuxDebugLog(
            "zebra.onboarding.step.start step=\(stepID.rawValue) " +
            "agent=\(agent == nil ? 0 : 1) bytes=\(startupLine.utf8.count)"
        )
        #endif
        if let agent {
            guard let agentTerminals = zebra?.agentTerminals else { return }
            let source = ZebraAgentTerminalSource.onboardingChecklist(stepID)
            if stepID == .agent {
                beginLaunchIfNeeded()
                if sendAgentOnboardingToInitialTerminalIfAvailable(
                    startupLine,
                    in: workspace,
                    source: source,
                    agent: agent,
                    markedBy: agentTerminals
                ) {
                    return
                }
            }
            beginLaunchIfNeeded()
            workspace.openZebraAgentTerminal(
                startupLine: startupLine,
                source: source,
                agent: agent,
                anchor: .focusAnchored,
                markedBy: agentTerminals
            )
            return
        }
        #if DEBUG
        cmuxDebugLog(
            "zebra.onboarding.step.fallbackTerminal step=\(stepID.rawValue) " +
            "bytes=\(startupLine.utf8.count)"
        )
        #endif
        beginLaunchIfNeeded()
        if let panel = workspace.newTerminalSurfaceInFocusedPane(focus: true) {
            if let agentTerminals = zebra?.agentTerminals {
                agentTerminals.prune(validPanelIds: Set(workspace.panels.keys))
                agentTerminals.mark(
                    panelId: panel.id,
                    source: .onboardingChecklist(stepID),
                    agent: nil
                )
            }
            panel.zebraSendStartupLineWhenReady(startupLine)
        }
    }

    private func handleOnboardingCompletionChange(
        _ completedStepIDs: Set<ZebraOnboardingChecklistStepID>
    ) {
        guard let previousCompletedStepIDs = observedOnboardingCompletedStepIDs else {
            observedOnboardingCompletedStepIDs = completedStepIDs
            return
        }
        observedOnboardingCompletedStepIDs = completedStepIDs
        if ZebraOnboardingChecklistStore.shouldBeginChainedRuntimeHandoff(
            previousCompletedStepIDs: previousCompletedStepIDs,
            currentCompletedStepIDs: completedStepIDs,
            didLaunchRuntimeInAgentTerminal: pendingChainedGBrainRuntimeRunningAfterAgentLaunch
        ) {
            pendingChainedGBrainRuntimeRunningAfterAgentLaunch = false
            beginChainedGBrainRuntimeRunningHandoff()
            return
        }
        guard let nextStep = ZebraOnboardingChecklistStore.automaticStepToStart(
            previousCompletedStepIDs: previousCompletedStepIDs,
            currentCompletedStepIDs: completedStepIDs,
            didStartAgentStepInCurrentSession: pendingGBrainRuntimeStartAfterAgentLaunch
        ) else {
            if pendingGBrainRuntimeStartAfterAgentLaunch,
               !previousCompletedStepIDs.contains(.agent),
               completedStepIDs.contains(.agent) {
                pendingGBrainRuntimeStartAfterAgentLaunch = false
            }
            if pendingChainedGBrainRuntimeRunningAfterAgentLaunch,
               !previousCompletedStepIDs.contains(.agent),
               completedStepIDs.contains(.agent) {
                pendingChainedGBrainRuntimeRunningAfterAgentLaunch = false
            }
            return
        }
        pendingGBrainRuntimeStartAfterAgentLaunch = false
        pendingChainedGBrainRuntimeRunningAfterAgentLaunch = false
        startOnboardingChecklistStep(nextStep)
    }

    private func beginChainedGBrainRuntimeRunningHandoff() {
        onboardingChecklistStore.beginLaunch(stepID: .gbrainRuntime)
        guard let workspace = tabManager.selectedWorkspace,
              let agentTerminals = zebra?.agentTerminals else {
            return
        }
        agentTerminals.prune(validPanelIds: Set(workspace.panels.keys))
        let registration = agentTerminals.reassignLatest(
            from: .onboardingChecklist(.agent),
            to: .onboardingChecklist(.gbrainRuntime),
            panelIds: workspace.panels.keys
        )
        #if DEBUG
        let panelPrefix = registration.map { String($0.panelId.uuidString.prefix(5)) } ?? "nil"
        cmuxDebugLog(
            "zebra.onboarding.chainedRuntime.handoff " +
            "panel=\(panelPrefix)"
        )
        #endif
    }

    private func startRuntimeInteractiveAuthIfNeeded(
        _ request: ZebraGBrainRuntimeOnboardingStore.InteractiveAuthRequest?
    ) {
        guard let request,
              !request.startupLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !launchedRuntimeInteractiveAuthRequestIDs.contains(request.id),
              let workspace = tabManager.selectedWorkspace else {
            return
        }
        let now = Date()
        if let lastLaunch = lastRuntimeInteractiveAuthLaunchByKey[request.authKey],
           now.timeIntervalSince(lastLaunch) < Self.runtimeInteractiveAuthAutoRetryInterval {
            #if DEBUG
            cmuxDebugLog(
                "zebra.onboarding.runtimeInteractiveAuth.skip authKey=\(request.authKey)"
            )
            #endif
            return
        }
        launchedRuntimeInteractiveAuthRequestIDs.insert(request.id)
        lastRuntimeInteractiveAuthLaunchByKey[request.authKey] = now
        #if DEBUG
        cmuxDebugLog(
            "zebra.onboarding.runtimeInteractiveAuth.start runtime=\(request.runtime) " +
            "provider=\(request.provider) bytes=\(request.startupLine.utf8.count)"
        )
        #endif
        if let panel = workspace.newTerminalSurfaceInFocusedPane(focus: true) {
            if let agentTerminals = zebra?.agentTerminals {
                agentTerminals.prune(validPanelIds: Set(workspace.panels.keys))
                agentTerminals.mark(
                    panelId: panel.id,
                    source: .onboardingChecklist(.gbrainRuntime),
                    agent: nil
                )
            }
            panel.zebraSendStartupLineWhenReady(request.startupLine)
        }
    }

    private func startOnboardingChecklistEmailStep(in workspace: Workspace) {
        guard let agentTerminals = zebra?.agentTerminals else { return }
        guard let agent = ZebraClawvisorOnboardingCommand.readyPrimaryAgent() else {
            startAgentOnboardingStep(in: workspace)
            return
        }
        let launchPlan = ZebraClawvisorOnboardingCommand.launchPlan(agent: agent)
        guard launchPlan.launchEnvironmentReady else {
            openClawvisorLaunchPreparationFailure(in: workspace, agent: launchPlan.agent)
            return
        }
        onboardingChecklistStore.beginLaunch(stepID: .email)
        workspace.openZebraAgentTerminal(
            startupLine: launchPlan.startupLine,
            source: .onboardingChecklist(.email),
            agent: launchPlan.agent,
            anchor: .focusAnchored,
            markedBy: agentTerminals
        )
    }

    private func openClawvisorLaunchPreparationFailure(
        in workspace: Workspace,
        agent: MarkdownPillAgent
    ) {
        let message = String(
            format: String(
                localized: "email.connect.launchPreparationFailed",
                defaultValue: "Zebra could not prepare %@ folder trust for ~/.gbrain. Fix the agent config file permissions, then retry Gmail connection."
            ),
            agent.agentKind.displayName
        )
        _ = workspace.newTerminalSurfaceInFocusedPane(
            focus: true,
            initialInput: "printf '%s\\n' \(terminalShellQuote(message))\n"
        )
    }

    private func startAgentOnboardingStep(in workspace: Workspace) {
        guard onboardingChecklistStore.runningStepID != .agent else { return }
        guard let startupLine = ZebraOnboardingChecklistCommand.shellStartupLine(
            for: .agent,
            selectedVaultPath: onboardingSelectedVaultPath
        ) else { return }
        guard let agentTerminals = zebra?.agentTerminals else { return }
        let agent = MarkdownPillAgent.primaryAgent() ?? .codex
        let source = ZebraAgentTerminalSource.onboardingChecklist(.agent)
        onboardingChecklistStore.beginLaunch(stepID: .agent)
        if sendAgentOnboardingToInitialTerminalIfAvailable(
            startupLine,
            in: workspace,
            source: source,
            agent: agent,
            markedBy: agentTerminals
        ) {
            return
        }
        workspace.openZebraAgentTerminal(
            startupLine: startupLine,
            source: source,
            agent: agent,
            anchor: .focusAnchored,
            markedBy: agentTerminals
        )
    }

    private func onboardingChecklistAgent(for stepID: ZebraOnboardingChecklistStepID) -> MarkdownPillAgent? {
        switch stepID {
        case .agent, .gbrainRuntime, .adapter, .ingest, .goals:
            return MarkdownPillAgent.defaultAgent()
        case .email:
            return MarkdownPillAgent.defaultAgent()
        case .gbrain:
            return nil
        }
    }

    private func sendAgentOnboardingToInitialTerminalIfAvailable(
        _ startupLine: String,
        in workspace: Workspace,
        source: ZebraAgentTerminalSource,
        agent: MarkdownPillAgent,
        markedBy registry: ZebraAgentTerminalRegistry
    ) -> Bool {
        let terminalPanels = workspace.panels.values.compactMap { $0 as? TerminalPanel }
        guard terminalPanels.count == 1,
              let terminalPanel = terminalPanels.first,
              workspace.focusedTerminalPanel?.id == terminalPanel.id,
              canReuseTerminalForAgentOnboarding(terminalPanel, in: workspace) else {
            return false
        }
        registry.prune(validPanelIds: Set(workspace.panels.keys))
        registry.mark(panelId: terminalPanel.id, source: source, agent: agent)
        terminalPanel.focus()
        #if DEBUG
        cmuxDebugLog(
            "zebra.onboarding.step.reuseInitialTerminal source=\(String(describing: source)) " +
            "panel=\(terminalPanel.id.uuidString.prefix(5)) bytes=\(startupLine.utf8.count)"
        )
        #endif
        terminalPanel.zebraSendStartupLine(startupLine)
        return true
    }

    private func canReuseTerminalForAgentOnboarding(
        _ terminalPanel: TerminalPanel,
        in workspace: Workspace
    ) -> Bool {
        guard !terminalPanel.needsConfirmClose() else { return false }
        switch workspace.panelShellActivityStates[terminalPanel.id] ?? .unknown {
        case .promptIdle, .unknown:
            return true
        case .commandRunning:
            return false
        }
    }

    private func refreshOnboardingChecklist() {
        onboardingChecklistStore.syncExternalState(
            selectedVaultPath: onboardingSelectedVaultPath,
            emailConnectionRepairState: emailListStore.connectionRepairState
        )
    }

    private var onboardingSelectedVaultPath: String? {
        vaultState.selectedVaultWasExplicitlyChosen ? vaultState.selectedVaultPath : nil
    }

    private func terminalShellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func openMarkdownFile(filePath: String) {
        guard let workspace = tabManager.selectedWorkspace else { return }
        let paneId = workspace.bonsplitController.focusedPaneId
            ?? workspace.bonsplitController.allPaneIds.first
        sidebarSelectionState.selection = .tabs
        // Markdown rail modes (goals / tasks / documents) route through the
        // brain-object-aware MarkdownPanel so the right-pane inspector lights
        // up. Keep Markdown and email in the shared content pane even after
        // ChatPill submit moves focus to the agent companion pane.
        _ = workspace.openMarkdownFromZebraSidebar(
            inPane: paneId,
            filePath: filePath,
            excludedAgentCompanionPaneIds: agentCompanionPaneIds(in: workspace)
        )
    }

    private func openEmailThread(_ thread: EmailThreadItem) {
        guard let workspace = tabManager.selectedWorkspace else { return }
        let paneId = workspace.bonsplitController.focusedPaneId
            ?? workspace.bonsplitController.allPaneIds.first
        sidebarSelectionState.selection = .tabs
        _ = workspace.openEmailThreadFromSidebar(
            inPane: paneId,
            thread: thread,
            excludedAgentCompanionPaneIds: agentCompanionPaneIds(in: workspace)
        )
        emailDetailStore.selectThread(thread)
    }

    private func agentCompanionPaneIds(in workspace: Workspace) -> Set<PaneID> {
        guard let agentTerminals = zebra?.agentTerminals else { return [] }
        return workspace.zebraAgentCompanionPaneIds(markedBy: agentTerminals)
    }
}

/// Zebra's composer that wraps the cmux slots inside `ZebraSidebarBody`.
/// Injected by `ZebraServices.injectIntoEnvironment`.
enum ZebraSidebarComposer {
    static let composer = SidebarComposer { slots in
        AnyView(ZebraSidebarBody(slots: slots))
    }
}
