import Foundation

public enum MarkdownInspectorVisibilityIntent: Equatable {
    case defaultShown
    case userShown
    case userHidden

    public var wantsVisible: Bool {
        self != .userHidden
    }
}

public struct MarkdownInspectorVisibilityState: Equatable {
    public let isVisible: Bool
    public let isAutoCollapsed: Bool

    public init(isVisible: Bool, isAutoCollapsed: Bool) {
        self.isVisible = isVisible
        self.isAutoCollapsed = isAutoCollapsed
    }
}

public enum MarkdownInspectorVisibilityPolicy {
    public static let markdownMinWidth: Double = 360
    public static let minInspectorWidth: Double = 280
    public static let maxInspectorWidth: Double = 420
    public static let dividerWidth: Double = 1

    public static var minimumPaneWidthForInspector: Double {
        markdownMinWidth + dividerWidth + minInspectorWidth
    }

    public static var preferredPaneWidthForInspectorReveal: Double {
        minimumPaneWidthForInspector + 24
    }

    public static func canRenderInspector(paneWidth: Double?) -> Bool {
        guard let paneWidth, paneWidth.isFinite else { return true }
        return paneWidth >= minimumPaneWidthForInspector
    }

    public static func state(
        intent: MarkdownInspectorVisibilityIntent,
        paneWidth: Double?
    ) -> MarkdownInspectorVisibilityState {
        let canRender = canRenderInspector(paneWidth: paneWidth)
        let wantsVisible = intent.wantsVisible
        return MarkdownInspectorVisibilityState(
            isVisible: wantsVisible && canRender,
            isAutoCollapsed: wantsVisible && !canRender
        )
    }
}
