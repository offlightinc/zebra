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
    @Environment(\.zebra) private var zebra

    var body: some View {
        HStack(spacing: 0) {
            VerticalTabsSidebarModeRail(state: modeState)
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
            onSendFeedback: slots.onSendFeedback
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
