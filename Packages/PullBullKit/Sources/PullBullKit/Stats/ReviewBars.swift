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

/// A label under the chart, for the bar at `index`.
public struct ReviewBarLabel: Equatable, Sendable {
    public let index: Int
    public let text: String

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
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
    private let capped: Bool
    private let total: Int

    private init(counts: [Int?], todayIndex: Int, dayStarts: [Date], loadedFrom: Date?, capped: Bool, total: Int) {
        self.counts = counts
        self.todayIndex = todayIndex
        self.dayStarts = dayStarts
        self.loadedFrom = loadedFrom
        self.capped = capped
        self.total = total
    }

    /// `loadedFrom` is the first fully loaded day's start when a cap cut in, and every day before it is
    /// nil; a `loadedFrom` implies `capped`. Capped with no `loadedFrom` means nothing in the window was
    /// loaded, so every day is nil.
    public static func make(
        reviewDates: [Date], window: StatsWindow, loadedFrom: Date?, capped: Bool = false, calendar: Calendar
    ) -> ReviewBars {
        let capped = capped || loadedFrom != nil
        let starts = window.dayStarts(calendar: calendar)
        var tally = [Int](repeating: 0, count: starts.count)
        var total = 0
        for date in reviewDates where window.contains(date) {
            guard let index = starts.lastIndex(where: { $0 <= date }) else { continue }
            tally[index] += 1
            total += 1
        }
        let counts = zip(starts, tally).map { start, n -> Int? in
            if capped, loadedFrom.map({ start < $0 }) ?? true { return nil }
            return n
        }
        return ReviewBars(
            counts: counts, todayIndex: max(starts.count - 1, 0), dayStarts: starts, loadedFrom: loadedFrom,
            capped: capped, total: total)
    }

    /// "12 reviews in the last 7 days, most on Tuesday (4)", with the date for 90 days; the most recent
    /// of tied days wins. Capped, the total reads "12+ reviews", and days not loaded add
    /// ". Days before 3 Oct not loaded", or ". No day fully loaded" when not even today is.
    public func hover(period: StatsPeriod, calendar: Calendar) -> String {
        let span = "in the last \(period.days) days"
        var text: String
        if capped {
            text = "\(total)+ reviews \(span)"
        } else {
            text = total == 0 ? "No reviews \(span)" : "\(total) \(total == 1 ? "review" : "reviews") \(span)"
        }
        if let busiest {
            let format = period == .quarter ? "d MMM" : "EEEE"
            text += ", most on \(Self.format(dayStarts[busiest.index], format, calendar)) (\(busiest.count))"
        }
        if counts.contains(where: { $0 == nil }), let loadedFrom {
            if let today = dayStarts.last, loadedFrom > today {
                text += ". No day fully loaded"
            } else {
                text += ". Days before \(Self.format(loadedFrom, "d MMM", calendar)) not loaded"
            }
        }
        return text
    }

    /// The space between bars: narrower as there are more, so 90 still fit a card.
    public static func gap(barCount: Int) -> CGFloat {
        barCount >= 90 ? 1 : barCount >= 30 ? 2 : 4
    }

    /// The widest a bar gets, so 7 bars stay bars rather than slabs.
    public static let maxBarWidth: CGFloat = 14

    /// The bars across `width`, oldest first, each as tall as its count against the busiest loaded day's
    /// `height`. A day with reviews is at least 2 pt, so it never passes for the 1-pt stub of a day with
    /// none; a day not loaded draws nothing. Bars are at most `maxBarWidth` wide, and when that cap
    /// applies they spread across `width` with equal gaps, the first at 0 and the last ending at `width`
    /// (a single bar is centred).
    public func marks(width: CGFloat, height: CGFloat) -> [ReviewBarMark] {
        guard !counts.isEmpty else { return [] }
        let layout = layout(width: width)
        let busiest = CGFloat(counts.compactMap { $0 }.max() ?? 0)
        return counts.enumerated().compactMap { index, count in
            guard let count else { return nil }
            let barHeight = count == 0 || busiest == 0 ? 1 : max(height * CGFloat(count) / busiest, 2)
            return ReviewBarMark(
                x: layout.x(of: index), width: layout.barWidth, height: min(barHeight, height),
                isEmpty: count == 0, isToday: index == todayIndex)
        }
    }

    /// The middle of the bar at `index` across `width`, laid out as `marks` lays it out, whether or not
    /// that day is loaded.
    public func centerX(of index: Int, width: CGFloat) -> CGFloat {
        let layout = layout(width: width)
        return layout.x(of: index) + layout.barWidth / 2
    }

    /// From the first bar's leading edge to the last bar's trailing edge, across `width`.
    public func extent(width: CGFloat) -> ClosedRange<CGFloat> {
        guard !counts.isEmpty else { return 0...0 }
        let layout = layout(width: width)
        return layout.x(of: 0)...(layout.x(of: counts.count - 1) + layout.barWidth)
    }

    /// The day with the most reviews; the most recent of tied days wins. Nil when no loaded day has any.
    public var busiest: (index: Int, count: Int)? {
        var best: (index: Int, count: Int)?
        for (index, count) in counts.enumerated() {
            guard let count, count > 0, count >= (best?.count ?? 0), index < dayStarts.count else { continue }
            best = (index, count)
        }
        return best
    }

    /// The labels under the chart, in English like the hover; `calendar` gives only the days. For 7
    /// days, every day's weekday initial ("T F S S M T W"); for 30 and 90, the first and last days' dates
    /// ("6 Oct", "4 Nov"). A day not loaded is labelled all the same.
    public func axisLabels(period: StatsPeriod, calendar: Calendar) -> [ReviewBarLabel] {
        guard let first = dayStarts.first, let last = dayStarts.last else { return [] }
        if period == .week {
            return dayStarts.enumerated().map { index, day in
                ReviewBarLabel(index: index, text: Self.format(day, "EEEEE", calendar))
            }
        }
        let lastIndex = dayStarts.count - 1
        let start = ReviewBarLabel(index: 0, text: Self.format(first, "d MMM", calendar))
        guard lastIndex > 0 else { return [start] }
        return [start, ReviewBarLabel(index: lastIndex, text: Self.format(last, "d MMM", calendar))]
    }

    private struct Layout {
        let origin: CGFloat
        let barWidth: CGFloat
        let gap: CGFloat

        func x(of index: Int) -> CGFloat { origin + CGFloat(index) * (barWidth + gap) }
    }

    private func layout(width: CGFloat) -> Layout {
        let n = CGFloat(max(counts.count, 1))
        let gap = Self.gap(barCount: counts.count)
        let fitted = max((width - gap * (n - 1)) / n, 0)
        guard fitted > Self.maxBarWidth else { return Layout(origin: 0, barWidth: fitted, gap: gap) }
        guard n > 1 else { return Layout(origin: (width - Self.maxBarWidth) / 2, barWidth: Self.maxBarWidth, gap: gap) }
        return Layout(origin: 0, barWidth: Self.maxBarWidth, gap: (width - n * Self.maxBarWidth) / (n - 1))
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
