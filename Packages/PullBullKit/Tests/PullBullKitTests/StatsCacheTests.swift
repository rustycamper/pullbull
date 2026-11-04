import Foundation
import Testing
@testable import PullBullKit

@Suite struct StatsCacheTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let org = FetchScope.org("acme")

    func report(_ period: StatsPeriod = .week, failures: [String] = []) -> StatsReport {
        let value = StatValue.unknown
        return StatsReport(
            period: period, fetchedAt: now, reviews: value, turnaround: value, merged: value, timeToMerge: value,
            firstReview: value, issuesClosed: value, issuesOpened: value, comments: value, bars: nil,
            topReviewers: nil, anyCapped: false, footerCapNote: nil, failures: failures)
    }

    func key(_ account: String = "a", scope: FetchScope? = nil, period: StatsPeriod = .week) -> StatsKey {
        StatsKey(account: account, scope: scope ?? org, period: period)
    }

    @Test func freshUntilFifteenMinutes() {
        var cache = StatsCache()
        cache.store(report(), for: key())
        #expect(cache.isFresh(key(), now: now.addingTimeInterval(14 * 60)))
        #expect(!cache.isFresh(key(), now: now.addingTimeInterval(15 * 60)))
    }

    @Test func incompleteIsNeverFresh() {
        var cache = StatsCache()
        cache.store(report(failures: ["Offline"]), for: key())
        #expect(!cache.isFresh(key(), now: now))
        #expect(cache.report(for: key()) != nil)
    }

    @Test func missingIsNotFresh() {
        #expect(!StatsCache().isFresh(key(), now: now))
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
        #expect(!cache.isFresh(key("b"), now: now))
    }
}
