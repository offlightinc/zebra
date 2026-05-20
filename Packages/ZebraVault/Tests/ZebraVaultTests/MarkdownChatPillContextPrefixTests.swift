import XCTest
@testable import ZebraVault

/// ChatPill 컨텍스트 prefix v1 회귀 테스트.
///
/// 정책 (`~/.claude/plans/graceful-forging-biscuit.md` + 후속 정정):
///   - surface enum: task / goal / fallback. (email/inbox/signal 류는 b-brain 측
///     문서 모델이 진행 중이라 v1 에서 의도적으로 제외 — markdown panel 에서 그런
///     frontmatter type 이 들어와도 fallback 으로 떨어진다. 라벨만 보존.)
///   - surface 결정은 **호출 사이트 책임**: markdown panel 은 `detect(fromContent:)`.
///     향후 다른 panel kind 가 ChatPill 마운트되면 그쪽 호출 사이트가 직접 enum 주입.
///   - 두 줄 prose. 줄1 surface advisory + 줄2 공통 b-brain advisory.
///   - `<path>` 는 모든 surface 에서, `<type>` 은 fallback 에서만 인터폴레이션.
///   - 톤 가드: 명령형/분기형/탐색 닫는 표현/리스트 마커/헤더 0건.
final class MarkdownChatPillContextPrefixTests: XCTestCase {
    // MARK: - Surface detection (markdown panel 전용)

