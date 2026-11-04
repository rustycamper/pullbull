import Foundation
import Testing
@testable import PullBullKit

@Suite struct ReviewBarsTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    // Tuesday 2025-10-14 is today; the week starts Wednesday 8 Oct.
    var now: Date { Date(timeIntervalSince1970: 1_760_443_200) }  // 2025-10-14 12:00 UTC
    func window(_ p: StatsPeriod) -> StatsWindow { p.window(now: now, calendar: cal) }
    func day(_ i: Int, _ p: StatsPeriod = .week) -> Date {
        window(p).dayStarts(calendar: cal)[i].addingTimeInterval(3600)
    }

    @Test func counts() {
        let bars = ReviewBars.make(reviewDates: [day(0), day(0), day(6)], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.counts == [2, 0, 0, 0, 0, 0, 1])
        #expect(bars.todayIndex == 6)
    }

    @Test func notLoadedDaysAreNil() {
        let w = window(.week)
        let bars = ReviewBars.make(reviewDates: [day(4)], window: w, loadedFrom: w.dayStarts(calendar: cal)[3], calendar: cal)
        #expect(bars.counts == [nil, nil, nil, 0, 1, 0, 0])
    }

    @Test func hoverWeek() {
        let bars = ReviewBars.make(reviewDates: [day(0), day(0), day(6)], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.hover(period: .week, calendar: cal) == "3 reviews in the last 7 days, most on Wednesday (2)")
    }

    @Test func hoverSingular() {
        let bars = ReviewBars.make(reviewDates: [day(2)], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.hover(period: .week, calendar: cal) == "1 review in the last 7 days, most on Friday (1)")
    }

    @Test func tieGoesToMostRecentDay() {
        let bars = ReviewBars.make(reviewDates: [day(0), day(3)], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.hover(period: .week, calendar: cal) == "2 reviews in the last 7 days, most on Saturday (1)")
    }

    @Test func hoverQuarterUsesDate() {
        let dates = [day(80, .quarter), day(80, .quarter), day(5, .quarter)]
        let bars = ReviewBars.make(reviewDates: dates, window: window(.quarter), loadedFrom: nil, calendar: cal)
        #expect(bars.counts.count == 90)
        #expect(bars.hover(period: .quarter, calendar: cal) == "3 reviews in the last 90 days, most on 5 Oct (2)")
    }

    @Test func hoverNone() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.month), loadedFrom: nil, calendar: cal)
        #expect(bars.hover(period: .month, calendar: cal) == "No reviews in the last 30 days")
    }

    @Test func hoverCapped() {
        let w = window(.week)
        let from = w.dayStarts(calendar: cal)[2]
        let bars = ReviewBars.make(reviewDates: [day(4)], window: w, loadedFrom: from, calendar: cal)
        #expect(bars.hover(period: .week, calendar: cal)
                == "1+ reviews in the last 7 days, most on Sunday (1). Days before 10 Oct not loaded")
    }

    @Test func hoverCappedReadsNPlusWithEveryDayLoaded() {
        let w = window(.week)
        let bars = ReviewBars.make(reviewDates: [day(0), day(4), day(4)], window: w,
                                   loadedFrom: w.dayStarts(calendar: cal)[0], calendar: cal)
        #expect(bars.counts == [1, 0, 0, 0, 2, 0, 0])
        #expect(bars.hover(period: .week, calendar: cal) == "3+ reviews in the last 7 days, most on Sunday (2)")
    }

    @Test func hoverCappedLoadedFromTomorrowSaysNoDayLoaded() {
        let w = window(.week)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: w.dayStarts(calendar: cal)[6])!
        let bars = ReviewBars.make(reviewDates: [day(4), day(6)], window: w, loadedFrom: tomorrow, calendar: cal)
        #expect(bars.counts == Array(repeating: nil, count: 7))
        #expect(bars.hover(period: .week, calendar: cal) == "2+ reviews in the last 7 days. No day fully loaded")
    }

    @Test func hoverCappedLoadedFromTodayNamesToday() {
        let w = window(.week)
        let bars = ReviewBars.make(reviewDates: [day(6)], window: w, loadedFrom: w.dayStarts(calendar: cal)[6], calendar: cal)
        #expect(bars.counts == [nil, nil, nil, nil, nil, nil, 1])
        #expect(bars.hover(period: .week, calendar: cal)
                == "1+ reviews in the last 7 days, most on Tuesday (1). Days before 14 Oct not loaded")
    }

    @Test func cappedWithNothingLoadedDrawsNoBars() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, capped: true, calendar: cal)
        #expect(bars.counts == Array(repeating: nil, count: 7))
        #expect(bars.marks(width: 80, height: 20).isEmpty)
        #expect(bars.hover(period: .week, calendar: cal) == "0+ reviews in the last 7 days")
    }

    @Test func gapNarrowsWithMoreBars() {
        #expect(ReviewBars.gap(barCount: 7) == 6)
        #expect(ReviewBars.gap(barCount: 30) == 2)
        #expect(ReviewBars.gap(barCount: 90) == 1)
    }

    @Test func marksScaleToTheBusiestDayWithStubsForNone() {
        let bars = ReviewBars.make(reviewDates: [day(0), day(0), day(0), day(0), day(2), day(6)],
                                   window: window(.week), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 78, height: 20)
        #expect(marks.count == 7)
        #expect(marks.map(\.width) == Array(repeating: 6, count: 7))
        #expect(marks.map(\.x) == [0, 12, 24, 36, 48, 60, 72])
        #expect(marks.map(\.height) == [20, 1, 5, 1, 1, 1, 5])
        #expect(marks.map(\.isEmpty) == [false, true, false, true, true, true, false])
        #expect(marks.map(\.isToday) == [false, false, false, false, false, false, true])
    }

    @Test func aDayWithReviewsIsTallerThanAStub() {
        let dates = Array(repeating: day(0), count: 40) + [day(1)]
        let marks = ReviewBars.make(reviewDates: dates, window: window(.week), loadedFrom: nil, calendar: cal)
            .marks(width: 80, height: 20)
        #expect(marks[1].height == 2)
    }

    @Test func noReviewsAreAllStubs() {
        let marks = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, calendar: cal)
            .marks(width: 80, height: 20)
        #expect(marks.allSatisfy { $0.isEmpty && $0.height == 1 })
    }

    @Test func ninetyBarsFitTheWidth() {
        let marks = ReviewBars.make(reviewDates: [day(89, .quarter)], window: window(.quarter), loadedFrom: nil, calendar: cal)
            .marks(width: 312, height: 20)
        #expect(marks.count == 90)
        let last = marks[89]
        #expect(abs(last.x + last.width - 312) < 0.001)
        #expect(last.isToday)
        #expect(last.height == 20)
    }

    @Test func ninetyBarsStayWithinAVeryNarrowWidth() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.quarter), loadedFrom: nil, calendar: cal)
        let extent = bars.extent(width: 60)
        #expect(extent.lowerBound >= 0)
        #expect(extent.upperBound <= 60.001)
        #expect(bars.marks(width: 60, height: 20).allSatisfy { $0.width >= 0 && $0.x + $0.width <= 60.001 })
        #expect(bars.day(at: 60, width: 60) == 89)
    }

    @Test func ninetyMarksAgreeWithDayAtANonIntegralWidth() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.quarter), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 301.5, height: 20)
        #expect(marks.count == 90)
        for mark in marks {
            #expect(bars.day(at: mark.x + mark.width / 2, width: 301.5) == mark.index)
        }
    }

    @Test func daysNotLoadedDrawNothing() {
        let w = window(.week)
        let bars = ReviewBars.make(reviewDates: [day(4)], window: w, loadedFrom: w.dayStarts(calendar: cal)[3], calendar: cal)
        let marks = bars.marks(width: 78, height: 20)
        #expect(marks.map(\.index) == [3, 4, 5, 6])
        #expect(marks.map(\.x) == [36, 48, 60, 72])
        #expect(marks.map(\.height) == [1, 20, 1, 1])
    }

    // MARK: Busiest day

    @Test func busiestTieGoesToTheMostRecentDay() {
        let bars = ReviewBars.make(reviewDates: [day(0), day(0), day(4), day(4), day(5)],
                                   window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.busiest?.index == 4)
        #expect(bars.busiest?.count == 2)
    }

    @Test func busiestIsNilWhenEveryDayIsZero() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.busiest == nil)
    }

    @Test func busiestIsNilWhenNoDayIsLoaded() {
        let bars = ReviewBars.make(reviewDates: [day(3)], window: window(.week), loadedFrom: nil, capped: true, calendar: cal)
        #expect(bars.counts == Array(repeating: nil, count: 7))
        #expect(bars.busiest == nil)
    }

    // MARK: Bar widths

    @Test func weekBarsFillTheCard() {
        let bars = ReviewBars.make(reviewDates: [day(5)], window: window(.week), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 300, height: 36)
        let width = (300 - 36) / CGFloat(7)
        #expect(marks.count == 7)
        #expect(marks.allSatisfy { abs($0.width - width) < 0.001 })
        #expect(abs(marks[0].x) < 0.001)
        for (a, b) in zip(marks, marks.dropFirst()) {
            #expect(abs(b.x - (a.x + a.width) - 6) < 0.001)
        }
        #expect(abs(marks[6].x + marks[6].width - 300) < 0.001)
    }

    @Test func quarterBarsFillTheCard() {
        let bars = ReviewBars.make(reviewDates: [day(89, .quarter)], window: window(.quarter), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 300, height: 36)
        let width = (300 - 89) / CGFloat(90)
        #expect(marks.count == 90)
        #expect(marks[0].x == 0)
        #expect(marks.allSatisfy { abs($0.width - width) < 0.001 })
        #expect(abs(marks[89].x + marks[89].width - 300) < 0.001)
    }

    @Test func monthBarsFillTheCard() {
        let bars = ReviewBars.make(reviewDates: [day(29, .month)], window: window(.month), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 300, height: 36)
        let width = (300 - 58) / CGFloat(30)
        #expect(marks.count == 30)
        #expect(abs(marks[0].x) < 0.001)
        #expect(marks.allSatisfy { abs($0.width - width) < 0.001 })
        #expect(abs(marks[29].x + marks[29].width - 300) < 0.001)
    }

    @Test func centerXIsTheMiddleOfEachMark() {
        for period in StatsPeriod.allCases {
            let bars = ReviewBars.make(reviewDates: [day(1, period)], window: window(period), loadedFrom: nil, calendar: cal)
            for (index, mark) in bars.marks(width: 300, height: 36).enumerated() {
                #expect(abs(bars.centerX(of: index, width: 300) - (mark.x + mark.width / 2)) < 0.001)
            }
        }
    }

    @Test func centerXCoversDaysNotLoaded() {
        let w = window(.week)
        let bars = ReviewBars.make(reviewDates: [day(4)], window: w, loadedFrom: w.dayStarts(calendar: cal)[3], calendar: cal)
        let first = bars.marks(width: 300, height: 36)[0]
        #expect(abs(bars.centerX(of: 0, width: 300) - (264.0 / 7) / 2) < 0.001)
        #expect(abs(bars.centerX(of: 3, width: 300) - (first.x + first.width / 2)) < 0.001)
    }

    @Test func extentRunsFromTheFirstBarToTheLast() {
        let week = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, calendar: cal)
        let weekExtent = week.extent(width: 300)
        #expect(abs(weekExtent.lowerBound) < 0.001)
        #expect(abs(weekExtent.upperBound - 300) < 0.001)
        let month = ReviewBars.make(reviewDates: [], window: window(.month), loadedFrom: nil, calendar: cal)
        let extent = month.extent(width: 300)
        #expect(abs(extent.lowerBound) < 0.001)
        #expect(abs(extent.upperBound - 300) < 0.001)
    }

    // MARK: Axis labels

    /// en_US_POSIX in UTC; today is Wednesday 4 Nov 2026.
    var posix: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    var nov4: Date { posix.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }

    @Test func weekLabelsAreWeekdayInitials() {
        let bars = ReviewBars.make(reviewDates: [], window: StatsPeriod.week.window(now: nov4, calendar: posix),
                                   loadedFrom: nil, calendar: posix)
        let labels = bars.axisLabels(period: .week, calendar: posix)
        #expect(labels.map(\.index) == Array(0..<7))
        #expect(labels.map(\.text) == ["T", "F", "S", "S", "M", "T", "W"])
    }

    @Test func weekLabelsAreEnglishWhateverTheCalendarsLocale() {
        var german = posix
        german.locale = Locale(identifier: "de_DE")
        german.firstWeekday = 2
        let bars = ReviewBars.make(reviewDates: [], window: StatsPeriod.week.window(now: nov4, calendar: german),
                                   loadedFrom: nil, calendar: german)
        #expect(bars.axisLabels(period: .week, calendar: german).map(\.text) == ["T", "F", "S", "S", "M", "T", "W"])
    }

    /// New York, where daylight saving ends on Sunday 1 Nov 2026, inside the week.
    var newYork: Calendar {
        var c = posix
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    var nov4NewYork: Date { newYork.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }

    @Test func weekLabelsAcrossTheEndOfDaylightSaving() {
        let bars = ReviewBars.make(reviewDates: [], window: StatsPeriod.week.window(now: nov4NewYork, calendar: newYork),
                                   loadedFrom: nil, calendar: newYork)
        #expect(bars.axisLabels(period: .week, calendar: newYork).map(\.text) == ["T", "F", "S", "S", "M", "T", "W"])
    }

    @Test func monthLabelsAcrossTheEndOfDaylightSaving() {
        let bars = ReviewBars.make(reviewDates: [], window: StatsPeriod.month.window(now: nov4NewYork, calendar: newYork),
                                   loadedFrom: nil, calendar: newYork)
        #expect(bars.axisLabels(period: .month, calendar: newYork)
                == [ReviewBarLabel(index: 0, text: "6 Oct"), ReviewBarLabel(index: 29, text: "4 Nov")])
    }

    @Test func monthLabelsAreTheFirstAndLastDates() {
        let bars = ReviewBars.make(reviewDates: [], window: StatsPeriod.month.window(now: nov4, calendar: posix),
                                   loadedFrom: nil, calendar: posix)
        #expect(bars.axisLabels(period: .month, calendar: posix)
                == [ReviewBarLabel(index: 0, text: "6 Oct"), ReviewBarLabel(index: 29, text: "4 Nov")])
    }

    @Test func quarterLabelsAreTheFirstAndLastDates() {
        let bars = ReviewBars.make(reviewDates: [], window: StatsPeriod.quarter.window(now: nov4, calendar: posix),
                                   loadedFrom: nil, calendar: posix)
        #expect(bars.axisLabels(period: .quarter, calendar: posix)
                == [ReviewBarLabel(index: 0, text: "7 Aug"), ReviewBarLabel(index: 89, text: "4 Nov")])
    }

    @Test func daysNotLoadedStillGetLabels() {
        let w = StatsPeriod.week.window(now: nov4, calendar: posix)
        let bars = ReviewBars.make(reviewDates: [], window: w, loadedFrom: nil, capped: true, calendar: posix)
        #expect(bars.axisLabels(period: .week, calendar: posix).map(\.text) == ["T", "F", "S", "S", "M", "T", "W"])
        let month = ReviewBars.make(reviewDates: [], window: StatsPeriod.month.window(now: nov4, calendar: posix),
                                    loadedFrom: nil, capped: true, calendar: posix)
        #expect(month.axisLabels(period: .month, calendar: posix).map(\.text) == ["6 Oct", "4 Nov"])
    }

    // MARK: Hovered day

    @Test func dayAtTheEdgesOfAWeek() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.day(at: 0, width: 300) == 0)
        #expect(bars.day(at: 300, width: 300) == 6)
    }

    @Test func dayAtTheMidpointOfAGapIsTheLaterDay() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 300, height: 36)
        for index in 1..<7 {
            let midpoint = (marks[index - 1].x + marks[index - 1].width + marks[index].x) / 2
            #expect(bars.day(at: midpoint, width: 300) == index)
            #expect(bars.day(at: midpoint - 0.01, width: 300) == index - 1)
        }
    }

    @Test func dayInsideEachBarIsThatBar() {
        let bars = ReviewBars.make(reviewDates: [day(2)], window: window(.week), loadedFrom: nil, calendar: cal)
        for (index, mark) in bars.marks(width: 300, height: 36).enumerated() {
            #expect(bars.day(at: mark.x + 0.01, width: 300) == index)
            #expect(bars.day(at: mark.x + mark.width / 2, width: 300) == index)
            #expect(bars.day(at: mark.x + mark.width - 0.01, width: 300) == index)
        }
    }

    @Test func dayCoversDaysNotLoaded() {
        let w = window(.week)
        let bars = ReviewBars.make(reviewDates: [day(4)], window: w, loadedFrom: w.dayStarts(calendar: cal)[3], calendar: cal)
        #expect(bars.counts[0...2] == [nil, nil, nil])
        for index in 0..<3 {
            #expect(bars.day(at: bars.centerX(of: index, width: 300), width: 300) == index)
        }
        #expect(bars.day(at: 0, width: 300) == 0)
        let none = ReviewBars.make(reviewDates: [], window: w, loadedFrom: nil, capped: true, calendar: cal)
        #expect(none.counts == Array(repeating: nil, count: 7))
        #expect(none.day(at: none.centerX(of: 5, width: 300), width: 300) == 5)
    }

    @Test func dayAtOneDayIsThatDayAcrossTheWidth() {
        let start = cal.startOfDay(for: now)
        let w = StatsWindow(start: start, end: cal.date(byAdding: .day, value: 1, to: start)!)
        let bars = ReviewBars.make(reviewDates: [now], window: w, loadedFrom: nil, calendar: cal)
        #expect(bars.counts == [1])
        for x in stride(from: CGFloat(0), through: 300, by: 12.5) {
            #expect(bars.day(at: x, width: 300) == 0)
        }
        #expect(bars.day(at: 300, width: 300) == 0)
    }

    @Test func dayAcrossThirtyDays() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.month), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 300, height: 36)
        #expect(marks.count == 30)
        #expect(bars.day(at: 0, width: 300) == 0)
        #expect(bars.day(at: 300, width: 300) == 29)
        for (index, mark) in marks.enumerated() {
            #expect(bars.day(at: mark.x + mark.width / 2, width: 300) == index)
        }
        for index in 1..<30 {
            let midpoint = (marks[index - 1].x + marks[index - 1].width + marks[index].x) / 2
            #expect(bars.day(at: midpoint, width: 300) == index)
        }
    }

    @Test func dayAtFixedPoints() {
        // 7 bars in 78 pt with 6-pt gaps: each bar is 6 wide, the first gap runs 6...12, its middle is 9.
        let bars = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.marks(width: 78, height: 20).map(\.width) == Array(repeating: 6, count: 7))
        #expect(bars.day(at: 9, width: 78) == 1)
        #expect(bars.day(at: 8.99, width: 78) == 0)
        #expect(bars.day(at: 21, width: 78) == 2)
        #expect(bars.day(at: 20.99, width: 78) == 1)
        #expect(bars.day(at: 78, width: 78) == 6)
    }

    @Test func dayAcrossNinetyDays() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.quarter), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 300, height: 36)
        #expect(bars.day(at: 0, width: 300) == 0)
        #expect(bars.day(at: 300, width: 300) == 89)
        for (index, mark) in marks.enumerated() {
            #expect(bars.day(at: mark.x + mark.width / 2, width: 300) == index)
        }
        let midpoint = (marks[44].x + marks[44].width + marks[45].x) / 2
        #expect(bars.day(at: midpoint, width: 300) == 45)
    }

    @Test func dayOutsideTheWidthIsNil() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, calendar: cal)
        #expect(bars.day(at: -0.5, width: 300) == nil)
        #expect(bars.day(at: 300.5, width: 300) == nil)
        #expect(bars.day(at: -100, width: 300) == nil)
        #expect(bars.day(at: 1000, width: 300) == nil)
    }

    /// The week ending Wednesday 4 Nov 2026: Thu 29 Oct … Wed 4 Nov.
    func weekBars(_ calendar: Calendar, now: Date, reviewDays: [Int], loadedFromDay: Int? = nil) -> ReviewBars {
        let w = StatsPeriod.week.window(now: now, calendar: calendar)
        let starts = w.dayStarts(calendar: calendar)
        return ReviewBars.make(reviewDates: reviewDays.map { starts[$0].addingTimeInterval(3600) }, window: w,
                               loadedFrom: loadedFromDay.map { starts[$0] }, calendar: calendar)
    }

    @Test func dayTextForALoadedDay() {
        let bars = weekBars(posix, now: nov4, reviewDays: [0, 2, 2])
        #expect(bars.dayText(at: 0, calendar: posix) == "1 · Thu 29 Oct")
        #expect(bars.dayText(at: 2, calendar: posix) == "2 · Sat 31 Oct")
    }

    @Test func dayTextForAZeroDay() {
        let bars = weekBars(posix, now: nov4, reviewDays: [0])
        #expect(bars.dayText(at: 1, calendar: posix) == "0 · Fri 30 Oct")
    }

    @Test func dayTextForADayNotLoaded() {
        let bars = weekBars(posix, now: nov4, reviewDays: [0, 4], loadedFromDay: 3)
        #expect(bars.counts == [nil, nil, nil, 0, 1, 0, 0])
        #expect(bars.dayText(at: 0, calendar: posix) == "Not loaded · Thu 29 Oct")
        #expect(bars.dayText(at: 4, calendar: posix) == "1 · Mon 2 Nov")
    }

    @Test func dayTextForToday() {
        let bars = weekBars(posix, now: nov4, reviewDays: [6, 6, 6])
        #expect(bars.dayText(at: bars.todayIndex, calendar: posix) == "3 · Wed 4 Nov")
    }

    @Test func dayTextIsEnglishWhateverTheCalendarsLocale() {
        var german = posix
        german.locale = Locale(identifier: "de_DE")
        german.firstWeekday = 2
        let bars = weekBars(german, now: nov4, reviewDays: [0])
        #expect(bars.dayText(at: 0, calendar: german) == "1 · Thu 29 Oct")
        #expect(bars.dayText(at: 6, calendar: german) == "0 · Wed 4 Nov")
    }

    @Test func dayTextAcrossTheEndOfDaylightSaving() {
        let bars = weekBars(newYork, now: nov4NewYork, reviewDays: [3, 4])
        #expect((0..<7).map { bars.dayText(at: $0, calendar: newYork) } == [
            "0 · Thu 29 Oct", "0 · Fri 30 Oct", "0 · Sat 31 Oct", "1 · Sun 1 Nov",
            "1 · Mon 2 Nov", "0 · Tue 3 Nov", "0 · Wed 4 Nov",
        ])
    }

    @Test func dayTextUsesTheCalendarsTimeZone() {
        var tokyo = posix
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        let bars = weekBars(tokyo, now: now, reviewDays: [0])
        #expect(bars.dayText(at: 0, calendar: tokyo) == "1 · Thu 29 Oct")
        #expect(bars.dayText(at: 6, calendar: tokyo) == "0 · Wed 4 Nov")
    }
}
