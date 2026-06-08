import XCTest
@testable import ZebraVault

final class ZebraAgentPreferenceStoreTests: XCTestCase {
    func testValidSavedValuesReadFromPreferencesJSON() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "primaryAgent": "antigravity",
              "surfaceOverrides": {
                "brainSync": "claude"
              }
            }
            """,
            to: fileURL
        )

        let preferences = makeStore(fileURL: fileURL).load()

        XCTAssertEqual(preferences.primaryAgent, .antigravity)
    }

    func testInvalidRawValuesAreIgnored() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "primaryAgent": "gemini",
              "surfaceOverrides": {
                "brainSync": "other"
              }
            }
            """,
            to: fileURL
        )

        let preferences = makeStore(fileURL: fileURL).load()

        XCTAssertNil(preferences.primaryAgent)
    }

    func testWritePrimaryAgentPersistsJSON() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        let store = makeStore(fileURL: fileURL)

        try store.setPrimaryAgent(.codex, updatedBy: "test")

        let preferences = store.load()
        XCTAssertEqual(preferences.primaryAgent, .codex)
        XCTAssertEqual(preferences.updatedBy, "test")
    }

    func testMarkdownPillDefaultAgentUsesPrimaryAgentPreference() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        let store = makeStore(fileURL: fileURL)
        try store.setPrimaryAgent(.antigravity, updatedBy: "test")

        XCTAssertEqual(MarkdownPillAgent.defaultAgent(preferenceStore: store), .antigravity)
    }

    func testMarkdownPillDefaultAgentIgnoresLegacyBrainSyncOverride() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "primaryAgent": "codex",
              "surfaceOverrides": {
                "brainSync": "claude"
              }
            }
            """,
            to: fileURL
        )

        let store = makeStore(fileURL: fileURL)

        XCTAssertEqual(MarkdownPillAgent.defaultAgent(preferenceStore: store), .codex)
    }

    func testMarkdownPillDefaultAgentFallsBackToCodexWithoutPrimaryAgent() throws {
        let store = makeStore(fileURL: try makeTemporaryPreferencesURL())

        XCTAssertEqual(MarkdownPillAgent.defaultAgent(preferenceStore: store), .codex)
    }

    func testAutomaticWelcomeRunsWhenOnboardingStateIsMissing() throws {
        let preferencesURL = try makeTemporaryPreferencesURL()
        let stateURL = try makeTemporaryOnboardingStateURL()
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "primaryAgent": "codex",
              "surfaceOverrides": {}
            }
            """,
            to: preferencesURL
        )

        XCTAssertTrue(ZebraAgentOnboardingStartup.shouldRunAutomaticWelcome(
            preferencesURL: preferencesURL,
            stateURL: stateURL
        ))
    }

    func testAutomaticWelcomeSkipsWhenOnboardingCompleteAndPrimaryAgentExists() throws {
        let preferencesURL = try makeTemporaryPreferencesURL()
        let stateURL = try makeTemporaryOnboardingStateURL()
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "primaryAgent": "antigravity",
              "surfaceOverrides": {}
            }
            """,
            to: preferencesURL
        )
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "phase": "complete",
              "selectedAgent": "antigravity"
            }
            """,
            to: stateURL
        )

        XCTAssertFalse(ZebraAgentOnboardingStartup.shouldRunAutomaticWelcome(
            preferencesURL: preferencesURL,
            stateURL: stateURL
        ))
    }

    func testAutomaticWelcomeRunsWhenPrimaryAgentIsInvalid() throws {
        let preferencesURL = try makeTemporaryPreferencesURL()
        let stateURL = try makeTemporaryOnboardingStateURL()
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "primaryAgent": "gemini",
              "surfaceOverrides": {}
            }
            """,
            to: preferencesURL
        )
        try writeJSON(
            """
            {
              "schemaVersion": 1,
              "phase": "complete"
            }
            """,
            to: stateURL
        )

        XCTAssertTrue(ZebraAgentOnboardingStartup.shouldRunAutomaticWelcome(
            preferencesURL: preferencesURL,
            stateURL: stateURL
        ))
    }

    private func makeStore(fileURL: URL) -> ZebraAgentPreferenceStore {
        ZebraAgentPreferenceStore(
            fileURL: fileURL,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func makeTemporaryPreferencesURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraAgentPreferenceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
    }

    private func makeTemporaryOnboardingStateURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraAgentOnboardingStartupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("agent-cli-state.json", isDirectory: false)
    }

    private func writeJSON(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }
}
