import Combine
import XCTest
@testable import ZebraVault

@MainActor
final class TaskSearchStoreTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testWatcherReconcilesAddedUpdatedAndDeletedTaskFiles() async throws {
        let root = try makeTempDirectory()
        let tasksRoot = root.appendingPathComponent("tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: tasksRoot, withIntermediateDirectories: true)

        let initialURL = tasksRoot.appendingPathComponent("initial.md")
        try writeTask(initialURL, title: "Initial Needle")

        let databaseURL = root.appendingPathComponent("task-search.sqlite")
        let store = TaskSearchStore(
            databaseURLForTasksRoot: { _ in databaseURL },
            reconcileDebounce: 0.05,
            searchDebounce: 0.01
        )
        store.bind(tasksRootPath: tasksRoot.path)

        store.query = "initial needle"
        let initialFound = await waitUntil { store.results.map(\.title) == ["Initial Needle"] }
        XCTAssertTrue(initialFound, "initial indexed search results: \(store.results.map(\.title)) error: \(store.lastError ?? "nil")")

        let addedURL = tasksRoot.appendingPathComponent("added.md")
        try writeTask(addedURL, title: "Added Watcher Needle")
        store.query = "added watcher"
        let addedFound = await waitUntil { store.results.map(\.title) == ["Added Watcher Needle"] }
        XCTAssertTrue(addedFound, "added file search results: \(store.results.map(\.title)) error: \(store.lastError ?? "nil")")

        try writeTask(initialURL, title: "Renamed Watcher Needle")
        store.query = "renamed watcher"
        let updatedFound = await waitUntil { store.results.map(\.title) == ["Renamed Watcher Needle"] }
        XCTAssertTrue(updatedFound, "updated file search results: \(store.results.map(\.title)) error: \(store.lastError ?? "nil")")

        try FileManager.default.removeItem(at: addedURL)
        store.query = "added watcher"
        let deletedRemoved = await waitUntil { store.results.isEmpty }
        XCTAssertTrue(deletedRemoved, "deleted file search results: \(store.results.map(\.title)) error: \(store.lastError ?? "nil")")
    }

    func testReplacePublishesEditedSearchResultForRowActions() async throws {
        let root = try makeTempDirectory()
        let tasksRoot = root.appendingPathComponent("tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: tasksRoot, withIntermediateDirectories: true)

        try writeTask(tasksRoot.appendingPathComponent("editable.md"), title: "Editable Needle")

        let databaseURL = root.appendingPathComponent("task-search.sqlite")
        let store = TaskSearchStore(
            databaseURLForTasksRoot: { _ in databaseURL },
            reconcileDebounce: 0.05,
            searchDebounce: 0.01
        )
        store.bind(tasksRootPath: tasksRoot.path)

        store.query = "editable needle"
        let initialFound = await waitUntil { store.results.map(\.title) == ["Editable Needle"] }
        XCTAssertTrue(initialFound, "initial editable result: \(store.results.map(\.title)) error: \(store.lastError ?? "nil")")

        let didPublishEditedResult = expectation(description: "edited search result published")
        store.$results
            .dropFirst()
            .sink { results in
                guard let first = results.first,
                      first.status == .done,
                      first.priority == .urgent,
                      first.dueDate.map({ BrainDateOnlyCodec.storageString(fromPickerDate: $0) }) == "2026-06-20" else {
                    return
                }
                didPublishEditedResult.fulfill()
            }
            .store(in: &cancellables)

        let original = try XCTUnwrap(store.results.first)
        let edited = original.with(
            status: .some(.done),
            unrecognizedStatusRaw: .some(nil),
            priority: .some(.urgent),
            dueDate: .some(try XCTUnwrap(BrainDateOnlyCodec.date(fromStorageString: "2026-06-20")))
        )
        store.replace(edited)

        await fulfillment(of: [didPublishEditedResult], timeout: 1)
        XCTAssertEqual(store.results.first?.status, .done)
        XCTAssertEqual(store.results.first?.priority, .urgent)
        XCTAssertEqual(
            store.results.first?.dueDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) },
            "2026-06-20"
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskSearchStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func writeTask(_ url: URL, title: String) throws {
        let source = """
        ---
        type: task
        title: "\(title)"
        status: todo
        priority: medium
        ---

        # \(title)
        """
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}
