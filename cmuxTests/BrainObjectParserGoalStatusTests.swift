import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Inspector parser (`BrainObjectParser`) 도 sidebar parser
/// (`GoalFrontmatterParser`) 와 같은 status 정책을 따르는지 검증.
///
/// 정책 (commit 2c41f73e7 + 본 commit):
///   - valid raw → `goal.status = .<case>`, `unrecognizedStatusRaw = nil`
///   - 키 누락 → `goal.status = nil`, `unrecognizedStatusRaw = nil`
///   - schema 위반 raw (오타 등) → `goal.status = nil`, `unrecognizedStatusRaw = raw`
///
/// 두 parser 가 같은 정책이라야 sidebar 의 UNKNOWN bucket "?" glyph 와
/// inspector pill 의 "?raw" 가 동일 데이터에 대해 시각 일관 보장.
@MainActor
final class BrainObjectParserGoalStatusTests: XCTestCase {
    func testGoalValidStatusParsed() throws {
        let parse = BrainObjectParser.parse(
            """
            ---
            type: goal
            status: active
            ---

            # Test
            """,
            filename: "g.md"
        )
        let goal = try unwrapGoal(parse)
        XCTAssertEqual(goal.status, .active)
        XCTAssertNil(goal.unrecognizedStatusRaw)
    }

    func testGoalMissingStatusYieldsNil() throws {
        let parse = BrainObjectParser.parse(
            """
            ---
            type: goal
            title: "no status"
            ---

            # Test
            """,
            filename: "g.md"
        )
        let goal = try unwrapGoal(parse)
        XCTAssertNil(goal.status)
        XCTAssertNil(goal.unrecognizedStatusRaw)
    }

    func testGoalUnknownRawStatusPreserved() throws {
        let parse = BrainObjectParser.parse(
            """
            ---
            type: goal
            status: actve
            ---

            # Test
            """,
            filename: "g.md"
        )
        let goal = try unwrapGoal(parse)
        XCTAssertNil(goal.status, "schema 위반 raw 는 BrainGoalStatus 로 매핑되면 안 됨")
        XCTAssertEqual(goal.unrecognizedStatusRaw, "actve", "원본 raw 가 보존되어 inspector pill 이 \"?\" glyph 로 노출할 수 있어야 함")
    }

    // MARK: - Fixtures

    private func unwrapGoal(_ parse: BrainObjectParse) throws -> GoalObject {
        let object: BrainObject
        switch parse.result {
        case .success(let value): object = value
        case .failure(let err):
            XCTFail("parse failed: \(err)")
            throw err
        }
        guard case .goal(let goal) = object else {
            XCTFail("expected .goal, got \(object)")
            throw BrainObjectParseError(line: 0, column: 0, message: "not a goal")
        }
        return goal
    }
}
