import AppKit
import SwiftUI

/// NSViewRepresentable wrap around NSTextView so the chat pill input gets
/// the full macOS native text-editing surface: ⌘←/→, ⌥←/→, Home/End,
/// word-wise delete, ⇧+selection, undo, IME composition, etc.
///
/// Why not SwiftUI `TextField(axis: .vertical)`?
/// SwiftUI's macOS TextField is built on NSTextField and does not implement
/// the full Cocoa text-editing keymap — ⌘← jumps to start-of-line in
/// NSTextView but is silently swallowed in TextField. On top of that,
/// `.onKeyPress(...)` modifiers on an outer container can preempt the
/// focused TextField's key handling, which is exactly the trap the pill
/// fell into for arrow / shift-enter / cmd-arrow.
///
/// Submit policy (mirrors the prior pill behavior):
///   - plain ⏎              → `onReturn()` (caller picks slash row or submits)
///   - ⇧⏎ / ⌥⏎ / ⌃⏎ / ⌘⏎  → newline inserted natively
///   - bare ↑ / ↓           → `onMoveUp` / `onMoveDown` (slash picker nav)
///   - ⌘↑ / ⌥↑ / ⇧↑ etc.    → native caret movement (we do not intercept)
///   - Escape               → `onCancel()` (collapse-when-empty etc.)
struct MarkdownChatPillTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: NSFont
    let textColor: NSColor
    let caretColor: NSColor
    /// Called on bare ⏎. We always consume the keystroke (newline is
    /// reserved for ⇧⏎), so the callback has no return value — it's the
    /// caller's job to decide whether to act (submit, slash-pick) or
    /// no-op on the current state.
    let onReturn: () -> Void
    /// Bare ↑. Return `true` to consume (slash picker handled it), `false`
    /// to let NSTextView do native caret movement.
    let onMoveUp: () -> Bool
    /// Bare ↓. Same semantics as `onMoveUp`.
    let onMoveDown: () -> Bool
    /// Bare Escape. Same semantics as `onMoveUp`.
    let onCancel: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ChatPillNSTextView()
        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = caretColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.contentView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChatPillNSTextView else { return }
        // Keep the coordinator's parent pointer fresh so its closures
        // capture the latest SwiftUI state (text binding, callbacks).
        context.coordinator.parent = self

        if Self.syncExternalTextIfNeeded(textView, text: text) {
            Self.moveCaretToEnd(textView)
        }

        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }
        if textView.insertionPointColor != caretColor {
            textView.insertionPointColor = caretColor
        }

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                guard isFocused, let window = textView.window else { return }
                window.makeFirstResponder(textView)
                // SwiftUI parent re-expanding the pill expects the caret at
                // the end of the preserved text, not the implicit start.
                if !textView.hasMarkedText() {
                    Self.moveCaretToEnd(textView)
                }
            }
        }
    }

    /// Sync external SwiftUI text mutations (e.g. slash-pick replaced the
    /// line) into the native editor. During IME composition, NSTextView owns
    /// the in-progress marked text; overwriting `string` here can discard a
    /// partially-composed Korean syllable.
    @discardableResult
    static func syncExternalTextIfNeeded(_ textView: NSTextView, text: String) -> Bool {
        guard textView.string != text else { return false }
        guard !textView.hasMarkedText() else { return false }
        textView.string = text
        return true
    }

    /// Collapse selection to a zero-length range at the end of the text
    /// view's content. Called both when SwiftUI hands us new text (slash
    /// pick) and when the pill re-expands so the caret lands where the
    /// user last left off, not at offset 0.
    private static func moveCaretToEnd(_ textView: NSTextView) {
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownChatPillTextView
        init(_ parent: MarkdownChatPillTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }

        /// NSTextView's `interpretKeyEvents(_:)` routes every key gesture
        /// through here as a named selector. We claim only the four we
        /// care about — everything else returns `false` so AppKit applies
        /// its native handler (moveLeft:, moveRight:, moveWordLeft:,
        /// moveToBeginningOfLine:, delete*, undo, IME, etc.).
        ///
        /// Why we inspect the current event for `insertNewline:`:
        /// NSTextView's default key bindings dispatch BOTH plain Return
        /// and ⇧+Return to `insertNewline:`. To preserve the Slack/Discord
        /// "⇧⏎ inserts a newline, ⏎ submits" gesture, we look at the live
        /// NSEvent modifier flags and only claim the bare-Return path —
        /// returning `false` for ⇧⏎ lets NSTextView do its default and
        /// insert a real \n. Any other modifier (⌥/⌃/⌘) also falls through.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                guard !textView.hasMarkedText() else { return false }
                let mods = NSApp.currentEvent?.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .subtracting([.numericPad, .function, .capsLock]) ?? []
                if !mods.isEmpty {
                    return false
                }
                parent.onReturn()
                return true
            case #selector(NSResponder.moveUp(_:)):
                guard !textView.hasMarkedText() else { return false }
                return parent.onMoveUp()
            case #selector(NSResponder.moveDown(_:)):
                guard !textView.hasMarkedText() else { return false }
                return parent.onMoveDown()
            case #selector(NSResponder.cancelOperation(_:)):
                guard !textView.hasMarkedText() else { return false }
                return parent.onCancel()
            default:
                return false
            }
        }
    }

    final class ChatPillNSTextView: NSTextView {
        weak var coordinator: Coordinator?

        /// AppKit asks every view in the window — including SwiftUI hosts
        /// of the surrounding markdown panel — `performKeyEquivalent:` before
        /// `keyDown:` reaches the first responder. Some of those hosting
        /// views claim bare ↑/↓/←/→ for their own focus traversal, which
        /// short-circuits our text editor.
        ///
        /// We claim plain arrows ourselves when we own first responder and
        /// hand them straight to `keyDown:` so the standard
        /// `interpretKeyEvents` flow runs and the caret moves.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if self.window?.firstResponder === self,
               (event.keyCode == 123  // ←
                || event.keyCode == 124  // →
                || event.keyCode == 125  // ↓
                || event.keyCode == 126) // ↑
            {
                let mods = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .subtracting([.numericPad, .function, .capsLock])
                // Anything with Command falls through to AppKit so global
                // shortcuts (focus-pane navigation, etc.) keep working.
                if !mods.contains(.command) {
                    self.keyDown(with: event)
                    return true
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        override func becomeFirstResponder() -> Bool {
            let ok = super.becomeFirstResponder()
            if ok, let coordinator, !coordinator.parent.isFocused {
                // `parent` is a struct snapshot, but `isFocused` is an
                // @Binding — assigning through it goes back to SwiftUI's
                // source-of-truth, so the stale-snapshot worry doesn't
                // apply to binding members.
                let parent = coordinator.parent
                DispatchQueue.main.async {
                    if !parent.isFocused { parent.isFocused = true }
                }
            }
            return ok
        }

        override func resignFirstResponder() -> Bool {
            let ok = super.resignFirstResponder()
            if ok, let coordinator, coordinator.parent.isFocused {
                let parent = coordinator.parent
                DispatchQueue.main.async {
                    if parent.isFocused { parent.isFocused = false }
                }
            }
            return ok
        }
    }
}
