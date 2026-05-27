import XCTest
@testable import ZebraVault

final class MarkdownChatPillLayoutTests: XCTestCase {
    func testMaxShellHeightStaysBaseInSmallVerticalSplitContent() {
        XCTAssertEqual(
            MarkdownChatPillLayout.maxShellHeight(availableContentHeight: 172),
            MarkdownChatPillLayout.expandedHeight
        )
    }

    func testMaxShellHeightGrowsAfterContentCanKeepReadableBody() {
        XCTAssertEqual(
            MarkdownChatPillLayout.maxShellHeight(availableContentHeight: 312),
            170
        )
    }

    func testMaxShellHeightCapsAtHardMaximumInTallContent() {
        XCTAssertEqual(
            MarkdownChatPillLayout.maxShellHeight(availableContentHeight: 372),
            MarkdownChatPillLayout.maxExpandedHeight
        )
    }

    func testInputHeightUsesPanelAwareCap() {
        XCTAssertEqual(
            MarkdownChatPillLayout.inputHeight(
                measuredContentHeight: 300,
                availableContentHeight: 312
            ),
            52
        )
    }

    func testInputHeightUsesHardCapWithoutPanelHeight() {
        XCTAssertEqual(
            MarkdownChatPillLayout.inputHeight(
                measuredContentHeight: 300,
                availableContentHeight: nil
            ),
            MarkdownChatPillLayout.maxExpandedInputHeight
        )
    }

    func testContentBottomInsetPreservesExistingBaseThenAddsGrowthDelta() {
        XCTAssertEqual(
            MarkdownChatPillLayout.contentBottomInset(shellHeight: MarkdownChatPillLayout.expandedHeight),
            MarkdownChatPillLayout.baseContentBottomInset
        )
        XCTAssertEqual(
            MarkdownChatPillLayout.contentBottomInset(shellHeight: MarkdownChatPillLayout.maxExpandedHeight),
            MarkdownChatPillLayout.baseContentBottomInset + 74
        )
    }
}
