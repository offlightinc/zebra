import Foundation

public enum ZebraAgentPreferenceSurface: String, CaseIterable, Codable, Sendable {
    case brainSync
}

public struct ZebraAgentPreferences: Equatable, Sendable {
    public var schemaVersion: Int
    public var primaryAgent: ZebraAgentKind?
    public var updatedAt: Date?
    public var updatedBy: String?
    public var surfaceOverrides: [ZebraAgentPreferenceSurface: ZebraAgentKind]

    public init(
        schemaVersion: Int = 1,
        primaryAgent: ZebraAgentKind? = nil,
        updatedAt: Date? = nil,
        updatedBy: String? = nil,
        surfaceOverrides: [ZebraAgentPreferenceSurface: ZebraAgentKind] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.primaryAgent = primaryAgent
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.surfaceOverrides = surfaceOverrides
    }

    public func resolvedAgent(for surface: ZebraAgentPreferenceSurface) -> ZebraAgentKind? {
        surfaceOverrides[surface] ?? primaryAgent
    }
}

extension ZebraAgentPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case primaryAgent
        case updatedAt
        case updatedBy
        case surfaceOverrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedBy = try container.decodeIfPresent(String.self, forKey: .updatedBy)

        let rawPrimary = try container.decodeIfPresent(String.self, forKey: .primaryAgent)
        primaryAgent = rawPrimary.flatMap(ZebraAgentKind.init(rawValue:))

        let rawOverrides = try container.decodeIfPresent([String: String].self, forKey: .surfaceOverrides) ?? [:]
        surfaceOverrides = rawOverrides.reduce(into: [:]) { result, entry in
            guard let surface = ZebraAgentPreferenceSurface(rawValue: entry.key),
                  let agent = ZebraAgentKind(rawValue: entry.value) else {
                return
            }
            result[surface] = agent
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(primaryAgent?.rawValue, forKey: .primaryAgent)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(updatedBy, forKey: .updatedBy)

        let rawOverrides = Dictionary(uniqueKeysWithValues: surfaceOverrides.map { key, value in
            (key.rawValue, value.rawValue)
        })
        try container.encode(rawOverrides, forKey: .surfaceOverrides)
    }
}

public struct ZebraAgentPreferenceStore {
    public static let legacyBrainSyncUserDefaultsKey = "zebra.brainSync.preferredAgent"

    private let fileURL: URL
    private let legacyDefaults: UserDefaults?
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        fileURL: URL = ZebraAgentPreferenceStore.defaultPreferencesURL(),
        legacyDefaults: UserDefaults? = .standard,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.legacyDefaults = legacyDefaults
        self.fileManager = fileManager
        self.now = now
    }

    public static func defaultPreferencesURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("preferences.json", isDirectory: false)
    }

    public func load(migratingLegacyDefaults: Bool = true) -> ZebraAgentPreferences {
        var preferences = loadFromDisk()
        if migratingLegacyDefaults {
            preferences = migrateLegacyBrainSyncPreferenceIfNeeded(preferences)
        }
        return preferences
    }

    public func resolvedAgent(for surface: ZebraAgentPreferenceSurface) -> ZebraAgentKind? {
        load().resolvedAgent(for: surface)
    }

    public func save(_ preferences: ZebraAgentPreferences) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }

    public func setPrimaryAgent(_ agent: ZebraAgentKind?, updatedBy: String) throws {
        var preferences = load()
        preferences.primaryAgent = agent
        preferences.updatedAt = now()
        preferences.updatedBy = updatedBy
        try save(preferences)
    }

    public func setSurfaceOverride(
        _ agent: ZebraAgentKind?,
        for surface: ZebraAgentPreferenceSurface,
        updatedBy: String
    ) throws {
        var preferences = load()
        preferences.surfaceOverrides[surface] = agent
        preferences.updatedAt = now()
        preferences.updatedBy = updatedBy
        try save(preferences)
    }

    private func loadFromDisk() -> ZebraAgentPreferences {
        guard let data = try? Data(contentsOf: fileURL) else {
            return ZebraAgentPreferences()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ZebraAgentPreferences.self, from: data)) ?? ZebraAgentPreferences()
    }

    private func migrateLegacyBrainSyncPreferenceIfNeeded(
        _ preferences: ZebraAgentPreferences
    ) -> ZebraAgentPreferences {
        guard let legacyDefaults,
              let rawValue = legacyDefaults.string(forKey: Self.legacyBrainSyncUserDefaultsKey) else {
            return preferences
        }

        var shouldRemoveLegacyValue = false
        defer {
            if shouldRemoveLegacyValue {
                legacyDefaults.removeObject(forKey: Self.legacyBrainSyncUserDefaultsKey)
            }
        }

        guard preferences.surfaceOverrides[.brainSync] == nil,
              let legacyAgent = ZebraAgentKind(rawValue: rawValue) else {
            shouldRemoveLegacyValue = true
            return preferences
        }

        var migrated = preferences
        migrated.surfaceOverrides[.brainSync] = legacyAgent
        migrated.updatedAt = now()
        migrated.updatedBy = "legacyBrainSyncPreference"
        do {
            try save(migrated)
            shouldRemoveLegacyValue = true
        } catch {
            return migrated
        }
        return migrated
    }
}
