import Foundation

/// GBrain 문서 종류를 ChatPill prefix 분기에 필요한 3개 surface 로만 좁힌 enum.
///
/// v1 은 **task / goal / fallback** 만 다룬다.
///
/// inbox / signal / email 같은 surface 는 의도적으로 빼뒀다. email/메시지 그래프는
/// 현재 GBrain 측에서 어떤 문서/객체 shape 로 정착할지 진행 중이라 prefix advisory
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
    /// Email panel 호출 사이트 전용. detail.messages 의 bodyText 가
    /// prefix 안에 전문으로 직렬화된다. threadSubject 는 thread-level
    /// 표시명 (보통 첫 메시지의 subject).
    case email(detail: EmailThreadDetail, threadSubject: String)

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
/// "이 터미널은 어떤 GBrain 문서 위에서 열렸는지" advisory prose.
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
///   - 두 줄 prose: 줄1 = surface advisory, 줄2 = 공통 GBrain advisory.
///   - `<path>` 는 모든 surface 에서 인터폴레이션, `<type>` 은 fallback 한정.
public enum MarkdownChatPillContextPrefix {
    /// 3 surface 가 공통으로 붙이는 둘째 줄. gbrain query/search/get advisory + citation·backlink advisory.
    /// active brain 에 `.gbrain-adapter` 가 있으면 그 vault 의 adapter 지침을 우선한다.
    private static let commonGbrainAdvisoryLine =
        "For tracking down related material, gbrain's `search` / `query` / `get` tend to surface backlinks and compiled_truth that raw grep misses. When using GBrain, active vault adapter instructions, when present, are the preferred routing. When writing new facts, leave a `[Source: …, YYYY-MM-DD]` citation alongside backlinks so the graph stays alive across sessions."

    private static let emailDraftGbrainAdvisoryLine =
        "Use this email thread as the target conversation. Before creating or revising a reply draft, decide whether the thread is self-contained or whether outside GBrain context would materially improve the reply. If the thread is enough, draft directly. Use GBrain only when the thread references prior work, a project, task, meeting, source, person or company relationship, unresolved decision, prior email context, or when the user asks for context-aware drafting. When more context is useful, start with `gbrain query`, `gbrain search`, or `gbrain get` to find the most relevant pages. From those pages, follow linked pages, backlinks, or graph connections only when they directly clarify the reply. Stop once you have enough context to write a good reply; do not run every GBrain command as a checklist. Create or update Zebra drafts through `cmux rpc zebra.email_draft.*`; use `base_version` when updating an existing draft and leave sending to the visible user action. Write the outgoing email as a natural human reply. Keep GBrain citations and source notes out of the email body unless the user explicitly asks for citations."

    private static let taskAdvisoryTemplate =
        "This terminal opened on top of a GBrain task document at <path>. A task is an execution unit owned by someone, and its `status` field carries two layered signals at once — a lifecycle phase (todo / doing / done) and a dependency signal (`blocked` for internal work, `waiting` for an external response). Glancing at that signal once tends to set the tone for the answer."

    private static let goalAdvisoryTemplate =
        "This terminal opened on top of a GBrain goal document at <path>. A goal is a time-bound outcome measured by metrics or milestones, usually fanning out into subgoals and linked tasks. The goal page itself is the primary source for current direction, while the linked tasks carry day-to-day execution state."

    private static let fallbackAdvisoryTemplate =
        "This terminal opened on top of a `<type>` GBrain document at <path>. Its body and frontmatter are the primary source."

    private static let emailAdvisoryTemplate =
        "This terminal opened on top of an email thread \"<subject>\" in account <account>. The full thread is included inline below — bodies are the plain-text rendition Clawvisor stored locally. Messages are ordered oldest → newest. Treat the thread as analysis context; any reply or mutation goes through the user."

    /// 호출 측이 그대로 사용자 prompt 앞에 붙이면 되는 prefix 한 덩어리를 반환한다.
    /// markdownFilePath 는 markdown surface (.task/.goal/.fallback) 에서만 의미가 있고,
    /// email surface 는 surface 안의 detail 만으로 prefix 가 완성되므로 nil 허용.
    public static func build(
        markdownFilePath: String?,
        surface: MarkdownChatPillContextSurface
    ) -> String {
        let pathForMarkdown = markdownFilePath ?? ""
        switch surface {
        case .task:
            let firstLine = taskAdvisoryTemplate.replacingOccurrences(of: "<path>", with: pathForMarkdown)
            return firstLine + "\n" + commonGbrainAdvisoryLine
        case .goal:
            let firstLine = goalAdvisoryTemplate.replacingOccurrences(of: "<path>", with: pathForMarkdown)
            return firstLine + "\n" + commonGbrainAdvisoryLine
        case .fallback(let typeLabel):
            let firstLine = fallbackAdvisoryTemplate
                .replacingOccurrences(of: "<path>", with: pathForMarkdown)
                .replacingOccurrences(of: "<type>", with: typeLabel)
            return firstLine + "\n" + commonGbrainAdvisoryLine
        case .email(let detail, let threadSubject):
            return buildEmailPrefix(detail: detail, threadSubject: threadSubject)
        }
    }

