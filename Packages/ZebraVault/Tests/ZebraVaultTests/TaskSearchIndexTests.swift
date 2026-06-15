import XCTest
@testable import ZebraVault

final class TaskSearchIndexTests: XCTestCase {
    func testSearchMatchesFilenameTitleAndMultiTokenPrefix() async throws {
        let index = try await makeIndex()
        try await index.upsert([
            record(path: "/tmp/tasks/critical-rollout.md", title: "Unrelated"),
            record(path: "/tmp/tasks/alpha.md", title: "Quarterly Launch Review"),
        ])

        let filenameMatches = try await index.search("critic")
        XCTAssertEqual(filenameMatches.map(\.absolutePath), ["/tmp/tasks/critical-rollout.md"])

        let titleMatches = try await index.search("quarter")
        XCTAssertEqual(titleMatches.map(\.absolutePath), ["/tmp/tasks/alpha.md"])

        let multiTokenMatches = try await index.search("quart rev")
        XCTAssertEqual(multiTokenMatches.map(\.absolutePath), ["/tmp/tasks/alpha.md"])
    }

    func testScannerExcludesNonTaskMarkdown() async throws {
        let root = try makeTempDirectory().appendingPathComponent("tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeMarkdown(
            root.appendingPathComponent("task.md"),
            title: "Indexed Searchable",
            type: "task"
        )
        try writeMarkdown(
            root.appendingPathComponent("note.md"),
            title: "Hidden Non Task",
            type: "note"
        )
        try "No frontmatter searchable text\n".write(
            to: root.appendingPathComponent("plain.md"),
            atomically: true,
            encoding: .utf8
        )

        let records = TaskSearchScanner.scan(root: root.path)
        let taskPath = normalizedPath(root.appendingPathComponent("task.md").path)
        XCTAssertEqual(records.map { normalizedPath($0.absolutePath) }, [taskPath])

        let index = try await makeIndex()
        try await index.replaceAll(records)

        let taskMatches = try await index.search("indexed")
        XCTAssertEqual(taskMatches.map { normalizedPath($0.absolutePath) }, [taskPath])

        let nonTaskMatches = try await index.search("hidden")
        XCTAssertTrue(nonTaskMatches.isEmpty)
    }

