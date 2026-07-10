import Foundation
import Combine

enum TaskListViewMode: String, CaseIterable, Hashable, Sendable {
    case all
    case todayPlan

    var label: String {
        switch self {
        case .all:
            return String(localized: "task.view.all", defaultValue: "All")
        case .todayPlan:
            return String(localized: "task.view.todayPlan", defaultValue: "Today")
        }
    }
}

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

enum TaskSort: String, CaseIterable, Hashable, Sendable {
    case title
    case priority
    case status
    case due
    case created
    case updated

    var label: String {
        switch self {
        case .title:   return String(localized: "task.sort.title", defaultValue: "Title")
        case .priority: return String(localized: "task.sort.priority", defaultValue: "Priority")
        case .status:   return String(localized: "task.sort.status", defaultValue: "Status")
        case .due:     return String(localized: "task.sort.due", defaultValue: "Due")
        case .created: return String(localized: "task.sort.created", defaultValue: "Created")
        case .updated: return String(localized: "task.sort.updated", defaultValue: "Updated")
        }
    }

    var defaultDirection: TaskSortDirection {
        switch self {
        case .title, .priority, .status, .due:
            return .ascending
        case .created, .updated:
            return .descending
        }
    }
}

enum TaskSortDirection: String, Hashable, Sendable {
    case ascending
    case descending

    var symbol: String {
        switch self {
        case .ascending:  return "↑"
        case .descending: return "↓"
        }
    }

    var toggled: TaskSortDirection {
        self == .ascending ? .descending : .ascending
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
    @Published var viewMode: TaskListViewMode = .all {
        didSet { persistState() }
    }
    @Published var groupBy: TaskGroupBy = .status {
        didSet { persistState() }
    }
    @Published var sort: TaskSort = .title {
        didSet { persistState() }
    }
    @Published var sortDirection: TaskSortDirection = TaskSort.title.defaultDirection {
        didSet { persistState() }
    }
    @Published var filters: [TaskFilter] = [] {
        didSet { persistState() }
    }
    @Published var collapsedSections: Set<String> = [] {
        didSet { persistState() }
    }
    /// Owner filter applied via the "내 것" toolbar entry-point. Kept separate from
    /// `filters` so the chip row can render it as a distinct chip and the toolbar
    /// can own its own popover. nil = inactive.
    @Published var myOwnerFilter: TaskFilter? = nil {
        didSet { persistState() }
    }

    private var persistenceRootPath: String?
    private var isRestoringState = false

    func bindPersistence(rootPath: String?) {
        guard rootPath != persistenceRootPath else { return }
        persistenceRootPath = rootPath

        let restored = VerticalTabsSidebarViewStatePersistence.loadTaskState(rootPath: rootPath)
        isRestoringState = true
        viewMode = restored.resolvedViewMode
        groupBy = restored.resolvedGroupBy
        sort = restored.resolvedSort
        sortDirection = restored.resolvedSortDirection
        filters = restored.resolvedFilters
        collapsedSections = Set(restored.collapsedSections)
        myOwnerFilter = restored.resolvedMyOwnerFilter
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
        var allFilters = filters
        if let mf = myOwnerFilter, !mf.values.isEmpty {
            allFilters.append(mf)
        }
        return Self.applyFilters(tasks, allFilters)
    }

    func displayTasks(from tasks: [TaskItem]) -> [TaskItem] {
        Self.sortTasks(visibleTasks(from: tasks), by: sort, direction: sortDirection)
    }

    func pickSort(_ selected: TaskSort) {
        if sort == selected {
            sortDirection = sortDirection.toggled
        } else {
            sort = selected
            sortDirection = selected.defaultDirection
        }
    }

    private func persistState() {
        guard !isRestoringState,
              let rootPath = persistenceRootPath else { return }
        VerticalTabsSidebarViewStatePersistence.saveTaskState(
            VerticalTabsSidebarViewStatePersistence.TaskState(
                groupBy: groupBy,
                sort: sort,
                sortDirection: sortDirection,
                filters: filters,
                collapsedSections: collapsedSections,
                myOwnerFilter: myOwnerFilter,
                viewMode: viewMode
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

    static func sortTasks(
        _ tasks: [TaskItem],
        by sort: TaskSort,
        direction: TaskSortDirection
    ) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch sort {
            case .title:
                return compareTitle(lhs, rhs, direction: direction)
            case .priority:
                if let result = compareRank(
                    lhs.priority.map { priorityOrder($0.rawValue) },
                    rhs.priority.map { priorityOrder($0.rawValue) },
                    direction: direction
                ) {
                    return result
                }
                if let result = compareDate(lhs.dueDate, rhs.dueDate, direction: .ascending) {
                    return result
                }
                return compareTitle(lhs, rhs, direction: .ascending)
            case .status:
                if let result = compareRank(
                    lhs.status.map { statusOrder($0.rawValue) },
                    rhs.status.map { statusOrder($0.rawValue) },
                    direction: direction
                ) {
                    return result
                }
                return compareTitle(lhs, rhs, direction: .ascending)
            case .due:
                if let result = compareDate(lhs.dueDate, rhs.dueDate, direction: direction) {
                    return result
                }
                return compareTitle(lhs, rhs, direction: .ascending)
            case .created:
                if let result = compareDate(lhs.createdDate, rhs.createdDate, direction: direction) {
                    return result
                }
                return compareTitle(lhs, rhs, direction: .ascending)
            case .updated:
                if let result = compareDate(lhs.updatedDate, rhs.updatedDate, direction: direction) {
                    return result
                }
                return compareTitle(lhs, rhs, direction: .ascending)
            }
        }
    }

    private static func compareRank(
        _ lhs: Int?,
        _ rhs: Int?,
        direction: TaskSortDirection
    ) -> Bool? {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l == r { return nil }
            return direction == .ascending ? l < r : l > r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return nil
        }
    }

    private static func compareDate(
        _ lhs: Date?,
        _ rhs: Date?,
        direction: TaskSortDirection
    ) -> Bool? {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l == r { return nil }
            return direction == .ascending ? l < r : l > r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return nil
        }
    }