    /// argv 한계(macOS ~256KB) 를 conservatively 피하기 위한 prefix 상한.
    /// codex/claude/gemini 의 다른 argv·env 분 + shell escape 비용까지 감안해
    /// thread 직렬화 부분이 이만큼 넘어가면 끝을 자르고 truncation marker 를 박는다.
    /// 일반 thread (수십 통 단위) 는 한참 못 미친다 — 인공적인 거대 케이스 안전망.
    private static let emailBodyByteBudget = 180_000

    private static func buildEmailPrefix(detail: EmailThreadDetail, threadSubject: String) -> String {
        let subjectDisplay = threadSubject.isEmpty ? "(no subject)" : threadSubject
        let accountDisplay = detail.accountEmail?.nilIfBlank ?? "(unknown account)"
        let advisory = emailAdvisoryTemplate
            .replacingOccurrences(of: "<subject>", with: subjectDisplay)
            .replacingOccurrences(of: "<account>", with: accountDisplay)

        let messageCount = detail.messages.count
        var header = "=== Email thread ===\n"
        header += "Subject: \(subjectDisplay)\n"
        header += "Account: \(accountDisplay)\n"
        header += "Thread ID: \(detail.threadId)\n"
        header += "Messages: \(messageCount)\n"
        header += "\n=== Reply drafting workflow ===\n"
        header += emailDraftGbrainAdvisoryLine + "\n"
        header += "\n=== Zebra draft RPC ===\n"
        header += "List drafts: cmux rpc zebra.email_draft.list '{\"thread_id\":\"\(detail.threadId)\"}'\n"
        header += "Create draft: cmux rpc zebra.email_draft.create '{\"thread_id\":\"\(detail.threadId)\",\"target_message_id\":\"<message_id>\",\"body_text\":\"<reply>\"}'\n"
        header += "Update draft: cmux rpc zebra.email_draft.update '{\"thread_id\":\"\(detail.threadId)\",\"local_draft_id\":\"<draft_id>\",\"base_version\":<version>,\"body_text\":\"<reply>\"}'\n"
        header += "Update draft needs the latest base_version from list; stale versions return conflict.\n"
        header += "Optional draft fields: subject, to, cc, bcc.\n"
        header += "Focus draft UI: cmux rpc zebra.email_draft.focus '{\"thread_id\":\"\(detail.threadId)\"}'\n"

        var rendered = advisory + "\n" + commonGbrainAdvisoryLine + "\n\n" + header
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var omittedMessageCount = 0
        var omittedBodyChars = 0

        for (index, message) in detail.messages.enumerated() {
            var block = "\n--- Message \(index + 1) of \(messageCount) ---\n"
            block += "Message ID: \(message.id)\n"
            if let from = formatFrom(message: message) {
                block += "From: \(from)\n"
            }
            if let receivedAt = message.receivedAt {
                block += "Date: \(isoFormatter.string(from: receivedAt))\n"
            }
            if let to = message.to?.nilIfBlank {
                block += "To: \(to)\n"
            }
            if let cc = message.cc?.nilIfBlank {
                block += "Cc: \(cc)\n"
            }
            if let subject = message.subject?.nilIfBlank, subject != subjectDisplay {
                block += "Subject: \(subject)\n"
            }
            block += "\n"
            let body = message.bodyText?.nilIfBlank
                ?? message.snippet?.nilIfBlank
                ?? "(no body returned by Clawvisor)"
            block += body
            block += "\n"

            let projectedSize = rendered.utf8.count + block.utf8.count
            if projectedSize > emailBodyByteBudget {
                omittedMessageCount = messageCount - index
                omittedBodyChars += body.count
                for remaining in detail.messages.dropFirst(index + 1) {
                    omittedBodyChars += (remaining.bodyText?.count ?? 0)
                }
                break
            }
            rendered += block
        }

        if omittedMessageCount > 0 {
            rendered += "\n*** truncated — \(omittedMessageCount) messages / \(omittedBodyChars) chars omitted to stay under argv limit ***\n"
        }
        return rendered
    }

    private static func formatFrom(message: EmailThreadMessage) -> String? {
        let name = message.fromName?.nilIfBlank
        let email = message.fromEmail?.nilIfBlank
        switch (name, email) {
        case let (n?, e?): return "\(n) <\(e)>"
        case (let n?, nil): return n
        case (nil, let e?): return e
        case (nil, nil): return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
