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

    @Test func cappedWithNothingLoadedDrawsNoBars() {
        let bars = ReviewBars.make(reviewDates: [], window: window(.week), loadedFrom: nil, capped: true, calendar: cal)
        #expect(bars.counts == Array(repeating: nil, count: 7))
        #expect(bars.marks(width: 80, height: 20).isEmpty)
        #expect(bars.hover(period: .week, calendar: cal) == "0+ reviews in the last 7 days")
    }

    @Test func gapNarrowsWithMoreBars() {
        #expect(ReviewBars.gap(barCount: 7) == 4)
        #expect(ReviewBars.gap(barCount: 30) == 2)
        #expect(ReviewBars.gap(barCount: 90) == 1)
    }

    @Test func marksScaleToTheBusiestDayWithStubsForNone() {
        let bars = ReviewBars.make(reviewDates: [day(0), day(0), day(0), day(0), day(2), day(6)],
                                   window: window(.week), loadedFrom: nil, calendar: cal)
        let marks = bars.marks(width: 80, height: 20)
        #expect(marks.count == 7)
        #expect(marks.map(\.width) == Array(repeating: 8, count: 7))
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

    @Test func daysNotLoadedDrawNothing() {
        let w = window(.week)
        let bars = ReviewBars.make(reviewDates: [day(4)], window: w, loadedFrom: w.dayStarts(calendar: cal)[3], calendar: cal)
        let marks = bars.marks(width: 80, height: 20)
        #expect(marks.map(\.x) == [36, 48, 60, 72])
        #expect(marks.map(\.height) == [1, 20, 1, 1])
    }
}
