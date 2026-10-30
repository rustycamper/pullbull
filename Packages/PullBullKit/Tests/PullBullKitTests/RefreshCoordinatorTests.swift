import Foundation
import Testing
@testable import PullBullKit

// MARK: - Fake fetcher

actor FakeFetcher: SnapshotFetching {
    struct Step {
        let result: Result<Snapshot, any Error>
        let hold: Bool
    }

    private var steps: [Step]
    private var held: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [(id: UUID, count: Int, continuation: CheckedContinuation<Bool, Never>)] = []
    private(set) var calls: [(account: String, previous: Snapshot?, board: BoardRef?, canReadProjects: Bool)] = []
    private(set) var scopes: [FetchScope] = []
    var callCount: Int { calls.count }

    init(_ steps: [Step]) { self.steps = steps }

    func fetch(
        account: String, scope: FetchScope, board: BoardRef?, canReadProjects: Bool, previous: Snapshot?
    ) async throws -> Snapshot {
        calls.append((account, previous, board, canReadProjects))
        scopes.append(scope)
        let due = callWaiters.filter { $0.count <= calls.count }
        callWaiters.removeAll { $0.count <= calls.count }
        due.forEach { $0.continuation.resume(returning: true) }
        guard !steps.isEmpty else {
            await withCheckedContinuation { held.append($0) }
            throw CancellationError()
        }
        let step = steps.removeFirst()
        if step.hold { await withCheckedContinuation { held.append($0) } }
        return try step.result.get()
    }

    /// Suspends until `count` fetches have started. Past `timeout` (real time) it records an issue and
    /// returns, so a fetch that never comes fails the test instead of hanging the run.
    func waitForCalls(
        _ count: Int, timeout: Duration = testWaitLimit, sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        if calls.count >= count { return }
        let id = UUID()
        let met = await withCheckedContinuation { continuation in
            callWaiters.append((id, count, continuation))
            Task {
                try? await Task.sleep(for: timeout)
                self.expireCallWaiter(id)
            }
        }
        if !met {
            Issue.record("\(count) fetches did not start within \(timeout)", sourceLocation: sourceLocation)
        }
    }

    private func expireCallWaiter(_ id: UUID) {
        guard let index = callWaiters.firstIndex(where: { $0.id == id }) else { return }
        callWaiters.remove(at: index).continuation.resume(returning: false)
    }

    func releaseHeld() {
        let waiting = held
        held.removeAll()
        waiting.forEach { $0.resume() }
    }

    // MARK: Fast CI follow

    struct FollowStep {
        let result: Result<[PullRequest], any Error>
        let hold: Bool

        static func ok(_ prs: [PullRequest], hold: Bool = false) -> Self { .init(result: .success(prs), hold: hold) }
        static func fail(_ error: any Error) -> Self { .init(result: .failure(error), hold: false) }
    }

    private var followSteps: [FollowStep] = []
    private var followHeld: [CheckedContinuation<Void, Never>] = []
    /// The keys of each `pullRequests` call, in order.
    private(set) var followCalls: [[PRKey]] = []

    func setFollows(_ steps: [FollowStep]) { followSteps = steps }

    func pullRequests(_ keys: [PRKey], account: String) async throws -> [PullRequest] {
        followCalls.append(keys)
        guard !followSteps.isEmpty else { throw APIError.server(500) }
        let step = followSteps.removeFirst()
        if step.hold { await withCheckedContinuation { followHeld.append($0) } }
        return try step.result.get()
    }

    func releaseFollows() {
        let waiting = followHeld
        followHeld.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private extension FakeFetcher.Step {
    static func ok(_ snapshot: Snapshot, hold: Bool = false) -> Self { .init(result: .success(snapshot), hold: hold) }
    static func fail(_ error: any Error, hold: Bool = false) -> Self { .init(result: .failure(error), hold: hold) }
}

// MARK: - Helpers

private final class NowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func get() -> Date { lock.withLock { value } }
    func set(_ date: Date) { lock.withLock { value = date } }
}

private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let appAccount = AccountRef(login: "octocat", source: .gitHubApp)

private func snapshot(_ title: String, at date: Date = t0, viewer: String = "me") -> Snapshot {
    let pr = PullRequest(
        key: PRKey(repo: "o/r", number: 1), title: title, url: URL(string: "https://x/1")!,
        author: "alice", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: date, updatedAt: date, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
        headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
    return Snapshot(
        fetchedAt: date,
        org: OrgContext(org: "o", viewer: viewer, members: [], myTeams: [], repos: []),
        reviewCandidates: [pr], mine: [], team: [], recentlyClosed: [], boardIssues: [])
}

private func pull(_ number: Int, repo: String) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "t", url: URL(string: "https://x/\(number)")!,
        author: "me", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
        headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

private func tempStore() -> SnapshotStore {
    SnapshotStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("pullbull-refresh-\(UUID().uuidString)"))
}

private typealias Update = (Snapshot?, RefreshStatus)

/// Next update that is not an "attempt started" (`isRefreshing`) marker.
private func nextSettled(_ iterator: inout AsyncStream<Update>.Iterator) async -> Update? {
    while let update = await iterator.next() {
        if !update.1.isRefreshing { return update }
    }
    return nil
}

private struct Harness {
    let fetcher: FakeFetcher
    let store: SnapshotStore
    let clock: TestClock
    let now: NowBox
    let coordinator: RefreshCoordinator

    init(_ steps: [FakeFetcher.Step]) {
        fetcher = FakeFetcher(steps)
        store = tempStore()
        clock = TestClock()
        let now = NowBox(t0)
        self.now = now
        coordinator = RefreshCoordinator(fetcher: fetcher, store: store, clock: clock, now: { now.get() })
    }

    func start(
        _ account: String = "me", interval: Duration = .seconds(120), canReadProjects: Bool = true,
        followsPendingCI: Bool = false
    ) async {
        await coordinator.start(
            account: account, scope: .org("o"), board: .org("o", 3), canReadProjects: canReadProjects, interval: interval,
            followsPendingCI: followsPendingCI)
    }
}

private func withBoard(_ snap: Snapshot) -> Snapshot {
    var snap = snap
    snap.boardIssues = [BoardIssue(key: PRKey(repo: "o/r", number: 9), title: "i", url: URL(string: "https://x/9")!, isOpen: true)]
    snap.boardProject = 3
    snap.boardTitle = "Board"
    snap.boardStatusOptions = [StatusOption(id: "t", name: "Todo")]
    snap.assignedIssues = [BoardIssue(key: PRKey(repo: "o/r", number: 7), title: "a", url: URL(string: "https://x/7")!, isOpen: true)]
    return snap
}

// MARK: - Coordinator

@Suite struct RefreshCoordinatorTests {
    @Test func emitsCacheFirst() async throws {
        let h = Harness([.ok(snapshot("fresh"), hold: true)])
        let cached = snapshot("cached", at: t0.addingTimeInterval(-600))
        try await h.store.save(cached, account: "me", scope: .org("o"))
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        let first = try #require(await updates.next())
        #expect(first.0 == cached)
        #expect(first.1.lastSuccess == cached.fetchedAt)
        #expect(first.1.error == nil)
        let next = try #require(await updates.next())
        #expect(next.0 == cached)
        #expect(next.1.isRefreshing)
    }

    @Test func emitsNilCacheFirstWhenEmpty() async throws {
        let h = Harness([.ok(snapshot("fresh"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        let first = try #require(await updates.next())
        #expect(first.0 == nil)
        #expect(first.1.lastSuccess == nil)
    }

    @Test func successSavesAndEmits() async throws {
        let fresh = snapshot("fresh")
        let h = Harness([.ok(fresh)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        let update = try #require(await nextSettled(&updates))
        #expect(update.0 == fresh)
        #expect(update.1 == RefreshStatus(lastSuccess: fresh.fetchedAt, error: nil, isRefreshing: false))
        #expect(await h.store.load(account: "me", scope: .org("o")) == fresh)
    }

    @Test func issuesErrorIsNotARefreshFailure() async throws {
        var partial = snapshot("partial")
        partial.assignedIssuesError = "GitHub server error 502"
        let h = Harness([.ok(partial)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start(interval: .seconds(120))
        _ = await nextSettled(&updates)
        let update = try #require(await nextSettled(&updates))
        #expect(update.0?.assignedIssuesError == "GitHub server error 502")
        #expect(update.1 == RefreshStatus(lastSuccess: partial.fetchedAt, error: nil, isRefreshing: false))
        // The next poll is a normal interval away, not a backoff retry.
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
    }

    @Test func passesPreviousSnapshot() async throws {
        let cached = snapshot("cached")
        let h = Harness([.ok(snapshot("fresh"))])
        try await h.store.save(cached, account: "me", scope: .org("o"))
        await h.start()
        await h.fetcher.waitForCalls(1)
        #expect(await h.fetcher.calls.first?.previous == cached)
    }

    @Test func singleFlight() async throws {
        let h = Harness([.ok(snapshot("fresh"), hold: true)])
        await h.start()
        await h.fetcher.waitForCalls(1)
        let coordinator = h.coordinator
        async let first: Void = coordinator.refreshNow()
        async let second: Void = coordinator.refreshNow()
        #expect(await eventually { await coordinator.joinedWaiters == 2 }, "two waiters did not join")
        await h.fetcher.releaseHeld()
        _ = await (first, second)
        #expect(await h.fetcher.callCount == 1)
    }

    @Test func failureKeepsData() async throws {
        let good = snapshot("good")
        let h = Harness([.ok(good), .fail(APIError.network("offline"))])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        #expect(await nextSettled(&updates)?.0 == good)
        await h.coordinator.refreshNow()
        let update = try #require(await nextSettled(&updates))
        #expect(update.0 == good)
        #expect(update.1.error == .offline)
        #expect(update.1.lastSuccess == good.fetchedAt)
        #expect(await h.store.load(account: "me", scope: .org("o")) == good)
    }

    @Test func backoffSchedule() async throws {
        let offline = APIError.network("offline")
        let h = Harness([.fail(offline), .fail(offline), .fail(offline), .fail(offline), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(15)])
        #expect(await h.fetcher.callCount == 1)
        h.clock.advance(by: .seconds(14))
        #expect(h.clock.pendingSleepers == 1)
        #expect(await h.fetcher.callCount == 1)
        h.clock.advance(by: .seconds(1))
        #expect(await h.clock.waitForSleeps(2) == [.seconds(15), .seconds(30)])
        #expect(await h.fetcher.callCount == 2)
        h.clock.advance(by: .seconds(30))
        #expect(await h.clock.waitForSleeps(3) == [.seconds(15), .seconds(30), .seconds(60)])
        h.clock.advance(by: .seconds(60))
        #expect(await h.clock.waitForSleeps(4) == [.seconds(15), .seconds(30), .seconds(60), .seconds(120)])
        #expect(await h.fetcher.callCount == 4)
    }

    @Test func backoffCappedByShortInterval() async throws {
        let h = Harness([.fail(APIError.network("x")), .fail(APIError.network("x")), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(20))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(15)])
        h.clock.advance(by: .seconds(15))
        #expect(await h.clock.waitForSleeps(2) == [.seconds(15), .seconds(20)])
    }

    @Test func successResetsBackoff() async throws {
        let offline = APIError.network("offline")
        let h = Harness([.fail(offline), .fail(offline), .ok(snapshot("x")), .fail(offline), .ok(snapshot("y"), hold: true)])
        await h.start(interval: .seconds(120))
        _ = await h.clock.waitForSleeps(1)
        h.clock.advance(by: .seconds(15))
        _ = await h.clock.waitForSleeps(2)
        h.clock.advance(by: .seconds(30))
        _ = await h.clock.waitForSleeps(3)
        h.clock.advance(by: .seconds(120))
        #expect(await h.clock.waitForSleeps(4) == [.seconds(15), .seconds(30), .seconds(120), .seconds(15)])
    }

    /// An unreachable failure backs off like any other error.
    @Test func unreachableBacksOff() async throws {
        let failure = APIError.unreachable(.secureConnectionFailed)
        let h = Harness([.fail(failure), .fail(failure), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(15)])
        #expect(await h.coordinator.heldStatus.error == .unreachable(.secureConnectionFailed))
        h.clock.advance(by: .seconds(15))
        #expect(await h.clock.waitForSleeps(2) == [.seconds(15), .seconds(30)])
    }

    /// A refused 403 retries at the poll interval, never the 15 s backoff; `refreshNow()` still
    /// retries at once.
    @Test func forbiddenRetriesAtThePollInterval() async throws {
        let h = Harness([.fail(APIError.forbidden), .fail(APIError.forbidden), .fail(APIError.forbidden),
                         .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        #expect(await h.coordinator.heldStatus.error == .forbidden)
        h.clock.advance(by: .seconds(15))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 })
        h.clock.advance(by: .seconds(105))
        #expect(await h.clock.waitForSleeps(2) == [.seconds(120), .seconds(120)])
        #expect(await h.fetcher.callCount == 2)
        await h.coordinator.refreshNow()
        #expect(await h.fetcher.callCount == 3)
        #expect(await h.clock.waitForSleeps(3) == [.seconds(120), .seconds(120), .seconds(120)])
    }

    /// A cancelled attempt after a refused 403 waits the poll interval, not the 15 s backoff.
    @Test func cancelledAttemptAfterForbiddenWaitsThePollInterval() async throws {
        let h = Harness([.fail(APIError.forbidden), .fail(CancellationError()), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        h.clock.advance(by: .seconds(120))
        #expect(await h.clock.waitForSleeps(2) == [.seconds(120), .seconds(120)])
        #expect(await h.fetcher.callCount == 2)
        h.clock.advance(by: .seconds(15))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 2 })
        h.clock.advance(by: .seconds(105))
        await h.fetcher.waitForCalls(3)
    }

    /// A cancelled attempt during a rate-limit wait keeps waiting for the reset.
    @Test func cancelledAttemptDuringARateLimitWaitsForTheReset() async throws {
        let reset = t0.addingTimeInterval(300)
        let h = Harness([.fail(APIError.rateLimited(resetAt: reset)), .fail(CancellationError()), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(300)])
        h.now.set(t0.addingTimeInterval(100))
        await h.coordinator.refreshNow()
        #expect(await h.clock.waitForSleeps(2) == [.seconds(300), .seconds(200)])
    }

    @Test func rateLimitWaitsUntilReset() async throws {
        let reset = t0.addingTimeInterval(300)
        let h = Harness([.fail(APIError.rateLimited(resetAt: reset)), .ok(snapshot("x"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        #expect(await nextSettled(&updates)?.1.error == .rateLimited(reset))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(300)])
    }

    @Test func rateLimitWaitIsClamped() async throws {
        let h = Harness([
            .fail(APIError.rateLimited(resetAt: t0.addingTimeInterval(-60))),
            .fail(APIError.rateLimited(resetAt: t0.addingTimeInterval(5 * 3600))),
            .ok(snapshot("x"), hold: true),
        ])
        await h.start()
        #expect(await h.clock.waitForSleeps(1) == [.seconds(15)])
        h.clock.advance(by: .seconds(15))
        #expect(await h.clock.waitForSleeps(2) == [.seconds(15), .seconds(3600)])
    }

    @Test func cancellationIsNeitherSuccessNorFailure() async throws {
        let h = Harness([.fail(CancellationError()), .ok(snapshot("x"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start(interval: .seconds(120))
        _ = await nextSettled(&updates)
        let update = try #require(await nextSettled(&updates))
        #expect(update.0 == nil)
        #expect(update.1.error == nil)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
    }

    @Test func staleGenerationDropped() async throws {
        let a = snapshot("from A", viewer: "a")
        let b = snapshot("from B", viewer: "b")
        let b2 = snapshot("from B again", viewer: "b")
        let h = Harness([.ok(a, hold: true), .ok(b), .ok(b2)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start("a")
        await h.fetcher.waitForCalls(1)
        await h.start("b")

        var seenB = false
        while !seenB, let update = await updates.next() {
            #expect(update.0 != a)
            seenB = update.0 == b
        }
        #expect(await h.fetcher.calls.map(\.account) == ["a", "b"])

        await h.fetcher.releaseHeld()
        #expect(await eventually { await h.coordinator.droppedResults == 1 }, "the stale result was not dropped")
        #expect(await h.store.load(account: "a", scope: .org("o")) == nil)
        #expect(await h.store.load(account: "b", scope: .org("o")) == b)

        await h.coordinator.refreshNow()
        var seenB2 = false
        while !seenB2, let update = await updates.next() {
            #expect(update.0 != a)
            seenB2 = update.0 == b2
        }
        #expect(await h.store.load(account: "b", scope: .org("o")) == b2)
    }

    @Test func switchDoesNotShowPreviousAccountCache() async throws {
        let cachedA = snapshot("cached A", viewer: "a")
        let h = Harness([.ok(snapshot("A"), hold: true), .ok(snapshot("B"), hold: true)])
        try await h.store.save(cachedA, account: "a", scope: .org("o"))
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start("a")
        #expect(await updates.next()?.0 == cachedA)
        await h.start("b")
        var update = try #require(await updates.next())
        while update.0 == cachedA, update.1.isRefreshing { update = try #require(await updates.next()) }
        #expect(update.0 == nil)
        #expect(update.1.lastSuccess == nil)
    }

    @Test func refreshDuringCacheLoadWaitsForCache() async throws {
        let cached = snapshot("cached", at: t0.addingTimeInterval(-600))
        let h = Harness([.ok(snapshot("fresh"), hold: true)])
        try await h.store.save(cached, account: "me", scope: .org("o"))
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        let coordinator = h.coordinator
        let refresh = Task { await coordinator.refreshNow() }
        await h.fetcher.waitForCalls(1)
        let first = try #require(await updates.next())
        #expect(first.0 == cached)
        #expect(!first.1.isRefreshing)
        #expect(await h.fetcher.calls.first?.previous == cached)
        await h.fetcher.releaseHeld()
        await refresh.value
    }

    @Test func staleAttemptNeverTouchesNewGeneration() async throws {
        let cachedA = snapshot("cached A", viewer: "a")
        for _ in 0..<200 {
            let h = Harness([.ok(snapshot("A")), .ok(snapshot("A2")), .ok(snapshot("B")), .ok(snapshot("B2"))])
            try await h.store.save(cachedA, account: "a", scope: .org("o"))
            var updates = h.coordinator.updates.makeAsyncIterator()
            await h.start("a")
            let coordinator = h.coordinator
            let refresh = Task { await coordinator.refreshNow() }
            await h.start("b")
            // B has no cache, so B's first update must be its (nil, not refreshing) cache emission;
            // a (nil, refreshing) before it is a marker from an attempt that belongs to A.
            while let update = await updates.next() {
                guard update.0 == nil else { continue }
                #expect(!update.1.isRefreshing)
                break
            }
            await h.coordinator.stop()
            await refresh.value
        }
    }

    /// Sign Out deletes the cache right after `stop()`, so `stop()` returns only once the fetch in
    /// flight has finished and can no longer save.
    @Test func stopWaitsForTheFetchInFlight() async throws {
        let h = Harness([.ok(snapshot("fresh"), hold: true)])
        await h.start()
        await h.fetcher.waitForCalls(1)
        let coordinator = h.coordinator
        let stopped = StopFlag()
        let stopping = Task {
            await coordinator.stop()
            stopped.set()
        }
        #expect(await !eventually(within: .milliseconds(100)) { stopped.isSet })
        await h.fetcher.releaseHeld()
        await stopping.value
        #expect(await h.store.load(account: "me", scope: .org("o")) == nil)
    }

    /// A signed-out app account's cache never shows, not even until the first fetch fails.
    @Test func cacheIsHiddenWhenTheGateSaysNo() async throws {
        let fetcher = FakeFetcher([.ok(snapshot("fresh"), hold: true)])
        let store = tempStore()
        try await store.save(snapshot("cached", at: t0.addingTimeInterval(-600)), account: "me", scope: .org("o"))
        let coordinator = RefreshCoordinator(
            fetcher: fetcher, store: store, clock: TestClock(), now: { t0 }, showsCache: { false })
        var updates = coordinator.updates.makeAsyncIterator()
        await coordinator.start(account: "me", scope: .org("o"), board: .org("o", 3), canReadProjects: true, interval: .seconds(120))
        let first = try #require(await updates.next())
        #expect(first.0 == nil)
        #expect(first.1.lastSuccess == nil)
        await fetcher.waitForCalls(1)
        await fetcher.releaseHeld()
        await coordinator.stop()
    }

    /// No org: the loop polls the personal scope, keeps no board, and caches under a key no org can share.
    @Test func personalScopePollsWithoutABoard() async throws {
        let fetcher = FakeFetcher([.ok(withBoard(snapshot("fresh")))])
        let store = tempStore()
        let coordinator = RefreshCoordinator(fetcher: fetcher, store: store, clock: TestClock(), now: { t0 })
        var updates = coordinator.updates.makeAsyncIterator()
        await coordinator.start(
            account: "me", scope: .personal(login: "me"), board: .org("o", 3), canReadProjects: true,
            interval: .seconds(120))
        _ = await nextSettled(&updates)
        let fresh = try #require(await nextSettled(&updates)?.0)
        #expect(await fetcher.scopes == [.personal(login: "me")])
        #expect(fresh.boardIssues.isEmpty)
        #expect(fresh.boardProject == nil)
        #expect(fresh.boardStatusOptions == nil)
        #expect(fresh.assignedIssues?.count == 1)
        #expect(await store.load(account: "me", scope: .personal(login: "me")) == fresh)
        #expect(await store.load(account: "me", scope: .org("me")) == nil)
        await coordinator.stop()
    }

    /// A no-org cache shows its board only when it is the chosen board of the same owner: a number
    /// cached without an owner is never taken for the user's board.
    @Test func cachedBoardShowsOnlyForTheSameOwner() async throws {
        for (owner, shown) in [(BoardOwner?.none, false), (.user("someone"), false), (.user("me"), true)] {
            let fetcher = FakeFetcher([])
            let store = tempStore()
            var cached = withBoard(snapshot("cached"))
            cached.org = .personal(login: "me", repos: ["r"], reposComplete: true)
            cached.boardIssues = [BoardIssue(
                key: PRKey(repo: "me/r", number: 9), title: "i", url: URL(string: "https://x/9")!, isOpen: true)]
            cached.boardOwner = owner
            try await store.save(cached, account: "me", scope: .personal(login: "me"))
            let coordinator = RefreshCoordinator(fetcher: fetcher, store: store, clock: TestClock(), now: { t0 })
            var updates = coordinator.updates.makeAsyncIterator()
            await coordinator.start(
                account: "me", scope: .personal(login: "me"), board: .user("me", 3), canReadProjects: true,
                interval: .seconds(120))
            let first = try #require(await updates.next()?.0)
            #expect(first.boardIssues.isEmpty == !shown)
            #expect((first.board == .user("me", 3)) == shown)
            await fetcher.waitForCalls(1)
            #expect(await fetcher.calls.first?.board == .user("me", 3))
            await fetcher.releaseHeld()
            await coordinator.stop()
        }
    }

    /// No-org mode polls the user's own board, and the snapshot keeps its owner.
    @Test func personalScopePollsTheUsersBoard() async throws {
        var fresh = withBoard(snapshot("fresh"))
        fresh.org = .personal(login: "me", repos: ["r"], reposComplete: true)
        fresh.boardOwner = .user("me")
        let fetcher = FakeFetcher([.ok(fresh)])
        let coordinator = RefreshCoordinator(fetcher: fetcher, store: tempStore(), clock: TestClock(), now: { t0 })
        var updates = coordinator.updates.makeAsyncIterator()
        await coordinator.start(
            account: "me", scope: .personal(login: "me"), board: .user("me", 3), canReadProjects: true,
            interval: .seconds(120))
        _ = await nextSettled(&updates)
        let polled = try #require(await nextSettled(&updates)?.0)
        #expect(polled.board == .user("me", 3))
        #expect(polled.boardStatus == .available)
        await coordinator.stop()
    }

    /// A cache written before the installation was limited to selected repos shows only those repos.
    @Test func personalCacheIsLimitedToTheScopesRepos() async throws {
        let fetcher = FakeFetcher([])
        let store = tempStore()
        var cached = snapshot("cached")
        cached.org = .personal(login: "me", repos: ["r", "x"], reposComplete: true)
        cached.mine = [cached.reviewCandidates[0], pull(2, repo: "me/x"), pull(3, repo: "other/x")]
        try await store.save(cached, account: "me", scope: .personal(login: "me"))
        let coordinator = RefreshCoordinator(fetcher: fetcher, store: store, clock: TestClock(), now: { t0 })
        var updates = coordinator.updates.makeAsyncIterator()
        let scope = FetchScope.personal(login: "me", repos: ["me/x"])
        await coordinator.start(account: "me", scope: scope, board: nil, canReadProjects: false, interval: .seconds(120))
        let first = try #require(await updates.next()?.0)
        #expect(first.mine.map(\.key.repo) == ["me/x"])
        #expect(first.reviewCandidates.isEmpty)
        #expect(first.scope == scope)
        await fetcher.waitForCalls(1)
        await fetcher.releaseHeld()
        await coordinator.stop()
    }

    @Test func refreshIfOlderThanRespectsRateLimit() async throws {
        let reset = t0.addingTimeInterval(300)
        let h = Harness([.fail(APIError.rateLimited(resetAt: reset)), .ok(snapshot("later"))])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        _ = await nextSettled(&updates)
        h.now.set(t0.addingTimeInterval(60))
        await h.coordinator.refreshIfOlderThan(.seconds(30))
        #expect(await h.fetcher.callCount == 1)
        h.now.set(t0.addingTimeInterval(301))
        await h.coordinator.refreshIfOlderThan(.seconds(30))
        #expect(await h.fetcher.callCount == 2)
    }

    @Test func ghMissingSurfaced() async throws {
        let cached = snapshot("cached", at: t0.addingTimeInterval(-900))
        let h = Harness([.fail(GhError.notInstalled)])
        try await h.store.save(cached, account: "me", scope: .org("o"))
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        let update = try #require(await nextSettled(&updates))
        #expect(update.0 == cached)
        #expect(update.1.error == .ghMissing)
        #expect(update.1.lastSuccess == cached.fetchedAt)
    }

    @Test func refreshIfOlderThan() async throws {
        let fresh = snapshot("fresh", at: t0)
        let h = Harness([.ok(fresh), .ok(snapshot("later"))])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        _ = await nextSettled(&updates)
        h.now.set(t0.addingTimeInterval(29))
        await h.coordinator.refreshIfOlderThan(.seconds(30))
        #expect(await h.fetcher.callCount == 1)
        h.now.set(t0.addingTimeInterval(31))
        await h.coordinator.refreshIfOlderThan(.seconds(30))
        #expect(await h.fetcher.callCount == 2)
    }

    // MARK: Config updates in place

    @Test func updateKeepsSnapshotAndErrorWithoutFetching() async throws {
        let good = withBoard(snapshot("good"))
        let h = Harness([.ok(good), .fail(APIError.network("offline")), .ok(snapshot("later"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        _ = await nextSettled(&updates)
        await h.coordinator.refreshNow()
        #expect(await nextSettled(&updates)?.1.error == .offline)

        await h.coordinator.update(board: .org("o", 3), canReadProjects: false, interval: .seconds(300))
        let update = try #require(await updates.next())
        #expect(update.1.error == .offline)
        #expect(update.1.lastSuccess == good.fetchedAt)
        #expect(update.0?.reviewCandidates == good.reviewCandidates)
        #expect(update.0?.boardIssues.isEmpty == true)
        #expect(update.0?.boardStatus == BoardStatus.none)
        #expect(update.0?.boardStatusOptions == nil)
        #expect(update.0?.assignedIssues == good.assignedIssues)
        #expect(await h.fetcher.callCount == 2)
    }

    @Test func turningBoardOffClearsStatusOptionsKeepsIssues() async throws {
        let good = withBoard(snapshot("good"))
        let h = Harness([.ok(good)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        _ = await nextSettled(&updates)

        await h.coordinator.update(board: nil, canReadProjects: true, interval: .seconds(120))
        let update = try #require(await updates.next())
        #expect(update.0?.boardStatusOptions == nil)
        #expect(update.0?.boardIssues.isEmpty == true)
        #expect(update.0?.assignedIssues == good.assignedIssues)
        #expect(update.0?.assignedIssues?.isEmpty == false)
        #expect(await h.fetcher.callCount == 1)
    }

    @Test func updateIntervalReschedulesFromLastSuccess() async throws {
        let h = Harness([.ok(snapshot("x")), .ok(snapshot("y"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        h.now.set(t0.addingTimeInterval(20))
        await h.coordinator.update(board: .org("o", 3), canReadProjects: true, interval: .seconds(60))
        #expect(await h.clock.waitForSleeps(2) == [.seconds(120), .seconds(40)])
        #expect(await h.fetcher.callCount == 1)
    }

    @Test func sameConfigUpdateDoesNothing() async throws {
        let h = Harness([.ok(snapshot("x")), .ok(snapshot("y"), hold: true)])
        await h.start(interval: .seconds(120))
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.update(board: .org("o", 3), canReadProjects: true, interval: .seconds(120))
        #expect(h.clock.requestedSleeps == [.seconds(120)])
        #expect(await h.fetcher.callCount == 1)
    }

    @Test func enablingBoardFetchesOnce() async throws {
        let h = Harness([.ok(snapshot("x")), .ok(withBoard(snapshot("y"))), .ok(snapshot("z"), hold: true)])
        await h.start(canReadProjects: false)
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.update(board: .org("o", 3), canReadProjects: true, interval: .seconds(120))
        await h.fetcher.waitForCalls(2)
        #expect(await h.clock.waitForSleeps(3).count == 3)
        let calls = await h.fetcher.calls
        #expect(calls.count == 2)
        #expect(calls.map(\.canReadProjects) == [false, true])
    }

    @Test func boardChangedDuringFetchRefetchesAfterIt() async throws {
        let h = Harness([.ok(withBoard(snapshot("x")), hold: true), .ok(snapshot("y")), .ok(snapshot("z"), hold: true)])
        await h.start()
        await h.fetcher.waitForCalls(1)
        await h.coordinator.update(board: .org("o", 4), canReadProjects: true, interval: .seconds(120))
        #expect(await h.fetcher.callCount == 1)
        await h.fetcher.releaseHeld()
        await h.fetcher.waitForCalls(2)
        #expect(await h.fetcher.calls.map(\.board?.number) == [3, 4])
    }

    @Test func disablingBoardDuringFetchStripsItsResult() async throws {
        let h = Harness([.ok(withBoard(snapshot("x")), hold: true), .ok(snapshot("y"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        await h.fetcher.waitForCalls(1)
        await h.coordinator.update(board: .org("o", 3), canReadProjects: false, interval: .seconds(120))
        await h.fetcher.releaseHeld()
        var result: Snapshot?
        while result == nil, let update = await updates.next() { result = update.0 }
        #expect(result?.boardIssues.isEmpty == true)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        #expect(await h.fetcher.callCount == 1)
    }

    @Test func switchingBoardDropsTheOldBoardAtOnce() async throws {
        let good = withBoard(snapshot("good"))
        let h = Harness([.ok(good), .ok(snapshot("y"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        _ = await nextSettled(&updates)

        await h.coordinator.update(board: .org("o", 4), canReadProjects: true, interval: .seconds(120))
        let update = try #require(await updates.next())
        #expect(update.0?.boardIssues.isEmpty == true)
        #expect(update.0?.board == nil)
        #expect(update.0?.boardTitle == nil)
        #expect(update.0?.boardStatusOptions == nil)
        #expect(update.0?.assignedIssues == good.assignedIssues)
        await h.fetcher.waitForCalls(2)
        #expect(await h.fetcher.calls.last?.previous?.boardIssues.isEmpty == true)
    }

    @Test func switchingBoardDuringFetchStripsTheStaleResult() async throws {
        let h = Harness([.ok(withBoard(snapshot("x")), hold: true), .ok(snapshot("y"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        await h.fetcher.waitForCalls(1)
        await h.coordinator.update(board: .org("o", 4), canReadProjects: true, interval: .seconds(120))
        await h.fetcher.releaseHeld()
        var result: Snapshot?
        while result == nil, let update = await updates.next() { result = update.0 }
        #expect(result?.reviewCandidates.first?.title == "x")
        #expect(result?.boardIssues.isEmpty == true)
        #expect(result?.board == nil)
        #expect(result?.boardTitle == nil)
        let saved = await h.store.load(account: "me", scope: .org("o"))
        #expect(saved?.reviewCandidates.first?.title == "x")
        #expect(saved?.boardIssues.isEmpty == true)
        #expect(saved?.board == nil)
        await h.fetcher.waitForCalls(2)
        #expect(await h.fetcher.calls.map(\.board?.number) == [3, 4])
    }

    @Test func boardChangeDuringBackoffWaitsForTheRetry() async throws {
        let h = Harness([.fail(APIError.network("offline")), .ok(snapshot("x"), hold: true)])
        await h.start()
        #expect(await h.clock.waitForSleeps(1) == [.seconds(15)])
        await h.coordinator.update(board: .org("o", 4), canReadProjects: true, interval: .seconds(120))
        // Give an immediate refetch, if one were scheduled, every chance to run.
        #expect(!(await eventually(within: .milliseconds(200)) { await h.fetcher.callCount == 2 }), "an immediate refetch ran")
        #expect(h.clock.requestedSleeps == [.seconds(15)])
        h.clock.advance(by: .seconds(15))
        await h.fetcher.waitForCalls(2)
        #expect(await h.fetcher.calls.map(\.board?.number) == [3, 4])
    }

    @Test func updateRightAfterFetchIsNeverLost() async throws {
        // The update may land before, during or after the result's save; every case must end
        // with the board gone from what the coordinator holds.
        for _ in 0..<200 {
            let h = Harness([.ok(withBoard(snapshot("x")), hold: true), .ok(snapshot("y"), hold: true)])
            await h.start()
            await h.fetcher.waitForCalls(1)
            await h.fetcher.releaseHeld()
            await h.coordinator.update(board: .org("o", 3), canReadProjects: false, interval: .seconds(120))
            #expect(
                await eventually { await h.coordinator.heldSnapshot?.boardIssues.isEmpty == true },
                "the board was still held after it was turned off")
            await h.coordinator.stop()
        }
    }

    @Test func cachedBoardIsDroppedWhenBoardIsOff() async throws {
        let h = Harness([.ok(snapshot("x"), hold: true)])
        try await h.store.save(withBoard(snapshot("cached")), account: "me", scope: .org("o"))
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start(canReadProjects: false)
        let first = try #require(await updates.next())
        #expect(first.0?.boardIssues.isEmpty == true)
    }

    // MARK: Signed out

    @Test func signedOutStopsScheduling() async throws {
        let h = Harness([.fail(AuthError.signedOut(appAccount)), .ok(snapshot("later"))])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        #expect(await nextSettled(&updates)?.1.error == .signedOut(appAccount))
        #expect(await !eventually(within: .milliseconds(200)) { !h.clock.requestedSleeps.isEmpty })
        h.clock.advance(by: .seconds(3600))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 })
    }

    @Test func refreshNowResumesAfterSignedOut() async throws {
        let fresh = snapshot("fresh")
        let h = Harness([.fail(AuthError.signedOut(appAccount)), .ok(fresh), .ok(snapshot("later"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start(interval: .seconds(120))
        _ = await nextSettled(&updates)
        #expect(await nextSettled(&updates)?.1.error == .signedOut(appAccount))
        await h.coordinator.refreshNow()
        let update = try #require(await nextSettled(&updates))
        #expect(update.0 == fresh)
        #expect(update.1.error == nil)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        h.clock.advance(by: .seconds(120))
        await h.fetcher.waitForCalls(3)
    }

    @Test func refreshIfOlderThanSkipsWhileSignedOut() async throws {
        let h = Harness([.fail(AuthError.signedOut(appAccount)), .ok(snapshot("later")), .ok(snapshot("again"))])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        _ = await nextSettled(&updates)
        h.now.set(t0.addingTimeInterval(3600))
        await h.coordinator.refreshIfOlderThan(.seconds(30))
        #expect(await h.fetcher.callCount == 1)
        await h.coordinator.refreshNow()
        #expect(await h.fetcher.callCount == 2)
    }

    // MARK: Network recovery

    /// The path coming back after an offline failure refreshes after the 2 s debounce, not the 15 s
    /// backoff; the backoff timer is left as it was.
    @Test func pathRecoveryRefreshesBeforeTheBackoff() async throws {
        let offline = APIError.network("offline")
        let h = Harness([.fail(offline), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(15)])
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await h.clock.waitForSleeps(2) == [.seconds(15), .seconds(2)])
        h.clock.advance(by: .seconds(2))
        await h.fetcher.waitForCalls(2)
        #expect(await h.fetcher.callCount == 2)
    }

    @Test func pathChangesWhileOnlineRefreshNothing() async throws {
        let h = Harness([.ok(snapshot("x")), .ok(snapshot("y"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        await h.coordinator.networkPathChanged(satisfied: true)
        await h.coordinator.networkPathChanged(satisfied: true)
        // Down and back with the data fresh: nothing to recover either.
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await !eventually(within: .milliseconds(200)) { h.clock.requestedSleeps.count > 1 })
        h.clock.advance(by: .seconds(2))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 })
    }

    /// Flapping restarts the debounce each time it comes back: one refresh, 2 s after the last change.
    @Test func pathFlappingIsDebounced() async throws {
        let offline = APIError.network("offline")
        let h = Harness([.fail(offline), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        _ = await h.clock.waitForSleeps(2)
        h.clock.advance(by: .seconds(1))
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await h.clock.waitForSleeps(3) == [.seconds(15), .seconds(2), .seconds(2)])
        h.clock.advance(by: .seconds(1))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 })
        h.clock.advance(by: .seconds(1))
        await h.fetcher.waitForCalls(2)
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 2 })
    }

    /// After wake the path coming back refreshes; with the wake's refresh still in flight it joins
    /// that fetch rather than starting another.
    @Test func wakeRecoveryJoinsTheFetchInFlight() async throws {
        let h = Harness([.ok(snapshot("x"), hold: true)])
        await h.start()
        await h.fetcher.waitForCalls(1)
        await h.coordinator.didWake()
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(2)])
        h.clock.advance(by: .seconds(2))
        let coordinator = h.coordinator
        #expect(await eventually { await coordinator.joinedWaiters == 1 }, "the recovery did not join")
        await h.fetcher.releaseHeld()
        #expect(await eventually { await coordinator.joinedWaiters == 0 })
        #expect(await h.fetcher.callCount == 1)
    }

    /// A wake whose refresh succeeded has nothing left to recover.
    @Test func wakeAfterASuccessfulRefreshRecoversNothing() async throws {
        let h = Harness([.ok(snapshot("x")), .ok(snapshot("y"), hold: true)])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.coordinator.didWake()
        await h.start(interval: .seconds(120))
        _ = await nextSettled(&updates)
        #expect(await nextSettled(&updates)?.1.error == nil)
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await !eventually(within: .milliseconds(200)) { h.clock.requestedSleeps.contains(.seconds(2)) })
    }

    /// A joined fetch that hung from before the path came back and then fails offline arms the
    /// debounce once more instead of leaving the icon offline until the backoff.
    @Test func hungFetchFailingAfterRecoveryRefreshesAgain() async throws {
        let offline = APIError.network("timed out")
        let h = Harness([.fail(offline, hold: true), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        await h.fetcher.waitForCalls(1)
        await h.coordinator.didWake()
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(2)])
        h.clock.advance(by: .seconds(2))
        let coordinator = h.coordinator
        #expect(await eventually { await coordinator.joinedWaiters == 1 }, "the recovery did not join")
        await h.fetcher.releaseHeld()
        #expect(await h.clock.waitForSleeps(3).sorted() == [.seconds(2), .seconds(2), .seconds(15)])
        h.clock.advance(by: .seconds(2))
        await h.fetcher.waitForCalls(2)
    }

    /// A new loop told the path is satisfied refreshes nothing for that alone, and its first fetch
    /// failing offline still gets the one extra refresh after 2 s.
    @Test func freshLoopToldSatisfiedRetriesItsFirstOfflineFailure() async throws {
        let offline = APIError.network("offline")
        let h = Harness([.fail(offline, hold: true), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        await h.coordinator.networkPathChanged(satisfied: true)
        await h.fetcher.waitForCalls(1)
        #expect(await !eventually(within: .milliseconds(200)) { !h.clock.requestedSleeps.isEmpty })
        await h.fetcher.releaseHeld()
        #expect(await h.clock.waitForSleeps(2).sorted() == [.seconds(2), .seconds(15)])
        h.clock.advance(by: .seconds(2))
        await h.fetcher.waitForCalls(2)
    }

    /// The extra refresh after an offline failure happens once per satisfied stretch: later failures
    /// wait for the backoff, never a 2 s retry loop.
    @Test func offlineFailuresWhileSatisfiedRetryOnlyOnce() async throws {
        let offline = APIError.network("offline")
        let h = Harness([.fail(offline), .fail(offline), .fail(offline), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        #expect(await h.clock.waitForSleeps(1) == [.seconds(15)])
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        _ = await h.clock.waitForSleeps(2)
        h.clock.advance(by: .seconds(2))
        await h.fetcher.waitForCalls(2)
        // The second failure: its backoff (30 s) and the one extra refresh.
        #expect(await h.clock.waitForSleeps(4).dropFirst(2).sorted() == [.seconds(2), .seconds(30)])
        h.clock.advance(by: .seconds(2))
        await h.fetcher.waitForCalls(3)
        // The third: only its backoff (60 s).
        #expect(await h.clock.waitForSleeps(5).last == .seconds(60))
        #expect(await !eventually(within: .milliseconds(200)) { h.clock.requestedSleeps.count > 5 })
        h.clock.advance(by: .seconds(2))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 3 })
        #expect(h.clock.requestedSleeps.filter { $0 == .seconds(2) }.count == 2)
    }

    /// Only a genuine offline failure is recovered early: the path coming back after an unreachable
    /// one (TLS, a bad response) or a refused 403 refreshes nothing.
    @Test(arguments: [APIError.unreachable(.secureConnectionFailed), .unreachable(.badServerResponse), .forbidden])
    func pathRecoveryIgnoresOtherFailures(failure: APIError) async throws {
        let h = Harness([.fail(failure), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await !eventually(within: .milliseconds(200)) { h.clock.requestedSleeps.contains(.seconds(2)) })
        #expect(await h.coordinator.heldStatus.error == RefreshError(failure))
        #expect(await h.fetcher.callCount == 1)
    }

    /// A debounce timer replaced after its sleep ended (its `recover` already queued) does nothing;
    /// the newer timer still runs.
    @Test func staleRecoveryTimerDoesNothing() async throws {
        let offline = APIError.network("offline")
        let h = Harness([.fail(offline), .ok(snapshot("x"), hold: true)])
        await h.start(interval: .seconds(120))
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        _ = await h.clock.waitForSleeps(2)
        let stale = await h.coordinator.recoveryToken
        await h.coordinator.networkPathChanged(satisfied: true)
        _ = await h.clock.waitForSleeps(3)
        await h.coordinator.recover(stale)
        #expect(await h.fetcher.callCount == 1)
        #expect(h.clock.pendingSleepers == 2)
        h.clock.advance(by: .seconds(2))
        await h.fetcher.waitForCalls(2)
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 2 })
    }

    @Test func recoverySkipsDuringARateLimitWait() async throws {
        let h = Harness([.fail(APIError.rateLimited(resetAt: t0.addingTimeInterval(300))), .ok(snapshot("x"))])
        await h.start()
        #expect(await h.clock.waitForSleeps(1) == [.seconds(300)])
        await h.coordinator.didWake()
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await h.clock.waitForSleeps(2) == [.seconds(300), .seconds(2)])
        h.clock.advance(by: .seconds(2))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 })
    }

    @Test func recoverySkipsWhileSignedOut() async throws {
        let h = Harness([.fail(AuthError.signedOut(appAccount)), .ok(snapshot("x"))])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start()
        _ = await nextSettled(&updates)
        #expect(await nextSettled(&updates)?.1.error == .signedOut(appAccount))
        await h.coordinator.didWake()
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(2)])
        h.clock.advance(by: .seconds(2))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 })
    }

    @Test func stopCancelsAPendingRecovery() async throws {
        let h = Harness([.fail(APIError.network("offline")), .ok(snapshot("x"))])
        await h.start()
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        _ = await h.clock.waitForSleeps(2)
        await h.coordinator.stop()
        #expect(await eventually { h.clock.pendingSleepers == 0 }, "sleepers were still pending")
        h.clock.advance(by: .seconds(2))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.callCount > 1 })
    }

    @Test func restartCancelsAPendingRecovery() async throws {
        let h = Harness([.fail(APIError.network("offline")), .ok(snapshot("x"), hold: true)])
        await h.start()
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.networkPathChanged(satisfied: false)
        await h.coordinator.networkPathChanged(satisfied: true)
        _ = await h.clock.waitForSleeps(2)
        await h.start("other")
        await h.fetcher.waitForCalls(2)
        h.clock.advance(by: .seconds(2))
        let coordinator = h.coordinator
        #expect(await !eventually(within: .milliseconds(200)) { await coordinator.joinedWaiters > 0 })
    }

    @Test func stopCancelsLoop() async throws {
        let h = Harness([.fail(APIError.network("x")), .ok(snapshot("x"))])
        await h.start()
        _ = await h.clock.waitForSleeps(1)
        await h.coordinator.stop()
        #expect(await eventually { h.clock.pendingSleepers == 0 }, "sleepers were still pending")
        h.clock.advance(by: .seconds(600))
        await h.coordinator.refreshNow()
        #expect(await h.fetcher.callCount == 1)
    }
}

// MARK: - Error mapping

@Suite struct RefreshErrorTests {
    @Test func mapsKnownErrors() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RefreshError(APIError.network("x")) == .offline)
        #expect(RefreshError(APIError.unreachable(.secureConnectionFailed)) == .unreachable(.secureConnectionFailed))
        #expect(RefreshError(APIError.forbidden) == .forbidden)
        #expect(RefreshError(APIError.unauthorized) == .unauthorized)
        #expect(RefreshError(APIError.rateLimited(resetAt: reset)) == .rateLimited(reset))
        #expect(RefreshError(APIError.rateLimited(resetAt: nil)) == .rateLimited(nil))
        #expect(RefreshError(GhError.notInstalled) == .ghMissing)
        #expect(RefreshError(GhError.notLoggedIn("devon")) == .notLoggedIn("devon"))
        #expect(RefreshError(GhError.failed("boom")) == .other("boom"))
        #expect(RefreshError(APIError.graphQL("bad query")) == .other("bad query"))
        #expect(RefreshError(APIError.server(502)) == .other("GitHub server error 502"))
        let sso = URL(string: "https://github.com/orgs/acme/sso?authorization_request=abc")
        #expect(RefreshError(AuthError.signedOut(appAccount)) == .signedOut(appAccount))
        #expect(RefreshError(APIError.ssoRequired(sso)) == .ssoRequired(sso))
        #expect(RefreshError(CredentialStoreError.locked) == .other("Keychain is locked"))
    }

    /// Refresh failures the broker doesn't turn into a sign-out or `APIError.network` are token-free
    /// poll errors.
    @Test func mapsDeviceFlowErrors() {
        #expect(RefreshError(DeviceFlowError.network) == .offline)
        #expect(RefreshError(DeviceFlowError.unexpected("secure connection failed"))
            == .other("Couldn't renew the GitHub sign-in (secure connection failed)"))
        #expect(RefreshError(DeviceFlowError.unexpected("HTTP 500"))
            == .other("Couldn't renew the GitHub sign-in (HTTP 500)"))
        #expect(RefreshError(DeviceFlowError.misconfigured)
            == .other("Couldn't renew the GitHub sign-in (app misconfigured)"))
        #expect(RefreshError(DeviceFlowError.expired) == .other("Couldn't renew the GitHub sign-in"))
    }

    @Test func signedOutMessage() {
        #expect(RefreshError.signedOut(appAccount).message == "Signed out of GitHub")
        #expect(RefreshError.unauthorized.message == "Token rejected — run gh auth login")
    }

    @Test func messageBySource() {
        #expect(RefreshError.unauthorized.message(org: "acme", source: .gitHubApp) == "GitHub rejected the sign-in")
        #expect(RefreshError.unauthorized.message(org: "acme", source: .gh) == "Token rejected — run gh auth login")
        #expect(RefreshError.unauthorized.message(org: nil, source: nil) == "Token rejected — run gh auth login")
        #expect(RefreshError.ssoRequired(nil).message(org: "acme", source: .gitHubApp)
            == "acme uses single sign-on. Sign in on GitHub, then Retry")
        #expect(RefreshError.signedOut(appAccount).message(org: "acme", source: .gitHubApp) == "Signed out of GitHub")
    }

    @Test func ssoMessage() {
        #expect(RefreshError.ssoRequired(nil).message == "Single sign-on required")
        #expect(RefreshError.ssoRequired(nil).message(org: "acme")
            == "acme uses single sign-on. Sign in on GitHub, then Retry")
        #expect(RefreshError.ssoRequired(nil).message(org: nil) == "Single sign-on required")
        #expect(RefreshError.offline.message(org: "acme") == "Offline")
    }

    @Test func staleness() {
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        let ok = RefreshStatus(lastSuccess: last, error: nil, isRefreshing: true)
        #expect(!ok.isStale(now: last.addingTimeInterval(240), interval: .seconds(120)))
        #expect(ok.isStale(now: last.addingTimeInterval(241), interval: .seconds(120)))
        #expect(!RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: true)
            .isStale(now: last, interval: .seconds(120)))
    }

    @Test func messages() {
        #expect(RefreshError.offline.message == "Offline")
        #expect(RefreshError.unauthorized.message == "Token rejected — run gh auth login")
        #expect(RefreshError.ghMissing.message == "gh not found")
        #expect(RefreshError.notLoggedIn("devon").message == "Log in to devon with gh auth login")
        #expect(RefreshError.other("boom").message == "boom")
        #expect(RefreshError.rateLimited(nil).message == "Rate limited")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let reset = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 14, minute: 5))!
        #expect(RefreshError.rateLimited(reset).message == "Rate limited until 14:05")
    }
}

// MARK: - Fast CI follow

private let followKey = PRKey(repo: "o/r", number: 5)

private func mine(_ ci: CIState, title: String = "mine", at date: Date = t0) -> PullRequest {
    PullRequest(
        key: followKey, title: title, url: URL(string: "https://x/5")!,
        author: "me", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: date, updatedAt: date, closedAt: nil, headRef: "h", baseRef: "main", ci: ci,
        headCommitDate: date, commentCount: 0, lastCommentAuthor: nil, latestReviews: [], reviewRequests: [],
        headCommitOid: "abc", mergeable: .mergeable)
}

/// `snapshot(title)` with one of my PRs in Mine, its CI `ci`.
private func withMine(_ ci: CIState, title: String = "full", at date: Date = t0) -> Snapshot {
    var snap = snapshot(title, at: date)
    snap.mine = [mine(ci, at: date)]
    return snap
}

private func thirties(_ sleeps: [Duration]) -> Int { sleeps.filter { $0 == .seconds(30) }.count }

extension RefreshCoordinatorTests {
    @Test func followPollsPendingMinePRsEvery30s() async throws {
        let full = withMine(.pending)
        let h = Harness([.ok(full), .ok(withMine(.failure, at: t0.addingTimeInterval(120)), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.failure, title: "followed")])])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start(interval: .seconds(120), followsPendingCI: true)
        _ = await nextSettled(&updates)
        #expect(await nextSettled(&updates)?.0 == full)
        await h.clock.waitForSleeps { $0.contains(.seconds(120)) && thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        let followed = try #require(await updates.next())
        #expect(await h.fetcher.followCalls == [[followKey]])
        #expect(followed.0?.mine == [mine(.failure, title: "followed")])
        #expect(followed.0?.reviewCandidates == full.reviewCandidates)
        #expect(followed.0?.fetchedAt == full.fetchedAt)
        #expect(followed.1.lastSuccess == full.fetchedAt)
        #expect(followed.1.error == nil)
        #expect(!followed.1.isRefreshing)
        #expect(followed.1.isCIFollow)
        #expect(await h.coordinator.heldStatus.isCIFollow == false)
        #expect(await h.store.load(account: "me", scope: .org("o"))?.mine.first?.ci == .failure)
    }

    @Test func followRepeatsWhilePendingUntilTheFullRefreshIsNear() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(withMine(.pending, at: t0.addingTimeInterval(120)), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.pending)]), .ok([mine(.pending)])])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        await h.clock.waitForSleeps { thirties($0) == 2 }
        h.now.set(t0.addingTimeInterval(60))
        h.clock.advance(by: .seconds(30))
        await h.clock.waitForSleeps { thirties($0) == 3 }
        #expect(await h.fetcher.followCalls.count == 2)
        // At 90 s the full refresh is due in 30 s: no follow, and none scheduled.
        h.now.set(t0.addingTimeInterval(90))
        h.clock.advance(by: .seconds(30))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.followCalls.count > 2 })
        #expect(thirties(h.clock.requestedSleeps) == 3)
    }

    @Test func followStopsWhenNoPending() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(snapshot("next"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.success)])])
        var updates = h.coordinator.updates.makeAsyncIterator()
        await h.start(interval: .seconds(120), followsPendingCI: true)
        _ = await nextSettled(&updates)
        _ = await nextSettled(&updates)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(try #require(await updates.next()).0?.mine.first?.ci == .success)
        #expect(await !eventually(within: .milliseconds(200)) { thirties(h.clock.requestedSleeps) > 1 })
        #expect(h.clock.pendingSleepers == 1)
        #expect(await h.fetcher.followCalls.count == 1)
    }

    @Test func followNeverRunsDuringFullRefresh() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(withMine(.pending, title: "second"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.failure)])])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        let coordinator = h.coordinator
        let refresh = Task { await coordinator.refreshNow() }
        await h.fetcher.waitForCalls(2)
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.followCalls.count > 0 })
        await h.fetcher.releaseHeld()
        await refresh.value
        // The full refresh still sees a pending PR, so following starts again from it.
        await h.clock.waitForSleeps { thirties($0) == 2 }
        #expect(await h.fetcher.followCalls.isEmpty)
    }

    @Test func followFailureIsSilent() async throws {
        let h = Harness([
            .ok(withMine(.pending)), .ok(withMine(.pending, at: t0.addingTimeInterval(120))),
            .ok(snapshot("third"), hold: true),
        ])
        await h.fetcher.setFollows([.fail(APIError.server(502)), .ok([mine(.pending)])])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 1 })
        #expect(await !eventually(within: .milliseconds(200)) { thirties(h.clock.requestedSleeps) > 1 })
        #expect(await h.coordinator.heldStatus.error == nil)
        #expect(await h.coordinator.heldStatus.lastSuccess == t0)
        // The next full refresh succeeds and following resumes.
        h.now.set(t0.addingTimeInterval(120))
        h.clock.advance(by: .seconds(90))
        await h.fetcher.waitForCalls(2)
        await h.clock.waitForSleeps { thirties($0) == 2 }
        h.now.set(t0.addingTimeInterval(150))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 2 })
    }

    @Test func followOffWhenSettingOff() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(snapshot("next"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.failure)])])
        await h.start(interval: .seconds(120), followsPendingCI: false)
        #expect(await h.clock.waitForSleeps(1) == [.seconds(120)])
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.followCalls.count > 0 })
        #expect(thirties(h.clock.requestedSleeps) == 0)
    }

    @Test func updateTurnsFollowOffAndOn() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(snapshot("next"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.pending)])])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        await h.coordinator.update(
            board: .org("o", 3), canReadProjects: true, interval: .seconds(120), followsPendingCI: false)
        #expect(await eventually { h.clock.pendingSleepers == 1 })
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.followCalls.count > 0 })
        await h.coordinator.update(
            board: .org("o", 3), canReadProjects: true, interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 2 }
        h.now.set(t0.addingTimeInterval(60))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 1 })
    }

    @Test func followSkipsWithOneMinuteInterval() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(snapshot("next"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.failure)])])
        await h.start(interval: .seconds(60), followsPendingCI: true)
        await h.clock.waitForSleeps { $0.contains(.seconds(60)) && thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.followCalls.count > 0 })
        #expect(thirties(h.clock.requestedSleeps) == 1)
    }

    @Test func followStopsWhenAFullRefreshFails() async throws {
        let h = Harness([.ok(withMine(.pending)), .fail(APIError.network("offline")), .ok(snapshot("x"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.failure)])])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        await h.coordinator.refreshNow()
        #expect(await h.coordinator.heldStatus.error == .offline)
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.followCalls.count > 0 })
    }

    @Test func followStopsWithTheLoop() async throws {
        let h = Harness([.ok(withMine(.pending))])
        await h.fetcher.setFollows([.ok([mine(.failure)])])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        await h.coordinator.stop()
        #expect(await eventually { h.clock.pendingSleepers == 0 })
        h.clock.advance(by: .seconds(30))
        #expect(await !eventually(within: .milliseconds(200)) { await h.fetcher.followCalls.count > 0 })
    }

    /// `stop()` waits for a follow in flight, which then writes nothing.
    @Test func stopWaitsForAFollowInFlight() async throws {
        let full = withMine(.pending)
        let h = Harness([.ok(full)])
        await h.fetcher.setFollows([.ok([mine(.failure)], hold: true)])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 1 })
        let stopped = StopFlag()
        let coordinator = h.coordinator
        let stopping = Task {
            await coordinator.stop()
            stopped.set()
        }
        #expect(await !eventually(within: .milliseconds(200)) { stopped.isSet })
        await h.fetcher.releaseFollows()
        await stopping.value
        #expect(await h.coordinator.droppedFollows == 1)
        #expect(await h.store.load(account: "me", scope: .org("o")) == full)
    }

    /// Turned off and on again while a follow runs: that follow is dropped without blocking the next.
    @Test func followCancelledByTheToggleDoesNotBlock() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(snapshot("next"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.pending)], hold: true), .ok([mine(.failure)])])
        await h.start(interval: .seconds(300), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 1 })
        await h.coordinator.update(
            board: .org("o", 3), canReadProjects: true, interval: .seconds(300), followsPendingCI: false)
        await h.coordinator.update(
            board: .org("o", 3), canReadProjects: true, interval: .seconds(300), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 2 }
        await h.fetcher.releaseFollows()
        #expect(await eventually { await h.coordinator.droppedFollows == 1 })
        h.now.set(t0.addingTimeInterval(60))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 2 })
        #expect(await eventually { await h.coordinator.heldSnapshot?.mine.first?.ci == .failure })
    }

    /// A follow that returns after a full refresh started never replaces that refresh's data.
    @Test func followResultNeverOverwritesANewerFullRefresh() async throws {
        let newer = withMine(.success, title: "newer", at: t0.addingTimeInterval(40))
        let h = Harness([.ok(withMine(.pending)), .ok(newer), .ok(snapshot("x"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.failure, title: "stale")], hold: true)])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 1 })
        h.now.set(t0.addingTimeInterval(40))
        await h.coordinator.refreshNow()
        #expect(await h.coordinator.heldSnapshot == newer)
        await h.fetcher.releaseFollows()
        #expect(await eventually { await h.coordinator.droppedFollows == 1 })
        #expect(await h.coordinator.heldSnapshot == newer)
        #expect(await h.store.load(account: "me", scope: .org("o")) == newer)
    }

    /// The same, when the full refresh is still running as the follow returns.
    @Test func followResultIsDroppedWhileAFullRefreshRuns() async throws {
        let h = Harness([.ok(withMine(.pending)), .ok(withMine(.success, title: "newer"), hold: true)])
        await h.fetcher.setFollows([.ok([mine(.failure, title: "stale")], hold: true)])
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        #expect(await eventually { await h.fetcher.followCalls.count == 1 })
        let coordinator = h.coordinator
        let refresh = Task { await coordinator.refreshNow() }
        await h.fetcher.waitForCalls(2)
        await h.fetcher.releaseFollows()
        #expect(await eventually { await h.coordinator.droppedFollows == 1 })
        #expect(await h.coordinator.heldSnapshot?.mine.first?.title == "mine")
        await h.fetcher.releaseHeld()
        await refresh.value
        #expect(await h.coordinator.heldSnapshot?.mine.first?.ci == .success)
    }

    /// Fed through the notification gate as the app feeds it: CI failed fires once, from the follow,
    /// and the next full refresh, which sees the same failure, fires nothing.
    @Test func followNotifiesOnceAcrossTheNextFullRefresh() async throws {
        let h = Harness([
            .ok(withMine(.pending)), .ok(withMine(.failure, title: "second", at: t0.addingTimeInterval(120))),
            .ok(snapshot("x"), hold: true),
        ])
        await h.fetcher.setFollows([.ok([mine(.failure)])])
        var gate = NotificationGate(launchedAt: t0.addingTimeInterval(-1))
        var kinds: [PREventKind] = []
        var updates = h.coordinator.updates.makeAsyncIterator()
        func drain(_ count: Int) async {
            for _ in 0..<count {
                guard let (snap, status) = await updates.next() else { return }
                kinds += gate.events(snapshot: snap, status: status, toggles: NotificationToggles()).map(\.kind)
            }
        }
        await h.start(interval: .seconds(120), followsPendingCI: true)
        await drain(3)  // cache, marker, first full refresh (the baseline)
        #expect(kinds.isEmpty)
        await h.clock.waitForSleeps { thirties($0) == 1 }
        h.now.set(t0.addingTimeInterval(30))
        h.clock.advance(by: .seconds(30))
        await drain(1)
        #expect(kinds == [.ciFailed])
        h.now.set(t0.addingTimeInterval(120))
        h.clock.advance(by: .seconds(90))
        await drain(2)  // marker, second full refresh
        #expect(await h.coordinator.heldSnapshot?.fetchedAt == t0.addingTimeInterval(120))
        #expect(kinds == [.ciFailed])
    }
}
