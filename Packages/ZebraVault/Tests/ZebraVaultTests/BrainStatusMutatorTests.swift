import XCTest
@testable import ZebraVault

/// `BrainStatusMutator` 의 다중-필드 + Timeline writeback 회귀 방지.
///
/// 정책 (계획서 cryptic-sparking-lobster):
///   - status 변경 시 status / updated 항상 갱신
///   - task `done` (goal `completed`) 진입 시 `completed:` 부여, 이탈 시 제거
///   - task `waiting` 진입 시 `waiting_on:` 보장 (기존 값 보존), 이탈 시 제거
///   - body `## Timeline` 에 bullet append (섹션 없으면 생성)
///   - 동일 status 재적용 → no-op
///   - frontmatter block 부재 → no-op
///   - 다른 frontmatter 키의 순서/quoting/주석/body 보존
@MainActor
final class BrainStatusMutatorTests: XCTestCase {
    private static let day = makeDate("2026-05-21")

    // MARK: - Basic transitions

    func testTaskTodoToInprogressUpdatesStatusAndAppendsTimeline() {
        let source = """
        ---
        type: task
        status: todo
        updated: 2026-05-18
        ---

        # Some task

        Body text.

        ## Timeline

        - **2026-05-18** | Created.
        """
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "todo", newStatusRaw: "inprogress",
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("status: inprogress"))
        XCTAssertTrue(outcome.newSource.contains("updated: 2026-05-21"))
        XCTAssertFalse(outcome.newSource.contains("completed:"),
                       "non-done transition must not add completed:")
        XCTAssertFalse(outcome.newSource.contains("waiting_on:"),
                       "non-waiting transition must not add waiting_on:")
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | status: todo → inprogress — status changed in Zebra."
        ))
        // 기존 Timeline 보존.
        XCTAssertTrue(outcome.newSource.contains("- **2026-05-18** | Created."))
    }

    func testTaskInprogressToDoneAddsCompleted() {
        let source = wrap(frontmatter: """
            type: task
            status: inprogress
            updated: 2026-05-20
            """, body: """

            ## Timeline

            - **2026-05-20** | Created.
            """)
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "inprogress", newStatusRaw: "done",
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("status: done"))
        XCTAssertTrue(outcome.newSource.contains("completed: 2026-05-21"))
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | status: inprogress → done — status changed in Zebra."
        ))
    }

    func testTaskDoneToInprogressRemovesCompleted() {
        let source = wrap(frontmatter: """
            type: task
            status: done
            updated: 2026-05-20
            completed: 2026-05-20
            """, body: """

            ## Timeline

            - **2026-05-20** | status: inprogress → done.
            """)
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "done", newStatusRaw: "inprogress",
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("status: inprogress"))
        XCTAssertFalse(outcome.newSource.contains("completed:"),
                       "completed: must be removed when leaving done")
    }

    // MARK: - Status clear (newStatusRaw == nil)

    func testStatusClearRemovesKeyAndRecordsTimeline() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "todo", newStatusRaw: nil,
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        // status 키가 frontmatter 에서 빠져야 함.
        let frontmatter = frontmatterBlock(of: outcome.newSource)
        XCTAssertFalse(frontmatter.contains("status:"),
                       "비우기 시 status 키가 frontmatter 에서 제거되어야 함")
        // Timeline 에 비우기 사건이 기록.
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | status: todo → (none) — status changed in Zebra."
        ))
    }

    func testStatusClearFromDoneAlsoRemovesCompleted() {
        let source = wrap(frontmatter: """
            type: task
            status: done
            completed: 2026-05-18
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "done", newStatusRaw: nil,
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        let frontmatter = frontmatterBlock(of: outcome.newSource)
        XCTAssertFalse(frontmatter.contains("status:"))
        XCTAssertFalse(frontmatter.contains("completed:"),
                       "done 이탈이므로 completed: 도 같이 제거")
    }

    // MARK: - waiting 은 picker UI 비노출 → mutator 가 waiting_on 안 건드림

    func testTaskTransitionDoesNotTouchWaitingOnField() {
        // BrainTaskStatus.waiting 은 picker primaryCases 에서 빠져 있고,
        // mutator 는 waiting_on 자동 관리를 하지 않는다. 사용자가 미리
        // waiting_on 값을 적어 둔 task 도 status 만 바뀌고 waiting_on 은
        // 그대로.
        let source = wrap(frontmatter: """
            type: task
            status: todo
            waiting_on: "user note"
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "todo", newStatusRaw: "inprogress",
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("status: inprogress"))
        XCTAssertTrue(outcome.newSource.contains("waiting_on: \"user note\""),
                       "mutator 가 waiting_on 을 임의로 건드리지 않아야 함")
    }

    // MARK: - Goal kind

    func testGoalActiveToCompletedAddsCompleted() {
        let source = wrap(frontmatter: """
            type: goal
            status: active
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .goal,
            oldStatusRaw: "active", newStatusRaw: "completed",
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("status: completed"))
        XCTAssertTrue(outcome.newSource.contains("completed: 2026-05-21"))
    }

    func testGoalDoesNotTouchWaitingOn() {
        // Goal 은 waiting 상태가 없으므로 임의의 raw 가 들어와도 waiting_on
        // 자동 관리하지 않는다 (caller 가 잘못 호출했더라도 silent).
        let source = wrap(frontmatter: """
            type: goal
            status: active
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .goal,
            oldStatusRaw: "active", newStatusRaw: "waiting",
            today: Self.day
        )
        XCTAssertFalse(outcome.newSource.contains("waiting_on:"))
    }

    // MARK: - No-op cases

    func testSameStatusIsNoOp() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "todo", newStatusRaw: "todo",
            today: Self.day
        )
        XCTAssertFalse(outcome.didChange)
        XCTAssertEqual(outcome.newSource, source)
    }

    func testNoFrontmatterIsNoOp() {
        let source = "# Just a plain document\n\nNo frontmatter here.\n"
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: nil, newStatusRaw: "todo",
            today: Self.day
        )
        XCTAssertFalse(outcome.didChange)
        XCTAssertEqual(outcome.newSource, source)
    }

    // MARK: - Timeline body editing

    func testTimelineSectionCreatedWhenAbsent() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "todo", newStatusRaw: "inprogress",
            today: Self.day
        )
        XCTAssertTrue(outcome.newSource.contains("## Timeline"))
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | status: todo → inprogress — status changed in Zebra."
        ))
    }

    func testTimelineAppendBeforeTrailingBlankAndNextSection() {
        let source = """
        ---
        type: task
        status: todo
        ---

        ## Timeline

        - **2026-05-18** | First event.
        - **2026-05-19** | Second event.

        ## See also

        - foo
        """
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "todo", newStatusRaw: "inprogress",
            today: Self.day
        )
        // 새 bullet 은 마지막 기존 bullet 다음, 다음 섹션의 빈줄/헤더 전에.
        guard let newIdx = outcome.newSource.range(of: "status changed in Zebra."),
              let secondIdx = outcome.newSource.range(of: "Second event."),
              let seeAlsoIdx = outcome.newSource.range(of: "## See also") else {
            XCTFail("expected substrings not found")
            return
        }
        XCTAssertLessThan(secondIdx.lowerBound, newIdx.lowerBound)
        XCTAssertLessThan(newIdx.lowerBound, seeAlsoIdx.lowerBound)
    }

    func testOldStatusNilDisplaysAsNone() {
        let source = wrap(frontmatter: """
            type: task
            """, body: "")
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: nil, newStatusRaw: "todo",
            today: Self.day
        )
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | status: (none) → todo — status changed in Zebra."
        ))
    }

    // MARK: - Preservation

    func testPreservesOtherFrontmatterFieldsAndQuoting() {
        let source = """
        ---
        title: "My task with: colons"
        type: task
        status: todo
        tags: [zebra, inspector]
        # a comment
        owner: people/han
        ---

        Body.
        """
        let outcome = BrainStatusMutator.applyStatusChange(
            in: source, kind: .task,
            oldStatusRaw: "todo", newStatusRaw: "inprogress",
            today: Self.day
        )
        XCTAssertTrue(outcome.newSource.contains("title: \"My task with: colons\""))
        XCTAssertTrue(outcome.newSource.contains("tags: [zebra, inspector]"))
        XCTAssertTrue(outcome.newSource.contains("# a comment"))
        XCTAssertTrue(outcome.newSource.contains("owner: people/han"))
        XCTAssertTrue(outcome.newSource.contains("\nBody.\n"),
                      "body 텍스트가 그대로 보존되어야 함")
    }

    // MARK: - applyPropertyChange

    func testPropertyChangePriorityBumpsUpdatedAndTimeline() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            priority: low
            updated: 2026-05-18
            """, body: "")
        let outcome = BrainStatusMutator.applyPropertyChange(
            in: source,
            field: "priority",
            oldValue: "low",
            newValue: "high",
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("priority: high"))
        XCTAssertTrue(outcome.newSource.contains("updated: 2026-05-21"))
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | priority: low → high — priority changed in Zebra."
        ))
        // status 는 건드리지 않음.
        XCTAssertTrue(outcome.newSource.contains("status: todo"))
    }

    func testPropertyChangeDueFromNilToValueShowsNoneArrow() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            """, body: "")
        let outcome = BrainStatusMutator.applyPropertyChange(
            in: source,
            field: "due",
            oldValue: nil,
            newValue: "2026-05-25",
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("due: 2026-05-25"))
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | due: (none) → 2026-05-25 — due changed in Zebra."
        ))
    }

    func testPropertyChangeDueFromValueToNilRemovesKey() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            due: 2026-05-25
            """, body: "")
        let outcome = BrainStatusMutator.applyPropertyChange(
            in: source,
            field: "due",
            oldValue: "2026-05-25",
            newValue: nil,
            today: Self.day
        )
        XCTAssertTrue(outcome.didChange)
        // 키 제거 검증: frontmatter 블록만 잘라내서 due: 라인이 사라졌는지.
        // Timeline bullet 본문에는 'due: 2026-05-25 → (none)' 가 들어가므로
        // 전체 contains 로는 구분 불가.
        let frontmatter = frontmatterBlock(of: outcome.newSource)
        XCTAssertFalse(frontmatter.contains("due:"),
                       "frontmatter 의 due: 라인이 제거되어야 함. got:\n\(frontmatter)")
        XCTAssertTrue(outcome.newSource.contains(
            "- **2026-05-21** | due: 2026-05-25 → (none) — due changed in Zebra."
        ))
    }

    func testPropertyChangeSameValueIsNoOp() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            owner: people/han
            """, body: "")
        let outcome = BrainStatusMutator.applyPropertyChange(
            in: source,
            field: "owner",
            oldValue: "people/han",
            newValue: "people/han",
            today: Self.day
        )
        XCTAssertFalse(outcome.didChange)
        XCTAssertEqual(outcome.newSource, source)
    }

    func testPropertyChangeRefusesStatusField() {
        // status 는 별도 의미론(`completed:` 처리)이 있으니까 applyStatusChange
        // 사용. 잘못 라우팅된 호출은 silent no-op.
        let source = wrap(frontmatter: """
            type: task
            status: todo
            """, body: "")
        let outcome = BrainStatusMutator.applyPropertyChange(
            in: source,
            field: "status",
            oldValue: "todo",
            newValue: "done",
            today: Self.day
        )
        XCTAssertFalse(outcome.didChange)
        XCTAssertEqual(outcome.newSource, source)
    }

    // MARK: - File-IO variant

    /// `applyStatusChange(at:)` 의 read → mutate → atomic write 라운드트립 검증.
    /// in-memory variant 가 잘 동작해도 wrapper 의 IO 단계에서 회귀가 생길 수
    /// 있으므로 (예: encoding 손실, 권한 처리) 최소 한 케이스는 디스크 경유.
    func testApplyStatusChangeAtFilePathRoundTrip() throws {
        let tmpDir = NSTemporaryDirectory()
        let path = (tmpDir as NSString).appendingPathComponent("brain-status-mutator-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let initial = wrap(frontmatter: """
            type: task
            status: todo
            updated: 2026-05-18
            """, body: """

            # Sample task

            Some body.
            """)
        try initial.write(toFile: path, atomically: true, encoding: .utf8)

        BrainStatusMutator.applyStatusChange(
            at: path,
            kind: .task,
            oldStatusRaw: "todo",
            newStatusRaw: "done",
            today: Self.day
        )

        let reread = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(reread.contains("status: done"))
        XCTAssertTrue(reread.contains("updated: 2026-05-21"))
        XCTAssertTrue(reread.contains("completed: 2026-05-21"))
        XCTAssertTrue(reread.contains(
            "- **2026-05-21** | status: todo → done — status changed in Zebra."
        ))
        XCTAssertTrue(reread.contains("Some body."), "body 텍스트 라운드트립 보존")

        // 동일 status 재호출 → didChange == false → 디스크 mtime 변하지 않아야 함.
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        BrainStatusMutator.applyStatusChange(
            at: path,
            kind: .task,
            oldStatusRaw: "done",
            newStatusRaw: "done",
            today: Self.day
        )
        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        XCTAssertEqual(mtimeBefore, mtimeAfter, "no-op 호출이 파일을 다시 쓰면 안 됨")
    }

    /// `applyPropertyChange(at:)` 의 file-IO 라운드트립. applyStatusChange
    /// 의 동일 형태 테스트와 symmetry 확보.
    func testApplyPropertyChangeAtFilePathRoundTrip() throws {
        let tmpDir = NSTemporaryDirectory()
        let path = (tmpDir as NSString).appendingPathComponent("brain-property-mutator-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let initial = wrap(frontmatter: """
            type: task
            status: todo
            priority: low
            updated: 2026-05-18
            """, body: "")
        try initial.write(toFile: path, atomically: true, encoding: .utf8)

        BrainStatusMutator.applyPropertyChange(
            at: path,
            field: "priority",
            oldValue: "low",
            newValue: "high",
            today: Self.day
        )

        let reread = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(reread.contains("priority: high"))
        XCTAssertTrue(reread.contains("updated: 2026-05-21"))
        XCTAssertTrue(reread.contains(
            "- **2026-05-21** | priority: low → high — priority changed in Zebra."
        ))

        // 동일 값 재호출 → didChange == false → mtime 변하지 않아야.
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        BrainStatusMutator.applyPropertyChange(
            at: path,
            field: "priority",
            oldValue: "high",
            newValue: "high",
            today: Self.day
        )
        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        XCTAssertEqual(mtimeBefore, mtimeAfter, "no-op 호출이 파일을 다시 쓰면 안 됨")
    }

    func testApplyPlannedIntervalChangeWritesBothBoundariesAndOneTimelineEntry() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            updated: 2026-05-18
            """, body: "")

        let outcome = BrainStatusMutator.applyPlannedIntervalChange(
            in: source,
            newStartRaw: "2026-07-10T14:00:00+09:00",
            newEndRaw: "2026-07-10T15:00:00+09:00",
            today: Self.day
        )

        XCTAssertTrue(outcome.didChange)
        let frontmatter = frontmatterBlock(of: outcome.newSource)
        XCTAssertTrue(frontmatter.contains("planned_start_at: 2026-07-10T14:00:00+09:00"))
        XCTAssertTrue(frontmatter.contains("planned_end_at: 2026-07-10T15:00:00+09:00"))
        XCTAssertTrue(frontmatter.contains("updated: 2026-05-21"))
        XCTAssertEqual(outcome.newSource.components(separatedBy: "| planned_time:").count - 1, 1)
    }

    func testApplyPlannedIntervalChangeRejectsPartialOrReversedPair() {
        let source = wrap(frontmatter: """
            type: task
            status: todo
            """, body: "")

        let partial = BrainStatusMutator.applyPlannedIntervalChange(
            in: source,
            newStartRaw: "2026-07-10T14:00:00+09:00",
            newEndRaw: nil
        )
        let reversed = BrainStatusMutator.applyPlannedIntervalChange(
            in: source,
            newStartRaw: "2026-07-10T15:00:00+09:00",
            newEndRaw: "2026-07-10T14:00:00+09:00"
        )

        XCTAssertFalse(partial.didChange)
        XCTAssertFalse(reversed.didChange)
        XCTAssertEqual(partial.newSource, source)
        XCTAssertEqual(reversed.newSource, source)
    }

    func testApplyPlannedIntervalChangeClearsBothBoundariesTogether() {
        let source = wrap(frontmatter: """
            type: task
            planned_start_at: 2026-07-10T14:00:00+09:00
            planned_end_at: 2026-07-10T15:00:00+09:00
            """, body: "")

        let outcome = BrainStatusMutator.applyPlannedIntervalChange(
            in: source,
            newStartRaw: nil,
            newEndRaw: nil,
            today: Self.day
        )

        let frontmatter = frontmatterBlock(of: outcome.newSource)
        XCTAssertTrue(outcome.didChange)
        XCTAssertFalse(frontmatter.contains("planned_start_at"))
        XCTAssertFalse(frontmatter.contains("planned_end_at"))
    }

    // MARK: - Helpers

    private func wrap(frontmatter: String, body: String) -> String {
        return "---\n\(frontmatter)\n---\n\(body)"
    }

    /// `source` 에서 첫 `---` 와 두 번째 `---` 사이의 frontmatter 본문만 추출.
    /// 본문/Timeline 에 들어간 키 이름이 frontmatter 라인 검증을 가리지 않게.
    private func frontmatterBlock(of source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return ""
        }
        var collected: [String] = []
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" { break }
            collected.append(lines[i])
        }
        return collected.joined(separator: "\n")
    }

    private static func makeDate(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }
}
