import Foundation

/// Shared helpers for parsing the YAML-ish frontmatter block at the head of a
/// markdown file. Used by Goal / Task / Person frontmatter parsers.
enum FrontmatterUtils {
    static let defaultHeadBytes: Int = 4096

    static func readHead(path: String, bytes: Int = defaultHeadBytes) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let data = (try? fh.read(upToCount: bytes)) ?? Data()
        // Lossy UTF-8 decoding: a read that lands mid-codepoint (common when
        // the head boundary falls inside a Korean character body, e.g.
        // 홍남호.md at byte 4094) must not nil out the whole file. Frontmatter
        // is at the top with ASCII keys, so invalid bytes near the clipped
        // tail are U+FFFD'd and ignored by the key/value parser.
        return String(decoding: data, as: UTF8.self)
    }

    static func extractFrontmatterBlock(from text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty, lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var body: [String] = []
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return body.joined(separator: "\n")
            }
            body.append(lines[i])
        }
        return nil
    }

    static func parseFlatKeyValues(_ block: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.hasPrefix("  ") || raw.hasPrefix("\t") || raw.hasPrefix("-") { continue }
            guard let colonIdx = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<colonIdx].trimmingCharacters(in: .whitespaces)
            let value = raw[raw.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if value.isEmpty { continue }
            result[key] = value
        }
        return result
    }
}

extension String {
    /// Strips matching surrounding single or double quotes after whitespace trim.
    var trimmedUnquoted: String {
        var s = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            if s.count >= 2 { s.removeFirst(); s.removeLast() }
        }
        return s
    }
}
