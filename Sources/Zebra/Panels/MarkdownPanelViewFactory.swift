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
                        store: services.emailDetail
                    )
                )
            }
            return nil
        }
    }
}

private struct ZebraEmailPanelHost: View {
    let panel: ZebraEmailThreadPanel
    @ObservedObject var store: ZebraEmailDetailStore

    var body: some View {
        ZebraEmailThreadDetailView(
            subject: panel.displayTitle,
            detail: store.detail(threadId: panel.threadId),
            isLoading: store.isLoading(threadId: panel.threadId),
            errorMessage: store.errorMessage(threadId: panel.threadId),
            expandedMessageIds: store.expandedMessageIds(threadId: panel.threadId),
            onRefresh: {
                Task { await store.reloadThread(threadId: panel.threadId, forceRefresh: true) }
            },
            onToggleMessage: { messageId in
                store.toggleMessage(threadId: panel.threadId, messageId: messageId)
            },
            onOpenURL: { url in
                NSWorkspace.shared.open(url)
            }
        )
        .task(id: panel.threadId) {
            await store.loadThreadIfNeeded(threadId: panel.threadId)
        }
    }
}
