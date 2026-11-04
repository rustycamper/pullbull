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
                == "1 review in the last 7 days, most on Sunday (1) Days before 10 Oct not loaded")
    }
}
