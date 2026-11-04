import Foundation
import Testing
@testable import PullBullKit

@Suite struct StatsCacheTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let org = FetchScope.org("acme")

    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func report(_ period: StatsPeriod = .week, failures: [String] = [], fetchedAt: Date? = nil) -> StatsReport {
        let value = StatValue.unknown
        return StatsReport(
            period: period, fetchedAt: fetchedAt ?? now, reviews: value, turnaround: value, merged: value, timeToMerge: value,
            firstReview: value, issuesClosed: value, issuesOpened: value, comments: value, bars: nil,
            topReviewers: nil, anyCapped: false, footerCapNote: nil, failures: failures)
    }

    func key(_ account: String = "a", scope: FetchScope? = nil, period: StatsPeriod = .week) -> StatsKey {
        StatsKey(account: account, scope: scope ?? org, period: period)
    }

    @Test func freshUntilFifteenMinutes() {
        var cache = StatsCache()
        cache.store(report(), for: key())
        #expect(cache.isFresh(key(), now: now.addingTimeInterval(14 * 60), calendar: utc))
        #expect(!cache.isFresh(key(), now: now.addingTimeInterval(15 * 60), calendar: utc))
    }

    @Test func incompleteIsNeverFresh() {
        var cache = StatsCache()
        cache.store(report(failures: ["Offline"]), for: key())
        #expect(!cache.isFresh(key(), now: now, calendar: utc))
        #expect(cache.report(for: key()) != nil)
    }

    @Test func missingIsNotFresh() {
        #expect(!StatsCache().isFresh(key(), now: now, calendar: utc))
    }

    @Test func dropRemovesOnlyThatAccount() {
        var cache = StatsCache()
        cache.store(report(), for: key("a"))
        cache.store(report(), for: key("a", period: .month))
        cache.store(report(), for: key("b"))
        cache.drop(account: "a")
        #expect(cache.report(for: key("a")) == nil)
        #expect(cache.report(for: key("a", period: .month)) == nil)
        #expect(cache.report(for: key("b")) != nil)
    }

    @Test func keysDifferByScopeAndPeriod() {
        var cache = StatsCache()
        cache.store(report(), for: key())
        #expect(cache.report(for: key(scope: .personal(login: "me"))) == nil)
        #expect(cache.report(for: key(period: .month)) == nil)
    }

    @Test func otherAccountIsNotFresh() {
        var cache = StatsCache()
        cache.store(report(), for: key("a"))
        #expect(!cache.isFresh(key("b"), now: now, calendar: utc))
    }

    @Test func staleAtLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Sofia")!
        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 58))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 0, minute: 3))!
        let beforeMidnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 23, minute: 59))!
        var cache = StatsCache()
        cache.store(report(fetchedAt: lateEvening), for: key())
        #expect(cache.isFresh(key(), now: beforeMidnight, calendar: calendar))
        #expect(!cache.isFresh(key(), now: afterMidnight, calendar: calendar))
    }

    @Test func futureReportIsNotFresh() {
        var cache = StatsCache()
        cache.store(report(), for: key())
        #expect(!cache.isFresh(key(), now: now.addingTimeInterval(-1), calendar: utc))
    }

    @Test func accountCaseIsIgnored() {
        var cache = StatsCache()
        cache.store(report(), for: key("Peter"))
        #expect(cache.isFresh(key("peter"), now: now, calendar: utc))
        cache.drop(account: "PETER")
        #expect(cache.report(for: key("peter")) == nil)
    }
}
