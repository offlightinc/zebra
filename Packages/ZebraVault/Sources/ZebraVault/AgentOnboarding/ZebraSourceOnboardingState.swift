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
        var onboardingLanguageCode: String?
        var gbrainWriteTargetPath: String?
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
        var slack: SlackReadiness? = nil
        var agentMemory: AgentMemoryReadiness? = nil
    }

    struct SlackReadiness: Codable, Equatable, Sendable {
        var status: SlackStatus
        var workspaceID: String?
        var authorizedUserID: String?
        var startDate: Date?
        var checkpointExists: Bool
        var reason: String?
    }

    enum SlackStatus: String, Codable, Equatable, Sendable {
        case credentialMissing = "credential_missing"
        case readyToPoll = "ready_to_poll"
        case polling
        case attention
        case checked
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

    struct AgentMemoryReadiness: Codable, Equatable, Sendable {
        var status: String
        var importableUnitCount: Int
        var agents: [AgentMemoryCandidate]
        var reasons: [String]
    }

    struct AgentMemoryCandidate: Codable, Equatable, Sendable {
        var agent: String
        var displayName: String
        var importableUnitCount: Int
    }

    struct Progress: Codable, Equatable, Sendable {
        var rawSourceInput: String?
        var normalizedSourceList: [String]
        var uncatalogedSources: [UncatalogedSource]
        var sourceConfirmation: SourceConfirmation?
        var executionOrder: [String]?
        var activeSourceID: String?
        var sourceRows: [String: SourceRow]
        var pendingQuestion: PendingQuestion?
        var actionReview: ActionReview?
        var dailyPlan: DailyPlan?
        // Deferred source-order slice:
        // var importanceOrder: [String]

        init(
            rawSourceInput: String? = nil,
            normalizedSourceList: [String] = [],
            uncatalogedSources: [UncatalogedSource] = [],
            sourceConfirmation: SourceConfirmation? = nil,
            executionOrder: [String]? = nil,
            activeSourceID: String? = nil,
            sourceRows: [String: SourceRow] = [:],
            pendingQuestion: PendingQuestion? = nil,
            actionReview: ActionReview? = nil,
            dailyPlan: DailyPlan? = nil
        ) {
            self.rawSourceInput = rawSourceInput
            self.normalizedSourceList = normalizedSourceList
            self.uncatalogedSources = uncatalogedSources
            self.sourceConfirmation = sourceConfirmation
            self.executionOrder = executionOrder
            self.activeSourceID = activeSourceID
            self.sourceRows = sourceRows
            self.pendingQuestion = pendingQuestion
            self.actionReview = actionReview
            self.dailyPlan = dailyPlan
        }

        private enum CodingKeys: String, CodingKey {
            case rawSourceInput
            case normalizedSourceList
            case uncatalogedSources
            case unsupportedInputs
            case sourceConfirmation
            case executionOrder
            case activeSourceID
            case sourceRows
            case pendingQuestion
            case actionReview
            case dailyPlan
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
            executionOrder = try container.decodeIfPresent([String].self, forKey: .executionOrder)
            activeSourceID = try container.decodeIfPresent(String.self, forKey: .activeSourceID)
            sourceRows = try container.decodeIfPresent(
                [String: SourceRow].self,
                forKey: .sourceRows
            ) ?? [:]
            pendingQuestion = try container.decodeIfPresent(
                PendingQuestion.self,
                forKey: .pendingQuestion
            )
            actionReview = try container.decodeIfPresent(
                ActionReview.self,
                forKey: .actionReview
            )
            dailyPlan = try container.decodeIfPresent(
                DailyPlan.self,
                forKey: .dailyPlan
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(rawSourceInput, forKey: .rawSourceInput)
            try container.encode(normalizedSourceList, forKey: .normalizedSourceList)
            try container.encode(uncatalogedSources, forKey: .uncatalogedSources)
            try container.encodeIfPresent(sourceConfirmation, forKey: .sourceConfirmation)
            try container.encodeIfPresent(executionOrder, forKey: .executionOrder)
            try container.encodeIfPresent(activeSourceID, forKey: .activeSourceID)
            try container.encode(sourceRows, forKey: .sourceRows)
            try container.encodeIfPresent(pendingQuestion, forKey: .pendingQuestion)
            try container.encodeIfPresent(actionReview, forKey: .actionReview)
            try container.encodeIfPresent(dailyPlan, forKey: .dailyPlan)
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
        var playbookID: String?
        var playbookVersion: String?
        var playbookStepID: String?
        var attentionReason: String?
        var skipReason: String?
        var resultSummary: String?
        var runStatePath: String?
        var updatedAt: Date?

        init(
            id: String,
            displayName: String? = nil,
            type: String? = nil,
            phase: String? = nil,
            status: String,
            selectionState: String? = nil,
            playbookID: String? = nil,
            playbookVersion: String? = nil,
            playbookStepID: String? = nil,
            attentionReason: String? = nil,
            skipReason: String? = nil,
            resultSummary: String? = nil,
            runStatePath: String? = nil,
            updatedAt: Date? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.type = type
            self.phase = phase
            self.status = status
            self.selectionState = selectionState
            self.playbookID = playbookID
            self.playbookVersion = playbookVersion
            self.playbookStepID = playbookStepID
            self.attentionReason = attentionReason
            self.skipReason = skipReason
            self.resultSummary = resultSummary
            self.runStatePath = runStatePath
            self.updatedAt = updatedAt
        }
    }

    struct PendingQuestion: Codable, Equatable, Sendable {
        var prompt: String
        var status: String
        var askedAt: Date?
    }

    struct ActionReview: Codable, Equatable, Sendable {
        var required: Bool
        var status: String
        var reviewID: String?
        var manifestPath: String?
        var skillPath: String?
        var eligibleSourceCount: Int?
        var candidateCount: Int?
        var approvedCount: Int?
        var taskPaths: [String]
        var reason: String?
        var updatedAt: Date?

        init(
            required: Bool,
            status: String,
            reviewID: String? = nil,
            manifestPath: String? = nil,
            skillPath: String? = nil,
            eligibleSourceCount: Int? = nil,
            candidateCount: Int? = nil,
            approvedCount: Int? = nil,
            taskPaths: [String] = [],
            reason: String? = nil,
            updatedAt: Date? = nil
        ) {
            self.required = required
            self.status = status
            self.reviewID = reviewID
            self.manifestPath = manifestPath
            self.skillPath = skillPath
            self.eligibleSourceCount = eligibleSourceCount
            self.candidateCount = candidateCount
            self.approvedCount = approvedCount
            self.taskPaths = taskPaths
            self.reason = reason
            self.updatedAt = updatedAt
        }
    }

    struct DailyPlan: Codable, Equatable, Sendable {
        var required: Bool
        var status: String
        var skillPath: String?
        var calendarCoverage: String?
        var freeMinutes: Int?
        var scheduledMinutes: Int?
        var plannedTaskCount: Int?
        var scheduledTaskPaths: [String]?
        var calendarWriteStatus: String?
        var calendarEventIDs: [String]
        var reason: String?
        var updatedAt: Date?

        init(
            required: Bool,
            status: String,
            skillPath: String? = nil,
            calendarCoverage: String? = nil,
            freeMinutes: Int? = nil,
            scheduledMinutes: Int? = nil,
            plannedTaskCount: Int? = nil,
            scheduledTaskPaths: [String]? = [],
            calendarWriteStatus: String? = nil,
            calendarEventIDs: [String] = [],
            reason: String? = nil,
            updatedAt: Date? = nil
        ) {
            self.required = required
            self.status = status
            self.skillPath = skillPath
            self.calendarCoverage = calendarCoverage
            self.freeMinutes = freeMinutes
            self.scheduledMinutes = scheduledMinutes
            self.plannedTaskCount = plannedTaskCount
            self.scheduledTaskPaths = scheduledTaskPaths
            self.calendarWriteStatus = calendarWriteStatus
            self.calendarEventIDs = calendarEventIDs
            self.reason = reason
            self.updatedAt = updatedAt
        }
    }
}
