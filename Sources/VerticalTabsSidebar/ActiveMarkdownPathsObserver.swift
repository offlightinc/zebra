import Combine
import Foundation

@MainActor
final class ActiveMarkdownPathsObserver: ObservableObject {
    @Published private(set) var paths: Set<String> = []

    private weak var tabManager: TabManager?
    private var selectedTabCancellable: AnyCancellable?
    private var workspaceCancellable: AnyCancellable?

    func wire(tabManager: TabManager) {
        guard self.tabManager !== tabManager else { return }
        self.tabManager = tabManager
        selectedTabCancellable = tabManager.$selectedTabId
            .sink { [weak self, weak tabManager] _ in
                guard let self, let tabManager else { return }
                self.rebindToSelectedWorkspace(tabManager: tabManager)
            }
        rebindToSelectedWorkspace(tabManager: tabManager)
    }

    func recompute() {
        guard let tabManager else {
            paths = []
            return
        }
        guard let workspace = currentWorkspace(in: tabManager) else {
            paths = []
            return
        }
        paths = Self.collectActiveMarkdownPaths(in: workspace)
    }

    private func rebindToSelectedWorkspace(tabManager: TabManager) {
        workspaceCancellable = nil
        guard let workspace = currentWorkspace(in: tabManager) else {
            paths = []
            return
        }
        workspaceCancellable = workspace.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak workspace] _ in
                // objectWillChange fires BEFORE @Published mutations land.
                // Defer one main-actor turn so we observe post-mutation state.
                DispatchQueue.main.async {
                    guard let self, let workspace else { return }
                    let next = Self.collectActiveMarkdownPaths(in: workspace)
                    if next != self.paths {
                        self.paths = next
                    }
                }
            }
        recompute()
    }

    private func currentWorkspace(in tabManager: TabManager) -> Workspace? {
        guard let selectedId = tabManager.selectedTabId else { return nil }
        return tabManager.tabs.first(where: { $0.id == selectedId })
    }

    private static func collectActiveMarkdownPaths(in workspace: Workspace) -> Set<String> {
        var paths: Set<String> = []
        for paneId in workspace.bonsplitController.allPaneIds {
            guard let tab = workspace.bonsplitController.selectedTab(inPane: paneId) else { continue }
            guard let panelId = workspace.panelIdFromSurfaceId(tab.id) else { continue }
            // Markdown can land in either panel kind: FilePreviewPanel is the
            // generic preview surface, MarkdownPanel is the richer view that also
            // hosts the brain object inspector. Accept both so sidebar highlight
            // works regardless of which entrypoint opened the file.
            let filePath: String
            if let preview = workspace.panels[panelId] as? FilePreviewPanel {
                filePath = preview.filePath
            } else if let markdown = workspace.panels[panelId] as? MarkdownPanel {
                filePath = markdown.filePath
            } else {
                continue
            }
            let ext = (filePath as NSString).pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                paths.insert(filePath)
            }
        }
        return paths
    }
}
