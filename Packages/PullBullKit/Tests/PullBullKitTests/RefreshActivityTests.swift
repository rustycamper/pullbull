import Foundation
import Testing
@testable import PullBullKit

private actor FakeActivity: ActivityChecking {
    enum Step {
        case unchanged, unsupported
        /// New activity at that time (nil: unknown).
        case changed(Date?)
        case fail(any Error)
    }

    private var steps: [Step]
    private(set) var callCount = 0

    init(_ steps: [Step]) { self.steps = steps }

    /// Answers the steps in order, then "unchanged".
    func check() async throws -> ActivityCheck {
        callCount += 1
        switch steps.isEmpty ? .unchanged : steps.removeFirst() {
        case .unchanged: return ActivityCheck(change: .unchanged, pollInterval: .seconds(60))
        case .unsupported: return ActivityCheck(change: .unsupported, pollInterval: .seconds(60))
        case .changed(let at): return ActivityCheck(change: .changed, pollInterval: .seconds(60), modifiedAt: at)
        case .fail(let error): throw error
        }
    }
}

private final class NowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func get() -> Date { lock.withLock { value } }
    func advance(by seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func snapshot(_ title: String) -> Snapshot {
    let pr = PullRequest(
        key: PRKey(repo: "o/r", number: 1), title: title, url: URL(string: "https://x/1")!,
        author: "alice", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
        headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
    return Snapshot(
        fetchedAt: t0, org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: [pr], mine: [], team: [], recentlyClosed: [], boardIssues: [])
}

private func ok(_ title: String, hold: Bool = false) -> FakeFetcher.Step {
    .init(result: .success(snapshot(title)), hold: hold)
}

/// Polls `condition` on the real clock until it holds or `timeout` passes.
private func eventually(within timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await clock.sleep(for: .milliseconds(1))
    }
    return await condition()
}

private struct Harness {
    let fetcher: FakeFetcher
    let clock = TestClock()
    let now = NowBox(t0)
    let coordinator: RefreshCoordinator

    init(_ steps: [FakeFetcher.Step]) {
        fetcher = FakeFetcher(steps)
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("pullbull-activity-\(UUID().uuidString)"))
        let now = now
        coordinator = RefreshCoordinator(fetcher: fetcher, store: store, clock: clock, now: { now.get() })
    }

    /// Moves the test clock and the wall clock together.
    func advance(by seconds: Int) {
        now.advance(by: TimeInterval(seconds))
        clock.advance(by: .seconds(seconds))
    }

    func start(interval: Duration, activity: FakeActivity?) async {
        await coordinator.start(
            account: "me", scope: .org("o"), board: nil, canReadProjects: true, interval: interval,
            activity: activity)
    }

    /// How many sleeps of `duration` were requested so far (poll timer and check timer alike).
    func sleeps(of duration: Duration) -> Int { clock.requestedSleeps.filter { $0 == duration }.count }
}

@Suite struct RefreshActivityTests {
    @Test func noCheckerMeansNoCheck() async throws {
        let h = Harness([ok("a")])
        await h.start(interval: .seconds(120), activity: nil)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        #expect(await h.coordinator.heldStatus.activity == .off)
    }

    @Test func firstAnswerMakesTheCheckActiveWithoutARefresh() async throws {
        let activity = FakeActivity([.unchanged])
        let h = Harness([ok("a"), ok("b", hold: true)])
        await h.start(interval: .seconds(120), activity: activity)
        #expect(await eventually { await h.coordinator.heldStatus.activity == .active })
        #expect(await eventually { h.sleeps(of: .seconds(120)) == 1 && h.sleeps(of: .seconds(60)) == 1 })
        #expect(await h.fetcher.callCount == 1)
    }

