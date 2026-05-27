import Foundation

// MARK: - Domain model

/// Top-level discriminated union for a parsed brain Markdown file.
///
/// `.unknown` is the catch-all for files that have no recognized `type:`
/// or no frontmatter at all. It is NOT an error state — the inspector
/// still renders them through the generic document path so unmapped
/// frontmatter keys aren't silently dropped.
public enum BrainObject {
    case task(TaskObject)
    case goal(GoalObject)
    case note(NoteObject)
    case unknown(UnknownObject)
}

public struct TaskObject {
    public var title: String
    public var status: BrainTaskStatus?
    public var priority: BrainPriority?
    public var owner: String?
    public var reviewer: String?
    public var due: BrainDate?
    public var related: [BrainObjectRef]
    public var blockedBy: [BrainObjectRef]
    public var blockedReason: String?
    public var waitingOn: String?
    public var tags: [String]
    public var lastUpdated: BrainDate?
    public var backlinks: Int?
    public var checklist: BrainChecklist?
}

public struct GoalObject {
    public var title: String
    public var goalId: String?
    public var status: BrainGoalStatus?
    /// frontmatter 의 `status:` 값이 있지만 BrainGoalStatus 의 어느 case 와도
    /// 매핑 안 될 때 원본 raw 를 보존. 사이드바 / 인스펙터의 status pill 이 ?
    /// 글리프로 노출해서 사용자가 정정할 수 있게 한다. (GoalFrontmatterParser
    /// 의 같은 패턴과 일관 — 두 parser 가 같은 정책.)
    public var unrecognizedStatusRaw: String?
    public var owner: String?
    public var targetDate: BrainDate?
    public var reviewCadence: String?
    public var parentGoal: BrainObjectRef?
    public var subgoals: [BrainObjectRef]
    public var tasks: [BrainObjectRef]
    public var metrics: [BrainMetric]
    public var milestones: [BrainMilestone]
    public var progressFraction: Double?
    public var tasksOpen: Int?
    public var tasksDone: Int?
    public var backlinks: Int?
    public var lastUpdated: BrainDate?
}

public struct NoteObject {
    public var title: String
    /// All parsed frontmatter in source order. Generic documents should not
    /// need per-key presets to expose metadata.
    public var frontmatter: [BrainFrontmatterField]
    public var headings: [String]
    public var seeAlso: [BrainObjectRef]
    public var referencedIn: [BrainObjectRef]
    public var backlinks: Int?
}

public struct BrainFrontmatterField {
    public var key: String
    public var value: BrainFrontmatterValue
}

public indirect enum BrainFrontmatterValue {
    case null
    case scalar(String)
    case array([BrainFrontmatterValue])
    case map([(key: String, value: BrainFrontmatterValue)])
}

public struct UnknownObject {
    /// Best-effort title: explicit `title:` frontmatter, first H1, or filename.
    public var title: String
    /// Every parsed key, preserved verbatim, so nothing is silently dropped.
    public var frontmatter: [(key: String, value: String)]
}

// MARK: - Property value types

public enum BrainTaskStatus: String, CaseIterable {
    // brain-offlight task schema 의 7개 상태가 canonical:
    // backlog → todo → inprogress → blocked → waiting → done → canceled.
    //
    // raw value(= frontmatter에 직렬화되는 문자열)는 HTML schema와 동일:
    //   backlog / todo / inprogress / blocked / waiting / done / canceled
    // legacy alias(doing → inprogress, completed → done, normal → medium)는
    // parser쪽에서 read-only로 흡수하고, writer는 항상 canonical로 저장한다.
    case backlog, todo, inprogress, blocked, waiting, done, canceled

    /// Picker/filter 노출용 canonical task status 전체.
    public static var primaryCases: [BrainTaskStatus] {
        [.backlog, .todo, .inprogress, .blocked, .waiting, .done, .canceled]
    }

    public var localizedLabel: String {
        switch self {
        case .backlog:    return String(localized: "task.status.backlog", defaultValue: "Backlog")
        case .todo:       return String(localized: "task.status.todo", defaultValue: "Todo")
        case .inprogress: return String(localized: "task.status.inprogress", defaultValue: "In progress")
        case .blocked:    return String(localized: "task.status.blocked", defaultValue: "Blocked")
        case .waiting:    return String(localized: "task.status.waiting", defaultValue: "Waiting")
        case .done:       return String(localized: "task.status.done", defaultValue: "Done")
        case .canceled:   return String(localized: "task.status.canceled", defaultValue: "Canceled")
        }
    }

