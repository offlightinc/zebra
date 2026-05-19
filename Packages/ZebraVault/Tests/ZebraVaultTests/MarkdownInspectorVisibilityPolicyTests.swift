import XCTest
@testable import ZebraVault

final class MarkdownInspectorVisibilityPolicyTests: XCTestCase {
    func testDefaultShownAutoCollapsesBelowMinimumWidth() {
        let state = MarkdownInspectorVisibilityPolicy.state(
            intent: .defaultShown,
            paneWidth: MarkdownInspectorVisibilityPolicy.minimumPaneWidthForInspector - 1
        )

        XCTAssertFalse(state.isVisible)
        XCTAssertTrue(state.isAutoCollapsed)
    }

    func testDefaultShownBecomesVisibleAtMinimumWidth() {
        let state = MarkdownInspectorVisibilityPolicy.state(
            intent: .defaultShown,
            paneWidth: MarkdownInspectorVisibilityPolicy.minimumPaneWidthForInspector
        )

        XCTAssertTrue(state.isVisible)
        XCTAssertFalse(state.isAutoCollapsed)
    }

    func testUserShownStillAutoCollapsesBelowMinimumWidth() {
        let state = MarkdownInspectorVisibilityPolicy.state(
            intent: .userShown,
            paneWidth: MarkdownInspectorVisibilityPolicy.minimumPaneWidthForInspector - 1
        )

        XCTAssertFalse(state.isVisible)
        XCTAssertTrue(state.isAutoCollapsed)
    }

    func testUserHiddenStaysHiddenEvenWhenWideEnough() {
        let state = MarkdownInspectorVisibilityPolicy.state(
            intent: .userHidden,
            paneWidth: MarkdownInspectorVisibilityPolicy.minimumPaneWidthForInspector + 200
        )

        XCTAssertFalse(state.isVisible)
        XCTAssertFalse(state.isAutoCollapsed)
    }

    func testUnknownPaneWidthKeepsVisibleIntentRenderable() {
        let state = MarkdownInspectorVisibilityPolicy.state(
            intent: .defaultShown,
            paneWidth: nil
        )

        XCTAssertTrue(state.isVisible)
        XCTAssertFalse(state.isAutoCollapsed)
    }
}
