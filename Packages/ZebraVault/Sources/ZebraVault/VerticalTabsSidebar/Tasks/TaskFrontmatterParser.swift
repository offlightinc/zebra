import Foundation

enum TaskFrontmatterParser {
    /// Parses a `.md` file's YAML frontmatter into a TaskItem.
    /// Reads only the head of the file (frontmatter is at the top).
    /// Returns nil if the file has no frontmatter or `type: task` marker.
    static func parse(filePath: String, headBytes: Int = FrontmatterUtils.defaultHeadBytes) -> TaskItem? {
        guard let head = FrontmatterUtils.readHead(path: filePath, bytes: headBytes) else { return nil }
        guard let raw = FrontmatterUtils.extractFrontmatterBlock(from: head) else { return nil }
        let kv = FrontmatterUtils.parseFlatKeyValues(raw)
        guard kv["type"]?.trimmedUnquoted.lowercased() == "task" else { return nil }

        let displayNameFallback = (filePath as NSString).lastPathComponent
        let title = kv["title"]?.trimmedUnquoted
        let displayName = title?.isEmpty == false ? title! : displayNameFallback

        // status/priority 매핑(legacy alias 포함)은 enum의 parseFrontmatter에서
        // 단일 소스로 관리한다. 인식 못한 status는 raw 그대로 보존(빨간 ? 칩 렌더).
        let statusRaw = kv["status"]?.trimmedUnquoted.lowercased() ?? ""
        let (status, unrecognized): (BrainTaskStatus?, String?) = {
            if statusRaw.isEmpty { return (nil, nil) }
            if let parsed = BrainTaskStatus.parseFrontmatter(statusRaw) {
                return (parsed, nil)
            }
            return (nil, statusRaw)
        }()

        let priorityRaw = kv["priority"]?.trimmedUnquoted.lowercased() ?? ""
        let priority = BrainPriority.parseFrontmatter(priorityRaw)

        let ownerRaw = kv["owner"]?.trimmedUnquoted
        let ownerSlug: String? = {
            guard let raw = ownerRaw, !raw.isEmpty, raw.lowercased() != "unassigned" else { return nil }
            if raw.hasPrefix("people/") {
                let slug = String(raw.dropFirst("people/".count))
                return slug.isEmpty ? nil : slug
            }
            return raw
        }()

        let dueDate = parseDate(kv["due"]?.trimmedUnquoted)

        let goalRaw = kv["goal"]?.trimmedUnquoted
        let goalSlug: String? = {
            guard let raw = goalRaw, !raw.isEmpty else { return nil }
            if raw.hasPrefix("goals/") {
                let slug = String(raw.dropFirst("goals/".count))
                return slug.isEmpty ? nil : slug
            }
            return raw
        }()

        // `related: - projects/xxx` (실제 vault schema) 와 단일 scalar `project: xxx`
        // (HTML prototype style) 둘 다 지원. 중복 슬러그는 제거.
        let relatedItems = parseListItems(block: raw, key: "related")
        var relatedProjects = relatedItems.compactMap { item -> String? in
            guard item.hasPrefix("projects/") else { return nil }
            let slug = String(item.dropFirst("projects/".count))
            return slug.isEmpty ? nil : slug
        }
        if let scalar = kv["project"]?.trimmedUnquoted, !scalar.isEmpty {
            let slug = scalar.hasPrefix("projects/")
                ? String(scalar.dropFirst("projects/".count))
                : scalar
            if !slug.isEmpty, !relatedProjects.contains(slug) {
                relatedProjects.append(slug)
            }
        }

        let tags = parseInlineList(kv["tags"]?.trimmedUnquoted)

        return TaskItem(
            absolutePath: filePath,
            displayName: displayName,
            title: displayName,
            status: status,
            unrecognizedStatusRaw: unrecognized,
            priority: priority,
            ownerSlug: ownerSlug,
            dueDate: dueDate,
            goalSlug: goalSlug,
            relatedProjects: relatedProjects,
            tags: tags
        )
    }

    /// Parses YAML list items under `key:` (one per line, `  - item`).
    private static func parseListItems(block: String, key: String) -> [String] {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let startIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):") }) else {
            return []
        }
        var items: [String] = []
        for i in (startIdx + 1)..<lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let leadingWS = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            if trimmed.isEmpty { continue }
            if leadingWS == 0 && !trimmed.hasPrefix("-") { break }
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmedUnquoted
                if !item.isEmpty { items.append(item) }
            } else if trimmed == "-" {
                continue
            }
        }
        return items
    }

    /// Parses inline list `[a, b, c]` or single value.
    private static func parseInlineList(_ raw: String?) -> [String] {
        guard let raw = raw, !raw.isEmpty else { return [] }
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") && s.hasSuffix("]") {
            s = String(s.dropFirst().dropLast())
        }
        return s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmedUnquoted }
            .filter { !$0.isEmpty }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "null" || trimmed == "~" { return nil }
        let stripped = raw.trimmedUnquoted
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: stripped)
    }
}
