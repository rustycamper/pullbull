import Foundation
import Testing
@testable import PullBullKit

private let launch = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ minutes: Double) -> Date { launch.addingTimeInterval(minutes * 60) }

@Suite struct ClearedTrackerTests {
    @Test func newerFetchThatEmptiesTheListClearsIt() {
        var tracker = ClearedTracker(since: launch)
        tracker.observe(count: 2, fetchedAt: at(1))
        #expect(tracker.clearedAt == nil)
        tracker.observe(count: 0, fetchedAt: at(2))
        #expect(tracker.clearedAt == at(2))
        // Still empty on the next poll: the time it was cleared stays.
        tracker.observe(count: 0, fetchedAt: at(3))
        #expect(tracker.clearedAt == at(2))
    }

    @Test func firstLoadEmptyIsNotCleared() {
        var tracker = ClearedTracker(since: launch)
        tracker.observe(count: 0, fetchedAt: at(1))
        tracker.observe(count: 0, fetchedAt: at(2))
        #expect(tracker.clearedAt == nil)
    }

    @Test func cacheFromBeforeLaunchIsOnlyABaseline() {
        var tracker = ClearedTracker(since: launch)
        tracker.observe(count: 3, fetchedAt: at(-90))
        tracker.observe(count: 0, fetchedAt: at(1))
        #expect(tracker.clearedAt == nil)
    }

    @Test func rebuildOfTheSameFetchIsNotCleared() {
        // "Hide PRs I've approved" turned on: the same fetch, built again, lists none.
        var tracker = ClearedTracker(since: launch)
        tracker.observe(count: 1, fetchedAt: at(1))
        tracker.observe(count: 0, fetchedAt: at(1))
        #expect(tracker.clearedAt == nil)
        // The next poll still finds none: the baseline was already empty.
        tracker.observe(count: 0, fetchedAt: at(2))
        #expect(tracker.clearedAt == nil)
    }

    @Test func failedPollKeepsTheLastGoodFetch() {
        var tracker = ClearedTracker(since: launch)
        tracker.observe(count: 1, fetchedAt: at(1))
        // A failed poll re-emits the same fetch.
        tracker.observe(count: 1, fetchedAt: at(1))
        #expect(tracker.clearedAt == nil)
        tracker.observe(count: 0, fetchedAt: at(4))
        #expect(tracker.clearedAt == at(4))
    }

    @Test func itemsAgainForgetTheClear() {
        var tracker = ClearedTracker(since: launch)
        tracker.observe(count: 1, fetchedAt: at(1))
        tracker.observe(count: 0, fetchedAt: at(2))
        tracker.observe(count: 1, fetchedAt: at(3))
        #expect(tracker.clearedAt == nil)
        tracker.observe(count: 0, fetchedAt: at(4))
        #expect(tracker.clearedAt == at(4))
    }

    @Test func resetForgetsTheBaseline() {
        var tracker = ClearedTracker(since: launch)
        tracker.observe(count: 1, fetchedAt: at(1))
        tracker.observe(count: 0, fetchedAt: at(2))
        tracker.reset()
        #expect(tracker.clearedAt == nil)
        // Another account's first list is a first load.
        tracker.observe(count: 0, fetchedAt: at(3))
        #expect(tracker.clearedAt == nil)
    }

    @Test func subtitleSaysWhen() {
        let cleared = at(10)
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: cleared) == "You cleared the last one just now.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: cleared.addingTimeInterval(59))
            == "You cleared the last one just now.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: cleared.addingTimeInterval(-30))
            == "You cleared the last one just now.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: at(22)) == "You cleared the last one 12 min ago.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: at(69)) == "You cleared the last one 59 min ago.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: at(70)) == "You cleared the last one 1 hr ago.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: at(10 + 60 * 23 + 59))
            == "You cleared the last one 23 hr ago.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: at(10 + 1440)) == "You cleared the last one 1 day ago.")
        #expect(ClearedTracker.subtitle(clearedAt: cleared, now: at(10 + 2880)) == "You cleared the last one 2 days ago.")
    }
}