    func testDetectsTask() {
        let content = """
        ---
        type: task
        status: todo
        ---

        # Foo
        """
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: content),
            .task
        )
    }

    func testDetectsGoal() {
        let content = """
        ---
        type: goal
        ---
        """
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: content),
            .goal
        )
    }

    /// inbox/signal/email 같은 frontmatter type 도 v1 에선 fallback 으로 떨어져야 한다.
    /// b-brain 측에서 email 문서 모델이 정해지면 별도 surface 추가 — 그 전까진 라벨만 보존.
    func testInboxSignalEmailFrontmatterFallsBackInV1() {
        for raw in ["inbox", "signal", "email"] {
            let content = "---\ntype: \(raw)\n---\n"
            XCTAssertEqual(
                MarkdownChatPillContextSurface.detect(fromContent: content),
                .fallback(typeLabel: raw),
                "v1 has no dedicated email surface; '\(raw)' must fall back with raw label preserved"
            )
        }
    }

    /// b-brain `PageType` 중 task/goal 이외는 전부 fallback 으로 빠져야 한다.
    /// 회귀 가드 — 누군가 "note 도 별도 surface 로" 같은 분기를 가볍게 추가하는 걸 막는다.
    func testNonTaskGoalPageTypesFallThroughToFallback() {
        let nonSpecial = [
            "note", "person", "company", "deal", "yc", "civic", "project",
            "concept", "source", "media", "writing", "analysis", "guide",
            "hardware", "architecture", "meeting",
        ]
        for raw in nonSpecial {
            let content = "---\ntype: \(raw)\n---\n"
            XCTAssertEqual(
                MarkdownChatPillContextSurface.detect(fromContent: content),
                .fallback(typeLabel: raw),
                "surface for type=\(raw) should fall through to fallback"
            )
        }
    }

    func testDetectsFallbackForMissingFrontmatter() {
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: "no frontmatter here\n"),
            .fallback(typeLabel: "general")
        )
    }

    func testDetectsFallbackForMissingTypeKey() {
        let content = """
        ---
        title: just a title
        ---
        """
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: content),
            .fallback(typeLabel: "general")
        )
    }

    func testIgnoresQuotedTypeWrapping() {
        let content = """
        ---
        type: "task"
        ---
        """
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: content),
            .task
        )
    }

    /// 들여쓰기된 `type:` 라인은 nested 필드라 top-level 로 잡으면 안 된다.
    /// `metadata.type` 같은 sub-key 가 우연히 `type` 이름이라고 surface 를 결정해버리면
    /// 모델링이 망가짐. extractFrontmatterType 의 indent 0 검사 회귀 가드.
    func testIgnoresIndentedTypeKey() {
        let content = """
        ---
        metadata:
          type: task
        ---
        """
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: content),
            .fallback(typeLabel: "general")
        )
    }

    /// `type: task # legacy` 같은 inline comment 는 잘라내고 순수 값만 surface 로 매핑.
    /// 회귀 가드 — 누군가 comment-stripping 코드 빼면 `task # legacy` 가 통째로
    /// typeLabel 로 넘어가 `.fallback("task # legacy")` 되는 버그 발생.
    func testStripsInlineCommentAfterType() {
        let content = """
        ---
        type: task # legacy field
        ---
        """
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: content),
            .task
        )
    }

    /// 첫 줄 `---` 인데 닫는 `---` 가 없는 잘못된 frontmatter. 코드는 끝까지 훑어보고
    /// type 없으면 nil 반환 → fallback. 회귀 가드.
    func testUnclosedFrontmatterFallsBackWhenTypeMissing() {
        let content = "---\ntitle: foo\n"
        XCTAssertEqual(
            MarkdownChatPillContextSurface.detect(fromContent: content),
            .fallback(typeLabel: "general")
        )
    }

    // MARK: - Build output (3 surface)

    func testTaskPrefixContainsPathAndTwoAxisStatusHint() {
        let out = MarkdownChatPillContextPrefix.build(
            markdownFilePath: "/Users/foo/brain/tasks/x.md",
            surface: .task
        )
        XCTAssertTrue(out.contains("/Users/foo/brain/tasks/x.md"))
        XCTAssertTrue(out.contains("task document"))
        // C 안: status 의 두 축 — lifecycle phase + dependency 신호 (blocked/waiting)
        XCTAssertTrue(out.contains("lifecycle phase"))
        XCTAssertTrue(out.contains("`blocked`"))
        XCTAssertTrue(out.contains("`waiting`"))
        XCTAssertEqual(out.components(separatedBy: "\n").count, 2)
    }

    func testGoalPrefixContainsPathAndTwoLayerHint() {
        let out = MarkdownChatPillContextPrefix.build(
            markdownFilePath: "/Users/foo/brain/goals/y.md",
            surface: .goal
        )
        XCTAssertTrue(out.contains("/Users/foo/brain/goals/y.md"))
        XCTAssertTrue(out.contains("goal document"))
        // D 안: time-bound outcome + measures + 2-layer (goal direction / linked tasks execution)
        XCTAssertTrue(out.contains("time-bound outcome"))
        XCTAssertTrue(out.contains("metrics or milestones"))
        XCTAssertTrue(out.contains("subgoals and linked tasks"))
    }

    func testFallbackPrefixInterpolatesTypeLabel() {
        let out = MarkdownChatPillContextPrefix.build(
            markdownFilePath: "/Users/foo/brain/people/p.md",
            surface: .fallback(typeLabel: "person")
        )
        XCTAssertTrue(out.contains("`person` b-brain document"))
        XCTAssertTrue(out.contains("/Users/foo/brain/people/p.md"))
    }

    func testAllSurfacesShareCommonGbrainAdvisory() {
        let path = "/tmp/x.md"
        let surfaces: [MarkdownChatPillContextSurface] = [
            .task, .goal, .fallback(typeLabel: "person")
        ]
        let commonHint = "b-brain's `search` / `query` / `get`"
        for surface in surfaces {
            let out = MarkdownChatPillContextPrefix.build(
                markdownFilePath: path,
                surface: surface
            )
            XCTAssertTrue(
                out.contains(commonHint),
                "surface \(surface) prefix missing common b-brain advisory line"
            )
            XCTAssertTrue(
                out.contains("[Source: …, YYYY-MM-DD]"),
                "surface \(surface) prefix missing citation advisory"
            )
        }
    }

    // MARK: - Tone guards (회귀 grep)

    /// prose 톤 가드. imperatives / conditionals / closing constructs / list markers /
    /// headers 가 0건이어야 한다. plan §5 의 영어 grep 규칙을 코드로 옮긴 것.
    /// case-insensitive 매칭.
    func testToneGuardsAcrossAllSurfaces() {
        let path = "/Users/foo/brain/tasks/x.md"
        let outputs: [String] = [
            MarkdownChatPillContextPrefix.build(markdownFilePath: path, surface: .task),
            MarkdownChatPillContextPrefix.build(markdownFilePath: path, surface: .goal),
            MarkdownChatPillContextPrefix.build(
                markdownFilePath: path,
                surface: .fallback(typeLabel: "person")
            ),
        ]

        // Imperatives — 동사형 명령. 단어 경계로 가두어 false positive 줄임 (e.g.
        // "must" 가 "automatic" 안에 잡히면 안 됨).
        let imperativeWords = ["must", "should", "do not", "don't", "always", "never", "immediately"]
        // Conditionals — 사용자/상황 가정.
        let conditionalPhrases = ["if you", "when you", "in case", "unless", "should you"]
        // Closing constructs — 탐색 좁히는 표현.
        let closingPhrases = ["only when", "only if", "except when", "except if"]
        // List markers / headers — prose 만 허용.
        let structurePatterns = ["\n- ", "\n* ", "\n1.", "\n#", "\n["]

        let wordPatterns = imperativeWords + conditionalPhrases + closingPhrases

        for output in outputs {
            let lower = output.lowercased()
            for pattern in wordPatterns {
                XCTAssertFalse(
                    lower.contains(pattern),
                    "tone guard violated: '\(pattern)' found in:\n\(output)"
                )
            }
            for pattern in structurePatterns {
                XCTAssertFalse(
                    output.contains(pattern),
                    "tone guard violated: structural marker '\(pattern.debugDescription)' found in:\n\(output)"
                )
            }
        }
    }

    /// prefix 본문에 본문 데이터 inline 금지 — frontmatter / timeline / checklist
    /// 토큰이 새어 들어오지 않았는지 가벼운 회귀 가드.
    func testNoBodyDataInlined() {
        let bait = """
        ---
        type: task
        status: inprogress
        owner: somebody
        ---

        ## Timeline
        - 2026-05-19 SHOULD_NOT_LEAK
        """
        let out = MarkdownChatPillContextPrefix.build(
            markdownFilePath: "/tmp/x.md",
            surface: MarkdownChatPillContextSurface.detect(fromContent: bait)
        )
        XCTAssertFalse(out.contains("SHOULD_NOT_LEAK"))
        XCTAssertFalse(out.contains("somebody"))
        XCTAssertFalse(out.contains("inprogress"))
    }
}
