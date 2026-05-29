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

        let preferences = makeStore(fileURL: fileURL).load(migratingLegacyDefaults: false)

        XCTAssertEqual(preferences.primaryAgent, .antigravity)
        XCTAssertEqual(preferences.surfaceOverrides[.brainSync], .claude)
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

        let preferences = makeStore(fileURL: fileURL).load(migratingLegacyDefaults: false)

        XCTAssertNil(preferences.primaryAgent)
        XCTAssertEqual(preferences.surfaceOverrides, [:])
    }

    func testWritePrimaryAgentPersistsJSON() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        let store = makeStore(fileURL: fileURL)

        try store.setPrimaryAgent(.codex, updatedBy: "test")

        let preferences = store.load(migratingLegacyDefaults: false)
        XCTAssertEqual(preferences.primaryAgent, .codex)
        XCTAssertEqual(preferences.updatedBy, "test")
    }

    func testLegacyBrainSyncUserDefaultsMigratesIntoSurfaceOverride() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        let defaults = try makeDefaults()
        defaults.set("claude", forKey: ZebraAgentPreferenceStore.legacyBrainSyncUserDefaultsKey)

        let store = makeStore(fileURL: fileURL, legacyDefaults: defaults)
        let preferences = store.load()

        XCTAssertEqual(preferences.surfaceOverrides[.brainSync], .claude)
        XCTAssertNil(defaults.string(forKey: ZebraAgentPreferenceStore.legacyBrainSyncUserDefaultsKey))
        XCTAssertEqual(store.load(migratingLegacyDefaults: false).surfaceOverrides[.brainSync], .claude)
    }

    func testLegacyBrainSyncMigrationKeepsUserDefaultsWhenJSONSaveFails() throws {
        let parentFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraAgentPreferenceStoreTests-parent-\(UUID().uuidString)", isDirectory: false)
        try Data("not a directory".utf8).write(to: parentFileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: parentFileURL)
        }

        let defaults = try makeDefaults()
        defaults.set("claude", forKey: ZebraAgentPreferenceStore.legacyBrainSyncUserDefaultsKey)
        let store = makeStore(
            fileURL: parentFileURL.appendingPathComponent("preferences.json", isDirectory: false),
            legacyDefaults: defaults
        )

        let preferences = store.load()

        XCTAssertEqual(preferences.surfaceOverrides[.brainSync], .claude)
        XCTAssertEqual(defaults.string(forKey: ZebraAgentPreferenceStore.legacyBrainSyncUserDefaultsKey), "claude")
    }

    func testBrainSyncResolutionUsesOverrideBeforePrimaryAgent() {
        let preferences = ZebraAgentPreferences(
            primaryAgent: .codex,
            surfaceOverrides: [.brainSync: .claude]
        )

        XCTAssertEqual(preferences.resolvedAgent(for: .brainSync), .claude)
    }

    func testMarkdownPillDefaultAgentUsesPrimaryAgentPreference() throws {
        let fileURL = try makeTemporaryPreferencesURL()
        let store = makeStore(fileURL: fileURL)
        try store.setPrimaryAgent(.antigravity, updatedBy: "test")

        XCTAssertEqual(MarkdownPillAgent.defaultAgent(preferenceStore: store), .antigravity)
    }

    func testMarkdownPillDefaultAgentFallsBackToCodexWithoutPrimaryAgent() throws {
        let store = makeStore(fileURL: try makeTemporaryPreferencesURL())

        XCTAssertEqual(MarkdownPillAgent.defaultAgent(preferenceStore: store), .codex)
    }

    private func makeStore(
        fileURL: URL,
        legacyDefaults: UserDefaults? = nil
    ) -> ZebraAgentPreferenceStore {
        ZebraAgentPreferenceStore(
            fileURL: fileURL,
            legacyDefaults: legacyDefaults,
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

    private func makeDefaults() throws -> UserDefaults {
        let name = "ZebraAgentPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func writeJSON(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }
}
