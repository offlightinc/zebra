import AppKit
import Bonsplit
import Combine
import Foundation
import ZebraVault

/// Side-car for `MarkdownPanel`. Holds every piece of state that used to
/// live on the panel model but only matters to Zebra's inspector / chat
/// pill / brain-object workflow.
///
/// Owned by `ZebraServices.panelControllers` — see the hard constraints in
/// `/Users/han/.claude/plans/cmux-zbrown-cmux-wise-treasure.md` Phase 2.2:
///
/// 1. Owner = `ZebraServices.panelControllers` (app-wide). Views may only
///    observe it via `@ObservedObject`. **No `@StateObject` in any view**
///    — that re-creates the controller on view churn and the chat pill's
///    `chatCompanionPaneId` would silently reset every time the markdown
///    panel disappears and reappears (split reparent, tab switch, etc.).
/// 2. Cleanup runs in response to `MarkdownPanel.close()` posting
///    `markdownPanelDidClose`. Never tie cleanup to a SwiftUI view's
///    `onDisappear` — the panel object can outlive any individual view.
@MainActor
final class MarkdownPanelController: ObservableObject {
    /// Latest parsed brain object. `nil` while the first parse is in
    /// flight; the view layer shows the loading skeleton in that window.
    @Published private(set) var parse: BrainObjectParse?

    /// Whether the right-pane inspector is visible. Persisted per main
    /// window via UserDefaults.
    @Published var showsInspector: Bool

    /// Pane where the markdown chat pill accumulates agent terminal tabs.
    /// Stored on the controller (panel-identified, not view-identified) so
    /// split layout reparenting does not lose the companion-pane reference.
    @Published var chatCompanionPaneId: PaneID?
    @Published var chatCompanionAgent: MarkdownPillAgent?

    private weak var panel: MarkdownPanel?
    private var contentCancellable: AnyCancellable?
    private let parseQueue = DispatchQueue(label: "com.cmux.brain-object-parse", qos: .userInitiated)
    private var parseGeneration: Int = 0

    private static let inspectorVisibilityKey = "cmux.brainViewer.showsInspector"

    init(panel: MarkdownPanel) {
        self.panel = panel
        self.showsInspector = Self.loadInspectorVisibility()
        // Subscribe to content changes once; every disk reload, optimistic
        // frontmatter update, or initial load fires a parse here. View
        // lifecycle does not affect this subscription.
        self.contentCancellable = panel.$content
            .sink { [weak self] newContent in
                self?.scheduleParse(of: newContent, filePath: panel.filePath)
            }
    }

    /// Toggle inspector visibility and persist to UserDefaults.
    func toggleInspector() {
        showsInspector.toggle()
        UserDefaults.standard.set(showsInspector, forKey: Self.inspectorVisibilityKey)
    }

    private func scheduleParse(of content: String, filePath: String) {
        parseGeneration &+= 1
        let gen = parseGeneration
        parseQueue.async { [weak self] in
            let result = BrainObjectParser.parse(content, filename: filePath)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.parseGeneration == gen else { return }
                self.parse = result
            }
        }
    }

    private static func loadInspectorVisibility() -> Bool {
        if UserDefaults.standard.object(forKey: inspectorVisibilityKey) == nil {
            // Inspector ships visible by default — that's the whole point
            // of the brain-viewer feature.
            return true
        }
        return UserDefaults.standard.bool(forKey: inspectorVisibilityKey)
    }
}

/// Per-panel registry of `MarkdownPanelController` instances. Looked up by
/// `panel.id`. Releases entries when `MarkdownPanel` posts
/// `markdownPanelDidClose` so closed panels don't pin controllers forever.
@MainActor
final class MarkdownPanelControllerRegistry {
    private var controllers: [UUID: MarkdownPanelController] = [:]
    private var closeObserver: NSObjectProtocol?

    init() {
        closeObserver = NotificationCenter.default.addObserver(
            forName: MarkdownPanel.didCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let panel = notification.object as? MarkdownPanel else { return }
            MainActor.assumeIsolated {
                self?.release(panelId: panel.id)
            }
        }
    }

    deinit {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    /// Look up (or lazily create) the controller for a panel. Stable across
    /// view churn because the registry outlives any individual SwiftUI view.
    func controller(for panel: MarkdownPanel) -> MarkdownPanelController {
        if let existing = controllers[panel.id] {
            return existing
        }
        let created = MarkdownPanelController(panel: panel)
        controllers[panel.id] = created
        return created
    }

    private func release(panelId: UUID) {
        controllers.removeValue(forKey: panelId)
    }
}
