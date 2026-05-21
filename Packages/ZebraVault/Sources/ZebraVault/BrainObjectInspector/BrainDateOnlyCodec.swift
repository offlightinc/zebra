import Foundation

enum BrainDateOnlyCodec {
    private static let storageTimeZone = TimeZone(secondsFromGMT: 0)!

    static func date(fromStorageString raw: String, calendar: Calendar = .current) -> Date? {
        guard let source = normalizedStorageString(from: raw),
              let year = Int(source.prefix(4)),
              let month = Int(source.dropFirst(5).prefix(2)),
              let day = Int(source.dropFirst(8).prefix(2)) else {
            return nil
        }
        var normalizedCalendar = Calendar(identifier: .gregorian)
        normalizedCalendar.timeZone = calendar.timeZone
        var components = DateComponents()
        components.calendar = normalizedCalendar
        components.timeZone = normalizedCalendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = normalizedCalendar.date(from: components),
              normalizedCalendar.component(.year, from: date) == year,
              normalizedCalendar.component(.month, from: date) == month,
              normalizedCalendar.component(.day, from: date) == day else {
            return nil
        }
        return date
    }

    static func normalizedStorageString(from raw: String) -> String? {
        let source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePrefix = String(source.prefix(10))
        guard datePrefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return datePrefix
    }

    static func storageString(fromParsedDate date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storageTimeZone
        return storageString(from: date, calendar: calendar)
    }

    static func storageString(fromPickerDate date: Date, calendar: Calendar = .current) -> String {
        var normalizedCalendar = Calendar(identifier: .gregorian)
        normalizedCalendar.timeZone = calendar.timeZone
        return storageString(from: date, calendar: normalizedCalendar)
    }

    private static func storageString(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return storageFallbackFormatter.string(from: date)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static let storageFallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = storageTimeZone
        return formatter
    }()
}
