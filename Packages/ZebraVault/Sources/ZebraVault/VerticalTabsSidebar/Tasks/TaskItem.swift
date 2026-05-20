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
    public let goalSlug: String?
    public let relatedProjects: [String]
    public let tags: [String]

    public var id: String { absolutePath }

    public func with(
        status: BrainTaskStatus?? = nil,
        unrecognizedStatusRaw: String?? = nil,
        priority: BrainPriority?? = nil,
        dueDate: Date?? = nil
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
            goalSlug: goalSlug,
            relatedProjects: relatedProjects,
            tags: tags
        )
    }
}
