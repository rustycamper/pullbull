import Foundation
import Testing
@testable import PullBullKit

/// 2026-10-29T10:00:00Z.
private let t0 = Date(timeIntervalSince1970: 1_793_268_000)
private let day: TimeInterval = 86_400

private final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}

private func iso(_ date: Date) -> String { date.formatted(.iso8601) }

private func item(_ repo: String, _ number: Int, kind: AskItem.Kind = .issue, updated: Date) -> AskItem {
    AskItem(
        key: PRKey(repo: repo, number: number), kind: kind, state: "open", author: "ann",
        created: updated.addingTimeInterval(-day), updated: updated, labels: [], title: "t\(number)", body: "b")
}

/// Serves `items` like GitHub search: honors `is:`, `repo:` and `updated:` qualifiers, 100 per page,
/// and never more than the first 1,000 results of a query.
private actor FakeAskFetcher: AskFetching {
    struct Call: Sendable { let query: String; let after: String?; let total: Int }

    var items: [AskItem]
    private(set) var calls: [Call] = []
    /// Thrown by the call with this 1-based number.
    var failures: [Int: any Error] = [:]
    var onFetch: (@Sendable (Int) async -> Void)?

    init(_ items: [AskItem]) { self.items = items }

    var queries: [String] { calls.map(\.query) }
    func setItems(_ items: [AskItem]) { self.items = items }
    func fail(call: Int, with error: any Error) { failures[call] = error }
    func setOnFetch(_ hook: @escaping @Sendable (Int) async -> Void) { onFetch = hook }

    func askPage(query: String, after: String?) async throws -> AskPage {
        let number = calls.count + 1
        let matches = items.filter { Self.matches($0, query) }.sorted { $0.updated > $1.updated }
        calls.append(Call(query: query, after: after, total: matches.count))
        await onFetch?(number)
        if let error = failures.removeValue(forKey: number) { throw error }
        let offset = after.flatMap(Int.init) ?? 0
        let end = min(offset + 100, matches.count, 1000)
        let slice = offset < end ? Array(matches[offset..<end]) : []
        return AskPage(items: slice, total: matches.count, next: end < min(matches.count, 1000) ? String(end) : nil)
    }

    private static func matches(_ item: AskItem, _ query: String) -> Bool {
        for token in query.split(separator: " ").map(String.init) {
            if token == "is:pr", item.kind != .pr { return false }
            if token == "is:issue", item.kind != .issue { return false }
            if token.hasPrefix("repo:"), token.dropFirst(5).lowercased() != item.key.repo.lowercased() { return false }
            if token.hasPrefix("updated:>=") {
                guard let since = try? Date(String(token.dropFirst(10)), strategy: .iso8601) else { return false }
                if item.updated < since { return false }
            } else if token.hasPrefix("updated:") {
                let bounds = token.dropFirst(8).components(separatedBy: "..")
                guard bounds.count == 2, let lower = try? Date(bounds[0], strategy: .iso8601),
                      let upper = try? Date(bounds[1], strategy: .iso8601) else { return false }
                if item.updated < lower || item.updated > upper { return false }
            }
        }
        return true
    }
}

private struct Harness {
    let index: AskIndex
    let fetcher: FakeAskFetcher
    let clock: TestClock
    let now: Box<Date>
    let refreshing: Box<Bool>
    let sync: AskSync

    init(
        _ items: [AskItem], scope: FetchScope = .org("acme"), excluded: Set<String> = [],
        pause: Duration = .zero
    ) throws {
        index = try AskIndex(fileURL: AskIndexTests.tempURL())
        fetcher = FakeAskFetcher(items)
        clock = TestClock()
        let now = Box(t0)
        let refreshing = Box(false)
        self.now = now
        self.refreshing = refreshing
        sync = AskSync(
            index: index, fetcher: fetcher, scope: scope, excluded: { excluded },
            refreshing: { refreshing.get() }, clock: clock, now: { now.get() }, pause: pause)
    }

    func stored() async throws -> Set<String> {
        try await index.keys(updatedSince: .distantPast).reduce(into: []) { $0.insert($1.askKey) }
    }
}

