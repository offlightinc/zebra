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
            let controller = services.panelControllers.controller(for: context.panel)
            return AnyView(
                ZebraMarkdownPanelHost(context: context, controller: controller)
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
    @EnvironmentObject private var tabManager: TabManager

    var body: some View {
        if let workspace = tabManager.tabs.first(where: { $0.id == context.panel.workspaceId }) {
            ZebraMarkdownPanelView(
                panel: context.panel,
                controller: controller,
                workspace: workspace,
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

struct ZebraEmailPanelViewContext {
    let panel: ZebraEmailThreadPanel
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void
}

typealias ZebraEmailPanelViewFactory = (ZebraEmailPanelViewContext) -> AnyView

private struct ZebraEmailPanelViewFactoryKey: EnvironmentKey {
    static let defaultValue: ZebraEmailPanelViewFactory? = nil
}

extension EnvironmentValues {
    var zebraEmailPanelViewFactory: ZebraEmailPanelViewFactory? {
        get { self[ZebraEmailPanelViewFactoryKey.self] }
        set { self[ZebraEmailPanelViewFactoryKey.self] = newValue }
    }
}

enum ZebraEmailPanelViewFactoryProvider {
    @MainActor
    static func make(services: ZebraServices) -> ZebraEmailPanelViewFactory {
        { context in
            AnyView(
                ZebraEmailPanelHost(context: context, store: services.emailDetail)
            )
        }
    }
}

private struct ZebraEmailPanelHost: View {
    let context: ZebraEmailPanelViewContext
    @ObservedObject var store: ZebraEmailDetailStore

    var body: some View {
        ZebraEmailThreadDetailView(
            subject: context.panel.displayTitle,
            detail: store.detail(threadId: context.panel.threadId),
            isLoading: store.isLoading(threadId: context.panel.threadId),
            errorMessage: store.errorMessage(threadId: context.panel.threadId),
            expandedMessageIds: store.expandedMessageIds(threadId: context.panel.threadId),
            onRefresh: {
                Task { await store.reloadThread(threadId: context.panel.threadId, forceRefresh: true) }
            },
            onToggleMessage: { messageId in
                store.toggleMessage(threadId: context.panel.threadId, messageId: messageId)
            },
            onOpenURL: { url in
                NSWorkspace.shared.open(url)
            }
        )
        .task(id: context.panel.threadId) {
            await store.loadThreadIfNeeded(threadId: context.panel.threadId)
        }
    }
}
