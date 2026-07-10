import XCTest
@testable import ZebraVault

final class TaskListViewModelTests: XCTestCase {
    @MainActor
    func testSortsByTitleByDefaultOrder() {
        let tasks = [
            task(path: "/tmp/b.md", title: "Beta"),
            task(path: "/tmp/a.md", title: "alpha"),
            task(path: "/tmp/c.md", title: "Alpha"),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .title, direction: .ascending)

        XCTAssertEqual(sorted.map(\.absolutePath), ["/tmp/a.md", "/tmp/c.md", "/tmp/b.md"])
    }

    @MainActor
    func testSortsByTitleDescending() {
        let tasks = [
            task(path: "/tmp/a.md", title: "alpha"),
            task(path: "/tmp/b.md", title: "Beta"),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .title, direction: .descending)

        XCTAssertEqual(sorted.map(\.absolutePath), ["/tmp/b.md", "/tmp/a.md"])
    }

    @MainActor
    func testSortsByPriorityHighestFirstWithMissingPriorityLast() {
        let tasks = [
            task(path: "/tmp/none.md", title: "None"),
            task(path: "/tmp/low.md", title: "Low", priority: .low),
            task(path: "/tmp/urgent.md", title: "Urgent", priority: .urgent),
            task(path: "/tmp/high.md", title: "High", priority: .high),
            task(path: "/tmp/medium.md", title: "Medium", priority: .medium),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .priority, direction: .ascending)

        XCTAssertEqual(
            sorted.map(\.absolutePath),
            ["/tmp/urgent.md", "/tmp/high.md", "/tmp/medium.md", "/tmp/low.md", "/tmp/none.md"]
        )
    }

    @MainActor
    func testPrioritySortUsesSoonestDueDateThenTitleForTies() {
        let tasks = [
            task(path: "/tmp/no-due.md", title: "No due", priority: .high),
            task(path: "/tmp/later.md", title: "Later", priority: .high, due: "2026-06-05"),
            task(path: "/tmp/b-soon.md", title: "Beta", priority: .high, due: "2026-06-01"),
            task(path: "/tmp/a-soon.md", title: "Alpha", priority: .high, due: "2026-06-01"),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .priority, direction: .ascending)

        XCTAssertEqual(
            sorted.map(\.absolutePath),
            ["/tmp/a-soon.md", "/tmp/b-soon.md", "/tmp/later.md", "/tmp/no-due.md"]
        )
    }

    @MainActor
    func testSortsByStatusActionOrderWithMissingStatusLast() {
        let tasks = [
            task(path: "/tmp/none.md", title: "None", status: nil),
            task(path: "/tmp/canceled.md", title: "Canceled", status: .canceled),
            task(path: "/tmp/done.md", title: "Done", status: .done),
            task(path: "/tmp/backlog.md", title: "Backlog", status: .backlog),
            task(path: "/tmp/waiting.md", title: "Waiting", status: .waiting),
            task(path: "/tmp/blocked.md", title: "Blocked", status: .blocked),
            task(path: "/tmp/todo.md", title: "Todo", status: .todo),
            task(path: "/tmp/inprogress.md", title: "In progress", status: .inprogress),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .status, direction: .ascending)

        XCTAssertEqual(
            sorted.map(\.absolutePath),
            [
                "/tmp/inprogress.md", "/tmp/todo.md", "/tmp/blocked.md", "/tmp/waiting.md",
                "/tmp/backlog.md", "/tmp/done.md", "/tmp/canceled.md", "/tmp/none.md",
            ]
        )
    }

    @MainActor
    func testDescendingStatusAndPrioritySortsStillKeepMissingValuesLast() {
        let statusTasks = [
            task(path: "/tmp/no-status.md", title: "No status", status: nil),
            task(path: "/tmp/todo.md", title: "Todo", status: .todo),
            task(path: "/tmp/done.md", title: "Done", status: .done),
        ]
        let priorityTasks = [
            task(path: "/tmp/no-priority.md", title: "No priority"),
            task(path: "/tmp/urgent.md", title: "Urgent", priority: .urgent),
            task(path: "/tmp/low.md", title: "Low", priority: .low),
        ]

        let sortedStatuses = TaskListViewModel.sortTasks(statusTasks, by: .status, direction: .descending)
        let sortedPriorities = TaskListViewModel.sortTasks(priorityTasks, by: .priority, direction: .descending)

        XCTAssertEqual(sortedStatuses.map(\.absolutePath), ["/tmp/done.md", "/tmp/todo.md", "/tmp/no-status.md"])
        XCTAssertEqual(sortedPriorities.map(\.absolutePath), ["/tmp/low.md", "/tmp/urgent.md", "/tmp/no-priority.md"])
    }

