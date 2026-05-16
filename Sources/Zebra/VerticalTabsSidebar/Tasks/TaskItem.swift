import Foundation

struct TaskItem: VaultSubdirEntry {
    let absolutePath: String
    let displayName: String
    let title: String
    let status: BrainTaskStatus?
    let unrecognizedStatusRaw: String?
    let priority: BrainPriority?
    let ownerSlug: String?
    let dueDate: Date?
    let goalSlug: String?
    let relatedProjects: [String]
    let tags: [String]

    var id: String { absolutePath }

    func with(
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
