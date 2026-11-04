import Foundation
import Testing
@testable import PullBullKit

private actor Calls {
    var names: [String] = []
    var orgIDReads = 0
    func add(_ name: String) { names.append(name) }
    func read() { orgIDReads += 1 }
}

private struct StubSource: StatsSource {
    let calls = Calls()
    var failMerged = false
    var cancelOpened = false
    var reviewedItems: [ReviewedPR] = []

    func organizationID(_ org: String) async throws -> String {
        await calls.add("organizationID")
        return "O_1"
    }

    func reviewedPRs(window: StatsWindow, orgID: String?, login: String, scope: FetchScope) async throws -> Capped<ReviewedPR> {
        await calls.add("reviewed")
        return Capped(items: reviewedItems, capped: false)
    }

    func openedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<OpenedPR> {
        await calls.add("opened")
        if cancelOpened { throw URLError(.cancelled) }
        return CountedList(total: 0, items: [])
    }

    func mergedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<MergedPR> {
        await calls.add("merged")
        if failMerged { throw APIError.rateLimited(resetAt: nil) }
        return CountedList(total: 0, items: [])
    }

    func issueCount(_ query: String) async throws -> Int {
        await calls.add("issueCount")
        return 4
    }

    func myComments(window: StatsWindow, scope: FetchScope) async throws -> Capped<Date> {
        await calls.add("comments")
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

    private func load(
        _ source: StubSource, scope: FetchScope = .org("acme"),
        orgID: @escaping @Sendable () async throws -> String? = { "O_1" }
    ) async -> StatsReport? {
        await StatsLoader.load(
            source, period: .week, scope: scope, me: "me", myTeams: [], orgID: orgID, now: now, calendar: calendar)
    }

    @Test func loadsAllInParallel() async {
        let source = StubSource()
        let report = await load(source)
        #expect(report?.isComplete == true)
        let names = await source.calls.names
        #expect(names.filter { $0 == "reviewed" }.count == 2)
        #expect(names.filter { $0 == "opened" }.count == 2)
        #expect(names.filter { $0 == "merged" }.count == 2)
        #expect(names.filter { $0 == "issueCount" }.count == 4)
        #expect(names.filter { $0 == "comments" }.count == 1)
        #expect(report?.issuesClosed.text == "4")
    }

    @Test func oneFailureKeepsOthers() async {
        let report = await load(StubSource(failMerged: true))
        #expect(report?.merged.text == "–")
        #expect(report?.issuesClosed.text == "4")
        #expect(report?.reviews.text == "0")
        #expect(report?.failures == ["Rate limited"])
    }

    @Test func orgIDFailureFailsReviewsOnly() async {
        let source = StubSource()
        let report = await load(source, orgID: { throw APIError.rateLimited(resetAt: nil) })
        #expect(report?.reviews.text == "–")
        #expect(report?.merged.text == "0")
        #expect(report?.failures.count == 1)
        #expect(await !source.calls.names.contains("reviewed"))
    }

    @Test func orgIDReadOnce() async {
        let source = StubSource()
        _ = await load(source, orgID: {
            await source.calls.read()
            return "O_1"
        })
        #expect(await source.calls.orgIDReads == 1)
    }

    @Test func personalScopeGetsNilOrgID() async {
        let report = await load(StubSource(), scope: .personal(login: "me"), orgID: { nil })
        #expect(report?.isComplete == true)
    }

    @Test func cancelledReturnsNil() async {
        #expect(await load(StubSource(cancelOpened: true)) == nil)
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