    @Test func changedRefreshesAtOnceAndThePollTimerCountsFromIt() async throws {
        let activity = FakeActivity([.unchanged, .changed(nil)])
        let h = Harness([ok("a"), ok("b"), ok("c", hold: true)])
        await h.start(interval: .seconds(300), activity: activity)
        #expect(await eventually { h.sleeps(of: .seconds(300)) == 1 && h.sleeps(of: .seconds(60)) == 1 })
        h.advance(by: 60)
        await h.fetcher.waitForCalls(2)
        // The early refresh restarted the poll timer: 300 s from t = 60, not from t = 0.
        #expect(await eventually { h.sleeps(of: .seconds(300)) == 2 && h.sleeps(of: .seconds(60)) == 2 })
        h.advance(by: 240)
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 3 })
        #expect(await h.fetcher.callCount == 2)
        h.advance(by: 60)
        await h.fetcher.waitForCalls(3)
        #expect(await h.fetcher.callCount == 3)
    }

    /// The first fetch (started at t0) is held; the second check, at t0 + 60 s, answers `second`.
    private func checkDuringAHeldRefresh(
        _ second: FakeActivity.Step, first: FakeFetcher.Step = ok("a", hold: true), then steps: [FakeFetcher.Step]
    ) async -> Harness {
        let activity = FakeActivity([.unchanged, second])
        let h = Harness([first] + steps)
        await h.start(interval: .seconds(120), activity: activity)
        await h.fetcher.waitForCalls(1)
        _ = await eventually { h.sleeps(of: .seconds(60)) == 1 }
        h.advance(by: 60)
        _ = await eventually { h.sleeps(of: .seconds(60)) == 2 }
        return h
    }

    @Test func changedBeforeTheRefreshInFlightStartedStartsNoOther() async throws {
        let h = await checkDuringAHeldRefresh(.changed(t0.addingTimeInterval(-10)), then: [ok("b", hold: true)])
        #expect(h.sleeps(of: .seconds(60)) == 2)
        // Not even an attempt that would join the one in flight.
        #expect(!(await eventually(within: .milliseconds(200)) { await h.coordinator.joinedWaiters > 0 }))
        await h.fetcher.releaseHeld()
        #expect(await eventually { h.sleeps(of: .seconds(120)) == 1 })
        #expect(await h.fetcher.callCount == 1)
    }

    @Test func changedAfterTheRefreshInFlightStartedRefreshesOnceMore() async throws {
        let h = await checkDuringAHeldRefresh(
            .changed(t0.addingTimeInterval(5)), then: [ok("b"), ok("c", hold: true)])
        #expect(h.sleeps(of: .seconds(60)) == 2)
        #expect(await h.coordinator.joinedWaiters == 0)
        await h.fetcher.releaseHeld()
        // Right after the first, without waiting for the timer; then the timer counts from it.
        #expect(await eventually { await h.fetcher.callCount == 2 })
        #expect(await eventually { h.sleeps(of: .seconds(120)) == 1 })
        #expect(await h.fetcher.callCount == 2)
    }

    @Test func activityDuringACancelledRefreshRetriesAtOnce() async throws {
        let h = await checkDuringAHeldRefresh(
            .changed(t0.addingTimeInterval(5)), first: .init(result: .failure(CancellationError()), hold: true),
            then: [ok("b"), ok("c", hold: true)])
        await h.fetcher.releaseHeld()
        // Not a full interval later: the flagged activity is fetched right away.
        #expect(await eventually { await h.fetcher.callCount == 2 })
        #expect(await eventually { h.sleeps(of: .seconds(120)) == 1 })
        #expect(await h.fetcher.callCount == 2)
    }

    @Test func changedOlderThanTheLastRefreshIsSkipped() async throws {
        let activity = FakeActivity([
            .unchanged, .changed(t0.addingTimeInterval(-5)), .changed(t0.addingTimeInterval(-0.5)),
        ])
        let h = Harness([ok("a"), ok("b"), ok("c", hold: true)])
        await h.start(interval: .seconds(600), activity: activity)
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 1 && h.sleeps(of: .seconds(600)) == 1 })
        h.advance(by: 60)
        // Activity from before the last refresh started is already shown.
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 2 })
        #expect(!(await eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 }))
        h.advance(by: 60)
        // Within Last-Modified's one-second precision it may be newer: refresh.
        #expect(await eventually { await h.fetcher.callCount == 2 })
    }

    @Test func unsupportedStopsCheckingAndPollsAsBefore() async throws {
        let activity = FakeActivity([.unsupported])
        let h = Harness([ok("a"), ok("b"), ok("c", hold: true)])
        await h.start(interval: .seconds(120), activity: activity)
        #expect(await eventually { await h.coordinator.heldStatus.activity == .unsupported })
        #expect(await eventually { h.sleeps(of: .seconds(120)) == 1 })
        h.advance(by: 120)
        #expect(await eventually { h.sleeps(of: .seconds(120)) == 2 })
        h.advance(by: 120)
        await h.fetcher.waitForCalls(3)
        #expect(await activity.callCount == 1)
        #expect(h.sleeps(of: .seconds(60)) == 0)
    }

    @Test func failedCheckChangesNothingAndTriesAgain() async throws {
        let activity = FakeActivity([.fail(APIError.network("offline")), .fail(APIError.server(502))])
        let h = Harness([ok("a"), ok("b", hold: true)])
        await h.start(interval: .seconds(120), activity: activity)
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 1 && h.sleeps(of: .seconds(120)) == 1 })
        let status = await h.coordinator.heldStatus
        #expect(status.error == nil)
        #expect(status.activity == .probing)
        h.advance(by: 60)
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 2 })
        h.advance(by: 60)
        #expect(await eventually { await h.coordinator.heldStatus.activity == .active })
        #expect(await activity.callCount == 3)
        #expect(await h.coordinator.heldStatus.error == nil)
    }

    @Test func rateLimitedCheckWaitsForTheReset() async throws {
        let activity = FakeActivity([.fail(APIError.rateLimited(resetAt: t0.addingTimeInterval(600)))])
        let h = Harness([ok("a", hold: true)])
        await h.start(interval: .seconds(120), activity: activity)
        #expect(await eventually { h.sleeps(of: .seconds(600)) == 1 })
        #expect(await h.coordinator.heldStatus.error == nil)
    }

    @Test func noChecksWhileThePollIsFailing() async throws {
        let activity = FakeActivity([.unchanged])
        let h = Harness([ok("a"), .init(result: .failure(APIError.network("offline")), hold: false), ok("b", hold: true)])
        await h.start(interval: .seconds(120), activity: activity)
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 1 && h.sleeps(of: .seconds(120)) == 1 })
        await h.coordinator.refreshNow()
        #expect(await h.coordinator.heldStatus.error == .offline)
        h.advance(by: 60)
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 2 })
        #expect(await activity.callCount == 1)
    }

    @Test func checkActivitySoonRunsTheCheckNow() async throws {
        let activity = FakeActivity([])
        let h = Harness([ok("a"), ok("b", hold: true)])
        await h.start(interval: .seconds(120), activity: activity)
        #expect(await eventually { await h.coordinator.heldStatus.activity == .active })
        #expect(await activity.callCount == 1)
        await h.coordinator.checkActivitySoon()
        #expect(await eventually { await activity.callCount == 2 })
    }

    @Test func stopEndsTheChecks() async throws {
        let activity = FakeActivity([])
        let h = Harness([ok("a")])
        await h.start(interval: .seconds(120), activity: activity)
        #expect(await eventually { h.sleeps(of: .seconds(60)) == 1 && h.sleeps(of: .seconds(120)) == 1 })
        await h.coordinator.stop()
        #expect(h.clock.pendingSleepers == 0)
        h.advance(by: 600)
        #expect(await activity.callCount == 1)
    }
}
