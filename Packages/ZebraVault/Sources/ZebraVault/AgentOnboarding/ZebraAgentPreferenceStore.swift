import Foundation

public struct ZebraAgentPreferences: Equatable, Sendable {
    public var schemaVersion: Int
    public var primaryAgent: ZebraAgentKind?
    public var primaryAgentExecutablePath: String?
    public var updatedAt: Date?
    public var updatedBy: String?

    public init(
        schemaVersion: Int = 1,
        primaryAgent: ZebraAgentKind? = nil,
        primaryAgentExecutablePath: String? = nil,
        updatedAt: Date? = nil,
        updatedBy: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.primaryAgent = primaryAgent
        self.primaryAgentExecutablePath = primaryAgentExecutablePath
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

extension ZebraAgentPreferences: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case primaryAgent
        case primaryAgentExecutablePath
        case updatedAt
        case updatedBy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedBy = try container.decodeIfPresent(String.self, forKey: .updatedBy)
        primaryAgentExecutablePath = try container.decodeIfPresent(String.self, forKey: .primaryAgentExecutablePath)

        let rawPrimary = try container.decodeIfPresent(String.self, forKey: .primaryAgent)
        primaryAgent = rawPrimary.flatMap(ZebraAgentKind.init(rawValue:))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(primaryAgent?.rawValue, forKey: .primaryAgent)
        try container.encodeIfPresent(primaryAgentExecutablePath, forKey: .primaryAgentExecutablePath)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(updatedBy, forKey: .updatedBy)
    }
}

public struct ZebraAgentPreferenceStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        fileURL: URL = ZebraAgentPreferenceStore.defaultPreferencesURL(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
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

    public func load() -> ZebraAgentPreferences {
        loadFromDisk()
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
        preferences.primaryAgentExecutablePath = nil
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
}
