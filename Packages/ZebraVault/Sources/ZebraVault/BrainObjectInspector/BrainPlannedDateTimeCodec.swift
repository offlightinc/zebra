import Foundation

enum BrainPlannedDateTimeCodec {
    static func date(fromStorageString raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, hasExplicitTimeZone(value) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func validatedInterval(startRaw: String?, endRaw: String?) -> DateInterval? {
        guard let startRaw, let endRaw,
              let start = date(fromStorageString: startRaw),
              let end = date(fromStorageString: endRaw),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func hasAnyBoundary(startRaw: String?, endRaw: String?) -> Bool {
        let start = startRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let end = endRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !start.isEmpty || !end.isEmpty
    }

    private static func hasExplicitTimeZone(_ value: String) -> Bool {
        value.range(of: #"(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil
    }
}
