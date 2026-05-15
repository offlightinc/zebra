import Foundation

/// Surgical, line-level YAML frontmatter mutator. Designed to preserve
/// everything outside the targeted key — other keys' order, comments,
/// quoting style, indentation, body text, and line endings.
///
/// The caller is expected to only invoke this for files that already
/// parse as a brain object (i.e. the frontmatter block exists). If no
/// frontmatter block is present, the source is returned unchanged.
enum BrainFrontmatterWriter {
    /// Returns the full file text with `key:` set to `value`. `value == nil`
    /// removes the matching line. If the key does not exist, a new line is
    /// inserted before the closing `---`.
    /// Read the file at `filePath`, apply `setScalar(key, to: value, in:)`,
    /// then atomic-write back. Silent no-op on read/decode/write failure —
    /// callers that need diagnostics should use `setScalar` directly.
    /// Sidebar 전용 (Task/Goal). MarkdownPanel 처럼 in-memory snapshot 을
    ///쥐고 있는 호출자는 `setScalar` 만 사용하고 자체 IO 흐름을 유지한다.
    static func applyScalar(at filePath: String, key: String, value: String?) {
        let url = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return }
        let updated = setScalar(key, to: value, in: content)
        guard updated != content,
              let newData = updated.data(using: .utf8) else { return }
        try? newData.write(to: url, options: .atomic)
    }

    static func setScalar(_ key: String, to value: String?, in source: String) -> String {
        let newline = detectNewline(in: source)
        let lines = source.components(separatedBy: newline)

        // Identify frontmatter block bounds. Must be `---` on the first line
        // and a matching `---` on its own line later.
        guard let firstLine = lines.first,
              firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            return source
        }
        var closeIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closeIndex = i
                break
            }
        }
        guard let close = closeIndex else { return source }

        // Look for an existing top-level `<key>:` line within (1..<close).
        var matchIndex: Int? = nil
        for i in 1..<close {
            if let parsed = parseTopLevelKey(in: lines[i]), parsed == key {
                matchIndex = i
                break
            }
        }

        var newLines = lines

        if let idx = matchIndex {
            if let value = value {
                newLines[idx] = renderLine(key: key, value: value, basedOn: lines[idx])
            } else {
                newLines.remove(at: idx)
            }
        } else {
            guard let value = value else {
                // Key doesn't exist and we're asked to remove — no-op.
                return source
            }
            newLines.insert("\(key): \(serialize(value))", at: close)
        }

        return newLines.joined(separator: newline)
    }

    // MARK: - Helpers

    /// Detect the file's primary line ending. Falls back to `\n` if the
    /// source contains no `\r\n`.
    private static func detectNewline(in source: String) -> String {
        return source.contains("\r\n") ? "\r\n" : "\n"
    }

    /// Returns the bare key if `line` looks like a top-level `key: value`
    /// entry (no leading whitespace, valid identifier-ish key). Returns
    /// nil for list items, comments, indented continuations, etc.
    private static func parseTopLevelKey(in line: String) -> String? {
        guard let first = line.first, first != " ", first != "\t",
              first != "#", first != "-" else {
            return nil
        }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        // Disallow keys containing spaces or quotes — those are unlikely
        // to be top-level frontmatter keys.
        if key.contains(" ") || key.contains("\"") || key.contains("'") {
            return nil
        }
        return key
    }

    /// Render a replacement line preserving the original line's quoting
    /// style when reasonable. Currently keeps it simple: matches the
    /// existing leading whitespace and reuses the prefix up to and
    /// including the colon, then re-serializes the value.
    private static func renderLine(key: String, value: String, basedOn original: String) -> String {
        // Preserve leading whitespace and the original "<key>:" prefix
        // verbatim. Anything after the colon gets replaced with our
        // serialized value, separated by a single space.
        guard let colon = original.firstIndex(of: ":") else {
            return "\(key): \(serialize(value))"
        }
        let prefix = original[...colon]
        return "\(prefix) \(serialize(value))"
    }

    /// Quote the value with double quotes if it contains characters that
    /// would confuse the simple YAML-ish parser. Plain alphanumerics,
    /// hyphens, underscores, slashes, dots, and colons remain unquoted.
    private static func serialize(_ value: String) -> String {
        if value.isEmpty {
            return "\"\""
        }
        if needsQuoting(value) {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private static func needsQuoting(_ value: String) -> Bool {
        if value.contains(" ") || value.contains("\t") || value.contains("\n") {
            return true
        }
        if value.hasPrefix("#") || value.hasPrefix("&") || value.hasPrefix("*")
            || value.hasPrefix("!") || value.hasPrefix("|") || value.hasPrefix(">")
            || value.hasPrefix("'") || value.hasPrefix("\"")
            || value.hasPrefix("[") || value.hasPrefix("{")
            || value.hasPrefix("-") || value.hasPrefix("?") || value.hasPrefix(",")
            || value.hasPrefix("@") || value.hasPrefix("`") {
            return true
        }
        // Bare YAML keywords would change type on round-trip if unquoted.
        let lower = value.lowercased()
        if lower == "true" || lower == "false" || lower == "null" || lower == "yes" || lower == "no" || lower == "~" {
            return true
        }
        return false
    }
}