    @MainActor
    func testSortsByDueSoonestFirstWithMissingDatesLast() {
        let tasks = [
            task(path: "/tmp/no-due.md", title: "No due"),
            task(path: "/tmp/later.md", title: "Later", due: "2026-06-05"),
            task(path: "/tmp/soon.md", title: "Soon", due: "2026-06-01"),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .due, direction: .ascending)

        XCTAssertEqual(sorted.map(\.absolutePath), ["/tmp/soon.md", "/tmp/later.md", "/tmp/no-due.md"])
    }

    @MainActor
    func testSortsByDueDescendingWithMissingDatesLast() {
        let tasks = [
            task(path: "/tmp/no-due.md", title: "No due"),
            task(path: "/tmp/later.md", title: "Later", due: "2026-06-05"),
            task(path: "/tmp/soon.md", title: "Soon", due: "2026-06-01"),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .due, direction: .descending)

        XCTAssertEqual(sorted.map(\.absolutePath), ["/tmp/later.md", "/tmp/soon.md", "/tmp/no-due.md"])
    }

    @MainActor
    func testSortsByCreatedNewestFirstWithMissingDatesLast() {
        let tasks = [
            task(path: "/tmp/old.md", title: "Old", created: "2026-05-01"),
            task(path: "/tmp/new.md", title: "New", created: "2026-05-03"),
            task(path: "/tmp/no-created.md", title: "No created"),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .created, direction: .descending)

        XCTAssertEqual(sorted.map(\.absolutePath), ["/tmp/new.md", "/tmp/old.md", "/tmp/no-created.md"])
    }

    @MainActor
    func testSortsByUpdatedNewestFirstWithMissingDatesLast() {
        let tasks = [
            task(path: "/tmp/no-updated.md", title: "No updated"),
            task(path: "/tmp/new.md", title: "New", updated: "2026-05-28"),
            task(path: "/tmp/old.md", title: "Old", updated: "2026-05-27"),
        ]

        let sorted = TaskListViewModel.sortTasks(tasks, by: .updated, direction: .descending)

        XCTAssertEqual(sorted.map(\.absolutePath), ["/tmp/new.md", "/tmp/old.md", "/tmp/no-updated.md"])
    }

    @MainActor
    func testPickSortTogglesCurrentSortDirection() {
        let viewModel = TaskListViewModel()

        viewModel.pickSort(.title)

        XCTAssertEqual(viewModel.sort, .title)
        XCTAssertEqual(viewModel.sortDirection, .descending)
    }

    @MainActor
    func testPickSortUsesDefaultDirectionForNewSort() {
        let viewModel = TaskListViewModel()

        viewModel.pickSort(.updated)

        XCTAssertEqual(viewModel.sort, .updated)
        XCTAssertEqual(viewModel.sortDirection, .descending)
    }

    @MainActor
    func testDisplayTasksFiltersBeforeSorting() {
        let viewModel = TaskListViewModel()
        viewModel.filters = [
            TaskFilter(field: .status, op: .is, values: [BrainTaskStatus.todo.rawValue])
        ]
        viewModel.sort = .due
        let tasks = [
            task(path: "/tmp/done.md", title: "Done", status: .done, due: "2026-06-01"),
            task(path: "/tmp/later.md", title: "Later", status: .todo, due: "2026-06-05"),
            task(path: "/tmp/soon.md", title: "Soon", status: .todo, due: "2026-06-01"),
        ]

        let displayed = viewModel.displayTasks(from: tasks)

        XCTAssertEqual(displayed.map(\.absolutePath), ["/tmp/soon.md", "/tmp/later.md"])
    }

    @MainActor
    func testPlannedGroupsSeparateTodayLaterAndInvalidInPlannedOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let now = try XCTUnwrap(BrainPlannedDateTimeCodec.date(fromStorageString: "2026-07-10T12:00:00+09:00"))
        let tasks = [
            task(path: "/tmp/later.md", title: "Later", plannedStart: "2026-07-11T09:00:00+09:00", plannedEnd: "2026-07-11T10:00:00+09:00"),
            task(path: "/tmp/today-2.md", title: "Second", plannedStart: "2026-07-10T14:00:00+09:00", plannedEnd: "2026-07-10T15:00:00+09:00"),
            task(path: "/tmp/invalid.md", title: "Broken", invalidPlannedInterval: true),
            task(path: "/tmp/today-1.md", title: "First", status: .done, plannedStart: "2026-07-10T09:00:00+09:00", plannedEnd: "2026-07-10T10:00:00+09:00"),
            task(path: "/tmp/unplanned.md", title: "Unplanned"),
        ]

