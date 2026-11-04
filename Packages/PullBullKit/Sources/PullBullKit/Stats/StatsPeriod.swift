import Foundation

/// The span a Stats screen covers: whole local days ending with today.
public enum StatsPeriod: String, CaseIterable, Codable, Sendable {
    case week, month, quarter

    public var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    public var title: String {
        switch self {
        case .week: "This week"
        case .month: "This month"
        case .quarter: "90 days"
        }
    }

    /// How the previous span is named next to a value: "last week 5 h".
    public var comparisonName: String {
        switch self {
        case .week: "last week"
        case .month: "last month"
        case .quarter: "previous 90 days"
        }
    }
}

/// A half-open span of time, `start <= t < end`, so a moment on the boundary
/// belongs to exactly one of two neighbouring windows.
public struct StatsWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }

    /// GitHub's date ranges include both ends, so it is asked for one second less.
    public var githubEnd: Date { end.addingTimeInterval(-1) }

    /// Every local midnight from `start` while before `end`, one per bar.
    /// Steps by calendar days so a daylight saving change cannot shift a bar.
    public func dayStarts(calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = start
        while day < end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

extension StatsPeriod {
    /// Today and the days before it, from local midnight of the first day until now.
    public func window(now: Date, calendar: Calendar) -> StatsWindow {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return StatsWindow(start: start, end: now)
    }

    /// The same number of whole days just before `window`, ending where it starts.
    public func comparisonWindow(now: Date, calendar: Calendar) -> StatsWindow {
        let current = window(now: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -days, to: current.start) ?? current.start
        return StatsWindow(start: start, end: current.start)
    }
}

public enum StatsComparison {
    /// "last week 5 h", "previous 90 days 2 d 4 h".
    public static func text(_ value: String, period: StatsPeriod) -> String {
        "\(period.comparisonName) \(value)"
    }
}
