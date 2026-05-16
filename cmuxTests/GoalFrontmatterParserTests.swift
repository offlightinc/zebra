import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Goal status parser 정책 회귀 방지 — `GoalFrontmatterParser` 가 frontmatter
/// 의 `status:` 값을 어떻게 다루는지 3 케이스로 검증.
///
/// 정책 (commit 2c41f73e7):
///   - valid raw → `entry.status = .<case>`, `unrecognizedStatusRaw = nil`
///   - 키 누락 → `entry.status = nil`, `unrecognizedStatusRaw = nil`
///   - schema 위반 raw (오타 등) → `entry.status = nil`, `unrecognizedStatusRaw = raw`
///
/// 위반값을 silently `.draft` 로 흡수하지 않는 게 핵심 — 사용자가 사이드바 /
/// 인스펙터의 ? glyph 로 발견해 picker 로 정정 가능해야 한다.
@MainActor
final class GoalFrontmatterParserTests: XCTestCase {
    func testValidStatusParsed() throws {
        let path = makeTempGoal(frontmatter: """
            type: goal
            status: active
            """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let entry = try XCTUnwrap(GoalFrontmatterParser.parse(filePath: path))
        XCTAssertEqual(entry.status, .active)
        XCTAssertNil(entry.unrecognizedStatusRaw)
    }

    func testMissingStatusYieldsNil() throws {
        let path = makeTempGoal(frontmatter: """
            type: goal
            title: "no status here"
            """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let entry = try XCTUnwrap(GoalFrontmatterParser.parse(filePath: path))
        XCTAssertNil(entry.status)
        XCTAssertNil(entry.unrecognizedStatusRaw)
    }

    func testUnknownRawStatusPreserved() throws {
        let path = makeTempGoal(frontmatter: """
            type: goal
            status: actve
            """)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let entry = try XCTUnwrap(GoalFrontmatterParser.parse(filePath: path))
        XCTAssertNil(entry.status, "schema 위반 raw 는 BrainGoalStatus 로 매핑되면 안 됨")
        XCTAssertEqual(entry.unrecognizedStatusRaw, "actve", "원본 raw 가 보존되어 UI 가 ? glyph 로 노출할 수 있어야 함")
    }

    // MARK: - Fixtures

    private func makeTempGoal(frontmatter: String) -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("goal-\(UUID().uuidString).md")
        let body = "---\n\(frontmatter)\n---\n\n# Test\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
