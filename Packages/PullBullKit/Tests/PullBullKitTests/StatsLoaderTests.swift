import Foundation
import Testing
@testable import PullBullKit

private actor Calls {
    struct Call: Equatable {
        let name: String
        let window: StatsWindow?
        let query: String?
    }

    var all: [Call] = []
    var inFlight = 0
    var maxInFlight = 0
    var names: [String] { all.map(\.name) }
    func windows(_ name: String) -> [StatsWindow] { all.filter { $0.name == name }.compactMap(\.window) }

    /// Records the call and stays in flight briefly, so overlapping calls show in `maxInFlight`.
    func enter(_ name: String, window: StatsWindow? = nil, query: String? = nil) async {
        all.append(Call(name: name, window: window, query: query))
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        try? await Task.sleep(nanoseconds: 100_000_000)
        inFlight -= 1
    }
}

private struct StubSource: StatsSource {
    let calls = Calls()
    var failMerged = false
    var failReviewed = false
    var cancelOpened = false
    var throwOnOpened: (any Error)?
    var reviewedItems: [ReviewedPR] = []
    var counts: [String: Int] = [:]

    func reviewedPRs(window: StatsWindow, login: String, scope: FetchScope) async throws -> Capped<ReviewedPR> {
        await calls.enter("reviewed", window: window)
        if failReviewed { throw APIError.rateLimited(resetAt: nil) }
        return Capped(items: reviewedItems, capped: false)
    }

    func openedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<OpenedPR> {
        await calls.enter("opened", window: window)
        if cancelOpened { throw URLError(.cancelled) }
        if let throwOnOpened { throw throwOnOpened }
        return CountedList(total: 0, items: [])
    }

    func mergedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<MergedPR> {
        await calls.enter("merged", window: window)
        if failMerged { throw APIError.rateLimited(resetAt: nil) }
        return CountedList(total: 0, items: [])
    }

    func issueCount(_ query: String) async throws -> Int {
        await calls.enter("issueCount", query: query)
        return counts[query] ?? 0
    }

    func myComments(window: StatsWindow, scope: FetchScope) async throws -> Capped<Date> {
        await calls.enter("comments", window: window)
        return Capped(items: [], capped: false)
    }
}

@Suite struct StatsLoaderTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func load(_ source: StubSource, scope: FetchScope = .org("acme")) async -> StatsReport? {
        await StatsLoader.load(
            source, period: .week, scope: scope, me: "me", myTeams: [], now: now, calendar: calendar)
    }

    @Test func loadsAllInParallel() async {
        let source = StubSource()
        let report = await load(source)
        #expect(report?.isComplete == true)
        let names = await source.calls.names
        #expect(names.count { $0 == "reviewed" } == 2)
        #expect(names.count { $0 == "opened" } == 2)
        #expect(names.count { $0 == "merged" } == 2)
        #expect(names.count { $0 == "issueCount" } == 4)
        #expect(names.count { $0 == "comments" } == 1)
        // All 11 fetches, the reviewed ones too, are in flight at once.
        #expect(await source.calls.maxInFlight == 11)
    }

    @Test func eachSourceGetsItsWindowAndQuery() async {
        let scope = FetchScope.org("acme")
        let current = StatsPeriod.week.window(now: now, calendar: calendar)
        let before = StatsPeriod.week.comparisonWindow(now: now, calendar: calendar)
        let closed = StatsQueries.closedIssues(window: current, scope: scope)
        let closedBefore = StatsQueries.closedIssues(window: before, scope: scope)
        let opened = StatsQueries.openedIssues(window: current, scope: scope)
        let openedBefore = StatsQueries.openedIssues(window: before, scope: scope)
        let source = StubSource(counts: [closed: 4, closedBefore: 3, opened: 7, openedBefore: 2])
        let report = await load(source, scope: scope)

        for name in ["reviewed", "opened", "merged"] {
            let windows = await source.calls.windows(name)
            #expect(windows.count == 2)
            #expect(windows.contains(current))
            #expect(windows.contains(before))
        }
        #expect(await source.calls.windows("comments") == [current])
        let queries = await source.calls.all.compactMap(\.query)
        #expect(Set(queries) == [closed, closedBefore, opened, openedBefore])
        #expect(queries.count == 4)

        #expect(report?.issuesClosed.text == "4")
        #expect(report?.issuesClosed.comparison == "last week 3")
        #expect(report?.issuesOpened.text == "7")
        #expect(report?.issuesOpened.comparison == "last week 2")
    }

    @Test func oneFailureKeepsOthers() async {
        let window = StatsPeriod.week.window(now: now, calendar: calendar)
        let closed = StatsQueries.closedIssues(window: window, scope: .org("acme"))
        let report = await load(StubSource(failMerged: true, counts: [closed: 4]))
        #expect(report?.merged.text == "–")
        #expect(report?.issuesClosed.text == "4")
        #expect(report?.reviews.text == "0")
        #expect(report?.failures == ["Rate limited"])
    }

    @Test func reviewedFailureFailsReviewsOnly() async {
        let report = await load(StubSource(failReviewed: true))
        #expect(report?.reviews.text == "–")
        #expect(report?.turnaround.text == "–")
        #expect(report?.merged.text == "0")
        #expect(report?.failures == ["Rate limited"])
    }

    @Test func personalScopeLoads() async {
        let report = await load(StubSource(), scope: .personal(login: "me"))
        #expect(report?.isComplete == true)
    }

    @Test func cancelledReturnsNil() async {
        #expect(await load(StubSource(cancelOpened: true)) == nil)
    }

    @Test func cancellationErrorReturnsNil() async {
        #expect(await load(StubSource(throwOnOpened: CancellationError())) == nil)
    }

    @Test func cancelledTaskReturnsNil() async {
        let source = StubSource()
        let task = Task { () -> StatsReport? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await load(source)
        }
        #expect(await task.value == nil)
    }
}
