import XCTest
@testable import ZebraVault

@MainActor
final class ZebraAgentTerminalRegistryTests: XCTestCase {
    func testMarkStoresTerminalSourceAgentAndCreatedAt() {
        let registry = ZebraAgentTerminalRegistry()
        let panelId = UUID()
        let createdAt = Date(timeIntervalSince1970: 42)

        registry.mark(
            panelId: panelId,
            source: .markdownFile("/brain/tasks/weekly.md"),
            agent: .codex,
            createdAt: createdAt
        )

        XCTAssertTrue(registry.isAgentTerminal(panelId: panelId))
        XCTAssertEqual(
            registry.registration(panelId: panelId),
            ZebraAgentTerminalRegistration(
                panelId: panelId,
                source: .markdownFile("/brain/tasks/weekly.md"),
                agent: .codex,
                createdAt: createdAt
            )
        )
    }

    func testLatestAgentIsScopedToSource() {
        let registry = ZebraAgentTerminalRegistry()
        let oldMarkdownPanelId = UUID()
        let newMarkdownPanelId = UUID()
        let emailPanelId = UUID()

        registry.mark(
            panelId: oldMarkdownPanelId,
            source: .markdownFile("/brain/tasks/weekly.md"),
            agent: .claude,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        registry.mark(
            panelId: emailPanelId,
            source: .emailThread("thread-1"),
            agent: .gemini,
            createdAt: Date(timeIntervalSince1970: 30)
        )
        registry.mark(
            panelId: newMarkdownPanelId,
            source: .markdownFile("/brain/tasks/weekly.md"),
            agent: .codex,
            createdAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(
            registry.latestAgent(
                for: .markdownFile("/brain/tasks/weekly.md"),
                panelIds: [oldMarkdownPanelId, newMarkdownPanelId, emailPanelId]
            ),
            .codex
        )
        XCTAssertEqual(
            registry.latestAgent(
                for: .emailThread("thread-1"),
                panelIds: [oldMarkdownPanelId, newMarkdownPanelId, emailPanelId]
            ),
            .gemini
        )
    }

    func testPruneDropsClosedTerminalPanels() {
        let registry = ZebraAgentTerminalRegistry()
        let livePanelId = UUID()
        let closedPanelId = UUID()

        registry.mark(
            panelId: livePanelId,
            source: .markdownFile("/brain/tasks/weekly.md"),
            agent: .codex
        )
        registry.mark(
            panelId: closedPanelId,
            source: .emailThread("thread-1"),
            agent: .claude
        )

        registry.prune(validPanelIds: [livePanelId])

        XCTAssertTrue(registry.isAgentTerminal(panelId: livePanelId))
        XCTAssertFalse(registry.isAgentTerminal(panelId: closedPanelId))
        XCTAssertNil(registry.registration(panelId: closedPanelId))
    }
}
