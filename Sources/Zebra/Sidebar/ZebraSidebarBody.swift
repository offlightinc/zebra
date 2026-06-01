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
            refreshOnboardingChecklist()
        }
        .onChange(of: vaultState.selectedVaultPath) { _ in
            refreshOnboardingChecklist()
        }
        .onChange(of: emailListStore.isConnected) { _ in
            refreshOnboardingChecklist()
        }
        .task {
            while !Task.isCancelled {
                refreshOnboardingChecklist()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private var onboardingChecklistOverlay: some View {
        ZebraOnboardingChecklistCard(
            store: onboardingChecklistStore,
            onStartStep: { stepID in
                startOnboardingChecklistStep(stepID)
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

    /// Sync failure reason 일 때 사용자가 agent picker 에서 agent 를 선택하면 호출.
    /// 현재 focused workspace 의 새 terminal surface 를 띄우고 그 안에서 선택된
    /// agent CLI 를 실행. agent 의 첫 prompt 에는 `BrainSyncFailureContextPrefix`
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
        _ = workspace.newTerminalSurfaceInFocusedPane(
            focus: true,
            initialInput: startupLine
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
                        onConnect: { agent in startClawvisorOnboardingAgent(agent: agent) },
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
    /// Claude Code, and seed an agent system prompt that walks them through
    /// signing up at Clawvisor and writing `~/.gbrain/.env`. Replaces the
    /// previous direct-OAuth flow (which is dead since the desktop moved to
    /// the local SQLite + Clawvisor brain RPC client).
    private func startClawvisorOnboardingAgent(agent: ZebraClawvisorAgent) {
        // Defense in depth — the picker UI disables non-available rows, but
        // a future keyboard shortcut / accessibility / socket-CLI path could
        // still hand us a "Coming soon" agent. Drop those at the domain
        // boundary instead of silently launching the Claude Code onboarding
        // flow for the wrong agent label.
        guard agent.isAvailable else { return }
        guard let workspace = tabManager.selectedWorkspace else { return }
        // Ensure `~/.gbrain` exists and is pre-trusted in `~/.claude.json` so
        // the user doesn't see Claude's "Trust this folder?" dialog mid-flow.
        ZebraClawvisorOnboardingCommand.prepareLaunchEnvironment()
        let startupLine = ZebraClawvisorOnboardingCommand.shellStartupLine(agent: agent)
        _ = workspace.newTerminalSurfaceInFocusedPane(
            focus: true,
            initialInput: startupLine
        )
    }

    private func startOnboardingChecklistStep(_ stepID: ZebraOnboardingChecklistStepID) {
        guard onboardingChecklistStore.runningStepID != stepID else { return }
        guard let workspace = tabManager.selectedWorkspace,
              let startupLine = ZebraOnboardingChecklistCommand.shellStartupLine(
                for: stepID,
                selectedVaultPath: vaultState.selectedVaultPath
              ) else {
            return
        }
        onboardingChecklistStore.beginLaunch(stepID: stepID)
        if stepID == .agent,
           sendAgentOnboardingToInitialTerminalIfAvailable(startupLine, in: workspace) {
            return
        }
        _ = workspace.newTerminalSurfaceInFocusedPane(
            focus: true,
            initialInput: startupLine
        )
    }

    private func sendAgentOnboardingToInitialTerminalIfAvailable(
        _ startupLine: String,
        in workspace: Workspace
    ) -> Bool {
        let terminalPanels = workspace.panels.values.compactMap { $0 as? TerminalPanel }
        guard terminalPanels.count == 1,
              let terminalPanel = terminalPanels.first,
              workspace.focusedTerminalPanel?.id == terminalPanel.id,
              canReuseTerminalForAgentOnboarding(terminalPanel, in: workspace) else {
            return false
        }
        terminalPanel.focus()
        terminalPanel.sendInput(startupLine)
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
            selectedVaultPath: vaultState.selectedVaultPath,
            emailConnected: emailListStore.isConnected
        )
    }

    private func openMarkdownFile(filePath: String) {
        guard let workspace = tabManager.selectedWorkspace else { return }
        sidebarSelectionState.selection = .tabs
        // Markdown rail modes (goals / tasks / documents) route through the
        // brain-object-aware MarkdownPanel so the right-pane inspector lights
        // up. Keep Markdown and email in the shared content pane even after
        // ChatPill submit moves focus to the agent companion pane.
        _ = workspace.openMarkdownFromZebraSidebar(
            filePath: filePath,
            excludedAgentCompanionPaneIds: chatCompanionPaneIds(in: workspace),
            anchorPanelId: workspace.focusedPanelId
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
            excludedAgentCompanionPaneIds: chatCompanionPaneIds(in: workspace),
            anchorPanelId: workspace.focusedPanelId
        )
        emailDetailStore.selectThread(thread)
    }

    private func chatCompanionPaneIds(in workspace: Workspace) -> Set<PaneID> {
        let validPaneIds = workspace.bonsplitController.allPaneIds
        let markdownPaneIds = zebra?.panelControllers.activeChatCompanionPaneIds(
            validPaneIds: validPaneIds
        ) ?? []
        let emailPaneIds = emailDetailStore.activeChatCompanionPaneIds(
            validPaneIds: validPaneIds
        )
        return markdownPaneIds.union(emailPaneIds)
    }
}

/// Zebra's composer that wraps the cmux slots inside `ZebraSidebarBody`.
/// Injected by `ZebraServices.injectIntoEnvironment`.
enum ZebraSidebarComposer {
    static let composer = SidebarComposer { slots in
        AnyView(ZebraSidebarBody(slots: slots))
    }
}
