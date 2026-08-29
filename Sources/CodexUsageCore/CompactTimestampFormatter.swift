import Foundation

public enum CompactTimestampFormatter {
    private static let cache = CompactDateFormatterCache()

    public static func string(
        for date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let dateFormat: String
        if calendar.isDate(date, inSameDayAs: now) {
            dateFormat = "HH:mm"
        } else if calendar.component(.year, from: date)
            == calendar.component(.year, from: now) {
            dateFormat = "MMM d, HH:mm"
        } else {
            dateFormat = "MMM d, yyyy, HH:mm"
        }

        return cache.string(
            from: date,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone,
            dateFormat: dateFormat
        )
    }
}

private final class CompactDateFormatterCache: @unchecked Sendable {
    private struct Key: Hashable {
        var calendarIdentifier: String
        var localeIdentifier: String
        var timeZoneIdentifier: String
        var dateFormat: String
    }

    private let lock = NSLock()
    private var formatters: [Key: DateFormatter] = [:]

    func string(
        from date: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone,
        dateFormat: String
    ) -> String {
        let key = Key(
            calendarIdentifier: String(describing: calendar.identifier),
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier,
            dateFormat: dateFormat
        )

        lock.lock()
        defer { lock.unlock() }

        let formatter: DateFormatter
        if let cachedFormatter = formatters[key] {
            formatter = cachedFormatter
        } else {
            let newFormatter = DateFormatter()
            newFormatter.calendar = calendar
            newFormatter.locale = locale
            newFormatter.timeZone = timeZone
            newFormatter.dateFormat = dateFormat
            formatters[key] = newFormatter
            formatter = newFormatter
        }
        return formatter.string(from: date)
    }
}