    func testDeleteRemovesSearchResult() async throws {
        let index = try await makeIndex()
        let path = "/tmp/tasks/delete-me.md"
        try await index.upsert(record(path: path, title: "Delete Target"))

        let beforeDelete = try await index.search("delete")
        XCTAssertEqual(beforeDelete.map(\.absolutePath), [path])

        try await index.delete(path: path)

        let afterDelete = try await index.search("delete")
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testUpsertUpdatesChangedTitle() async throws {
        let index = try await makeIndex()
        let path = "/tmp/tasks/retitle.md"
        try await index.upsert(record(path: path, title: "Old Title"))

        let oldMatches = try await index.search("old")
        XCTAssertEqual(oldMatches.map(\.absolutePath), [path])

        try await index.upsert(record(path: path, title: "New Searchable Title"))

        let staleMatches = try await index.search("old")
        XCTAssertTrue(staleMatches.isEmpty)
        let newMatches = try await index.search("new searchable")
        XCTAssertEqual(newMatches.map(\.absolutePath), [path])
    }

    func testSearchResultsPreserveMetadataForListControls() async throws {
        let index = try await makeIndex()
        try await index.upsert(
            record(
                path: "/tmp/tasks/metadata.md",
                title: "Metadata Needle",
                status: .blocked,
                priority: .high,
                owner: "han",
                due: "2026-06-19",
                created: "2026-06-01",
                updated: "2026-06-02",
                goal: "ship-search",
                projects: ["zebra"],
                tags: ["search"]
            )
        )

        let results = try await index.search("metadata needle")
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.priority, .high)
        XCTAssertEqual(result.ownerSlug, "han")
        XCTAssertEqual(result.dueDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) }, "2026-06-19")
        XCTAssertEqual(result.createdDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) }, "2026-06-01")
        XCTAssertEqual(result.updatedDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) }, "2026-06-02")
        XCTAssertEqual(result.goalSlug, "ship-search")
        XCTAssertEqual(result.relatedProjects, ["zebra"])
        XCTAssertEqual(result.tags, ["search"])
    }

    func testSearchIndexFindsTaskPastLoweredListScanCapHarness() async throws {
        let root = try makeTempDirectory().appendingPathComponent("tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let loweredListScanCap = 10
        let fixtureCount = 25
        let needleTitle = "Zulu Needle Beyond Cap"
        for i in 1...fixtureCount {
            let title = i == fixtureCount ? needleTitle : String(format: "Alpha Task %03d", i)
            try writeMarkdown(
                root.appendingPathComponent(String(format: "task-%03d.md", i)),
                title: title,
                type: "task"
            )
        }

        let records = TaskSearchScanner.scan(root: root.path)
        XCTAssertEqual(records.count, fixtureCount)

        let cappedListSnapshot = Array(records.prefix(loweredListScanCap))
        XCTAssertEqual(cappedListSnapshot.count, loweredListScanCap)
        XCTAssertFalse(cappedListSnapshot.contains { $0.task.title == needleTitle })

        let index = try await makeIndex()
        try await index.replaceAll(records)

        let matches = try await index.search("needle beyond")
        XCTAssertEqual(matches.map(\.title), [needleTitle])
    }

    func testSyntheticRecordSearchPerformanceEvidence() async throws {
        guard ProcessInfo.processInfo.environment["ZEBRA_TASK_SEARCH_PERF"] == "1" else {
            throw XCTSkip("Set ZEBRA_TASK_SEARCH_PERF=1 to run synthetic task search performance evidence.")
        }

        let (index, databaseURL) = try await makeIndexWithURL()
        let records = (0..<10_000).map { i in
            record(
                path: String(format: "/tmp/tasks/perf-alpha-%05d.md", i),
                title: "Perf Alpha \(i) Owner \(i % 10) Batch \(i % 100)"
            )
        }
        let bulkStarted = Date()
        try await index.upsert(records)
        let bulkElapsed = Date().timeIntervalSince(bulkStarted)
        let databaseFootprintBytes = sqliteFootprintBytes(for: databaseURL)

        let queries = ["perf", "alpha", "batch 42", "owner 7", "perf 9999"]
        var timings: [(query: String, elapsed: TimeInterval, count: Int)] = []
        for query in queries {
            let started = Date()
            let results = try await index.search(query, limit: 200)
            let elapsed = Date().timeIntervalSince(started)
            timings.append((query, elapsed, results.count))
        }

        let evidence = timings
            .map { "\($0.query)=\(String(format: "%.4f", $0.elapsed))s/\($0.count)" }
            .joined(separator: ", ")
        print(
            "TaskSearchIndex performance evidence: records=10000 " +
            "bulk=\(String(format: "%.4f", bulkElapsed))s " +
            "sqliteFootprintBytes=\(databaseFootprintBytes) queries=\(evidence)"
        )

        let worst = timings.map(\.elapsed).max() ?? 0
        XCTAssertLessThan(worst, 1.0)
        XCTAssertLessThan(bulkElapsed, 30.0)
        XCTAssertLessThan(databaseFootprintBytes, 50 * 1024 * 1024)
    }

    private func makeIndex() async throws -> TaskSearchIndex {
        (try await makeIndexWithURL()).index
    }

    private func makeIndexWithURL() async throws -> (index: TaskSearchIndex, url: URL) {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("task-search.sqlite")
        return (try TaskSearchIndex(databaseURL: url), url)
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskSearchIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func writeMarkdown(_ url: URL, title: String, type: String) throws {
        let source = """
        ---
        type: \(type)
        title: "\(title)"
        status: todo
        priority: medium
        ---

        # \(title)
        """
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    private func record(
        path: String,
        title: String,
        status: BrainTaskStatus? = .todo,
        priority: BrainPriority? = .medium,
        owner: String? = "owner",
        due: String? = nil,
        created: String? = nil,
        updated: String? = nil,
        goal: String? = nil,
        projects: [String] = [],
        tags: [String] = []
    ) -> TaskSearchRecord {
        let task = TaskItem(
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
            goalSlug: goal,
            relatedProjects: projects,
            tags: tags
        )
        return TaskSearchRecord(
            task: task,
            fileModifiedAt: Date(timeIntervalSince1970: 1),
            fileSize: 128
        )
    }

    private func normalizedPath(_ path: String) -> String {
        if path.hasPrefix("/private/var/") {
            return "/var/" + path.dropFirst("/private/var/".count)
        }
        return path
    }

    private func sqliteFootprintBytes(for databaseURL: URL) -> Int {
        let paths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm"
        ]
        return paths.reduce(0) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
                .intValue ?? 0
            return total + size
        }
    }
}