    private static func compareTitle(
        _ lhs: TaskItem,
        _ rhs: TaskItem,
        direction: TaskSortDirection
    ) -> Bool {
        let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if comparison != .orderedSame {
            return direction == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
        return lhs.absolutePath < rhs.absolutePath
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

    func plannedGroups(
        from tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskGroup] {
        Self.groupPlannedTasks(visibleTasks(from: tasks), now: now, calendar: calendar)
    }

    static func groupPlannedTasks(
        _ tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskGroup] {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        var today: [TaskItem] = []
        var later: [TaskItem] = []
        var invalid: [TaskItem] = []

        for task in tasks {
            if task.hasInvalidPlannedInterval {
                invalid.append(task)
            } else if let interval = task.plannedInterval {
                if interval.start < dayEnd && interval.end > dayStart {
                    today.append(task)
                } else if interval.start >= dayEnd {
                    later.append(task)
                }
            }
        }

        func plannedOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
            let left = lhs.plannedStartDate ?? .distantFuture
            let right = rhs.plannedStartDate ?? .distantFuture
            if left != right { return left < right }
            return lhs.absolutePath < rhs.absolutePath
        }

        var groups: [TaskGroup] = []
        if !today.isEmpty {
            groups.append(TaskGroup(
                key: TaskGroupKey(
                    raw: "planned_today",
                    label: String(localized: "task.plan.group.today", defaultValue: "Today"),
                    order: 0
                ),
                items: today.sorted(by: plannedOrder)
            ))
        }
        if !later.isEmpty {
            groups.append(TaskGroup(
                key: TaskGroupKey(
                    raw: "planned_later",
                    label: String(localized: "task.plan.group.later", defaultValue: "Later"),
                    order: 1
                ),
                items: later.sorted(by: plannedOrder)
            ))
        }
        if !invalid.isEmpty {
            groups.append(TaskGroup(
                key: TaskGroupKey(
                    raw: "planned_invalid",
                    label: String(localized: "task.plan.group.needsReview", defaultValue: "Needs review"),
                    order: 2
                ),
                items: invalid.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            ))
        }
        return groups
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
        // Actionable states first; terminal and unknown states stay at the end.
        switch raw {
        case BrainTaskStatus.inprogress.rawValue: return 0
        case BrainTaskStatus.todo.rawValue: return 1
        case BrainTaskStatus.blocked.rawValue: return 2
        case BrainTaskStatus.waiting.rawValue: return 3
        case BrainTaskStatus.backlog.rawValue: return 4
        case BrainTaskStatus.done.rawValue: return 5
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
