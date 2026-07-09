import Bonsplit
import AppKit
import SwiftUI
import ZebraVault

/// What cmux's `PanelContentView` hands to a markdown panel view factory.
/// The factory returns the actual view; default (`nil`) means cmux has no
/// built-in markdown panel renderer and the case falls through.
///
/// This is the adapter seam for the entire MarkdownPanel feature: Zebra
/// injects `ZebraMarkdownPanelViewFactory.factory` to supply the
/// inspector + chat pill view; without it cmux renders nothing for
/// `.markdown` panels (markdown still opens through the generic
/// `FilePreviewPanel` from cmux paths).
struct MarkdownPanelViewContext {
    let panel: MarkdownPanel
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void
}

typealias MarkdownPanelViewFactory = (MarkdownPanelViewContext) -> AnyView

private struct MarkdownPanelViewFactoryKey: EnvironmentKey {
    static let defaultValue: MarkdownPanelViewFactory? = nil
}

extension EnvironmentValues {
    /// Render the markdown panel body. `nil` (default) means cmux ships
    /// without a built-in markdown view; Zebra plugs one in via
    /// `ZebraServices.injectIntoEnvironment`.
    var markdownPanelViewFactory: MarkdownPanelViewFactory? {
        get { self[MarkdownPanelViewFactoryKey.self] }
        set { self[MarkdownPanelViewFactoryKey.self] = newValue }
    }
}

/// Zebra's factory implementation. Resolves the per-panel side-car
/// controller from `ZebraServices.panelControllers` and hands the context
/// to `ZebraMarkdownPanelHost`, which looks up the panel's `Workspace`
/// from `TabManager` so cmux's `PanelContentView` can stay workspace-free.
enum ZebraMarkdownPanelViewFactory {
    @MainActor
    static func make(services: ZebraServices) -> MarkdownPanelViewFactory {
        { context in
            guard let controller = services.panelControllers.controllerIfOpen(for: context.panel) else {
                return AnyView(Color.clear)
            }
            return AnyView(
                ZebraMarkdownPanelHost(
                    context: context,
                    controller: controller,
                    agentTerminals: services.agentTerminals
                )
            )
        }
    }
}

/// Resolves the `Workspace` for a `MarkdownPanel` at view-construction time
/// so the factory doesn't need a `Workspace` in its context. Keeps cmux's
/// `PanelContentView` and `WorkspaceContentView` byte-identical to upstream
/// (no `workspace:` parameter threading).
private struct ZebraMarkdownPanelHost: View {
    let context: MarkdownPanelViewContext
    @ObservedObject var controller: MarkdownPanelController
    let agentTerminals: ZebraAgentTerminalRegistry
    @EnvironmentObject private var tabManager: TabManager

    var body: some View {
        if let workspace = tabManager.tabs.first(where: { $0.id == context.panel.workspaceId }) {
            ZebraMarkdownPanelView(
                panel: context.panel,
                controller: controller,
                workspace: workspace,
                agentTerminals: agentTerminals,
                paneId: context.paneId,
                isFocused: context.isFocused,
                isVisibleInUI: context.isVisibleInUI,
                portalPriority: context.portalPriority,
                onRequestPanelFocus: context.onRequestPanelFocus
            )
        } else {
            // Panel's workspace went away mid-render. Fall through to an
            // empty surface; cmux will tear down the panel shortly after.
            Color.clear
        }
    }
}

/// Zebra's implementation of the generic `customPanelViewFactory` seam
/// declared by cmux in `PanelContentView`. Cmux common code never sees
/// `ZebraEmailThreadPanel` (or any future Zebra panel type) — the cast
/// happens here, inside Zebra's module. Returning `nil` means "this panel
/// kind isn't ours; let cmux handle it" (currently a no-op for `.email`
/// since there's no cmux-side renderer).
enum ZebraCustomPanelViewFactoryProvider {
    @MainActor
    static func make(services: ZebraServices) -> CustomPanelViewFactory {
        { context in
            if let emailPanel = context.panel as? ZebraEmailThreadPanel {
                return AnyView(
                    ZebraEmailPanelHost(
                        panel: emailPanel,
                        paneId: context.paneId,
                        agentTerminals: services.agentTerminals,
                        detailStore: services.emailDetail,
                        listStore: services.email
                    )
                )
            }
            return nil
        }
    }
}

