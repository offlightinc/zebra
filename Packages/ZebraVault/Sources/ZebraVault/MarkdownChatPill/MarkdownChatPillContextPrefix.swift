import Foundation

/// G-Brain 문서 종류를 ChatPill prefix 분기에 필요한 3개 surface 로만 좁힌 enum.
///
/// v1 은 **task / goal / fallback** 만 다룬다.
///
/// inbox / signal / email 같은 surface 는 의도적으로 빼뒀다. email/메시지 그래프는
/// 현재 b-brain 측에서 어떤 문서/객체 shape 로 정착할지 진행 중이라 prefix advisory
/// 형태도 그 결정에 종속이다. v1 에서 미리 surface 케이스를 박아두면 모델링이 바뀔
/// 때 prose 와 enum 둘 다 회귀로 갈 위험이 있어서, 후속 작업으로 분리한다.
///
/// 그래서 markdown panel 에서 `type: inbox` / `type: signal` / `type: email` 같은
/// frontmatter 가 들어와도 모두 `.fallback(typeLabel: raw)` 로 떨어진다 — fallback
/// advisory 가 라벨만 보존한 채 일반 prose 를 내보낸다.
public enum MarkdownChatPillContextSurface: Equatable {
    case task
    case goal
    case fallback(typeLabel: String)

    /// **Markdown panel 전용 helper.** frontmatter 첫 `type:` 스칼라를 보고
    /// `.task` / `.goal` / `.fallback(typeLabel:)` 중 하나를 반환한다.
    public static func detect(fromContent content: String) -> MarkdownChatPillContextSurface {
        guard let raw = extractFrontmatterType(content),
              !raw.isEmpty else {
            return .fallback(typeLabel: "general")
        }
        switch raw {
        case "task":
            return .task
        case "goal":
            return .goal
        default:
            // inbox/signal/email/note/person/... 전부 여기로. label 만 보존해
            // fallback advisory 에 인터폴레이션된다.
            return .fallback(typeLabel: raw)
        }
    }

    /// 첫 `---` 블록 안에서 최상위(들여쓰기 0) `type: <scalar>` 한 줄만 뽑는다.
    /// 따옴표·주석·trailing comment 정도만 처리. 본격적인 YAML 파싱은 `BrainObjectParser`
    /// 가 하지만, prefix 합성은 type 한 키만 필요해서 따로 가볍게 처리한다.
    private static func extractFrontmatterType(_ content: String) -> String? {
        let lines = content.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        for i in 1..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { return nil }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            // 들여쓰기 0 의 top-level key 만 본다.
            let leadingSpaces = line.prefix { $0 == " " }.count
            guard leadingSpaces == 0 else { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            guard key == "type" else { continue }
            var value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            // trailing inline comment ` # foo` 제거 (quoted 안의 # 까지 분리하진 않음 — v1 범위)
            if !value.hasPrefix("\""), !value.hasPrefix("'"),
               let hashIdx = value.firstIndex(of: "#") {
                value = String(value[..<hashIdx]).trimmingCharacters(in: .whitespaces)
            }
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }
}

/// ChatPill 이 새 에이전트 터미널을 띄울 때 사용자 프롬프트 앞에 흘려보내는
/// "이 터미널은 어떤 G-Brain 문서 위에서 열렸는지" advisory prose.
///
/// **영어 prose 인 이유**: 사용자 프롬프트는 한국어가 기본이라, prefix 도 한국어면
/// 에이전트 입장에서 advisory 가 어디 끝나고 user prompt 가 어디서 시작하는지 시각적
/// 경계가 흐려진다. 영어로 두면 언어 자체가 분리 신호가 되어 advisory 와 user 발화가
/// 섞이지 않는다.
///
/// 정책 (graceful-forging-biscuit.md):
///   - imperatives / conditionals / closing constructs 금지. advisory 톤만.
///     (must/should/do not/don't/always/never/if you/when you/only when/except 등)
///   - 본문 데이터 inline 금지 (timeline·checklist 발췌 등).
///   - 메타룰(citation/mutation/사용자 지시 우선) 은 글로벌 CLAUDE.md 의 책임.
///     단 brain-first lookup + cite·backlink 한 줄은 ChatPill 의 본질이라 공통으로 붙는다.
///   - 두 줄 prose: 줄1 = surface advisory, 줄2 = 공통 gbrain advisory.
///   - `<path>` 는 모든 surface 에서 인터폴레이션, `<type>` 은 fallback 한정.
public enum MarkdownChatPillContextPrefix {
    /// 3 surface 가 공통으로 붙이는 둘째 줄. gbrain query/search/get advisory + citation·backlink advisory.
    private static let commonGbrainAdvisoryLine =
        "For tracking down related material, gbrain's `search` / `query` / `get` tend to surface backlinks and compiled_truth that raw grep misses, and leaving a `[Source: …, YYYY-MM-DD]` citation alongside backlinks when writing new facts keeps the graph alive across sessions."

    private static let taskAdvisoryTemplate =
        "This terminal opened on top of a G-Brain task document at <path>. A task is an execution unit owned by someone, and its `status` field carries two layered signals at once — a lifecycle phase (todo / doing / done) and a dependency signal (`blocked` for internal work, `waiting` for an external response). Glancing at that signal once tends to set the tone for the answer."

    private static let goalAdvisoryTemplate =
        "This terminal opened on top of a G-Brain goal document at <path>. A goal is a time-bound outcome measured by metrics or milestones, usually fanning out into subgoals and linked tasks. The goal page itself is the primary source for current direction, while the linked tasks carry day-to-day execution state."

    private static let fallbackAdvisoryTemplate =
        "This terminal opened on top of a `<type>` G-Brain document at <path>. This surface has no special operational-phase marker; its body and frontmatter are the primary source."

    /// 두 줄 prose 한 덩어리를 반환한다. 호출 측은 prefix 뒤에 빈 줄 한 개 + 사용자 message 형태로 붙인다.
    public static func build(
        markdownFilePath: String,
        surface: MarkdownChatPillContextSurface
    ) -> String {
        let firstLine: String
        switch surface {
        case .task:
            firstLine = taskAdvisoryTemplate.replacingOccurrences(of: "<path>", with: markdownFilePath)
        case .goal:
            firstLine = goalAdvisoryTemplate.replacingOccurrences(of: "<path>", with: markdownFilePath)
        case .fallback(let typeLabel):
            firstLine = fallbackAdvisoryTemplate
                .replacingOccurrences(of: "<path>", with: markdownFilePath)
                .replacingOccurrences(of: "<type>", with: typeLabel)
        }
        return firstLine + "\n" + commonGbrainAdvisoryLine
    }
}
