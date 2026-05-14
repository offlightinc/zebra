import Foundation

enum BrainGoalStatus: String, Codable, CaseIterable, Sendable {
    case active
    case blocked
    case draft
    case completed
    case archived

    var label: String {
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

enum GoalCadence: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case quarterly

    var label: String {
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

struct GoalEntry: VaultSubdirEntry {
    let absolutePath: String
    let displayName: String
    let goalId: String
    let parentGoalId: String?
    let status: BrainGoalStatus
    let cadence: GoalCadence
    let targetDate: Date?
    let milestoneDone: Int
    let milestoneTotal: Int

    var id: String { absolutePath }
}
