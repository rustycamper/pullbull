import Foundation

/// One bar of the chart as drawn: points from the chart's leading edge, standing on its baseline.
public struct ReviewBarMark: Equatable, Sendable {
    public let x: CGFloat
    public let width: CGFloat
    public let height: CGFloat
    /// A day with no reviews: the stub on the baseline.
    public let isEmpty: Bool
    public let isToday: Bool

    public init(x: CGFloat, width: CGFloat, height: CGFloat, isEmpty: Bool, isToday: Bool) {
        self.x = x
        self.width = width
        self.height = height
        self.isEmpty = isEmpty
        self.isToday = isToday
    }
}

/// Reviews per local day for the bar chart. A day that may be missing reviews because a cap cut in is
/// `nil`, not 0: missing beats wrong.
public struct ReviewBars: Equatable, Sendable {
    /// One entry per day of the window, oldest first; nil = not loaded.
    public let counts: [Int?]
    /// The last bar, today's.
    public let todayIndex: Int
    private let dayStarts: [Date]
    private let loadedFrom: Date?
    private let total: Int

    private init(counts: [Int?], todayIndex: Int, dayStarts: [Date], loadedFrom: Date?, total: Int) {
        self.counts = counts
        self.todayIndex = todayIndex
        self.dayStarts = dayStarts
        self.loadedFrom = loadedFrom
        self.total = total
    }

    /// `loadedFrom` is nil when nothing was capped; otherwise the first fully loaded day's start, and
    /// every day before it is nil.
    public static func make(reviewDates: [Date], window: StatsWindow, loadedFrom: Date?, calendar: Calendar) -> ReviewBars {
        let starts = window.dayStarts(calendar: calendar)
        var tally = [Int](repeating: 0, count: starts.count)
        var total = 0
        for date in reviewDates where window.contains(date) {
            guard let index = starts.lastIndex(where: { $0 <= date }) else { continue }
            tally[index] += 1
            total += 1
        }
        let counts = zip(starts, tally).map { start, n -> Int? in
            if let loadedFrom, start < loadedFrom { return nil }
            return n
        }
        return ReviewBars(
            counts: counts, todayIndex: max(starts.count - 1, 0), dayStarts: starts, loadedFrom: loadedFrom, total: total)
    }

    /// "12 reviews in the last 7 days, most on Tuesday (4)", with the date for 90 days; the most recent
    /// of tied days wins. Days not loaded add " Days before 3 Oct not loaded".
    public func hover(period: StatsPeriod, calendar: Calendar) -> String {
        let span = "in the last \(period.days) days"
        var text = total == 0 ? "No reviews \(span)" : "\(total) \(total == 1 ? "review" : "reviews") \(span)"
        if total > 0, let busiest = busiestDay() {
            let format = period == .quarter ? "d MMM" : "EEEE"
            text += ", most on \(Self.format(dayStarts[busiest.index], format, calendar)) (\(busiest.count))"
        }
        if counts.contains(where: { $0 == nil }), let loadedFrom {
            text += " Days before \(Self.format(loadedFrom, "d MMM", calendar)) not loaded"
        }
        return text
    }

    /// The space between bars: narrower as there are more, so 90 still fit a card.
    public static func gap(barCount: Int) -> CGFloat {
        barCount >= 90 ? 1 : barCount >= 30 ? 2 : 4
    }

    /// The bars across `width`, oldest first, each as tall as its count against the busiest loaded day's
    /// `height`. A day with reviews is at least 2 pt, so it never passes for the 1-pt stub of a day with
    /// none; a day not loaded draws nothing.
    public func marks(width: CGFloat, height: CGFloat) -> [ReviewBarMark] {
        guard !counts.isEmpty else { return [] }
        let n = CGFloat(counts.count)
        let gap = Self.gap(barCount: counts.count)
        let barWidth = max((width - gap * (n - 1)) / n, 0)
        let busiest = CGFloat(counts.compactMap { $0 }.max() ?? 0)
        return counts.enumerated().compactMap { index, count in
            guard let count else { return nil }
            let barHeight = count == 0 || busiest == 0 ? 1 : max(height * CGFloat(count) / busiest, 2)
            return ReviewBarMark(
                x: CGFloat(index) * (barWidth + gap), width: barWidth, height: min(barHeight, height),
                isEmpty: count == 0, isToday: index == todayIndex)
        }
    }

    private func busiestDay() -> (index: Int, count: Int)? {
        var best: (index: Int, count: Int)?
        for (index, count) in counts.enumerated() {
            guard let count, count > 0, count >= (best?.count ?? 0), index < dayStarts.count else { continue }
            best = (index, count)
        }
        return best
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
