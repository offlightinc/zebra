import SwiftUI
import Foundation
import Bonsplit
import AppKit

/// Context handed to an external panel renderer registered through
/// `customPanelViewFactory`. The factory receives the abstract `any Panel`
/// — concrete-type casts (e.g. to `ZebraEmailThreadPanel`) live in the
/// registering module so cmux common code stays free of Zebra-specific
/// types.
struct CustomPanelViewContext {
    let panel: any Panel
    let paneId: PaneID
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void
}

typealias CustomPanelViewFactory = (CustomPanelViewContext) -> AnyView?

private struct CustomPanelViewFactoryKey: EnvironmentKey {
    static let defaultValue: CustomPanelViewFactory? = nil
}

extension EnvironmentValues {
    /// Generic panel renderer seam. Currently used by Zebra-owned panel
    /// kinds (e.g. `.email`). Cmux common code only knows the factory
    /// signature; it never references the concrete Zebra panel type.
    var customPanelViewFactory: CustomPanelViewFactory? {
        get { self[CustomPanelViewFactoryKey.self] }
        set { self[CustomPanelViewFactoryKey.self] = newValue }
    }
}

/// View that renders the appropriate panel view based on panel type
struct PanelContentView: View {
    let panel: any Panel
    let workspaceId: UUID
    let paneId: PaneID
    let isFocused: Bool
    let isSelectedInPane: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let isSplit: Bool
    let appearance: PanelAppearance
    let hasUnreadNotification: Bool
    let onFocus: () -> Void
    let onRequestPanelFocus: () -> Void
    let onTriggerFlash: () -> Void
    @Environment(\.markdownPanelViewFactory) private var markdownPanelViewFactory
    @Environment(\.customPanelViewFactory) private var customPanelViewFactory

    var body: some View {
        renderedPanel
            .overlay {
                paneDropTargetOverlay
            }
    }

    @ViewBuilder
    private var renderedPanel: some View {
        switch panel.panelType {
        case .terminal:
            if let terminalPanel = panel as? TerminalPanel {
                TerminalPanelView(
                    panel: terminalPanel,
                    paneId: paneId,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    isSplit: isSplit,
                    appearance: appearance,
                    hasUnreadNotification: hasUnreadNotification,
                    onFocus: onFocus,
                    onTriggerFlash: onTriggerFlash
                )
            }
        case .browser:
            if let browserPanel = panel as? BrowserPanel {
                BrowserPanelView(
                    panel: browserPanel,
                    paneId: paneId,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .markdown:
            if let markdownPanel = panel as? MarkdownPanel,
               let factory = markdownPanelViewFactory {
                factory(MarkdownPanelViewContext(
                    panel: markdownPanel,
                    paneId: paneId,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    onRequestPanelFocus: onRequestPanelFocus
                ))
            }
        case .filePreview:
            if let filePreviewPanel = panel as? FilePreviewPanel {
                FilePreviewPanelView(
                    panel: filePreviewPanel,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    portalPriority: portalPriority,
                    appearance: appearance,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .rightSidebarTool:
            if let rightSidebarToolPanel = panel as? RightSidebarToolPanel {
                RightSidebarToolPanelView(
                    panel: rightSidebarToolPanel,
                    isFocused: isFocused,
                    isVisibleInUI: isVisibleInUI,
                    appearance: appearance,
                    onRequestPanelFocus: onRequestPanelFocus
                )
            }
        case .email:
            // Cmux common code stays Zebra-type-free. The registered
            // `customPanelViewFactory` (set up by `ZebraServices`) decides
            // how to render and what concrete panel type to cast to.
            if let factory = customPanelViewFactory,
               let view = factory(CustomPanelViewContext(
                   panel: panel,
                   paneId: paneId,
                   isFocused: isFocused,
                   isVisibleInUI: isVisibleInUI,
                   portalPriority: portalPriority,
                   onRequestPanelFocus: onRequestPanelFocus
               )) {
                view
            }
        }
    }

    @ViewBuilder
    private var paneDropTargetOverlay: some View {
        if shouldInstallPaneDropTarget {
            PaneDropTargetRepresentable(dropContext: PaneDropContext(
                workspaceId: workspaceId,
                panelId: panel.id,
                paneId: paneId
            ))
        }
    }

    private var shouldInstallPaneDropTarget: Bool {
        guard isVisibleInUI else { return false }
        switch panel.panelType {
        case .markdown, .filePreview, .rightSidebarTool, .email:
            return true
        case .terminal, .browser:
            return false
        }
    }
}

struct PanelFilePathHeader<TrailingContent: View>: View {
    let iconSystemName: String
    let filePath: String
    let foregroundColor: NSColor
    @ViewBuilder let trailingContent: () -> TrailingContent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconSystemName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(filePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(nsColor: foregroundColor).opacity(0.68))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            trailingContent()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color.clear)
    }
}

struct PanelHeaderIconButton: View {
    let systemName: String
    let label: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PanelHeaderIconGlyph(systemName: systemName)
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .disabled(isDisabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct PanelHeaderIconGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: 13, height: 13)
            .frame(width: 20, height: 20, alignment: .center)
            .contentShape(Rectangle())
    }
}
