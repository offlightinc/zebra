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

    private func task(
        path: String,
        title: String,
        status: BrainTaskStatus? = .todo,
        priority: BrainPriority? = nil,
        due: String? = nil,
        created: String? = nil,
        updated: String? = nil
    ) -> TaskItem {
        TaskItem(
            absolutePath: path,
            displayName: title,
            title: title,
            status: status,
            unrecognizedStatusRaw: nil,
            priority: priority,
            ownerSlug: nil,
            dueDate: due.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            createdDate: created.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            updatedDate: updated.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            goalSlug: nil,
            relatedProjects: [],
            tags: []
        )
    }
}
