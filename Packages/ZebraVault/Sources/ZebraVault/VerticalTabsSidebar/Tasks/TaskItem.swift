import Foundation

public struct TaskItem: VaultSubdirEntry {
    public let absolutePath: String
    public let displayName: String
    public let title: String
    public let status: BrainTaskStatus?
    public let unrecognizedStatusRaw: String?
    public let priority: BrainPriority?
    public let ownerSlug: String?
    public let dueDate: Date?
    public let createdDate: Date?
    public let updatedDate: Date?
    public let plannedStartDate: Date?
    public let plannedEndDate: Date?
    public let hasInvalidPlannedInterval: Bool
    public let goalSlug: String?
    public let relatedProjects: [String]
    public let tags: [String]

    public init(
        absolutePath: String,
        displayName: String,
        title: String,
        status: BrainTaskStatus?,
        unrecognizedStatusRaw: String?,
        priority: BrainPriority?,
        ownerSlug: String?,
        dueDate: Date?,
        createdDate: Date?,
        updatedDate: Date?,
        plannedStartDate: Date? = nil,
        plannedEndDate: Date? = nil,
        hasInvalidPlannedInterval: Bool = false,
        goalSlug: String?,
        relatedProjects: [String],
        tags: [String]
    ) {
        self.absolutePath = absolutePath
        self.displayName = displayName
        self.title = title
        self.status = status
        self.unrecognizedStatusRaw = unrecognizedStatusRaw
        self.priority = priority
        self.ownerSlug = ownerSlug
        self.dueDate = dueDate
        self.createdDate = createdDate
        self.updatedDate = updatedDate
        self.plannedStartDate = plannedStartDate
        self.plannedEndDate = plannedEndDate
        self.hasInvalidPlannedInterval = hasInvalidPlannedInterval
        self.goalSlug = goalSlug
        self.relatedProjects = relatedProjects
        self.tags = tags
    }

    public var id: String { absolutePath }

    public func with(
        status: BrainTaskStatus?? = nil,
        unrecognizedStatusRaw: String?? = nil,
        priority: BrainPriority?? = nil,
        dueDate: Date?? = nil,
        plannedStartDate: Date?? = nil,
        plannedEndDate: Date?? = nil,
        hasInvalidPlannedInterval: Bool? = nil
    ) -> TaskItem {
        TaskItem(
            absolutePath: absolutePath,
            displayName: displayName,
            title: title,
            status: status ?? self.status,
            unrecognizedStatusRaw: unrecognizedStatusRaw ?? self.unrecognizedStatusRaw,
            priority: priority ?? self.priority,
            ownerSlug: ownerSlug,
            dueDate: dueDate ?? self.dueDate,
            createdDate: createdDate,
            updatedDate: updatedDate,
            plannedStartDate: plannedStartDate ?? self.plannedStartDate,
            plannedEndDate: plannedEndDate ?? self.plannedEndDate,
            hasInvalidPlannedInterval: hasInvalidPlannedInterval ?? self.hasInvalidPlannedInterval,
            goalSlug: goalSlug,
            relatedProjects: relatedProjects,
            tags: tags
        )
    }

    public var plannedInterval: DateInterval? {
        guard !hasInvalidPlannedInterval,
              let plannedStartDate,
              let plannedEndDate,
              plannedEndDate > plannedStartDate else { return nil }
        return DateInterval(start: plannedStartDate, end: plannedEndDate)
    }
}
