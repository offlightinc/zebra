import Foundation
import Combine

enum TaskGroupBy: String, CaseIterable, Hashable, Sendable {
    case status
    case priority
    case owner
    case project
    case goal
    case none

    var label: String {
        switch self {
        case .status:   return String(localized: "task.groupBy.status", defaultValue: "Status")
        case .priority: return String(localized: "task.groupBy.priority", defaultValue: "Priority")
        case .owner:    return String(localized: "task.groupBy.owner", defaultValue: "Owner")
        case .project:  return String(localized: "task.groupBy.project", defaultValue: "Project")
        case .goal:     return String(localized: "task.groupBy.goal", defaultValue: "Goal")
        case .none:     return String(localized: "task.groupBy.none", defaultValue: "No grouping")
        }
    }
}

enum TaskFilterField: String, CaseIterable, Hashable, Sendable {
    case status, priority, owner

    var label: String {
        switch self {
        case .status:   return String(localized: "task.filter.field.status", defaultValue: "Status")
        case .priority: return String(localized: "task.filter.field.priority", defaultValue: "Priority")
        case .owner:    return String(localized: "task.filter.field.owner", defaultValue: "Owner")
        }
    }
}

enum TaskFilterOp: Hashable, Sendable {
    case `is`
    case isNot

    var symbol: String { self == .is ? "=" : "≠" }
}

/// One filter chip = one field, one operator, multiple selected values.
struct TaskFilter: Hashable, Sendable, Identifiable {
    let field: TaskFilterField
    var op: TaskFilterOp
    /// Values are raw strings. Interpretation per field:
    /// - status: BrainTaskStatus rawValue, or "__unrecognized__"
    /// - priority: BrainPriority rawValue, or "__none__"
    /// - owner: owner slug, or "__unassigned__"
    var values: [String]

    var id: TaskFilterField { field }
}

/// Group key for layout. Stable identity for SwiftUI ForEach.
struct TaskGroupKey: Hashable, Sendable {
    let raw: String
    let label: String
    let order: Int
}

struct TaskGroup: Identifiable, Sendable {
    let key: TaskGroupKey
    let items: [TaskItem]

