import XCTest
@testable import ZebraVault

final class TaskFrontmatterParserTests: XCTestCase {
    func testParsesCreatedAndUpdatedDatesFromFrontmatter() throws {
        let url = try makeTaskFile("""
        ---
        type: task
        title: "Sort me"
        status: todo
        priority: high
        created: 2026-05-27
        updated: 2026-05-28
        ---

        # Sort me
        """)

        let item = try XCTUnwrap(TaskFrontmatterParser.parse(filePath: url.path))

        XCTAssertEqual(item.createdDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) }, "2026-05-27")
        XCTAssertEqual(item.updatedDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) }, "2026-05-28")
    }

    func testMissingCreatedAndUpdatedDatesParseAsNil() throws {
        let url = try makeTaskFile("""
        ---
        type: task
        title: "No dates"
        status: todo
        ---

        # No dates
        """)

        let item = try XCTUnwrap(TaskFrontmatterParser.parse(filePath: url.path))

        XCTAssertNil(item.createdDate)
        XCTAssertNil(item.updatedDate)
    }

    func testParsesValidPlannedIntervalWithExplicitTimeZone() throws {
        let url = try makeTaskFile("""
        ---
        type: task
        title: "Planned task"
        status: todo
        planned_start_at: 2026-07-10T09:30:00+09:00
        planned_end_at: 2026-07-10T10:15:00+09:00
        ---
        """)

        let item = try XCTUnwrap(TaskFrontmatterParser.parse(filePath: url.path))

        XCTAssertNotNil(item.plannedInterval)
        XCTAssertFalse(item.hasInvalidPlannedInterval)
        XCTAssertEqual(try XCTUnwrap(item.plannedInterval).duration, 45 * 60, accuracy: 0.001)
    }

    func testMarksPartialOrTimezoneLessPlannedIntervalAsInvalid() throws {
        let partialURL = try makeTaskFile("""
        ---
        type: task
        title: "Partial"
        planned_start_at: 2026-07-10T09:30:00+09:00
        ---
        """)
        let timezoneLessURL = try makeTaskFile("""
        ---
        type: task
        title: "No timezone"
        planned_start_at: 2026-07-10T09:30:00
        planned_end_at: 2026-07-10T10:30:00
        ---
        """)

        let partial = try XCTUnwrap(TaskFrontmatterParser.parse(filePath: partialURL.path))
        let timezoneLess = try XCTUnwrap(TaskFrontmatterParser.parse(filePath: timezoneLessURL.path))

        XCTAssertTrue(partial.hasInvalidPlannedInterval)
        XCTAssertNil(partial.plannedInterval)
        XCTAssertTrue(timezoneLess.hasInvalidPlannedInterval)
        XCTAssertNil(timezoneLess.plannedInterval)
    }

    private func makeTaskFile(_ source: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskFrontmatterParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("task.md")
        try source.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }
}
