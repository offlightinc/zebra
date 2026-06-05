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
