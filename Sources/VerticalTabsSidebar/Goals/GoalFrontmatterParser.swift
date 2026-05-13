import Foundation

enum GoalFrontmatterParser {
    private static let isoFormatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withFullDate]
        let withTime = ISO8601DateFormatter()
        withTime.formatOptions = [.withInternetDateTime]
        return [plain, withTime]
    }()

    /// Parses a `.md` file's YAML frontmatter into a GoalEntry.
    /// Reads only the head of the file (frontmatter is at the top).
    static func parse(filePath: String, headBytes: Int = 4096) -> GoalEntry? {
        guard let head = readHead(path: filePath, bytes: headBytes) else { return nil }
        guard let raw = extractFrontmatterBlock(from: head) else { return nil }
        let kv = parseFlatKeyValues(raw)
        let milestones = parseMilestones(raw)

        let displayNameFallback = (filePath as NSString).lastPathComponent
        let stem = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension

        // goalId is always the file stem (used for parent-child matching).
        // frontmatter `goal_id` / `id` are display-only hints; ignored for matching.
        let goalId = stem
        let parentRaw = kv["parent_goal"]?.trimmedUnquoted
        let parent = parentRaw.map { goalIdStem(from: $0) }
        let status = GoalStatus(rawValue: (kv["status"]?.trimmedUnquoted ?? "").lowercased()) ?? .draft
        let cadenceRaw = kv["review_cadence"]?.trimmedUnquoted ?? ""
        let cadence = GoalCadence(rawValue: cadenceRaw.lowercased()) ?? .weekly
        let targetDate = parseTargetDate(kv["target_date"]?.trimmedUnquoted)
        let title = kv["title"]?.trimmedUnquoted

        let total = milestones.count
        let done = milestones.filter { $0 }.count

        return GoalEntry(
            absolutePath: filePath,
            displayName: title?.isEmpty == false ? title! : displayNameFallback,
            goalId: goalId,
            parentGoalId: (parent?.isEmpty == false) ? parent : nil,
            status: status,
            cadence: cadence,
            targetDate: targetDate,
            milestoneDone: done,
            milestoneTotal: total
        )
    }

    private static func readHead(path: String, bytes: Int) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let data = (try? fh.read(upToCount: bytes)) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    private static func extractFrontmatterBlock(from text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty, lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        var body: [String] = []
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return body.joined(separator: "\n")
            }
            body.append(lines[i])
        }
        return nil
    }

    private static func parseFlatKeyValues(_ block: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.hasPrefix("  ") || raw.hasPrefix("\t") || raw.hasPrefix("-") {
                continue
            }
            guard let colonIdx = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<colonIdx].trimmingCharacters(in: .whitespaces)
            let value = raw[raw.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if value.isEmpty { continue }
            result[key] = value
        }
        return result
    }

    /// Returns `done` flag per milestone, in order.
    /// Supports inline `- { done: true, title: "..." }` form and indented multi-line form.
    private static func parseMilestones(_ block: String) -> [Bool] {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let startIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("milestones:") }) else {
            return []
        }
        var result: [Bool] = []
        var currentBlock: [String]? = nil

        func flushBlock() {
            if let block = currentBlock {
                let joined = block.joined(separator: " ")
                result.append(extractDone(from: joined))
            }
            currentBlock = nil
        }

        for i in (startIdx + 1)..<lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let leadingWS = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            if trimmed.isEmpty { continue }
            if leadingWS == 0 && !trimmed.hasPrefix("-") {
                // end of milestones section
                break
            }
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                flushBlock()
                let after = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
                currentBlock = [String(after)]
            } else {
                currentBlock?.append(trimmed)
            }
        }
        flushBlock()
        return result
    }

    private static func extractDone(from text: String) -> Bool {
        // Tokenize by whitespace; check key-value pairs for done indicators.
        // Recognized patterns: `done: true`, `done: yes`, `status: done`, `status: completed`.
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map { String($0) }
        for i in 0..<tokens.count {
            let token = tokens[i].lowercased()
            if token == "done:" || token.hasPrefix("done:") {
                let value = token == "done:" ? (i + 1 < tokens.count ? tokens[i + 1].lowercased() : "") : String(token.dropFirst("done:".count))
                if value.hasPrefix("true") || value.hasPrefix("yes") { return true }
            }
            if token == "status:" || token.hasPrefix("status:") {
                let value = token == "status:" ? (i + 1 < tokens.count ? tokens[i + 1].lowercased() : "") : String(token.dropFirst("status:".count))
                let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"',"))
                if trimmed.hasPrefix("done") || trimmed.hasPrefix("completed") { return true }
            }
        }
        return false
    }

    private static func goalIdStem(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last: String
        if let lastSlash = trimmed.lastIndex(of: "/") {
            last = String(trimmed[trimmed.index(after: lastSlash)...])
        } else {
            last = trimmed
        }
        return (last as NSString).deletingPathExtension
    }

    private static func parseTargetDate(_ raw: String?) -> Date? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "null" || trimmed == "ongoing" || trimmed == "~" {
            return nil
        }
        let stripped = raw.trimmedUnquoted
        for f in isoFormatters {
            if let date = f.date(from: stripped) { return date }
        }
        // try yyyy-MM-dd via DateFormatter as fallback
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: stripped)
    }
}

private extension String {
    var trimmedUnquoted: String {
        var s = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            if s.count >= 2 {
                s.removeFirst()
                s.removeLast()
            }
        }
        return s
    }
}