    /// frontmatter `status:` 문자열을 enum으로. HTML schema canonical 값과
    /// legacy alias(doing→inprogress, completed→done) 둘 다 흡수. 이 한 곳에서만
    /// 매핑하고 모든 parser는 이 메서드를 호출한다.
    public static func parseFrontmatter(_ raw: String) -> BrainTaskStatus? {
        switch raw.lowercased() {
        case "backlog":    return .backlog
        case "todo":       return .todo
        case "inprogress": return .inprogress
        case "doing":      return .inprogress
        case "blocked":    return .blocked
        case "waiting":    return .waiting
        case "done":       return .done
        case "completed":  return .done
        case "canceled":   return .canceled
        default:           return nil
        }
    }
}

public enum BrainPriority: String, CaseIterable {
    // HTML: none / urgent / high / medium / low. `none`은 nil로 표현하므로 enum엔
    // 4개만. legacy `normal`은 parser에서 .medium으로 읽고, writer는 "medium"으로 저장.
    case urgent, high, medium, low

    /// frontmatter `priority:` 문자열을 enum으로. legacy `normal` → `.medium` 흡수.
    public static func parseFrontmatter(_ raw: String) -> BrainPriority? {
        switch raw.lowercased() {
        case "urgent": return .urgent
        case "high":   return .high
        case "medium": return .medium
        case "normal": return .medium
        case "low":    return .low
        default:       return nil
        }
    }

    public var localizedLabel: String {
        switch self {
        case .urgent: return String(localized: "task.priority.urgent", defaultValue: "Urgent")
        case .high:   return String(localized: "task.priority.high", defaultValue: "High")
        case .medium: return String(localized: "task.priority.medium", defaultValue: "Medium")
        case .low:    return String(localized: "task.priority.low", defaultValue: "Low")
        }
    }
}

/// A relation to another object in the vault. The target may or may not
/// be resolvable — the design says the row stays clickable either way
/// and shows a faint "unresolved" caption when the link can't be found.
public struct BrainObjectRef: Hashable {
    /// Verbatim from the frontmatter: `tasks/x`, `G-2026-Q2-04`, etc.
    public var raw: String
    /// Heuristic: looks like `<TYPE>-<YYYY>-…` rather than a path.
    public var looksLikeId: Bool { !raw.contains("/") && raw.uppercased() == raw.prefix(1).uppercased() + raw.dropFirst() }
    /// Final path component, sans `.md`, hyphens turned to spaces for display.
    public var displayTitle: String {
        let last = raw.split(separator: "/").last.map(String.init) ?? raw
        let stripped = last.hasSuffix(".md") ? String(last.dropLast(3)) : last
        return stripped.replacingOccurrences(of: "-", with: " ")
    }
    /// Right-side caption: vault folder (`tasks`, `docs`, …) or the raw ID.
    public var displayMeta: String {
        if raw.contains("/") {
            return String(raw.split(separator: "/").first ?? "")
        }
        return raw
    }
}

/// Date is kept as a `(Date, sourceString)` pair so we can render the
/// exact frontmatter formatting back if needed but still do relative
/// math against today.
public struct BrainDate: Equatable {
    public var date: Date
    public var source: String
}

public struct BrainChecklist: Equatable {
    public var done: Int
    public var total: Int
}

public struct BrainMetric: Equatable {
    public var name: String
    public var from: Double
    public var to: Double
    public var unit: String?
}

public struct BrainMilestone: Equatable {
    public var name: String
    public var date: BrainDate?
    public var done: Bool
    public var current: Bool
}

// MARK: - Parse error

public struct BrainObjectParseError: Error, Equatable {
    public var line: Int
    public var column: Int
    public var message: String
}

// MARK: - Parse result

/// The full parse output the panel publishes. Even on parse failure we
/// hold onto a stripped body so the markdown side keeps rendering.
public struct BrainObjectParse {
    /// Markdown body with the leading `---...---\n` block removed if any.
    public var strippedBody: String
    /// `.success(.task(...))` for typed files, `.success(.unknown(...))`
    /// for missing/no-type frontmatter, `.failure` when YAML-ish parse
    /// failed mid-block.
    public var result: Result<BrainObject, BrainObjectParseError>
}

// MARK: - Parser entry point

