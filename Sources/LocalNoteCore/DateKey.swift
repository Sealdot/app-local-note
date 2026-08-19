import Foundation

public struct CalendarDay: Equatable {
    public let dateKey: String
    public let dayNumber: Int
    public let isInDisplayedMonth: Bool

    public init(dateKey: String, dayNumber: Int, isInDisplayedMonth: Bool) {
        self.dateKey = dateKey
        self.dayNumber = dayNumber
        self.isInDisplayedMonth = isInDisplayedMonth
    }
}

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

    public static func adding(months: Int, to dateKey: String, calendar: Calendar = .current) -> String? {
        guard let date = date(from: dateKey, calendar: calendar) else { return nil }
        var firstComponents = calendar.dateComponents([.year, .month], from: date)
        firstComponents.calendar = calendar
        firstComponents.day = 1
        firstComponents.hour = 12
        guard let firstOfMonth = calendar.date(from: firstComponents),
              let shifted = calendar.date(byAdding: .month, value: months, to: firstOfMonth) else { return nil }
        return make(from: shifted, calendar: calendar)
    }

    /// Returns a stable six-week, Monday-first grid for the month containing
    /// `dateKey`. A fixed 42-day range prevents the popover from changing
    /// height while navigating between months.
    public static func monthGrid(
        containing dateKey: String,
        calendar: Calendar = .current,
        firstWeekday: Int = 2
    ) -> [CalendarDay] {
        guard let date = date(from: dateKey, calendar: calendar) else { return [] }
        let displayed = calendar.dateComponents([.year, .month], from: date)
        var firstComponents = displayed
        firstComponents.calendar = calendar
        firstComponents.day = 1
        firstComponents.hour = 12
        guard let firstOfMonth = calendar.date(from: firstComponents) else { return [] }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDays = (weekday - firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth) else {
            return []
        }

        return (0..<42).compactMap { offset in
            guard let value = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: value)
            return CalendarDay(
                dateKey: make(from: value, calendar: calendar),
                dayNumber: parts.day ?? 0,
                isInDisplayedMonth: parts.year == displayed.year && parts.month == displayed.month
            )
        }
    }

    public static func isValid(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return date(from: value) != nil
    }
}
