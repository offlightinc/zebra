import Foundation

public enum BrainGoalStatus: String, Codable, CaseIterable, Sendable {
    case active
    case blocked
    case draft
    case completed
    case archived

    public var label: String {
        switch self {
        case .active:
            return String(localized: "verticalTabsSidebar.goals.status.active", defaultValue: "ACTIVE")
        case .blocked:
            return String(localized: "verticalTabsSidebar.goals.status.blocked", defaultValue: "BLOCKED")
        case .draft:
            return String(localized: "verticalTabsSidebar.goals.status.draft", defaultValue: "DRAFT")
        case .completed:
            return String(localized: "verticalTabsSidebar.goals.status.completed", defaultValue: "COMPLETED")
        case .archived:
            return String(localized: "verticalTabsSidebar.goals.status.archived", defaultValue: "ARCHIVED")
        }
    }
}

public enum GoalCadence: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case quarterly

    public var label: String {
        switch self {
        case .daily:
            return String(localized: "verticalTabsSidebar.goals.cadence.daily", defaultValue: "DAILY")
        case .weekly:
            return String(localized: "verticalTabsSidebar.goals.cadence.weekly", defaultValue: "WEEKLY")
        case .monthly:
            return String(localized: "verticalTabsSidebar.goals.cadence.monthly", defaultValue: "MONTHLY")
        case .quarterly:
            return String(localized: "verticalTabsSidebar.goals.cadence.quarterly", defaultValue: "QUARTERLY")
        }
    }
}

public struct GoalEntry: VaultSubdirEntry {
    public let absolutePath: String
    public let displayName: String
    public let goalId: String
    public let parentGoalId: String?
    public let status: BrainGoalStatus?
    public let unrecognizedStatusRaw: String?
    public let cadence: GoalCadence
    public let targetDate: Date?
    public let milestoneDone: Int
    public let milestoneTotal: Int

    public var id: String { absolutePath }

    public func with(
        status: BrainGoalStatus?? = nil,
        unrecognizedStatusRaw: String?? = nil
    ) -> GoalEntry {
        GoalEntry(
            absolutePath: absolutePath,
            displayName: displayName,
            goalId: goalId,
            parentGoalId: parentGoalId,
            status: status ?? self.status,
            unrecognizedStatusRaw: unrecognizedStatusRaw ?? self.unrecognizedStatusRaw,
            cadence: cadence,
            targetDate: targetDate,
            milestoneDone: milestoneDone,
            milestoneTotal: milestoneTotal
        )
    }
}