public enum BrainObjectParser {
    /// Parse a full markdown file into a `BrainObjectParse`.
    ///
    /// Best-effort and side-effect free; safe to run off the main actor.
    public static func parse(_ source: String, filename: String) -> BrainObjectParse {
        let split = extractFrontmatter(source)
        let body = split.body

        guard let block = split.frontmatter else {
            // No frontmatter at all → unknown with title from H1/filename.
            let title = firstH1(in: body) ?? defaultTitle(filename: filename)
            return BrainObjectParse(
                strippedBody: body,
                result: .success(.unknown(UnknownObject(title: title, frontmatter: [])))
            )
        }

        do {
            let pairs = try parseFrontmatterBlock(block, blockStartLine: split.blockStartLine)
            let type = (pairs.first(where: { $0.0 == "type" })?.1).flatMap { $0.scalar }
            let title = (pairs.first(where: { $0.0 == "title" })?.1).flatMap { $0.scalar }
                ?? firstH1(in: body)
                ?? defaultTitle(filename: filename)

            switch type {
            case "task":
                return BrainObjectParse(
                    strippedBody: body,
                    result: .success(.task(buildTask(pairs: pairs, title: title, body: body)))
                )
            case "goal":
                return BrainObjectParse(
                    strippedBody: body,
                    result: .success(.goal(buildGoal(pairs: pairs, title: title, body: body)))
                )
            case "note":
                return BrainObjectParse(
                    strippedBody: body,
                    result: .success(.note(buildNote(pairs: pairs, title: title, body: body)))
                )
            default:
                if type != nil {
                    return BrainObjectParse(
                        strippedBody: body,
                        result: .success(.note(buildNote(pairs: pairs, title: title, body: body)))
                    )
                }
                let flat = pairs.map { (key: $0.0, value: $0.1.debugFlat) }
                return BrainObjectParse(
                    strippedBody: body,
                    result: .success(.unknown(UnknownObject(title: title, frontmatter: flat)))
                )
            }
        } catch let err as BrainObjectParseError {
            return BrainObjectParse(strippedBody: body, result: .failure(err))
        } catch {
            return BrainObjectParse(
                strippedBody: body,
                result: .failure(BrainObjectParseError(line: split.blockStartLine, column: 1, message: error.localizedDescription))
            )
        }
    }

    // MARK: - Frontmatter extraction

