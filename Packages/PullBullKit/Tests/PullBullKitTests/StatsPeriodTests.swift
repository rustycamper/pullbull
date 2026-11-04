import Foundation
import Testing
@testable import PullBullKit

@Suite struct StatsPeriodTests {
    private func calendar(_ zone: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func weekWindowStartsSixDaysBackAtMidnight() {
        let cal = calendar("Europe/Sofia")
        let now = date(2026, 11, 4, 15, 30, cal)
        let window = StatsPeriod.week.window(now: now, calendar: cal)
        #expect(window.start == date(2026, 10, 29, 0, 0, cal))
        #expect(window.end == now)
    }

    @Test func weekComparisonIsThePrecedingSevenDays() {
        let cal = calendar("Europe/Sofia")
        let now = date(2026, 11, 4, 15, 30, cal)
        let window = StatsPeriod.week.comparisonWindow(now: now, calendar: cal)
        #expect(window.start == date(2026, 10, 22, 0, 0, cal))
        #expect(window.end == date(2026, 10, 29, 0, 0, cal))
    }

    @Test func dayStartsCountMatchesPeriodForBothWindows() {
        let cal = calendar("Europe/Sofia")
        let now = date(2026, 11, 4, 15, 30, cal)
        for period in StatsPeriod.allCases {
            #expect(period.window(now: now, calendar: cal).dayStarts(calendar: cal).count == period.days)
            #expect(period.comparisonWindow(now: now, calendar: cal).dayStarts(calendar: cal).count == period.days)
        }
    }

    @Test func lastDayStartIsToday() {
        let cal = calendar("Europe/Sofia")
        let now = date(2026, 11, 4, 15, 30, cal)
        let days = StatsPeriod.month.window(now: now, calendar: cal).dayStarts(calendar: cal)
        #expect(days.last == date(2026, 11, 4, 0, 0, cal))
    }

    @Test func windowIsHalfOpen() {
        let cal = calendar("Europe/Sofia")
        let now = date(2026, 11, 4, 15, 30, cal)
        let window = StatsPeriod.week.window(now: now, calendar: cal)
        #expect(window.contains(window.start))
        #expect(!window.contains(window.end))
        #expect(!window.contains(window.start.addingTimeInterval(-1)))
        let previous = StatsPeriod.week.comparisonWindow(now: now, calendar: cal)
        #expect(!previous.contains(window.start))
    }

    @Test func githubEndIsOneSecondBeforeEnd() {
        let cal = calendar("Europe/Sofia")
        let window = StatsPeriod.week.window(now: date(2026, 11, 4, 15, 30, cal), calendar: cal)
        #expect(window.githubEnd == window.end.addingTimeInterval(-1))
    }

    @Test func dayStartsSurviveDaylightSavingChange() {
        let cal = calendar("America/New_York")
        let now = date(2026, 11, 4, 12, 0, cal)
        let days = StatsPeriod.week.window(now: now, calendar: cal).dayStarts(calendar: cal)
        #expect(days.count == 7)
        for day in days {
            let parts = cal.dateComponents([.hour, .minute], from: day)
            #expect(parts.hour == 0 && parts.minute == 0)
        }
        let dates = days.map { cal.dateComponents([.year, .month, .day], from: $0) }
        let expected = [(10, 29), (10, 30), (10, 31), (11, 1), (11, 2), (11, 3), (11, 4)]
        #expect(dates.map { $0.month! } == expected.map(\.0))
        #expect(dates.map { $0.day! } == expected.map(\.1))
        let gaps = zip(days, days.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect(gaps.contains(90_000))
    }

    @Test func titlesDaysAndComparisonNames() {
        #expect(StatsPeriod.allCases.map(\.days) == [7, 30, 90])
        #expect(StatsPeriod.allCases.map(\.title) == ["This week", "This month", "90 days"])
        #expect(StatsPeriod.allCases.map(\.comparisonName) == ["last week", "last month", "previous 90 days"])
    }

    @Test func arrowsStepThroughTheChipsWithoutWrapping() {
        #expect(ListNavigation.tab(StatsPeriod.week, movedBy: 1) == .month)
        #expect(ListNavigation.tab(StatsPeriod.month, movedBy: 1) == .quarter)
        #expect(ListNavigation.tab(StatsPeriod.quarter, movedBy: 1) == .quarter)
        #expect(ListNavigation.tab(StatsPeriod.quarter, movedBy: -1) == .month)
        #expect(ListNavigation.tab(StatsPeriod.week, movedBy: -1) == .week)
    }

    @Test func comparisonText() {
        #expect(StatsComparison.text("5 h", period: .quarter) == "previous 90 days 5 h")
        #expect(StatsComparison.text("5 h", period: .week) == "last week 5 h")
    }
}
