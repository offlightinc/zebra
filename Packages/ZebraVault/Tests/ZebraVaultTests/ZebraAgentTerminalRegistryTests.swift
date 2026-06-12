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
            agent: .antigravity,
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
            .antigravity
        )
    }

    func testReassignLatestMovesNewestMatchingTerminalToNewSource() {
        let registry = ZebraAgentTerminalRegistry()
        let oldAgentPanelId = UUID()
        let newAgentPanelId = UUID()
        let emailPanelId = UUID()
        let reassignedAt = Date(timeIntervalSince1970: 50)

        registry.mark(
            panelId: oldAgentPanelId,
            source: .onboardingChecklist(.agent),
            agent: .claude,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        registry.mark(
            panelId: emailPanelId,
            source: .emailThread("thread-1"),
            agent: .antigravity,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        registry.mark(
            panelId: newAgentPanelId,
            source: .onboardingChecklist(.agent),
            agent: .codex,
            createdAt: Date(timeIntervalSince1970: 30)
        )

        let registration = registry.reassignLatest(
            from: .onboardingChecklist(.agent),
            to: .onboardingChecklist(.gbrainRuntime),
            panelIds: [oldAgentPanelId, newAgentPanelId, emailPanelId],
            reassignedAt: reassignedAt
        )

        XCTAssertEqual(registration?.panelId, newAgentPanelId)
        XCTAssertEqual(registration?.source, .onboardingChecklist(.gbrainRuntime))
        XCTAssertEqual(registration?.agent, .codex)
        XCTAssertEqual(registration?.createdAt, reassignedAt)
        XCTAssertEqual(
            registry.registration(panelId: newAgentPanelId)?.source,
            .onboardingChecklist(.gbrainRuntime)
        )
        XCTAssertEqual(
            registry.registration(panelId: oldAgentPanelId)?.source,
            .onboardingChecklist(.agent)
        )
        XCTAssertEqual(
            registry.registration(panelId: emailPanelId)?.source,
            .emailThread("thread-1")
        )
    }

    func testReassignLatestIgnoresPanelsOutsideLiveSet() {
        let registry = ZebraAgentTerminalRegistry()
        let livePanelId = UUID()
        let ignoredPanelId = UUID()

        registry.mark(
            panelId: livePanelId,
            source: .onboardingChecklist(.agent),
            agent: .claude,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        registry.mark(
            panelId: ignoredPanelId,
            source: .onboardingChecklist(.agent),
            agent: .codex,
            createdAt: Date(timeIntervalSince1970: 30)
        )

        let registration = registry.reassignLatest(
            from: .onboardingChecklist(.agent),
            to: .onboardingChecklist(.gbrainRuntime),
            panelIds: [livePanelId],
            reassignedAt: Date(timeIntervalSince1970: 50)
        )

        XCTAssertEqual(registration?.panelId, livePanelId)
        XCTAssertEqual(
            registry.registration(panelId: livePanelId)?.source,
            .onboardingChecklist(.gbrainRuntime)
        )
        XCTAssertEqual(
            registry.registration(panelId: ignoredPanelId)?.source,
            .onboardingChecklist(.agent)
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
