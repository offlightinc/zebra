import Bonsplit
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
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        VerticalTabsSidebarFooter(
            vaultState: vaultState,
            brainSync: brainSyncService,
            onSendFeedback: slots.onSendFeedback,
            onBrainSyncConflictAgent: { agent in
                startBrainSyncConflictAgent(agent: agent)
            }
        )
    }

    /// Conflict reason 일 때 사용자가 agent picker 에서 agent 를 선택하면 호출.
    /// 현재 focused workspace 의 새 terminal surface 를 띄우고 그 안에서 선택된
    /// agent CLI 를 실행. agent 의 첫 prompt 에는 `BrainSyncConflictContextPrefix`
    /// 가 인자로 들어가 conflict 컨텍스트 (git status, 충돌 파일, marker 발췌, 4
    /// 가지 resolution 옵션 카탈로그) 가 모두 주입된 상태. 사용자는 그 다음부터
    /// agent 와 자연어로 대화하며 해결.
    ///
    /// `startClawvisorOnboardingAgent` 와 같은 결로, 그 패턴을 그대로 따라간다.
    private func startBrainSyncConflictAgent(agent: MarkdownPillAgent) {
        guard let workspace = tabManager.selectedWorkspace else { return }
        guard let vaultPath = vaultState.selectedVaultPath, !vaultPath.isEmpty else { return }
        // Claude 의 .claude.json trust 처리는 prep 단계에서 (codex/gemini 는 no-op).
        _ = MarkdownChatPillCommand.prepareLaunchEnvironmentForBrainSyncConflict(
            agent: agent,
            vaultPath: vaultPath
        )
        let startupLine = MarkdownChatPillCommand.shellStartupLineForBrainSyncConflict(
            agent: agent,
            vaultPath: vaultPath
        )
        _ = workspace.newTerminalSurfaceInFocusedPane(
            focus: true,
            initialInput: startupLine
        )
    }

    private var modeContent: some View {
        ZStack(alignment: .topLeading) {
            modeLayer(isVisible: modeState.selectedMode == .terminal) {
                slots.workspaceList
            }
            modeLayer(isVisible: modeState.selectedMode == .goals && modeState.listVisible) {
                VerticalTabsSidebarGoalsContent(
                    state: modeState,
                    goalsStore: goalFileListStore,
                    viewState: goalsViewState,
                    onSelectFile: openMarkdownFile
                )
            }
            modeLayer(isVisible: modeState.selectedMode == .tasks && modeState.listVisible) {
                VerticalTabsSidebarTasksContent(
                    state: modeState,
                    taskStore: taskFileListStore,
                    onSelectFile: openMarkdownFile
                )
            }
            modeLayer(isVisible: modeState.selectedMode == .email && modeState.listVisible) {
                VerticalTabsSidebarEmailContent(
                    state: modeState,
                    threads: emailListStore.threads,
                    userLabels: emailListStore.userLabels,
                    isConnected: emailListStore.isConnected,
                    isLoading: emailListStore.isLoading,
                    isSyncing: emailListStore.isSyncing,
                    errorMessage: emailListStore.lastError,
                    selectedThreadId: emailDetailStore.selectedThreadId,
                    onConnect: { agent in startClawvisorOnboardingAgent(agent: agent) },
                    onRefresh: { Task { await emailListStore.refresh() } },
                    onSelectThread: openEmailThread,
                    onCreateLabel: { emailListStore.localLabel(named: $0) }
                )
                .task(id: modeState.selectedMode) {
                    guard modeState.selectedMode == .email else { return }
                    await emailListStore.refreshIfNeeded()
                }
            }
            modeLayer(isVisible: modeState.selectedMode == .documents && modeState.listVisible) {
                VerticalTabsSidebarDocumentsContent(
                    state: modeState,
                    store: markdownFileListStore,
                    onSelectFile: openMarkdownFile
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: modeState.selectedMode)
        .animation(.easeOut(duration: 0.15), value: modeState.listVisible)
    }

    private func modeLayer<Content: View>(
        isVisible: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
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

    private func openMarkdownFile(filePath: String) {
        guard let workspace = tabManager.selectedWorkspace else { return }
        guard let paneId = workspace.bonsplitController.focusedPaneId
            ?? workspace.bonsplitController.allPaneIds.first else {
            return
        }
        sidebarSelectionState.selection = .tabs
        // Markdown rail modes (goals / tasks / documents) route through the
        // brain-object-aware MarkdownPanel so the right-pane inspector lights
        // up. If the focused tab is already Markdown, keep that tab and swap
        // its file instead of creating another Markdown tab.
        _ = workspace.openMarkdownFromSidebar(inPane: paneId, filePath: filePath)
    }

    private func openEmailThread(_ thread: EmailThreadItem) {
        guard let workspace = tabManager.selectedWorkspace else { return }
        sidebarSelectionState.selection = .tabs
        _ = workspace.openOrFocusEmailThreadContent(
            thread: thread,
            excludedAgentCompanionPaneIds: chatCompanionPaneIds(in: workspace),
            anchorPanelId: workspace.focusedPanelId
        )
        emailDetailStore.selectThread(thread)
    }

    private func chatCompanionPaneIds(in workspace: Workspace) -> Set<PaneID> {
        zebra?.panelControllers.activeChatCompanionPaneIds(
            validPaneIds: workspace.bonsplitController.allPaneIds
        ) ?? []
    }
}

/// Zebra's composer that wraps the cmux slots inside `ZebraSidebarBody`.
/// Injected by `ZebraServices.injectIntoEnvironment`.
enum ZebraSidebarComposer {
    static let composer = SidebarComposer { slots in
        AnyView(ZebraSidebarBody(slots: slots))
    }
}