        let groups = TaskListViewModel.groupPlannedTasks(tasks, now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.key.raw), ["planned_today", "planned_later", "planned_invalid"])
        XCTAssertEqual(groups[0].items.map(\.absolutePath), ["/tmp/today-1.md", "/tmp/today-2.md"])
        XCTAssertEqual(groups[1].items.map(\.absolutePath), ["/tmp/later.md"])
        XCTAssertEqual(groups[2].items.map(\.absolutePath), ["/tmp/invalid.md"])
    }

    @MainActor
    func testPlannedGroupsHonorRegularOwnerFilter() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let now = try XCTUnwrap(BrainPlannedDateTimeCodec.date(fromStorageString: "2026-07-10T12:00:00+09:00"))
        let viewModel = TaskListViewModel()
        viewModel.filters = [TaskFilter(field: .owner, op: .is, values: ["dan"])]
        let tasks = [
            task(path: "/tmp/dan.md", title: "Dan", owner: "dan", plannedStart: "2026-07-10T14:00:00+09:00", plannedEnd: "2026-07-10T15:00:00+09:00"),
            task(path: "/tmp/other.md", title: "Other", owner: "other", plannedStart: "2026-07-10T13:00:00+09:00", plannedEnd: "2026-07-10T14:00:00+09:00"),
        ]

        let groups = viewModel.plannedGroups(from: tasks, now: now, calendar: calendar)

        XCTAssertEqual(groups.flatMap(\.items).map(\.absolutePath), ["/tmp/dan.md"])
    }

    @MainActor
    func testLegacyOwnerShortcutMigratesIntoVisibleOwnerFilter() {
        let migrated = TaskListViewModel.migratedFilters(
            [TaskFilter(field: .status, op: .is, values: ["todo"])],
            legacyOwnerFilter: TaskFilter(field: .owner, op: .is, values: ["dan"])
        )

        XCTAssertEqual(migrated.count, 2)
        XCTAssertEqual(migrated.first(where: { $0.field == .owner })?.values, ["dan"])
    }

    @MainActor
    func testLegacyAndRegularOwnerFiltersPreserveTheirIntersection() {
        let migrated = TaskListViewModel.migratedFilters(
            [TaskFilter(field: .owner, op: .is, values: ["dan", "han"])],
            legacyOwnerFilter: TaskFilter(field: .owner, op: .is, values: ["han", "namho"])
        )
        let owner = migrated.first(where: { $0.field == .owner })

        XCTAssertEqual(owner?.op, .is)
        XCTAssertEqual(owner?.values, ["han"])

        let noMatch = TaskListViewModel.migratedFilters(
            [TaskFilter(field: .owner, op: .is, values: ["dan"])],
            legacyOwnerFilter: TaskFilter(field: .owner, op: .is, values: ["han"])
        )
        let visible = TaskListViewModel.applyFilters(
            [task(path: "/tmp/dan.md", title: "Dan", owner: "dan")],
            noMatch
        )
        XCTAssertTrue(visible.isEmpty)
    }

    private func task(
        path: String,
        title: String,
        status: BrainTaskStatus? = .todo,
        priority: BrainPriority? = nil,
        owner: String? = nil,
        due: String? = nil,
        created: String? = nil,
        updated: String? = nil,
        plannedStart: String? = nil,
        plannedEnd: String? = nil,
        invalidPlannedInterval: Bool = false
    ) -> TaskItem {
        TaskItem(
            absolutePath: path,
            displayName: title,
            title: title,
            status: status,
            unrecognizedStatusRaw: nil,
            priority: priority,
            ownerSlug: owner,
            dueDate: due.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            createdDate: created.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            updatedDate: updated.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            plannedStartDate: plannedStart.flatMap { BrainPlannedDateTimeCodec.date(fromStorageString: $0) },
            plannedEndDate: plannedEnd.flatMap { BrainPlannedDateTimeCodec.date(fromStorageString: $0) },
            hasInvalidPlannedInterval: invalidPlannedInterval,
            goalSlug: nil,
            relatedProjects: [],
            tags: []
        )
    }
}