private struct ZebraEmailPanelHost: View {
    @ObservedObject var panel: ZebraEmailThreadPanel
    let paneId: PaneID
    let agentTerminals: ZebraAgentTerminalRegistry
    @ObservedObject var detailStore: ZebraEmailDetailStore
    let listStore: ZebraEmailListStore
    @EnvironmentObject private var tabManager: TabManager
    @EnvironmentObject private var vaultState: VerticalTabsSidebarVaultState
    /// Chat pill expand state. Per-thread persistence isn't needed — the
    /// pill collapses cleanly when the user dismisses it, and a fresh
    /// thread view should not inherit another thread's open state.
    @State private var pillExpanded: Bool = false
    @State private var chatPillShellHeight: CGFloat = MarkdownChatPillLayout.expandedHeight

    var body: some View {
        let workspace = tabManager.tabs.first(where: { $0.id == panel.workspaceId })

        GeometryReader { proxy in
            ZebraEmailThreadDetailView(
                subject: panel.displayTitle,
                detail: detailStore.detail(threadId: panel.threadId),
                drafts: detailStore.drafts(threadId: panel.threadId),
                isLoading: detailStore.isLoading(threadId: panel.threadId),
                isArchiving: detailStore.isArchiving(threadId: panel.threadId),
                errorMessage: detailStore.errorMessage(threadId: panel.threadId),
                archiveErrorMessage: detailStore.archiveErrorMessage(threadId: panel.threadId),
                draftErrorMessage: detailStore.draftErrorMessage(threadId: panel.threadId),
                draftErrorMessages: Dictionary(uniqueKeysWithValues: detailStore
                    .drafts(threadId: panel.threadId)
                    .compactMap { draft in
                        detailStore.draftErrorMessage(threadId: panel.threadId, localDraftId: draft.localDraftId)
                            .map { (draft.localDraftId, $0) }
                }),
                sendingDraftIds: detailStore.sendingDraftIds(threadId: panel.threadId),
                expandedMessageIds: detailStore.expandedMessageIds(threadId: panel.threadId),
                // Markdown 측 `ZebraMarkdownPanelView` 가 ScrollView 본문에 부여하는
                // bottom 여백과 같은 값. 마지막 메시지가 floating chat pill 뒤로
                // 가리지 않도록 한다.
                bottomContentInset: MarkdownChatPillLayout.contentBottomInset(shellHeight: chatPillShellHeight),
                onArchive: {
                    Task {
                        if await detailStore.archiveThread(threadId: panel.threadId) {
                            listStore.removeLocalThread(threadId: panel.threadId)
                        }
                    }
                },
                onDismissArchiveError: {
                    detailStore.clearArchiveError(threadId: panel.threadId)
                },
                onDismissDraftError: {
                    detailStore.clearDraftError(threadId: panel.threadId)
                },
                onRefresh: {
                    Task { await detailStore.reloadThread(threadId: panel.threadId, forceRefresh: true) }
                },
                onToggleMessage: { messageId in
                    detailStore.toggleMessage(threadId: panel.threadId, messageId: messageId)
                },
                onCreateReply: { targetMessageId in
                    detailStore.createReplyDraft(
                        threadId: panel.threadId,
                        targetMessageId: targetMessageId
                    )
                },
                onUpdateDraft: { localDraftId, baseVersion, patch in
                    detailStore.updateDraft(
                        threadId: panel.threadId,
                        localDraftId: localDraftId,
                        baseVersion: baseVersion,
                        patch: patch
                    )
                },
                onSendDraft: { localDraftId, baseVersion, patch in
                    detailStore.sendDraft(
                        threadId: panel.threadId,
                        localDraftId: localDraftId,
                        baseVersion: baseVersion,
                        patch: patch
                    )
                },
                onDiscardDraft: { localDraftId in
                    detailStore.discardDraft(threadId: panel.threadId, localDraftId: localDraftId)
                },
                onOpenURL: { url in
                    let ok = NSWorkspace.shared.open(url)
                    #if DEBUG
                    if !ok {
                        cmuxDebugLog("email.openURL.failed url=\(url.absoluteString)")
                    }
                    #endif
                }
            )
            .overlay {
                if let workspace, detailStore.detail(threadId: panel.threadId) != nil {
                    MarkdownChatPillOverlay(
                        isExpanded: $pillExpanded,
                        displayTitle: panel.displayTitle,
                        availableContentHeight: proxy.size.height,
                        activeAgent: workspace.activeAgentTerminalAgent(
                            for: agentTerminalSource,
                            contentPane: paneId,
                            markedBy: agentTerminals
                        ),
                        onSubmit: { text, agent in
                            handlePillSubmit(text: text, agent: agent, workspace: workspace)
                        },
                        onManageDefaultAgent: { agent in
                            startDefaultAgentManager(workspace: workspace, agent: agent)
                        },
                        onHeightChange: handleChatPillHeightChange
                    )
                }
            }
        }
        .task(id: panel.threadId) {
            await detailStore.loadThreadIfNeeded(threadId: panel.threadId)
        }
    }

