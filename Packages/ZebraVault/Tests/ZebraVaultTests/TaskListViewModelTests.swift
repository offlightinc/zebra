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
    func testSearchResultSnapshotsUseSameFilterSortAndGroupPipeline() {
        let viewModel = TaskListViewModel()
        viewModel.filters = [
            TaskFilter(field: .owner, op: .is, values: ["han"]),
            TaskFilter(field: .priority, op: .is, values: [BrainPriority.high.rawValue])
        ]
        viewModel.sort = .due
        viewModel.sortDirection = .ascending

        let searchResults = [
            task(
                path: "/tmp/search/other-owner.md",
                title: "Needle Other Owner",
                priority: .high,
                owner: "lee",
                due: "2026-06-17"
            ),
            task(
                path: "/tmp/search/later.md",
                title: "Needle Later",
                priority: .high,
                owner: "han",
                due: "2026-06-20"
            ),
            task(
                path: "/tmp/search/soon.md",
                title: "Needle Soon",
                priority: .high,
                owner: "han",
                due: "2026-06-18"
            ),
            task(
                path: "/tmp/search/low.md",
                title: "Needle Low",
                priority: .low,
                owner: "han",
                due: "2026-06-16"
            ),
        ]

        let displayed = viewModel.displayTasks(from: searchResults)
        let groups = TaskListViewModel.groupTasks(displayed, by: .priority)

        XCTAssertEqual(displayed.map(\.absolutePath), ["/tmp/search/soon.md", "/tmp/search/later.md"])
        XCTAssertEqual(groups.map(\.key.raw), [BrainPriority.high.rawValue])
        XCTAssertEqual(groups.first?.items.map(\.absolutePath), ["/tmp/search/soon.md", "/tmp/search/later.md"])
    }

    private func task(
        path: String,
        title: String,
        status: BrainTaskStatus? = .todo,
        priority: BrainPriority? = nil,
        owner: String? = nil,
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
            ownerSlug: owner,
            dueDate: due.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            createdDate: created.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            updatedDate: updated.flatMap { BrainDateOnlyCodec.date(fromStorageString: $0) },
            goalSlug: nil,
            relatedProjects: [],
            tags: []
        )
    }
}
