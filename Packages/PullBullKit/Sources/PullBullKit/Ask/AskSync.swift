import Foundation

/// How far the Ask index has got, for Settings → Ask.
public struct AskSyncProgress: Equatable, Sendable {
    public let indexed: Int
    /// GitHub's result counts for the backfill slices seen so far; nil outside a backfill.
    public let estimatedTotal: Int?
    public let backfilling: Bool
    public let lastSync: Date?

    public init(indexed: Int, estimatedTotal: Int?, backfilling: Bool, lastSync: Date?) {
        self.indexed = indexed
        self.estimatedTotal = estimatedTotal
        self.backfilling = backfilling
        self.lastSync = lastSync
    }
}

/// Keeps an `AskIndex` in step with GitHub for one scope: a backfill over the window, then incremental
/// syncs, with a weekly full re-sync that drops rows search no longer returns. Pages run one at a time,
/// a `pause` apart and never while a regular refresh runs; a rate limit stops all fetching until it resets.
public actor AskSync {
    public static let window: TimeInterval = 90 * 86_400
    /// How far before the last sync an incremental sync starts.
    static let overlap: TimeInterval = 10 * 60
    static let fullSyncInterval: TimeInterval = 7 * 86_400
    /// GitHub search returns at most this many results per query.
    static let resultCap = 1000
    /// A slice this short is not split further, even at the cap.
    static let minimumSlice: TimeInterval = 60
    /// How long to stop when a rate limit has no reset time.
    static let rateLimitFallback: TimeInterval = 60

    public nonisolated let progress: AsyncStream<AskSyncProgress>

    private let index: AskIndex
    private let fetcher: any AskFetching
    private let scope: FetchScope
    private let excluded: @Sendable () async -> Set<String>
    private let refreshing: @Sendable () async -> Bool
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let pause: Duration
    private let continuation: AsyncStream<AskSyncProgress>.Continuation

    private var running: Task<Void, Never>?
    private var blockedUntil: Date?
    /// Lowercased owner/name of every repo the current pass skips.
    private var skipped: Set<String> = []
    /// Lowercased keys the current full re-sync has seen; nil outside one.
    private var seen: Set<String>?
    private var backfilling = false
    private var estimateBase = 0
    private var estimate = 0

    public init(
        index: AskIndex, fetcher: any AskFetching, scope: FetchScope,
        excluded: @escaping @Sendable () async -> Set<String>,
        refreshing: @escaping @Sendable () async -> Bool,
        clock: any Clock<Duration> = ContinuousClock(), now: @escaping @Sendable () -> Date = Date.init,
        pause: Duration = .seconds(1)
    ) {
        self.index = index
        self.fetcher = fetcher
        self.scope = scope
        self.excluded = excluded
        self.refreshing = refreshing
        self.clock = clock
        self.now = now
        self.pause = pause
        (progress, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    deinit { continuation.finish() }

    // MARK: Entry points

    /// Backfills if no backfill has finished, runs a full re-sync when the last one is over a week old,
    /// and otherwise fetches what changed since the last sync. Returns at once while another pass runs.
    public func sync() async {
        guard running == nil, !isBlocked else { return }
        await run { try await $0.syncPass() }
    }

    /// Fetches `repo` (`owner/name`) over the window, as when it leaves the exclude list. Waits for a
    /// running pass first.
    public func backfill(repo: String) async {
        await waitForRunning()
        guard !isBlocked else { return }
        await run { try await $0.repoPass(repo) }
    }

    /// Deletes every row and the sync state, then syncs from scratch.
    public func rebuild() async {
        running?.cancel()
        await waitForRunning()
        await run { sync in
            try await sync.clear()
            guard await !sync.isBlocked else { return }
            try await sync.syncPass()
        }
    }

    /// Stops the running pass; it writes nothing further.
    public func cancel() {
        running?.cancel()
    }

    // MARK: Passes

    private var isBlocked: Bool { blockedUntil.map { now() < $0 } ?? false }

    private func run(_ work: @escaping @Sendable (AskSync) async throws -> Void) async {
        let task = Task {
            do {
                try await work(self)
            } catch let APIError.rateLimited(resetAt) {
                self.block(until: resetAt)
            } catch {}
            await self.finishPass()
        }
        running = task
        await task.value
        if running == task { running = nil }
    }

    private func waitForRunning() async {
        while let task = running {
            await task.value
            if running == task { running = nil }
        }
    }

    private func block(until resetAt: Date?) {
        blockedUntil = resetAt ?? now().addingTimeInterval(Self.rateLimitFallback)
    }

    private func clear() async throws {
        try await index.deleteRepos { _ in true }
        for key in [AskIndex.MetaKey.lastSync, .lastFullSync, .backfilledUntil] {
            try await index.setMeta(key, nil)
        }
    }

    private func syncPass() async throws {
        let start = Self.wholeSeconds(now())
        let windowStart = start.addingTimeInterval(-Self.window)
        try await prepareFilter()
        let skipped = skipped
        try await index.deleteRepos { [scope] in !scope.covers($0) || skipped.contains($0) }

        let base = scope.searchQualifier
        if try await index.meta(.lastFullSync) == nil {
            let resumeFrom = try await index.meta(.backfilledUntil)
            try await startBackfill()
            try await sweep(max(windowStart, resumeFrom ?? windowStart), start, base: base, records: true)
            try Task.checkCancellation()
            try await index.setMeta(.backfilledUntil, nil)
            try await index.setMeta(.lastFullSync, start)
        } else if let lastFull = try await index.meta(.lastFullSync),
                  start.timeIntervalSince(lastFull) > Self.fullSyncInterval {
            seen = []
            try await sweep(windowStart, start, base: base)
            try Task.checkCancellation()
            let seen = seen ?? []
            let stale = try await index.keys(updatedSince: windowStart).filter { !seen.contains($0.askKey.lowercased()) }
            try await index.delete(keys: stale)
            try await index.setMeta(.lastFullSync, start)
        } else {
            let last = try await index.meta(.lastSync) ?? start
            try await incremental(since: last.addingTimeInterval(-Self.overlap), until: start, base: base)
        }
        try Task.checkCancellation()
        try await index.prune(updatedBefore: windowStart)
        try await index.setMeta(.lastSync, start)
    }

    private func repoPass(_ repo: String) async throws {
        let start = Self.wholeSeconds(now())
        try await prepareFilter()
        try await startBackfill()
        try await sweep(start.addingTimeInterval(-Self.window), start, base: "repo:\(repo)")
    }

    private func prepareFilter() async throws {
        skipped = await excluded()
        try Task.checkCancellation()
    }

    private func startBackfill() async throws {
        backfilling = true
        estimate = 0
        estimateBase = try await index.count()
    }

    private func finishPass() async {
        backfilling = false
        seen = nil
        await report()
    }

    // MARK: Fetching

    /// Fetches PRs and issues updated since `since`, splitting the range if it hits the cap.
    private func incremental(since: Date, until upper: Date, base: String) async throws {
        for kind in [AskItem.Kind.pr, .issue] {
            let query = "\(base) is:\(kind.rawValue) updated:>=\(Self.format(since))"
            let first = try await fetch(query, after: nil)
            if first.total >= Self.resultCap {
                try await sweep(since, upper, base: base, kinds: [kind])
            } else {
                try await drain(query, from: first)
            }
        }
    }

    /// Fetches every item of `kinds` updated in `lower...upper`, halving the range for each kind whose
    /// query hits the cap, oldest half first. `reserved` is what the estimate already counts for this
    /// range per kind; nil keeps the estimate as it is (the parent's total stands in for the lower half).
    /// With `records`, the end of each finished range is saved as `backfilledUntil`. Returns each
    /// kind's total for the range.
    @discardableResult
    private func sweep(
        _ lower: Date, _ upper: Date, base: String, kinds: [AskItem.Kind] = [.pr, .issue],
        reserved: [AskItem.Kind: Int]? = [:], records: Bool = false
    ) async throws -> [AskItem.Kind: Int] {
        guard lower < upper else { return [:] }
        var totals: [AskItem.Kind: Int] = [:]
        var over: [AskItem.Kind] = []
        for kind in kinds {
            let query = "\(base) is:\(kind.rawValue) updated:\(Self.format(lower))..\(Self.format(upper))"
            let first = try await fetch(query, after: nil) { total in
                if let reserved { self.estimate += total - reserved[kind, default: 0] }
            }
            totals[kind] = first.total
            if first.total >= Self.resultCap, upper.timeIntervalSince(lower) > Self.minimumSlice {
                over.append(kind)
            } else {
                try await drain(query, from: first)
            }
        }
        if !over.isEmpty {
            let mid = Self.wholeSeconds(Date(
                timeIntervalSince1970: (lower.timeIntervalSince1970 + upper.timeIntervalSince1970) / 2))
            let lowTotals = try await sweep(lower, mid, base: base, kinds: over, reserved: nil, records: records)
            var rest: [AskItem.Kind: Int] = [:]
            for kind in over { rest[kind] = totals[kind, default: 0] - lowTotals[kind, default: 0] }
            try await sweep(mid, upper, base: base, kinds: over, reserved: rest, records: records)
        }
        if records {
            try Task.checkCancellation()
            try await index.setMeta(.backfilledUntil, upper)
        }
        return totals
    }

    private func drain(_ query: String, from page: AskPage) async throws {
        var next = page.next
        while let cursor = next {
            next = try await fetch(query, after: cursor).next
        }
    }

    /// Waits its turn, fetches one page and stores what the scope and exclude list allow.
    /// `counted` sees the page's total before progress is reported.
    private func fetch(
        _ query: String, after: String?, counted: (Int) -> Void = { _ in }
    ) async throws -> AskPage {
        try Task.checkCancellation()
        while await refreshing() {
            try await clock.sleep(for: pause)
        }
        try await clock.sleep(for: pause)
        let page = try await fetcher.askPage(query: query, after: after)
        try Task.checkCancellation()
        seen?.formUnion(page.items.map { $0.key.askKey.lowercased() })
        let kept = page.items.filter { scope.covers($0.key.repo) && !skipped.contains($0.key.repo.lowercased()) }
        try await index.upsert(kept)
        counted(page.total)
        await report()
        return page
    }

    private func report() async {
        let indexed = (try? await index.count()) ?? 0
        let lastSync = (try? await index.meta(.lastSync)) ?? nil
        continuation.yield(AskSyncProgress(
            indexed: indexed, estimatedTotal: backfilling ? estimateBase + estimate : nil,
            backfilling: backfilling, lastSync: lastSync))
    }

    // MARK: Dates

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// ISO 8601 UTC to the second, as GitHub's `updated:` qualifier takes it.
    static func format(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