@Suite struct AskSyncTests {
    @Test func backfillSplitsRangesOver1000() async throws {
        let items = (0..<1500).map { item("acme/web", $0, updated: t0.addingTimeInterval(-Double($0) * 5000)) }
        let h = try Harness(items)
        await h.sync.sync()
        #expect(try await h.index.count() == 1500)
        let calls = await h.fetcher.calls
        #expect(calls.first { $0.query.contains("is:issue") }?.total == 1500)
        #expect(calls.filter { $0.after != nil }.allSatisfy { $0.total < 1000 })
        #expect(calls.contains { $0.after != nil })
    }

    @Test func backfillQueriesPRsAndIssuesSeparately() async throws {
        let h = try Harness([
            item("acme/web", 1, kind: .pr, updated: t0.addingTimeInterval(-day)),
            item("acme/web", 2, kind: .issue, updated: t0.addingTimeInterval(-day)),
        ])
        await h.sync.sync()
        let queries = await h.fetcher.queries
        let window = "updated:\(iso(t0.addingTimeInterval(-AskSync.window)))..\(iso(t0))"
        #expect(queries == ["org:acme is:pr \(window)", "org:acme is:issue \(window)"])
        #expect(try await h.index.count() == 2)
    }

    @Test func incrementalUsesTenMinuteOverlap() async throws {
        let h = try Harness([item("acme/web", 1, updated: t0.addingTimeInterval(-day))])
        await h.sync.sync()
        let before = await h.fetcher.calls.count
        h.now.set(t0.addingTimeInterval(3600))
        await h.fetcher.setItems([item("acme/web", 2, kind: .pr, updated: t0.addingTimeInterval(1800))])
        await h.sync.sync()
        let queries = await h.fetcher.queries.dropFirst(before)
        #expect(Array(queries) == [
            "org:acme is:pr updated:>=2026-10-29T09:50:00Z", "org:acme is:issue updated:>=2026-10-29T09:50:00Z",
        ])
        #expect(try await h.stored() == ["acme/web#1", "acme/web#2"])
        #expect(try await h.index.meta(.lastSync) == t0.addingTimeInterval(3600))
    }

    @Test func excludedAndUncoveredReposNeverStored() async throws {
        let recent = t0.addingTimeInterval(-day)
        let h = try Harness(
            [item("Me/A", 1, updated: recent), item("me/b", 2, updated: recent), item("me/c", 3, updated: recent)],
            scope: .personal(login: "me", repos: ["me/a", "me/c"]), excluded: ["me/a"])
        await h.sync.sync()
        #expect(await h.fetcher.queries.allSatisfy { $0.hasPrefix("user:me ") })
        #expect(try await h.stored() == ["me/c#3"])
    }

    @Test func syncDeletesRowsOutOfScopeAndExcluded() async throws {
        let recent = t0.addingTimeInterval(-day)
        let h = try Harness([], scope: .personal(login: "me"), excluded: ["me/hidden"])
        try await h.index.upsert([
            item("other/x", 1, updated: recent), item("Me/Hidden", 2, updated: recent), item("me/kept", 3, updated: recent),
        ])
        await h.sync.sync()
        #expect(try await h.stored() == ["me/kept#3"])
    }

    @Test func fullResyncDeletesUnseenRows() async throws {
        let a = item("acme/web", 1, updated: t0.addingTimeInterval(-10 * day))
        let b = item("acme/web", 2, updated: t0.addingTimeInterval(-10 * day))
        let h = try Harness([a, b])
        await h.sync.sync()
        await h.fetcher.setItems([a])

        h.now.set(t0.addingTimeInterval(day))
        await h.sync.sync()
        #expect(try await h.stored() == ["acme/web#1", "acme/web#2"])

        let later = t0.addingTimeInterval(8 * day)
        h.now.set(later)
        let before = await h.fetcher.calls.count
        await h.sync.sync()
        #expect(try await h.stored() == ["acme/web#1"])
        let window = "updated:\(iso(later.addingTimeInterval(-AskSync.window)))..\(iso(later))"
        #expect(await h.fetcher.queries.dropFirst(before).first == "org:acme is:pr \(window)")
        #expect(try await h.index.meta(.lastFullSync) == later)
    }

    @Test func pruneAfterSync() async throws {
        let h = try Harness([])
        try await h.index.upsert([
            item("acme/web", 1, updated: t0.addingTimeInterval(-91 * day)),
            item("acme/web", 2, updated: t0.addingTimeInterval(-30 * day)),
        ])
        await h.sync.sync()
        #expect(try await h.stored() == ["acme/web#2"])
    }

    @Test func pacesPagesAndWaitsForRefresh() async throws {
        let items = (0..<150).map { item("acme/web", $0, kind: .pr, updated: t0.addingTimeInterval(Double($0))) }
        let h = try Harness(items, pause: .seconds(1))
        try await h.index.setMeta(.lastFullSync, t0)
        try await h.index.setMeta(.lastSync, t0)
        h.now.set(t0.addingTimeInterval(3600))
        h.refreshing.set(true)
        let task = Task { await h.sync.sync() }

        _ = await h.clock.waitForSleeps(1)
        h.clock.advance(by: .seconds(1))
        _ = await h.clock.waitForSleeps(2)
        #expect(await h.fetcher.calls.isEmpty)
        h.refreshing.set(false)
        h.clock.advance(by: .seconds(1))
        _ = await h.clock.waitForSleeps(3)
        #expect(await h.fetcher.calls.isEmpty)
        for page in 1...3 {
            h.clock.advance(by: .seconds(1))
            if page < 3 {
                _ = await h.clock.waitForSleeps(3 + page)
                #expect(await h.fetcher.calls.count == page)
            }
        }
        await task.value
        #expect(await h.fetcher.calls.count == 3)
        #expect(h.clock.requestedSleeps == Array(repeating: .seconds(1), count: 5))
        #expect(try await h.index.count() == 150)
    }

    @Test func rateLimitStopsUntilReset() async throws {
        let h = try Harness([item("acme/web", 1, updated: t0.addingTimeInterval(-day))])
        await h.fetcher.fail(call: 1, with: APIError.rateLimited(resetAt: t0.addingTimeInterval(300)))
        await h.sync.sync()
        #expect(await h.fetcher.calls.count == 1)
        #expect(try await h.index.meta(.lastSync) == nil)

        h.now.set(t0.addingTimeInterval(299))
        await h.sync.sync()
        await h.sync.backfill(repo: "acme/web")
        #expect(await h.fetcher.calls.count == 1)

        h.now.set(t0.addingTimeInterval(300))
        await h.sync.sync()
        #expect(await h.fetcher.calls.count == 3)
        #expect(try await h.index.count() == 1)
    }

    @Test func rateLimitWithoutResetWaitsAMinute() async throws {
        let h = try Harness([item("acme/web", 1, updated: t0.addingTimeInterval(-day))])
        await h.fetcher.fail(call: 1, with: APIError.rateLimited(resetAt: nil))
        await h.sync.sync()
        h.now.set(t0.addingTimeInterval(59))
        await h.sync.sync()
        #expect(await h.fetcher.calls.count == 1)
        h.now.set(t0.addingTimeInterval(60))
        await h.sync.sync()
        #expect(await h.fetcher.calls.count == 3)
    }

    @Test func backfillResumesFromBackfilledUntil() async throws {
        let items = (0..<1500).map { item("acme/web", $0, updated: t0.addingTimeInterval(-Double($0) * 5000)) }
        let h = try Harness(items)
        await h.fetcher.fail(call: 12, with: APIError.rateLimited(resetAt: t0.addingTimeInterval(60)))
        await h.sync.sync()
        let mark = try #require(try await h.index.meta(.backfilledUntil))
        #expect(mark > t0.addingTimeInterval(-AskSync.window))
        #expect(try await h.index.meta(.lastFullSync) == nil)

        let resumed = t0.addingTimeInterval(60)
        h.now.set(resumed)
        let before = await h.fetcher.calls.count
        await h.sync.sync()
        #expect(await h.fetcher.queries.dropFirst(before).first == "org:acme is:pr updated:\(iso(mark))..\(iso(resumed))")
        #expect(try await h.index.count() == 1500)
        #expect(try await h.index.meta(.backfilledUntil) == nil)
        #expect(try await h.index.meta(.lastFullSync) == resumed)
    }

    @Test func backfillRepoUsesRepoQualifier() async throws {
        let recent = t0.addingTimeInterval(-day)
        let h = try Harness([item("acme/web", 1, updated: recent), item("acme/api", 2, updated: recent)])
        await h.sync.backfill(repo: "acme/web")
        let window = "updated:\(iso(t0.addingTimeInterval(-AskSync.window)))..\(iso(t0))"
        #expect(await h.fetcher.queries == ["repo:acme/web is:pr \(window)", "repo:acme/web is:issue \(window)"])
        #expect(try await h.stored() == ["acme/web#1"])
        #expect(try await h.index.meta(.lastFullSync) == nil)
    }

    @Test func scopeChangeCancelsSync() async throws {
        let recent = t0.addingTimeInterval(-day)
        let h = try Harness([item("acme/web", 1, kind: .pr, updated: recent), item("acme/web", 2, updated: recent)])
        let sync = h.sync
        await h.fetcher.setOnFetch { number in if number == 2 { await sync.cancel() } }
        await h.sync.sync()
        #expect(await h.fetcher.calls.count == 2)
        #expect(try await h.stored() == ["acme/web#1"])
        #expect(try await h.index.meta(.lastSync) == nil)
    }

    @Test func syncWhileRunningReturnsImmediately() async throws {
        let h = try Harness([item("acme/web", 1, updated: t0.addingTimeInterval(-day))], pause: .seconds(1))
        let task = Task { await h.sync.sync() }
        _ = await h.clock.waitForSleeps(1)
        await h.sync.sync()
        #expect(h.clock.requestedSleeps.count == 1)
        #expect(await h.fetcher.calls.isEmpty)
        h.clock.advance(by: .seconds(1))
        _ = await h.clock.waitForSleeps(2)
        h.clock.advance(by: .seconds(1))
        await task.value
        #expect(await h.fetcher.calls.count == 2)
    }

    @Test func rebuildDropsRowsAndResyncs() async throws {
        let h = try Harness([item("acme/web", 1, updated: t0.addingTimeInterval(-day))])
        try await h.index.upsert([item("acme/web", 9, updated: t0.addingTimeInterval(-day))])
        try await h.index.setMeta(.lastFullSync, t0)
        try await h.index.setMeta(.lastSync, t0)
        h.now.set(t0.addingTimeInterval(60))
        await h.sync.rebuild()
        #expect(try await h.stored() == ["acme/web#1"])
        #expect(await h.fetcher.queries.first?.contains("..") == true)
        #expect(try await h.index.meta(.lastFullSync) == t0.addingTimeInterval(60))
    }

    @Test func progressReportsBackfillEstimate() async throws {
        let items = (0..<150).map { item("acme/web", $0, kind: .pr, updated: t0.addingTimeInterval(-Double($0)))
        } + (0..<50).map { item("acme/web", 1000 + $0, updated: t0.addingTimeInterval(-Double($0))) }
        let h = try Harness(items, pause: .seconds(1))
        var updates = h.sync.progress.makeAsyncIterator()
        let task = Task { await h.sync.sync() }

        _ = await h.clock.waitForSleeps(1)
        h.clock.advance(by: .seconds(1))
        _ = await h.clock.waitForSleeps(2)
        #expect(await updates.next() == AskSyncProgress(indexed: 100, estimatedTotal: 150, backfilling: true, lastSync: nil))
        h.clock.advance(by: .seconds(1))
        _ = await h.clock.waitForSleeps(3)
        #expect(await updates.next() == AskSyncProgress(indexed: 150, estimatedTotal: 150, backfilling: true, lastSync: nil))
        h.clock.advance(by: .seconds(1))
        await task.value
        #expect(await updates.next() == AskSyncProgress(indexed: 200, estimatedTotal: nil, backfilling: false, lastSync: t0))
    }
}
