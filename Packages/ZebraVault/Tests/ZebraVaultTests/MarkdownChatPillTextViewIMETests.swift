import AppKit
import SwiftUI
import XCTest
@testable import ZebraVault

@MainActor
final class MarkdownChatPillTextViewIMETests: XCTestCase {
    func testExternalSyncSkipsActiveKoreanMarkedText() {
        let textView = MarkdownChatPillTextView.ChatPillNSTextView(frame: .zero)
        textView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(textView.hasMarkedText())
        let stringBeforeSync = textView.string
        let markedRangeBeforeSync = textView.markedRange()

        let didSync = MarkdownChatPillTextView.syncExternalTextIfNeeded(
            textView,
            text: ""
        )

        XCTAssertFalse(didSync)
        XCTAssertEqual(textView.string, stringBeforeSync)
        XCTAssertEqual(textView.markedRange(), markedRangeBeforeSync)
        XCTAssertTrue(textView.hasMarkedText())
    }

    func testExternalSyncStillAppliesWhenNotComposing() {
        let textView = MarkdownChatPillTextView.ChatPillNSTextView(frame: .zero)
        textView.string = "old"

        let didSync = MarkdownChatPillTextView.syncExternalTextIfNeeded(
            textView,
            text: "new"
        )

        XCTAssertTrue(didSync)
        XCTAssertEqual(textView.string, "new")
        XCTAssertFalse(textView.hasMarkedText())
    }

    func testReturnDoesNotSubmitDuringKoreanMarkedText() {
        var didSubmit = false
        let coordinator = MarkdownChatPillTextView.Coordinator(
            parent(onReturn: { didSubmit = true })
        )
        let textView = MarkdownChatPillTextView.ChatPillNSTextView(frame: .zero)
        textView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let handled = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertFalse(handled)
        XCTAssertFalse(didSubmit)
        XCTAssertTrue(textView.hasMarkedText())
    }

    func testReturnStillSubmitsWhenNotComposing() {
        var didSubmit = false
        let coordinator = MarkdownChatPillTextView.Coordinator(
            parent(onReturn: { didSubmit = true })
        )
        let textView = MarkdownChatPillTextView.ChatPillNSTextView(frame: .zero)

        let handled = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didSubmit)
    }

    func testCancelDoesNotCollapseDuringKoreanMarkedText() {
        var didCancel = false
        let coordinator = MarkdownChatPillTextView.Coordinator(
            parent(onCancel: {
                didCancel = true
                return true
            })
        )
        let textView = MarkdownChatPillTextView.ChatPillNSTextView(frame: .zero)
        textView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let handled = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        )

        XCTAssertFalse(handled)
        XCTAssertFalse(didCancel)
        XCTAssertTrue(textView.hasMarkedText())
    }

    func testArrowNavigationDoesNotMoveSlashSelectionDuringKoreanMarkedText() {
        var didMoveUp = false
        var didMoveDown = false
        let coordinator = MarkdownChatPillTextView.Coordinator(
            parent(
                onMoveUp: {
                    didMoveUp = true
                    return true
                },
                onMoveDown: {
                    didMoveDown = true
                    return true
                }
            )
        )
        let textView = MarkdownChatPillTextView.ChatPillNSTextView(frame: .zero)
        textView.setMarkedText(
            "한",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let handledUp = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.moveUp(_:))
        )
        let handledDown = coordinator.textView(
            textView,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        )

        XCTAssertFalse(handledUp)
        XCTAssertFalse(handledDown)
        XCTAssertFalse(didMoveUp)
        XCTAssertFalse(didMoveDown)
        XCTAssertTrue(textView.hasMarkedText())
    }

    private func parent(
        onReturn: @escaping () -> Void = {},
        onMoveUp: @escaping () -> Bool = { false },
        onMoveDown: @escaping () -> Bool = { false },
        onCancel: @escaping () -> Bool = { false }
    ) -> MarkdownChatPillTextView {
        MarkdownChatPillTextView(
            text: .constant(""),
            isFocused: .constant(false),
            font: NSFont.systemFont(ofSize: 14),
            textColor: .textColor,
            caretColor: .controlAccentColor,
            onReturn: onReturn,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown,
            onCancel: onCancel
        )
    }
}
