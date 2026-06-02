import XCTest
import ZebraVault

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

    @MainActor
    func testChatPillCompanionReuseRequiresRegistryMarkedTerminalPane() throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("source.md")
        try "# source\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let contentPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let markdownPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: contentPaneId, filePath: fileURL.path)
        )
        let rightTerminal = try XCTUnwrap(
            workspace.newTerminalSplit(from: markdownPanel.id, orientation: .horizontal, focus: false)
        )
        let rightPaneId = try XCTUnwrap(workspace.paneId(forPanelId: rightTerminal.id))
        let registry = ZebraAgentTerminalRegistry()
        let source = ZebraAgentTerminalSource.markdownFile(fileURL.path)

        XCTAssertNil(workspace.reusableAgentCompanionPane(forContentPane: contentPaneId, markedBy: registry))
        XCTAssertTrue(workspace.zebraAgentCompanionPaneIds(markedBy: registry).isEmpty)
        XCTAssertNil(workspace.activeAgentTerminalAgent(for: source, contentPane: contentPaneId, markedBy: registry))

        registry.mark(panelId: rightTerminal.id, source: source, agent: .codex)

        XCTAssertEqual(workspace.reusableAgentCompanionPane(forContentPane: contentPaneId, markedBy: registry), rightPaneId)
        XCTAssertEqual(workspace.zebraAgentCompanionPaneIds(markedBy: registry), Set([rightPaneId]))
        XCTAssertEqual(workspace.activeAgentTerminalAgent(for: source, contentPane: contentPaneId, markedBy: registry), .codex)
        XCTAssertNil(
            workspace.activeAgentTerminalAgent(
                for: .markdownFile(root.appendingPathComponent("other.md").path),
                contentPane: contentPaneId,
                markedBy: registry
            )
        )
    }

    @MainActor
    func testChatPillAgentLaunchDoesNotReuseUnmarkedNeutralTerminalPane() throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("source.md")
        try "# source\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let contentPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let markdownPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: contentPaneId, filePath: fileURL.path)
        )
        let rightTerminal = try XCTUnwrap(
            workspace.newTerminalSplit(from: markdownPanel.id, orientation: .horizontal, focus: false)
        )
        let rightTerminalPaneId = try XCTUnwrap(workspace.paneId(forPanelId: rightTerminal.id))
        let registry = ZebraAgentTerminalRegistry()

        let agentPanel = try XCTUnwrap(
            workspace.openZebraAgentTerminal(
                startupLine: "printf test\\r",
                source: .markdownFile(fileURL.path),
                agent: .codex,
                anchor: .contentAnchored(contentPanelId: markdownPanel.id, contentPaneId: contentPaneId),
                markedBy: registry
            )
        )
        let agentPaneId = try XCTUnwrap(workspace.paneId(forPanelId: agentPanel.id))

        XCTAssertNotEqual(agentPaneId, contentPaneId)
        XCTAssertNotEqual(agentPaneId, rightTerminalPaneId)
        XCTAssertFalse(workspace.zebraAgentCompanionPaneIds(markedBy: registry).contains(rightTerminalPaneId))
        XCTAssertTrue(workspace.zebraAgentCompanionPaneIds(markedBy: registry).contains(agentPaneId))
    }

    @MainActor
    func testZebraSidebarMarkdownOpenSkipsRegistryMarkedAgentPane() throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try "# first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let contentPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let contentPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: contentPaneId, filePath: firstURL.path)
        )
        let agentPanel = try XCTUnwrap(
            workspace.newTerminalSplit(from: contentPanel.id, orientation: .horizontal, focus: false)
        )
        let agentPaneId = try XCTUnwrap(workspace.paneId(forPanelId: agentPanel.id))
        let registry = ZebraAgentTerminalRegistry()
        registry.mark(panelId: agentPanel.id, source: .markdownFile(firstURL.path), agent: .codex)

        let excludedPaneIds = workspace.zebraAgentCompanionPaneIds(markedBy: registry)
        let openedPanel = try XCTUnwrap(
            workspace.openMarkdownFromZebraSidebar(
                inPane: agentPaneId,
                filePath: secondURL.path,
                excludedAgentCompanionPaneIds: excludedPaneIds
            )
        )

        XCTAssertEqual(excludedPaneIds, Set([agentPaneId]))
        XCTAssertEqual(openedPanel.id, contentPanel.id)
        XCTAssertEqual(openedPanel.filePath, secondURL.path)
        XCTAssertEqual(workspace.paneId(forPanelId: openedPanel.id), contentPaneId)
        XCTAssertNotEqual(workspace.paneId(forPanelId: openedPanel.id), agentPaneId)
    }

    @MainActor
    func testZebraSidebarMarkdownOpenUsesRequestedNonAgentPaneWithoutScoring() throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try "# first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let firstPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let firstMarkdownPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: firstPaneId, filePath: firstURL.path)
        )
        let terminalPanel = try XCTUnwrap(
            workspace.newTerminalSplit(from: firstMarkdownPanel.id, orientation: .horizontal, focus: false)
        )
        let terminalPaneId = try XCTUnwrap(workspace.paneId(forPanelId: terminalPanel.id))

        let openedPanel = try XCTUnwrap(
            workspace.openMarkdownFromZebraSidebar(
                inPane: terminalPaneId,
                filePath: secondURL.path,
                excludedAgentCompanionPaneIds: []
            )
        )

        XCTAssertNotEqual(openedPanel.id, firstMarkdownPanel.id)
        XCTAssertEqual(openedPanel.filePath, secondURL.path)
        XCTAssertEqual(workspace.paneId(forPanelId: openedPanel.id), terminalPaneId)
    }

    @MainActor
    func testZebraSidebarMarkdownOpenSkipsNonChatPillAgentPanes() throws {
        try assertZebraSidebarMarkdownOpenSkipsAgentPane(
            source: .clawvisorOnboarding,
            agent: .claude
        )
        try assertZebraSidebarMarkdownOpenSkipsAgentPane(
            source: .brainSyncFailure,
            agent: .codex
        )
    }

    @MainActor
    func testStandaloneAgentLaunchCreatesCompanionSplitInsteadOfMarkingFocusedContentPane() throws {
        try assertStandaloneAgentLaunchCreatesCompanionSplit(
            source: .clawvisorOnboarding,
            agent: .claude
        )
        try assertStandaloneAgentLaunchCreatesCompanionSplit(
            source: .brainSyncFailure,
            agent: .codex
        )
    }

    @MainActor
    func testStandaloneAgentLaunchUsesFocusedNeutralTerminalPane() throws {
        let workspace = Workspace()
        let terminalPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let terminalPanelId = try XCTUnwrap(workspace.focusedPanelId)
        let registry = ZebraAgentTerminalRegistry()

        let agentPanel = try XCTUnwrap(
            workspace.openZebraAgentTerminal(
                startupLine: "printf test\\r",
                source: .brainSyncFailure,
                agent: .codex,
                anchor: .focusAnchored,
                markedBy: registry
            )
        )

        XCTAssertEqual(workspace.paneId(forPanelId: terminalPanelId), terminalPaneId)
        XCTAssertEqual(workspace.paneId(forPanelId: agentPanel.id), terminalPaneId)
        XCTAssertEqual(workspace.zebraAgentCompanionPaneIds(markedBy: registry), Set([terminalPaneId]))
        XCTAssertEqual(workspace.bonsplitController.allPaneIds, [terminalPaneId])

        let secondAgentPanel = try XCTUnwrap(
            workspace.openZebraAgentTerminal(
                startupLine: "printf second\\r",
                source: .brainSyncFailure,
                agent: .codex,
                anchor: .focusAnchored,
                markedBy: registry
            )
        )

        XCTAssertEqual(workspace.paneId(forPanelId: secondAgentPanel.id), terminalPaneId)
        XCTAssertEqual(workspace.bonsplitController.allPaneIds, [terminalPaneId])
    }

    @MainActor
    func testZebraSidebarMarkdownOpenSkipsReusedOnboardingChecklistAgentPane() throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("first.md")
        try "# first\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let terminalPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let terminalPanelId = try XCTUnwrap(workspace.focusedPanelId)
        let registry = ZebraAgentTerminalRegistry()
        registry.mark(
            panelId: terminalPanelId,
            source: .onboardingChecklist(.agent),
            agent: .codex
        )

        let excludedPaneIds = workspace.zebraAgentCompanionPaneIds(markedBy: registry)
        let openedPanel = try XCTUnwrap(
            workspace.openMarkdownFromZebraSidebar(
                inPane: terminalPaneId,
                filePath: fileURL.path,
                excludedAgentCompanionPaneIds: excludedPaneIds
            )
        )

        XCTAssertEqual(excludedPaneIds, Set([terminalPaneId]))
        XCTAssertNotEqual(workspace.paneId(forPanelId: openedPanel.id), terminalPaneId)
        XCTAssertEqual(workspace.bonsplitController.allPaneIds.count, 2)
    }

    @MainActor
    private func assertZebraSidebarMarkdownOpenSkipsAgentPane(
        source: ZebraAgentTerminalSource,
        agent: MarkdownPillAgent
    ) throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try "# first\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# second\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let contentPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let contentPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: contentPaneId, filePath: firstURL.path)
        )
        let agentPanel = try XCTUnwrap(
            workspace.newTerminalSplit(from: contentPanel.id, orientation: .horizontal, focus: false)
        )
        let agentPaneId = try XCTUnwrap(workspace.paneId(forPanelId: agentPanel.id))
        let registry = ZebraAgentTerminalRegistry()
        registry.mark(panelId: agentPanel.id, source: source, agent: agent)

        let excludedPaneIds = workspace.zebraAgentCompanionPaneIds(markedBy: registry)
        let openedPanel = try XCTUnwrap(
            workspace.openMarkdownFromZebraSidebar(
                inPane: agentPaneId,
                filePath: secondURL.path,
                excludedAgentCompanionPaneIds: excludedPaneIds
            )
        )

        XCTAssertEqual(excludedPaneIds, Set([agentPaneId]))
        XCTAssertEqual(openedPanel.id, contentPanel.id)
        XCTAssertEqual(workspace.paneId(forPanelId: openedPanel.id), contentPaneId)
        XCTAssertNotEqual(workspace.paneId(forPanelId: openedPanel.id), agentPaneId)
    }

    @MainActor
    private func assertStandaloneAgentLaunchCreatesCompanionSplit(
        source: ZebraAgentTerminalSource,
        agent: MarkdownPillAgent
    ) throws {
        let root = try makeMarkdownFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("content.md")
        try "# content\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        let contentPaneId = try XCTUnwrap(workspace.bonsplitController.allPaneIds.first)
        let contentPanel = try XCTUnwrap(
            workspace.openMarkdownFromSidebar(inPane: contentPaneId, filePath: fileURL.path)
        )
        let registry = ZebraAgentTerminalRegistry()

        let agentPanel = try XCTUnwrap(
            workspace.openZebraAgentTerminal(
                startupLine: "printf test\\r",
                source: source,
                agent: agent,
                anchor: .focusAnchored,
                markedBy: registry
            )
        )
        let agentPaneId = try XCTUnwrap(workspace.paneId(forPanelId: agentPanel.id))

        XCTAssertNotEqual(agentPaneId, contentPaneId)
        XCTAssertEqual(workspace.paneId(forPanelId: contentPanel.id), contentPaneId)
        XCTAssertEqual(workspace.zebraAgentCompanionPaneIds(markedBy: registry), Set([agentPaneId]))
        XCTAssertFalse(workspace.zebraAgentCompanionPaneIds(markedBy: registry).contains(contentPaneId))
    }

    private func makeMarkdownFixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-sidebar-markdown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
