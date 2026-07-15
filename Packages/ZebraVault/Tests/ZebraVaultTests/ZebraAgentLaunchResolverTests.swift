import XCTest
@testable import ZebraVault

final class ZebraAgentLaunchResolverTests: XCTestCase {
    func testKeepsValidSavedPrimaryWithoutWriting() throws {
        let store = ZebraAgentPreferenceStore(fileURL: try preferencesURL())
        try store.setPrimaryAgent(.antigravity, executablePath: "/old/agy", updatedBy: "test")

        let resolution = try ZebraAgentLaunchResolver().resolvePrimary(
            preferenceStore: store,
            candidates: [installed(.antigravity, path: "/tools/agy")]
        )

        XCTAssertEqual(resolution, .launch(agent: .antigravity, executablePath: "/tools/agy", changedPrimary: false))
        XCTAssertEqual(store.load().primaryAgentExecutablePath, "/old/agy")
    }

    func testInvalidPrimaryFallsBackToCodexAndPersistsPath() throws {
        try assertFallback(
            candidates: [installed(.claude, path: "/tools/claude"), installed(.codex, path: "/tools/codex")],
            invalidPrimary: .antigravity,
            expectedAgent: .codex,
            expectedPath: "/tools/codex"
        )
    }

    func testInvalidPrimaryFallsBackToClaudeWhenCodexUnavailable() throws {
        try assertFallback(
            candidates: [installed(.claude, path: "/tools/claude"), installed(.antigravity, path: "/tools/agy")],
            invalidPrimary: .codex,
            expectedAgent: .claude,
            expectedPath: "/tools/claude"
        )
    }

    func testInvalidPrimaryFallsBackToAntigravityWhenOthersUnavailable() throws {
        try assertFallback(
            candidates: [installed(.antigravity, path: "/tools/agy")],
            invalidPrimary: .claude,
            expectedAgent: .antigravity,
            expectedPath: "/tools/agy"
        )
    }

    func testNoLaunchableAgentRequiresManagementFlow() throws {
        let store = ZebraAgentPreferenceStore(fileURL: try preferencesURL())
        try store.setPrimaryAgent(.claude, executablePath: "/missing/claude", updatedBy: "test")

        let resolution = try ZebraAgentLaunchResolver().resolvePrimary(
            preferenceStore: store,
            candidates: [missing(.claude), missing(.codex), missing(.antigravity)]
        )

        XCTAssertEqual(resolution, .manageAgents)
        XCTAssertEqual(store.load().primaryAgent, .claude)
    }

    func testRequestedAgentRequiresAbsoluteLaunchablePath() {
        let resolver = ZebraAgentLaunchResolver()
        XCTAssertNil(resolver.executablePath(for: .codex, candidates: [installed(.codex, path: "relative/codex")]))
        XCTAssertNil(resolver.executablePath(for: .codex, candidates: [missing(.codex)]))
        XCTAssertEqual(
            resolver.executablePath(for: .codex, candidates: [installed(.codex, path: "/tools/codex")]),
            "/tools/codex"
        )
    }

    private func assertFallback(
        candidates: [ZebraAgentInstallCandidate],
        invalidPrimary: ZebraAgentKind,
        expectedAgent: ZebraAgentKind,
        expectedPath: String
    ) throws {
        let store = ZebraAgentPreferenceStore(fileURL: try preferencesURL())
        try store.setPrimaryAgent(invalidPrimary, executablePath: "/missing/agent", updatedBy: "test")

        let resolution = try ZebraAgentLaunchResolver().resolvePrimary(
            preferenceStore: store,
            candidates: candidates
        )

        XCTAssertEqual(resolution, .launch(agent: expectedAgent, executablePath: expectedPath, changedPrimary: true))
        let saved = store.load()
        XCTAssertEqual(saved.primaryAgent, expectedAgent)
        XCTAssertEqual(saved.primaryAgentExecutablePath, expectedPath)
        XCTAssertEqual(saved.updatedBy, "resolveAutomaticFallback")
    }

    private func installed(_ agent: ZebraAgentKind, path: String) -> ZebraAgentInstallCandidate {
        ZebraAgentInstallCandidate(
            id: agent,
            displayName: agent.displayName,
            binaryName: agent.binaryName,
            executablePath: path,
            appBundlePath: nil,
            version: "fixture",
            installState: .installed,
            authState: .unknown,
            terminalLaunchable: true,
            recommendedAction: .launch
        )
    }

    private func missing(_ agent: ZebraAgentKind) -> ZebraAgentInstallCandidate {
        ZebraAgentInstallCandidate(
            id: agent,
            displayName: agent.displayName,
            binaryName: agent.binaryName,
            executablePath: nil,
            appBundlePath: nil,
            version: nil,
            installState: .missing,
            authState: .unknown,
            terminalLaunchable: false,
            recommendedAction: .install
        )
    }

    private func preferencesURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("preferences.json")
    }
}
