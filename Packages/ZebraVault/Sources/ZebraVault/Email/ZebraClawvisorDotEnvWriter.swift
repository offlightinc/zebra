import Foundation

/// Merges Clawvisor key updates into `~/.gbrain/.env` while preserving every
/// other key the file already holds.
///
/// `ZebraClawvisorEmailClient` reads that file at first config load (see
/// `readDotEnv` in the client). The user-facing settings view writes through
/// this helper so non-Clawvisor entries (e.g. brain CLI keys, OpenAI tokens)
/// stay intact when the user pastes new Clawvisor credentials.
public enum ZebraClawvisorDotEnvWriter {
    public enum WriteError: LocalizedError {
        case homeDirectoryUnreachable
        case fileError(String)

        public var errorDescription: String? {
            switch self {
            case .homeDirectoryUnreachable:
                return "Could not locate the home directory to write ~/.gbrain/.env."
            case .fileError(let detail):
                return "Failed to write ~/.gbrain/.env: \(detail)"
            }
        }
    }

    /// Merge `updates` into `~/.gbrain/.env`. Empty-string values delete the
    /// key. Keys not present in `updates` are left untouched. New keys are
    /// appended in the order callers pass them.
    public static func update(_ updates: KeyValuePairs<String, String>) throws {
        let fileURL = try dotEnvURL()
        var existing = parse(contentsOf: fileURL)
        var keyOrder = existing.map { $0.0 }
        var keyValues: [String: String] = Dictionary(uniqueKeysWithValues: existing)
        for (key, value) in updates {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if keyValues.removeValue(forKey: key) != nil {
                    keyOrder.removeAll { $0 == key }
                }
            } else {
                if keyValues[key] == nil {
                    keyOrder.append(key)
                }
                keyValues[key] = trimmed
            }
        }
        existing = keyOrder.compactMap { key in
            guard let value = keyValues[key] else { return nil }
            return (key, value)
        }
        try write(existing, to: fileURL)
    }

    private static func dotEnvURL() throws -> URL {
        let homePath = NSHomeDirectory()
        guard !homePath.isEmpty else {
            throw WriteError.homeDirectoryUnreachable
        }
        let directory = URL(fileURLWithPath: homePath)
            .appendingPathComponent(".gbrain", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw WriteError.fileError(error.localizedDescription)
        }
        return directory.appendingPathComponent(".env", isDirectory: false)
    }

    /// Parses `~/.gbrain/.env` into an ordered key/value list. Tolerates the
    /// same dialect the client reads (`KEY=VALUE`, optional `export `, simple
    /// quoting). Comments and unparseable lines are dropped — callers should
    /// not depend on them being preserved.
    private static func parse(contentsOf url: URL) -> [(String, String)] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [(String, String)] = []
        var seen: Set<String> = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("#") { continue }
            if text.hasPrefix("export ") {
                text = String(text.dropFirst("export ".count))
            }
            guard let equals = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            var value = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            seen.insert(key)
            result.append((key, value))
        }
        return result
    }

    private static func write(_ pairs: [(String, String)], to url: URL) throws {
        let body = pairs
            .map { "\($0.0)=\(escapeValue($0.1))" }
            .joined(separator: "\n")
        let contents = body.isEmpty ? "" : body + "\n"
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw WriteError.fileError(error.localizedDescription)
        }
    }

    private static func escapeValue(_ value: String) -> String {
        // Wrap in double quotes only when the value carries a character that
        // would otherwise confuse a shell-style dotenv reader. Plain tokens
        // (URLs, base64, hex ids) stay unquoted to match how the file is
        // usually hand-edited.
        let suspicious: Set<Character> = [" ", "\t", "\"", "'", "#", "$"]
        if value.contains(where: suspicious.contains) {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