    private func handleChatPillHeightChange(_ height: CGFloat) {
        guard height.isFinite, abs(height - chatPillShellHeight) > 0.5 else { return }
        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.30)) {
            chatPillShellHeight = height
        }
    }

    private var agentTerminalSource: ZebraAgentTerminalSource {
        .emailThread(panel.threadId)
    }

    /// Send the pill prompt into an agent terminal in the companion pane.
    /// A split is created only when this content pane has no reusable
    /// terminal companion yet.
    private func handlePillSubmit(text: String, agent: MarkdownPillAgent, workspace: Workspace) {
        guard let detail = detailStore.detail(threadId: panel.threadId) else { return }
        let surface = MarkdownChatPillContextSurface.email(
            detail: detail,
            threadSubject: panel.displayTitle,
            drafts: detailStore.drafts(threadId: panel.threadId)
        )
        let launchPlan = MarkdownChatPillCommand.launchPlan(
            agent: agent,
            markdownContent: nil,
            markdownFilePath: nil,
            fallbackDirectory: vaultState.selectedVaultPath,
            surface: surface,
            userPrompt: text
        )
        guard let startupLine = launchPlan.startupLine else { return }
        ZebraTelemetry.trackChatPillPromptSubmitted(
            surface: "email",
            submitMethod: "enter",
            agent: agent.rawValue,
            promptLength: text.count
        )

        #if DEBUG
        if !launchPlan.launchEnvironmentReady {
            cmuxDebugLog("email.chatPill.launchEnvironment.failed agent=\(agent.rawValue)")
        }
        #endif

        workspace.openZebraAgentTerminal(
            startupLine: startupLine,
            source: agentTerminalSource,
            agent: agent,
            anchor: .contentAnchored(contentPanelId: panel.id, contentPaneId: paneId),
            markedBy: agentTerminals
        )
    }

    private func startDefaultAgentManager(workspace: Workspace, agent: ZebraAgentKind?) {
        let cwd = defaultAgentManagerCWD()
        guard let startupLine = ZebraAgentOnboardingScriptCommand.shellStartupLine(
            command: .choosePrimary,
            cwd: cwd,
            agent: agent
        ) else {
            #if DEBUG
            cmuxDebugLog("email.chatPill.defaultAgent.scriptMissing")
            #endif
            return
        }
        let launchAgent = agent.map(MarkdownPillAgent.init(agentKind:)) ?? MarkdownPillAgent.defaultAgent()
        workspace.openZebraAgentTerminal(
            startupLine: startupLine,
            source: agentTerminalSource,
            agent: launchAgent,
            anchor: .contentAnchored(contentPanelId: panel.id, contentPaneId: paneId),
            markedBy: agentTerminals
        )
    }

    private func defaultAgentManagerCWD() -> String {
        let vaultPath = vaultState.selectedVaultPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let vaultPath, !vaultPath.isEmpty {
            return vaultPath
        }
        return NSHomeDirectory()
    }
}
