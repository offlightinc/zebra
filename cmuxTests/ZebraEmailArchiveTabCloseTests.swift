import XCTest
import ZebraVault

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class ZebraEmailArchiveTabCloseTests: XCTestCase {
    private func makeThread(id: String, subject: String) -> EmailThreadItem {
        EmailThreadItem(
            id: id,
            subject: subject,
            senderName: "Sender",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            unread: false,
            starred: false,
            hasAttachment: false,
            labelIds: ["INBOX"],
            category: nil
        )
    }

    func testCloseEmailThreadPanelsClosesOnlyArchivedThreadTab() throws {
        let manager = TabManager()
        let workspace = try XCTUnwrap(manager.selectedWorkspace)
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)

        let archivedThread = makeThread(id: "thread-archived", subject: "Archive me")
        let keptThread = makeThread(id: "thread-kept", subject: "Keep me")

        let archivedPanel = try XCTUnwrap(
            workspace.openOrFocusEmailThreadSurface(inPane: paneId, thread: archivedThread, focus: false)
        )
        let keptPanel = try XCTUnwrap(
            workspace.openOrFocusEmailThreadSurface(inPane: paneId, thread: keptThread, focus: false)
        )
        XCTAssertNotNil(workspace.surfaceIdFromPanelId(archivedPanel.id))
        XCTAssertNotNil(workspace.surfaceIdFromPanelId(keptPanel.id))

        workspace.closeEmailThreadPanels(threadId: archivedThread.id)

        XCTAssertNil(workspace.panels[archivedPanel.id])
        XCTAssertNil(workspace.surfaceIdFromPanelId(archivedPanel.id))
        XCTAssertNotNil(workspace.panels[keptPanel.id])
        XCTAssertNotNil(workspace.surfaceIdFromPanelId(keptPanel.id))
    }

    func testCloseEmailThreadPanelsWithUnknownThreadIsNoOp() throws {
        let manager = TabManager()
        let workspace = try XCTUnwrap(manager.selectedWorkspace)
        let paneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)

        let thread = makeThread(id: "thread-open", subject: "Still open")
        let panel = try XCTUnwrap(
            workspace.openOrFocusEmailThreadSurface(inPane: paneId, thread: thread, focus: false)
        )

        workspace.closeEmailThreadPanels(threadId: "thread-that-never-opened")

        XCTAssertNotNil(workspace.panels[panel.id])
        XCTAssertNotNil(workspace.surfaceIdFromPanelId(panel.id))
    }
}
