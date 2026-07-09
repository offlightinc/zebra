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
///    — that re-creates the controller on view churn and loses per-panel
///    inspector / parse state every time the markdown panel disappears and
///    reappears (split reparent, tab switch, etc.).
/// 2. Cleanup runs in response to `MarkdownPanel.close()` posting
///    `markdownPanelDidClose`. Never tie cleanup to a SwiftUI view's
///    `onDisappear` — the panel object can outlive any individual view.
@MainActor
final class MarkdownPanelController: ObservableObject {
    /// Latest parsed brain object. `nil` while the first parse is in
    /// flight; the view layer shows the loading skeleton in that window.
    @Published private(set) var parse: BrainObjectParse?

    /// The user's explicit inspector intent for this markdown panel. New
    /// panels start visible by default; width-based auto-collapse is derived
    /// in the view and never writes back here.
    @Published private(set) var inspectorVisibilityIntent: MarkdownInspectorVisibilityIntent = .defaultShown

    /// Bumped when the user asks to reveal an auto-collapsed inspector while
    /// the panel already wants the inspector visible. This gives SwiftUI a real
    /// observed state change even though the visibility intent did not change.
    @Published private(set) var inspectorRevealToken: Int = 0

    private weak var panel: MarkdownPanel?
    private var contentCancellable: AnyCancellable?
    private let parseQueue = DispatchQueue(label: "com.cmux.brain-object-parse", qos: .userInitiated)
    private var parseGeneration: Int = 0

    init(panel: MarkdownPanel) {
        self.panel = panel
        // Subscribe to content changes once; every disk reload, optimistic
        // frontmatter update, or initial load fires a parse here. View
        // lifecycle does not affect this subscription.
        self.contentCancellable = panel.$content
            .sink { [weak self] newContent in
                self?.scheduleParse(of: newContent, filePath: panel.filePath)
            }
    }

    var wantsInspectorVisible: Bool {
        inspectorVisibilityIntent.wantsVisible
    }

    /// Toggle only this markdown panel's user intent.
    func toggleInspector() {
        let newVisible = !wantsInspectorVisible
        setInspectorVisibility(newVisible)
        ZebraTelemetry.trackInspectorToggled(visible: newVisible)
    }

    /// Set this panel's inspector visibility intent. Auto-collapse in the view
    /// layer must not call this with `false`.
    func setInspectorVisibility(_ visible: Bool) {
        inspectorVisibilityIntent = visible ? .userShown : .userHidden
    }

    /// Preserve the user's "show inspector" intent and force one render pass.
    /// Used when the inspector is auto-collapsed by width rather than manually
    /// hidden by the user.
    func revealInspector() {
        if !wantsInspectorVisible {
            setInspectorVisibility(true)
        }
        inspectorRevealToken &+= 1
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

}

/// Per-panel registry of `MarkdownPanelController` instances. Looked up by
/// `panel.id`. Releases entries when `MarkdownPanel` posts
/// `markdownPanelDidClose` so closed panels don't pin controllers forever.
@MainActor
final class MarkdownPanelControllerRegistry {
    private var controllers: [UUID: MarkdownPanelController] = [:]
    private var closedPanelIds: Set<UUID> = []
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
        closedPanelIds.remove(panel.id)
        let created = MarkdownPanelController(panel: panel)
        controllers[panel.id] = created
        return created
    }

    /// Same as `controller(for:)`, but refuses stale view work for panels that
    /// already completed their close lifecycle. SwiftUI can briefly ask the
    /// factory to rebuild content for a closed tab while Bonsplit is tearing
    /// down the subtree; that must not resurrect per-tab inspector state.
    func controllerIfOpen(for panel: MarkdownPanel) -> MarkdownPanelController? {
        guard !closedPanelIds.contains(panel.id) else { return nil }
        return controller(for: panel)
    }

    func hasController(for panel: MarkdownPanel) -> Bool {
        controllers[panel.id] != nil
    }

    private func release(panelId: UUID) {
        controllers.removeValue(forKey: panelId)
        closedPanelIds.insert(panelId)
    }
}
