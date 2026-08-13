import Foundation

public enum DateKey {
    public static func make(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func compact(_ dateKey: String) -> String {
        dateKey.replacingOccurrences(of: "-", with: "")
    }

    public static func date(from dateKey: String, calendar: Calendar = .current) -> Date? {
        let values = dateKey.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        var parts = DateComponents()
        parts.calendar = calendar
        parts.year = values[0]
        parts.month = values[1]
        parts.day = values[2]
        parts.hour = 12
        return calendar.date(from: parts)
    }

    public static func adding(days: Int, to dateKey: String, calendar: Calendar = .current) -> String? {
        guard let date = date(from: dateKey, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return make(from: shifted, calendar: calendar)
    }

    public static func isValid(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return date(from: value) != nil
    }
}

