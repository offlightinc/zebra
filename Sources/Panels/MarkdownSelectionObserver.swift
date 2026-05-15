import AppKit
import SwiftUI

/// Invisible SwiftUI view that observes NSTextView selection changes inside
/// the markdown body and reports captured snapshots back to its parent.
///
/// Background:
/// `MarkdownUI` renders the markdown body with SwiftUI `Text` views and
/// `.textSelection(.enabled)`. SwiftUI does not expose a `selectedRange`
/// API on `Text`; under the hood macOS instantiates `NSTextView`s for the
/// selection-capable text. The reliable way to watch user highlights is
/// therefore the AppKit notification `NSText.didChangeSelectionNotification`,
/// filtered to NSTextViews that live inside this observer's hosting NSView
/// hierarchy. Anything outside our subtree (other panels, sidebars, dialogs)
/// is ignored.
///
/// The observer is rendered into the parent via `.background(...)` so it
/// gets a real NSView in the panel's hierarchy but does not paint anything.
struct MarkdownSelectionObserver: NSViewRepresentable {
    /// Snapshot of the latest markdown source so the captured selection can
    /// be reverse-looked-up against it (for the nearest preceding heading).
    let panelContent: String
    /// Called whenever the selection inside this observer's subtree changes.
    /// Receives `nil` when the user has no active selection (or the selection
    /// is too short — `MarkdownChatPillSelection.capture` filters those out).
    let onChange: (MarkdownChatPillSelection?) -> Void

    func makeNSView(context: Context) -> SelectionObserverView {
        let view = SelectionObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SelectionObserverView, context: Context) {
        // panelContent and onChange are captured in the coordinator on every
        // SwiftUI update — keeps the closure pointing at the latest @State
        // bindings without rebuilding the NSView.
        context.coordinator.panelContent = panelContent
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(panelContent: panelContent, onChange: onChange)
    }

    final class Coordinator {
        var panelContent: String
        var onChange: (MarkdownChatPillSelection?) -> Void
        /// The hosting NSView attached as background to the markdown panel.
        /// We use this to scope the global selection-change notification to
        /// only those NSTextViews that descend from this subtree.
        weak var hostView: NSView?
        private var observer: NSObjectProtocol?

        init(panelContent: String, onChange: @escaping (MarkdownChatPillSelection?) -> Void) {
            self.panelContent = panelContent
            self.onChange = onChange
            // AppKit emits this as `NSTextDidChangeSelectionNotification`,
            // posted by NSTextView whenever the user's selection changes.
            // (`NSText.didChangeSelectionNotification` doesn't exist as a
            // Swift symbol on the macOS SDK we target — use the raw name.)
            self.observer = NotificationCenter.default.addObserver(
                forName: Notification.Name("NSTextViewDidChangeSelectionNotification"),
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.handle(note)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        private func handle(_ note: Notification) {
            guard let textView = note.object as? NSTextView,
                  let hostView else { return }
            // The observer view is attached via `.background(...)` so the
            // markdown-body NSTextView is a *sibling*, not a descendant —
            // `isDescendant(of: hostView)` would always be false. Falling
            // back to window-equality scopes us to the same NSWindow, which
            // matches the current single-markdown-panel-per-window reality.
            // Multi-panel disambiguation (plan §D1) can revisit by walking
            // to a shared NSHostingView ancestor.
            guard let window = hostView.window,
                  textView.window === window else { return }

            // Force the highlight color to mockup yellow (#e8b75c @ 0.35).
            // NSTextView's default selectedTextAttributes uses the system
            // blue. We rewrite it on every notification because MarkdownUI
            // re-renders create fresh NSTextViews — there is no global
            // "set this once" hook we can use without subclassing.
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor(
                    red: 232.0 / 255,
                    green: 183.0 / 255,
                    blue: 92.0 / 255,
                    alpha: 0.35
                )
            ]

            let nsString = textView.string as NSString
            let selectedText = textView.selectedRanges
                .compactMap { value -> String? in
                    let range = value.rangeValue
                    guard range.length > 0,
                          range.location + range.length <= nsString.length else { return nil }
                    return nsString.substring(with: range)
                }
                .joined(separator: "\n")

            let snapshot = MarkdownChatPillSelection.capture(
                rawText: selectedText,
                in: panelContent
            )
            onChange(snapshot)
        }
    }

    /// Concrete NSView the SwiftUI representable hosts. Doesn't paint —
    /// only exists so the coordinator has an anchor in the view hierarchy
    /// for the `isDescendant(of:)` filter.
    final class SelectionObserverView: NSView {
        weak var coordinator: Coordinator?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            // No drawing, no hit-testing — fully transparent overlay.
        }

        required init?(coder: NSCoder) { super.init(coder: coder) }

        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.hostView = self
        }
    }
}
