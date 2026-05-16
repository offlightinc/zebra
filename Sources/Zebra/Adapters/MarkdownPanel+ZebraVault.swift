import Bonsplit
import Foundation
import ZebraVault

// MARK: - cmux model conformances to ZebraVault protocols
//
// `MarkdownPanel`, `TerminalPanel`, and `Workspace` are internal to the
// cmux app target. The protocols (`ZebraMarkdownPanelModel`,
// `ZebraTerminalPanel`, `ZebraMarkdownWorkspace`) live in the ZebraVault
// SPM package. Conformances stay on the cmux side because that is where
// the conformed types live; Zebra views consume them only through the
// protocol-typed surface.

extension MarkdownPanel: ZebraMarkdownPanelModel {}

extension TerminalPanel: ZebraTerminalPanel {
    var isSurfaceReady: Bool {
        surface.surface != nil
    }
}

extension Workspace: ZebraMarkdownWorkspace {
    var allPaneIds: [PaneID] {
        bonsplitController.allPaneIds
    }

    func openOrFocusMarkdownSurface(
        inPane paneId: PaneID,
        filePath: String,
        focus: Bool
    ) -> (any ZebraMarkdownPanelModel)? {
        let concrete: MarkdownPanel? = openOrFocusMarkdownSurface(
            inPane: paneId,
            filePath: filePath,
            focus: focus
        )
        return concrete
    }

    func newTerminalSurface(
        inPane paneId: PaneID,
        focus: Bool?,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)? {
        let concrete: TerminalPanel? = newTerminalSurface(
            inPane: paneId,
            focus: focus,
            initialCommand: initialCommand
        )
        return concrete
    }

    func newTerminalSplit(
        from panelId: UUID,
        orientation: SplitOrientation,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)? {
        let concrete: TerminalPanel? = newTerminalSplit(
            from: panelId,
            orientation: orientation,
            initialCommand: initialCommand
        )
        return concrete
    }
}
