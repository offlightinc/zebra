import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class MarkdownSidebarOpeningTests: XCTestCase {
    @MainActor
    func testSidebarMarkdownOpenReusesFocusedMarkdownPanel() throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try "# first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)

        let firstPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: paneId, filePath: firstURL.path)
        )
        let firstTabId = try XCTUnwrap(workspace.surfaceIdFromPanelId(firstPanel.id))
        let panelCountAfterFirstOpen = workspace.panels.count

        let secondPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: paneId, filePath: secondURL.path)
        )

        XCTAssertEqual(secondPanel.id, firstPanel.id)
        XCTAssertEqual(workspace.surfaceIdFromPanelId(secondPanel.id), firstTabId)
        XCTAssertEqual(secondPanel.filePath, secondURL.path)
        XCTAssertEqual(workspace.panels.count, panelCountAfterFirstOpen)
    }

    @MainActor
    func testSidebarMarkdownOpenCreatesNewPanelWhenTerminalIsFocused() throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try "# first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let terminalPanelId = try XCTUnwrap(workspace.focusedPanelId)

        let firstPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: paneId, filePath: firstURL.path)
        )
        workspace.focusPanel(terminalPanelId)
        let panelCountBeforeSecondOpen = workspace.panels.count

        let secondPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: paneId, filePath: secondURL.path)
        )

        XCTAssertNotEqual(secondPanel.id, firstPanel.id)
        XCTAssertEqual(secondPanel.filePath, secondURL.path)
        XCTAssertEqual(workspace.panels.count, panelCountBeforeSecondOpen + 1)
    }

    private func makeMarkdownFixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-sidebar-markdown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
