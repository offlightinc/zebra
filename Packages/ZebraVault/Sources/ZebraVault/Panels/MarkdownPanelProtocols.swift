import Bonsplit
import Combine
import Foundation

// Protocol seam between cmux's concrete `MarkdownPanel` / `Workspace` /
// `TerminalPanel` and ZebraVault's markdown-panel view. Conformances live
// on the cmux side under `Sources/Zebra/Adapters/MarkdownPanel+ZebraVault.swift`
// so this package never has to name the cmux model types.

@MainActor
public protocol ZebraMarkdownPanelModel: ObservableObject {
    var id: UUID { get }
    var filePath: String { get }
    var displayTitle: String { get }
    var content: String { get }
    var isFileUnavailable: Bool { get }
    /// Bumped each time cmux asks the panel to flash its focus ring.
    /// Drives a SwiftUI `.onChange` in `ZebraMarkdownPanelView`.
    var focusFlashToken: Int { get }
    func updateFrontmatter(key: String, value: String?)
}

@MainActor
public protocol ZebraTerminalPanel: AnyObject {
    var id: UUID { get }
    func sendInput(_ text: String)
    /// True once the underlying ghostty surface pointer is non-nil.
    var isSurfaceReady: Bool { get }
}

@MainActor
public protocol ZebraMarkdownWorkspace: AnyObject, ObservableObject {
    var allPaneIds: [PaneID] { get }

    func openOrFocusMarkdownSurface(
        inPane paneId: PaneID,
        filePath: String,
        focus: Bool
    ) -> (any ZebraMarkdownPanelModel)?

    func newTerminalSurface(
        inPane paneId: PaneID,
        focus: Bool?,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)?

    func newTerminalSplit(
        from panelId: UUID,
        orientation: SplitOrientation,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)?

    func paneId(forPanelId panelId: UUID) -> PaneID?
}