    fileprivate static func extractFrontmatter(_ source: String) -> (frontmatter: String?, body: String, blockStartLine: Int) {
        // Frontmatter must be the first non-empty content. We require an
        // exact leading `---\n` (allowing CRLF) and a closing `\n---\n`.
        let lines = source.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, source, 1)
        }

        // Search for a closing `---` on its own line.
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            let block = lines[1..<i].joined(separator: "\n")
            // Body skips the closing `---` line.
            let bodyStart = i + 1
            let body = bodyStart < lines.count
                ? lines[bodyStart..<lines.count].joined(separator: "\n")
                : ""
            // Drop a single leading blank line for cleaner markdown rendering.
            let trimmedBody = body.hasPrefix("\n") ? String(body.dropFirst()) : body
            return (block, trimmedBody, 2)
        }

        // Unclosed frontmatter — treat as body so we don't break rendering.
        return (nil, source, 1)
    }

    // MARK: - Block parser

    /// Minimal YAML-ish parser. Covers the shapes the brain vault uses:
    /// scalars (`a: b`), block sequences (`- v`), inline lists (`[a, b]`)
    /// and inline maps (`{ k: v, k2: v2 }`). Returns ordered key/value
    /// pairs so we can preserve property order for the unknown view.
    fileprivate static func parseFrontmatterBlock(_ block: String, blockStartLine: Int) throws -> [(String, YamlValue)] {
        var pairs: [(String, YamlValue)] = []
        let rawLines = block.components(separatedBy: "\n")
        var i = 0
        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.drop { $0 == " " }
            if trimmed.isEmpty || trimmed.first == "#" {
                i += 1
                continue
            }

            let leadingSpaces = line.count - trimmed.count
            guard leadingSpaces == 0 else {
                // A continuation line at non-zero indent without a recognized
                // parent is unexpected at the top level — skip rather than
                // throw so the rest of the file still parses.
                i += 1
                continue
            }

            guard let colon = trimmed.firstIndex(of: ":") else {
                throw BrainObjectParseError(
                    line: blockStartLine + i,
                    column: 1,
                    message: "Expected `key:` at start of line"
                )
            }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if rest.isEmpty {
                // Block-style child: gather indented `- item` lines that follow.
                var items: [YamlValue] = []
                var j = i + 1
                while j < rawLines.count {
                    let next = rawLines[j]
                    let nextTrim = next.drop { $0 == " " }
                    if nextTrim.isEmpty { j += 1; continue }
                    let indent = next.count - nextTrim.count
                    if indent == 0 { break }
                    if nextTrim.hasPrefix("- ") {
                        let valStr = String(nextTrim.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        let parsed = try parseBlockListItem(
                            firstValue: valStr,
                            rawLines: rawLines,
                            startIndex: j,
                            itemIndent: indent,
                            blockStartLine: blockStartLine
                        )
                        items.append(parsed.value)
                        j = parsed.nextIndex
                        continue
                    } else if nextTrim == "-" {
                        items.append(.null)
                    } else {
                        // Top-level only — anything else inside a block we
                        // don't try to recurse into for v1.
                        break
                    }
                    j += 1
                }
                pairs.append((key, items.isEmpty ? .null : .array(items)))
                i = j
            } else {
                pairs.append((key, try parseInlineValue(rest, line: blockStartLine + i)))
                i += 1
            }
        }
        return pairs
    }

    private static func parseBlockListItem(
        firstValue: String,
        rawLines: [String],
        startIndex: Int,
        itemIndent: Int,
        blockStartLine: Int
    ) throws -> (value: YamlValue, nextIndex: Int) {
        guard let firstPair = try parseMapEntry(firstValue, line: blockStartLine + startIndex) else {
            return (try parseInlineValue(firstValue, line: blockStartLine + startIndex), startIndex + 1)
        }

        var map: [(String, YamlValue)] = [firstPair]
        var j = startIndex + 1
        while j < rawLines.count {
            let line = rawLines[j]
            let trimmed = line.drop { $0 == " " }
            if trimmed.isEmpty {
                j += 1
                continue
            }
            let indent = line.count - trimmed.count
            if indent <= itemIndent { break }
            if trimmed.hasPrefix("- ") { break }
            guard let pair = try parseMapEntry(String(trimmed), line: blockStartLine + j) else { break }
            map.append(pair)
            j += 1
        }
        return (.map(map), j)
    }

    private static func parseMapEntry(_ raw: String, line: Int) throws -> (String, YamlValue)? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.hasPrefix("["),
              !s.hasPrefix("{"),
              let colon = s.firstIndex(of: ":") else { return nil }
        let key = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        let rest = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, try parseInlineValue(rest, line: line))
    }

    fileprivate static func parseInlineValue(_ raw: String, line: Int) throws -> YamlValue {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "~" || s.lowercased() == "null" {
            return .null
        }
        if s.hasPrefix("[") {
            guard s.hasSuffix("]") else {
                let col = (raw.firstIndex(of: "[").map { raw.distance(from: raw.startIndex, to: $0) } ?? 0) + 1
                throw BrainObjectParseError(
                    line: line,
                    column: col + 1,
                    message: "Unclosed inline array in frontmatter — expected ']' before line break"
                )
            }
            let inner = String(s.dropFirst().dropLast())
            let parts = splitTopLevel(inner, separator: ",")
            return .array(try parts.map { try parseInlineValue($0, line: line) })
        }
        if s.hasPrefix("{") {
            guard s.hasSuffix("}") else {
                throw BrainObjectParseError(
                    line: line,
                    column: 1,
                    message: "Unclosed inline map in frontmatter — expected '}' before line break"
                )
            }
            let inner = String(s.dropFirst().dropLast())
            var map: [(String, YamlValue)] = []
            for part in splitTopLevel(inner, separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard let colon = trimmed.firstIndex(of: ":") else {
                    throw BrainObjectParseError(line: line, column: 1, message: "Expected `key: value` inside inline map")
                }
                let k = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                map.append((k, try parseInlineValue(v, line: line)))
            }
            return .map(map)
        }
        // Quoted strings.
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return .scalar(String(s.dropFirst().dropLast()))
        }
        return .scalar(s)
    }

    /// Split on `separator` but ignore separators inside nested `[…]` or `{…}`.
    fileprivate static func splitTopLevel(_ s: String, separator: Character) -> [String] {
        var out: [String] = []
        var depth = 0
        var current = ""
        var inQuotes: Character? = nil
        for c in s {
            if let q = inQuotes {
                current.append(c)
                if c == q { inQuotes = nil }
                continue
            }
            if c == "\"" || c == "'" { inQuotes = c; current.append(c); continue }
            if c == "[" || c == "{" { depth += 1; current.append(c); continue }
            if c == "]" || c == "}" { depth -= 1; current.append(c); continue }
            if c == separator && depth == 0 {
                let v = current.trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { out.append(v) }
                current = ""
            } else {
                current.append(c)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { out.append(last) }
        return out
    }
}

// MARK: - Type-specific assembly

extension BrainObjectParser {
    fileprivate static func buildTask(pairs: [(String, YamlValue)], title: String, body: String) -> TaskObject {
        let dict = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) })
        return TaskObject(
            title: title,
            status: dict["status"]?.scalar.flatMap(parseStatus(_:)),
            priority: dict["priority"]?.scalar.flatMap(BrainPriority.init(rawValue:)),
            owner: dict["owner"]?.scalar,
            reviewer: dict["reviewer"]?.scalar,
            due: dict["due"]?.scalar.flatMap(parseDate(_:)),
            related: refList(dict["related"]),
            blockedBy: refList(dict["blocked_by"]),
            blockedReason: dict["blocked_reason"]?.scalar,
            waitingOn: dict["waiting_on"]?.scalar,
            tags: stringList(dict["tags"]),
            lastUpdated: dict["updated"]?.scalar.flatMap(parseDate(_:)) ?? lastUpdatedFromBody(body),
            backlinks: referencedInCount(body),
            checklist: checklistFromBody(body)
        )
    }

    fileprivate static func buildGoal(pairs: [(String, YamlValue)], title: String, body: String) -> GoalObject {
        let dict = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) })
        let metrics = (dict["metrics"]?.arrayValue ?? []).compactMap(parseMetric)
        let milestones = (dict["milestones"]?.arrayValue ?? []).compactMap(parseMilestone)
        let taskRefs = refList(dict["tasks"])
        // Best-effort task rollup; if we resolve nothing, leave nil so we
        // fall back to the "—" presentation rather than fake "0 of 0".
        let progress: Double? = nil
        let statusRaw = dict["status"]?.scalar
        let parsedStatus = statusRaw.flatMap { BrainGoalStatus(rawValue: $0.lowercased()) }
        let unrecognizedStatusRaw: String? = {
            guard let raw = statusRaw, !raw.isEmpty else { return nil }
            return parsedStatus == nil ? raw : nil
        }()
        return GoalObject(
            title: title,
            goalId: dict["goal_id"]?.scalar,
            status: parsedStatus,
            unrecognizedStatusRaw: unrecognizedStatusRaw,
            owner: dict["owner"]?.scalar,
            targetDate: dict["target_date"]?.scalar.flatMap(parseDate(_:)),
            reviewCadence: dict["review_cadence"]?.scalar,
            parentGoal: dict["parent_goal"]?.scalar.map { BrainObjectRef(raw: $0) },
            subgoals: refList(dict["subgoals"]),
            tasks: taskRefs,
            metrics: metrics,
            milestones: milestones,
            progressFraction: progress,
            tasksOpen: nil,
            tasksDone: nil,
            backlinks: referencedInCount(body),
            lastUpdated: dict["updated"]?.scalar.flatMap(parseDate(_:)) ?? lastUpdatedFromBody(body)
        )
    }

    fileprivate static func buildNote(pairs: [(String, YamlValue)], title: String, body: String) -> NoteObject {
        let referencedIn = extractReferencedIn(body)
        return NoteObject(
            title: title,
            frontmatter: pairs.map { BrainFrontmatterField(key: $0.0, value: $0.1.frontmatterValue) },
            headings: extractH2Outline(body),
            seeAlso: extractSeeAlso(body),
            referencedIn: referencedIn,
            backlinks: referencedIn.isEmpty ? nil : referencedIn.count
        )
    }

    // MARK: - Coercions

    fileprivate static func refList(_ v: YamlValue?) -> [BrainObjectRef] {
        guard let arr = v?.arrayValue else { return [] }
        return arr.compactMap { $0.scalar.map { BrainObjectRef(raw: $0) } }
    }

    fileprivate static func stringList(_ v: YamlValue?) -> [String] {
        guard let arr = v?.arrayValue else { return [] }
        return arr.compactMap { $0.scalar }
    }

    fileprivate static func parseStatus(_ s: String) -> BrainTaskStatus? {
        BrainTaskStatus.parseFrontmatter(s)
    }

    fileprivate static func parsePriority(_ s: String) -> BrainPriority? {
        BrainPriority.parseFrontmatter(s)
    }

    fileprivate static func parseMetric(_ v: YamlValue) -> BrainMetric? {
        guard let map = v.mapValue else { return nil }
        let d = Dictionary(uniqueKeysWithValues: map.map { ($0.0, $0.1) })
        guard let name = d["name"]?.scalar else { return nil }
        let from = d["from"]?.scalar.flatMap(Double.init) ?? 0
        let to = d["to"]?.scalar.flatMap(Double.init) ?? 0
        return BrainMetric(name: name, from: from, to: to, unit: d["unit"]?.scalar)
    }

    fileprivate static func parseMilestone(_ v: YamlValue) -> BrainMilestone? {
        guard let map = v.mapValue else { return nil }
        let d = Dictionary(uniqueKeysWithValues: map.map { ($0.0, $0.1) })
        guard let name = d["description"]?.scalar ?? d["name"]?.scalar ?? d["id"]?.scalar else { return nil }
        let status = d["status"]?.scalar?.lowercased()
        let done = (d["done"]?.scalar ?? "false") == "true" || status == "done" || status == "completed"
        let current = (d["current"]?.scalar ?? "false") == "true" || status == "active" || status == "doing" || status == "current"
        return BrainMilestone(
            name: name,
            date: d["date"]?.scalar.flatMap(parseDate(_:)),
            done: done,
            current: current
        )
    }

    /// Accepts `YYYY-MM-DD`. Anything else returns nil — the date badge
    /// then renders the muted em-dash via the `is-empty` styling.
    fileprivate static func parseDate(_ s: String) -> BrainDate? {
        guard let source = BrainDateOnlyCodec.normalizedStorageString(from: s),
              let date = BrainDateOnlyCodec.date(fromStorageString: source) else {
            return nil
        }
        return BrainDate(date: date, source: source)
    }

    // MARK: - Body-derived properties

    fileprivate static func firstH1(in body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let t = line.drop { $0 == " " }
            if t.hasPrefix("# ") {
                return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    fileprivate static func defaultTitle(filename: String) -> String {
        let last = (filename as NSString).lastPathComponent
        return last.hasSuffix(".md") ? String(last.dropLast(3)) : last
    }

    /// Counts `- [ ]` / `- [x]` lines anywhere in the body.
    fileprivate static func checklistFromBody(_ body: String) -> BrainChecklist? {
        var done = 0
        var total = 0
        for line in body.components(separatedBy: "\n") {
            let t = line.drop { $0 == " " }
            if t.hasPrefix("- [ ]") || t.hasPrefix("* [ ]") {
                total += 1
            } else if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") || t.hasPrefix("* [x]") || t.hasPrefix("* [X]") {
                total += 1
                done += 1
            }
        }
        return total > 0 ? BrainChecklist(done: done, total: total) : nil
    }

    fileprivate static func extractH2Outline(_ body: String) -> [String] {
        var headings: [String] = []
        for line in body.components(separatedBy: "\n") {
            let t = line.drop { $0 == " " }
            if t.hasPrefix("## ") && !t.hasPrefix("### ") {
                let h = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !h.isEmpty { headings.append(h) }
            }
        }
        return headings
    }

    /// Captures bulleted refs under a `## See also` heading. Stops at the
    /// next heading. Strips backticks and trailing commas.
    fileprivate static func extractSeeAlso(_ body: String) -> [BrainObjectRef] {
        let lines = body.components(separatedBy: "\n")
        var seeAlso: [BrainObjectRef] = []
        var inSection = false
        for line in lines {
            let t = line.drop { $0 == " " }
            if t.hasPrefix("## ") {
                let title = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                inSection = (title == "see also")
                continue
            }
            guard inSection else { continue }
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                let raw = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let wiki = firstWikiLink(in: raw) {
                    seeAlso.append(BrainObjectRef(raw: wiki))
                } else if let md = firstMarkdownLinkTarget(in: raw) {
                    seeAlso.append(BrainObjectRef(raw: normalizedBrainPath(md)))
                } else {
                    let fallback = raw.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                    if !fallback.isEmpty {
                        seeAlso.append(BrainObjectRef(raw: fallback))
                    }
                }
            }
        }
        return seeAlso
    }

    /// MVP backlink source: use generated/manual `Referenced in ...` timeline
    /// rows when present. A later graph index should replace this with actual
    /// inbound link computation across the vault.
    fileprivate static func extractReferencedIn(_ body: String) -> [BrainObjectRef] {
        var seen = Set<BrainObjectRef>()
        return body.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- "), trimmed.localizedStandardContains("Referenced in") else {
                return nil
            }
            guard let ref = referencedInRef(from: trimmed), !seen.contains(ref) else {
                return nil
            }
            seen.insert(ref)
            return ref
        }
    }

    fileprivate static func referencedInCount(_ body: String) -> Int? {
        let count = extractReferencedIn(body).count
        return count > 0 ? count : nil
    }

    private static func referencedInRef(from line: String) -> BrainObjectRef? {
        guard let marker = line.range(of: "Referenced in") else { return nil }
        let rest = String(line[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let wiki = firstWikiLink(in: rest) {
            return BrainObjectRef(raw: wiki)
        }
        if let md = firstMarkdownLinkTarget(in: rest) {
            return BrainObjectRef(raw: normalizedBrainPath(md))
        }
        return nil
    }

    private static func firstWikiLink(in text: String) -> String? {
        guard let start = text.range(of: "[["),
              let end = text[start.upperBound...].range(of: "]]") else { return nil }
        let inner = String(text[start.upperBound..<end.lowerBound])
        let target = inner.split(separator: "|", maxSplits: 1).first.map(String.init) ?? inner
        return target.trimmingCharacters(in: .whitespaces)
    }

    private static func firstMarkdownLinkTarget(in text: String) -> String? {
        guard let closeBracket = text.firstIndex(of: "]") else { return nil }
        let afterBracket = text[text.index(after: closeBracket)...]
        guard afterBracket.first == "(",
              let closeParen = afterBracket.dropFirst().firstIndex(of: ")") else { return nil }
        return String(afterBracket.dropFirst()[..<closeParen])
    }

    private static func normalizedBrainPath(_ path: String) -> String {
        var normalized = path.trimmingCharacters(in: .whitespaces)
        while normalized.hasPrefix("../") {
            normalized = String(normalized.dropFirst(3))
        }
        if normalized.hasPrefix("./") {
            normalized = String(normalized.dropFirst(2))
        }
        if normalized.hasSuffix(".md") {
            normalized = String(normalized.dropLast(3))
        }
        return normalized
    }

    /// Cheap "last touched" heuristic: the latest `YYYY-MM-DD` mention in the body.
    fileprivate static func lastUpdatedFromBody(_ body: String) -> BrainDate? {
        let pattern = #"\b(20\d\d)-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        var best: BrainDate?
        for m in matches {
            let s = ns.substring(with: m.range)
            if let d = parseDate(s) {
                if best == nil || d.date > best!.date { best = d }
            }
        }
        return best
    }
}

// MARK: - Intermediate YAML value

/// A tiny ADT for what our hand-rolled parser actually produces. Kept
/// internal to the parser implementation; consumers never see it.
fileprivate indirect enum YamlValue {
    case null
    case scalar(String)
    case array([YamlValue])
    case map([(String, YamlValue)])

    public var scalar: String? {
        if case .scalar(let s) = self { return s }
        return nil
    }
    public var arrayValue: [YamlValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    public var mapValue: [(String, YamlValue)]? {
        if case .map(let m) = self { return m }
        return nil
    }

    /// Single-line representation used by the unknown-type fallback so the
    /// reader can see what came in without us pretending to understand it.
    public var debugFlat: String {
        switch self {
        case .null: return "—"
        case .scalar(let s): return s
        case .array(let a):
            return "[" + a.map { $0.debugFlat }.joined(separator: ", ") + "]"
        case .map(let m):
            return "{" + m.map { "\($0.0): \($0.1.debugFlat)" }.joined(separator: ", ") + "}"
        }
    }

    public var frontmatterValue: BrainFrontmatterValue {
        switch self {
        case .null:
            return .null
        case .scalar(let s):
            return .scalar(s)
        case .array(let values):
            return .array(values.map { $0.frontmatterValue })
        case .map(let pairs):
            return .map(pairs.map { (key: $0.0, value: $0.1.frontmatterValue) })
        }
    }
}
