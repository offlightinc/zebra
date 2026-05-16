import Bonsplit
import Foundation

extension Workspace {
    /// Open a markdown panel for `filePath` in the requested pane, or focus
    /// the existing panel if one is already open for the same file (after
    /// symlink resolution).
    ///
    /// Lives in the Zebra layer because the markdown panel itself is a
    /// Zebra concept (brain-object inspector + chat pill). Routing through
    /// `Workspace.newFilePreviewSurface` from cmux paths still works
    /// independently — this entry point is for the goals / tasks / docs
    /// sidebar modes that need the richer markdown panel.
    @discardableResult
    func openOrFocusMarkdownSurface(
        inPane paneId: PaneID,
        filePath: String,
        focus: Bool = true
    ) -> MarkdownPanel? {
        let canonical = (filePath as NSString).resolvingSymlinksInPath
        for (existingId, panel) in panels {
            guard let markdown = panel as? MarkdownPanel else { continue }
            if (markdown.filePath as NSString).resolvingSymlinksInPath == canonical {
                if focus {
                    focusPanel(existingId)
                }
                return markdown
            }
        }

        return newMarkdownSurface(inPane: paneId, filePath: filePath, focus: focus)
    }
}