    var id: String { key.raw }
}

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published var groupBy: TaskGroupBy = .status {
        didSet { persistState() }
    }
    @Published var filters: [TaskFilter] = [] {
        didSet { persistState() }
    }
    @Published var collapsedSections: Set<String> = [] {
        didSet { persistState() }
    }

    private var persistenceRootPath: String?
    private var isRestoringState = false

    func bindPersistence(rootPath: String?) {
        guard rootPath != persistenceRootPath else { return }
        persistenceRootPath = rootPath

        let restored = VerticalTabsSidebarViewStatePersistence.loadTaskState(rootPath: rootPath)
        isRestoringState = true
        groupBy = restored.resolvedGroupBy
        filters = restored.resolvedFilters
        collapsedSections = Set(restored.collapsedSections)
        isRestoringState = false
    }

    func setFilter(_ filter: TaskFilter) {
        if let idx = filters.firstIndex(where: { $0.field == filter.field }) {
            filters[idx] = filter
        } else {
            filters.append(filter)
        }
    }

    func removeFilter(field: TaskFilterField) {
        filters.removeAll { $0.field == field }
    }

    func visibleTasks(from tasks: [TaskItem]) -> [TaskItem] {
        Self.applyFilters(tasks, filters)
    }

    private func persistState() {
        guard !isRestoringState,
              let rootPath = persistenceRootPath else { return }
        VerticalTabsSidebarViewStatePersistence.saveTaskState(
            VerticalTabsSidebarViewStatePersistence.TaskState(
                groupBy: groupBy,
                filters: filters,
                collapsedSections: collapsedSections
            ),
            rootPath: rootPath
        )
    }

    /// Filter chain: 필드 내 OR (values 배열 포함), 필드 간 AND (every).
    static func applyFilters(_ tasks: [TaskItem], _ filters: [TaskFilter]) -> [TaskItem] {
        guard !filters.isEmpty else { return tasks }
        return tasks.filter { task in
            filters.allSatisfy { f in
                if f.values.isEmpty { return true }
                let v = currentValue(for: task, field: f.field)
                let inSet = f.values.contains(v)
                return f.op == .is ? inSet : !inSet
            }
        }
    }

    private static func currentValue(for task: TaskItem, field: TaskFilterField) -> String {
        switch field {
        case .status:
            if let s = task.status { return s.rawValue }
            return task.unrecognizedStatusRaw != nil ? "__unrecognized__" : "__none__"
        case .priority:
            return task.priority?.rawValue ?? "__none__"
        case .owner:
            return task.ownerSlug ?? "__unassigned__"
        }
    }

    /// Groups tasks for display. `.project` is multi-group (a single task with
    /// `relatedProjects: [A, B]` appears in both A and B sections).
    static func groupTasks(_ tasks: [TaskItem], by mode: TaskGroupBy) -> [TaskGroup] {
        switch mode {
        case .none:
            return [
                TaskGroup(
                    key: TaskGroupKey(raw: "all", label: String(localized: "task.group.all", defaultValue: "All"), order: 0),
                    items: tasks
                )
            ]
        case .status:
            return groupBySingleKey(tasks, order: statusOrder) { task in
                if let s = task.status { return (s.rawValue, s.localizedLabel) }
                if task.unrecognizedStatusRaw != nil {
                    return ("__unrecognized__", String(localized: "task.group.unrecognized", defaultValue: "Unrecognized"))
                }
                return ("__none__", String(localized: "task.group.noStatus", defaultValue: "No status"))
            }
        case .priority:
            // Linear convention: completed/canceled bucketed into "Done" (priority irrelevant).
            return groupBySingleKey(tasks, order: priorityOrder) { task in
                if let s = task.status, s == .done || s == .canceled {
                    return ("__done__", String(localized: "task.group.done", defaultValue: "Done"))
                }
                if let p = task.priority { return (p.rawValue, p.localizedLabel) }
                return ("__none__", String(localized: "task.priority.none", defaultValue: "No priority"))
            }
        case .owner:
            return groupBySingleKey(tasks, order: { _ in 99 }) { task in
                if let slug = task.ownerSlug { return (slug, slug) }
                return ("__unassigned__", String(localized: "task.group.unassigned", defaultValue: "Unassigned"))
            }
        case .goal:
            return groupBySingleKey(tasks, order: { _ in 99 }) { task in
                if let slug = task.goalSlug { return (slug, slug) }
                return ("__none__", String(localized: "task.group.noGoal", defaultValue: "No goal"))
            }
        case .project:
            return groupMulti(tasks)
        }
    }

    private static func groupBySingleKey(
        _ tasks: [TaskItem],
        order: (String) -> Int,
        keyOf: (TaskItem) -> (String, String)
    ) -> [TaskGroup] {
        var buckets: [String: (label: String, order: Int, items: [TaskItem])] = [:]
        for task in tasks {
            let (raw, label) = keyOf(task)
            let ord = order(raw)
            if buckets[raw] != nil {
                buckets[raw]!.items.append(task)
            } else {
                buckets[raw] = (label, ord, [task])
            }
        }
        return buckets.map { (raw, v) in
            TaskGroup(
                key: TaskGroupKey(raw: raw, label: v.label, order: v.order),
                items: v.items
            )
        }
        .sorted { lhs, rhs in
            if lhs.key.order != rhs.key.order { return lhs.key.order < rhs.key.order }
            return lhs.key.label.localizedCaseInsensitiveCompare(rhs.key.label) == .orderedAscending
        }
    }

    /// Multi-group: a task with N relatedProjects appears in N sections.
    /// Tasks without any project go into "No project".
    private static func groupMulti(_ tasks: [TaskItem]) -> [TaskGroup] {
        var buckets: [String: (label: String, items: [TaskItem])] = [:]
        let noKey = "__none__"
        for task in tasks {
            if task.relatedProjects.isEmpty {
                buckets[noKey, default: (String(localized: "task.group.noProject", defaultValue: "No project"), [])].items.append(task)
            } else {
                for slug in task.relatedProjects {
                    buckets[slug, default: (slug, [])].items.append(task)
                }
            }
        }
        return buckets.map { (raw, v) in
            TaskGroup(
                key: TaskGroupKey(raw: raw, label: v.label, order: raw == noKey ? 99 : 0),
                items: v.items
            )
        }
        .sorted { lhs, rhs in
            if lhs.key.order != rhs.key.order { return lhs.key.order < rhs.key.order }
            return lhs.key.label.localizedCaseInsensitiveCompare(rhs.key.label) == .orderedAscending
        }
    }

    private static func statusOrder(_ raw: String) -> Int {
        // HTML group order: inprogress → todo → blocked → backlog → done.
        // waiting/canceled는 보존 호환 — done 다음에 둔다.
        switch raw {
        case BrainTaskStatus.inprogress.rawValue: return 0
        case BrainTaskStatus.todo.rawValue: return 1
        case BrainTaskStatus.blocked.rawValue: return 2
        case BrainTaskStatus.backlog.rawValue: return 3
        case BrainTaskStatus.done.rawValue: return 4
        case BrainTaskStatus.waiting.rawValue: return 5
        case BrainTaskStatus.canceled.rawValue: return 6
        case "__unrecognized__": return 7
        default: return 8
        }
    }

    private static func priorityOrder(_ raw: String) -> Int {
        switch raw {
        case BrainPriority.urgent.rawValue: return 0
        case BrainPriority.high.rawValue: return 1
        case BrainPriority.medium.rawValue: return 2
        case BrainPriority.low.rawValue: return 3
        case "__none__": return 4
        case "__done__": return 5
        default: return 9
        }
    }

}
