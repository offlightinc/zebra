import Foundation

struct ZebraSourceOnboardingState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var status: Status
    var entryContext: EntryContext
    var sourceReadiness: SourceReadiness
    var progress: Progress
    var updatedAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        status: Status,
        entryContext: EntryContext,
        sourceReadiness: SourceReadiness,
        progress: Progress = Progress(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.entryContext = entryContext
        self.sourceReadiness = sourceReadiness
        self.progress = progress
        self.updatedAt = updatedAt
    }

    static func defaultStateURL(homeDirectoryPath: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("zebra", isDirectory: true)
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("source-onboarding-state.json", isDirectory: false)
    }
}

extension ZebraSourceOnboardingState {
    enum Status: String, Codable, Equatable, Sendable {
        case notStarted = "not_started"
        case ready
        case running
        case attention
        case completed
    }

    struct EntryContext: Codable, Equatable, Sendable {
        var selectedVaultPath: String?
        var gbrainTargetPath: String?
        var gbrainTargetKey: String?
        var gbrainReceiptPath: String?
        var gbrainTargetStatus: String?
        var gbrainTargetMissingReason: String?
        var gbrainWarnings: [String]
        var liveProbe: LiveProbe
        var adapterReady: Bool
        var adapterReadinessReasons: [String]
    }

    struct LiveProbe: Codable, Equatable, Sendable {
        var ran: Bool
        var status: String?
        var reason: String?
    }

    struct SourceReadiness: Codable, Equatable, Sendable {
        var gmail: GmailReadiness
    }

    struct GmailReadiness: Codable, Equatable, Sendable {
        var status: GmailStatus
        var connectionPath: String?
        var envPath: String
        var localArtifact: LocalArtifact?
        var repairKind: String?
        var reasons: [String]
    }

    enum GmailStatus: String, Codable, Equatable, Sendable {
        case missingEnv = "missing_env"
        case unverified
        case attention
        case ready
    }

    struct LocalArtifact: Codable, Equatable, Sendable {
        var kind: String
        var path: String
        var exists: Bool
    }

    struct Progress: Codable, Equatable, Sendable {
        var rawSourceInput: String?
        var normalizedSourceList: [String]
        var uncatalogedSources: [UncatalogedSource]
        var sourceConfirmation: SourceConfirmation?
        var sourceRows: [String: SourceRow]
        var pendingQuestion: PendingQuestion?
        // Deferred source-order slices:
        // var importanceOrder: [String]
        // var finalExecutionOrder: [String]

        init(
            rawSourceInput: String? = nil,
            normalizedSourceList: [String] = [],
            uncatalogedSources: [UncatalogedSource] = [],
            sourceConfirmation: SourceConfirmation? = nil,
            sourceRows: [String: SourceRow] = [:],
            pendingQuestion: PendingQuestion? = nil
        ) {
            self.rawSourceInput = rawSourceInput
            self.normalizedSourceList = normalizedSourceList
            self.uncatalogedSources = uncatalogedSources
            self.sourceConfirmation = sourceConfirmation
            self.sourceRows = sourceRows
            self.pendingQuestion = pendingQuestion
        }

        private enum CodingKeys: String, CodingKey {
            case rawSourceInput
            case normalizedSourceList
            case uncatalogedSources
            case unsupportedInputs
            case sourceConfirmation
            case sourceRows
            case pendingQuestion
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rawSourceInput = try container.decodeIfPresent(String.self, forKey: .rawSourceInput)
            normalizedSourceList = try container.decodeIfPresent(
                [String].self,
                forKey: .normalizedSourceList
            ) ?? []
            uncatalogedSources = try container.decodeIfPresent(
                [UncatalogedSource].self,
                forKey: .uncatalogedSources
            ) ?? container.decodeIfPresent(
                [UncatalogedSource].self,
                forKey: .unsupportedInputs
            ) ?? []
            sourceConfirmation = try container.decodeIfPresent(
                SourceConfirmation.self,
                forKey: .sourceConfirmation
            )
            sourceRows = try container.decodeIfPresent(
                [String: SourceRow].self,
                forKey: .sourceRows
            ) ?? [:]
            pendingQuestion = try container.decodeIfPresent(
                PendingQuestion.self,
                forKey: .pendingQuestion
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(rawSourceInput, forKey: .rawSourceInput)
            try container.encode(normalizedSourceList, forKey: .normalizedSourceList)
            try container.encode(uncatalogedSources, forKey: .uncatalogedSources)
            try container.encodeIfPresent(sourceConfirmation, forKey: .sourceConfirmation)
            try container.encode(sourceRows, forKey: .sourceRows)
            try container.encodeIfPresent(pendingQuestion, forKey: .pendingQuestion)
        }
    }

    struct UncatalogedSource: Codable, Equatable, Sendable {
        var rawValue: String
        var normalizedValue: String
        var displayName: String?
        var reason: String
    }

    struct SourceConfirmation: Codable, Equatable, Sendable {
        var sourceIDs: [String]
        var prompt: String
        var status: SourceConfirmationStatus
        var confirmedAt: Date?
        var updatedAt: Date?
    }

    enum SourceConfirmationStatus: String, Codable, Equatable, Sendable {
        case pending
        case confirmed
        case rejected
    }

    struct SourceRow: Codable, Equatable, Sendable {
        var id: String
        var displayName: String?
        var type: String?
        var phase: String?
        var status: String
        var selectionState: String?
        var updatedAt: Date?
    }

    struct PendingQuestion: Codable, Equatable, Sendable {
        var prompt: String
        var status: String
        var askedAt: Date?
    }
}
