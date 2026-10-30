import Foundation
import Testing
@testable import PullBullKit

private let zone = TimeZone(identifier: "America/New_York")!
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// Friday 2026-10-30, mid-afternoon in New York.
private let now = at(2026, 10, 30, 15)
private let repo = "initech/gadgets"

private func pr(
    _ number: Int, state: PRState = .open, updatedAt: Date, closedAt: Date? = nil
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "someone",
        authorAvatarURL: nil, state: state, isDraft: false, createdAt: updatedAt, updatedAt: updatedAt,
        closedAt: closedAt, headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

@Suite struct UpdatedQueryTests {
    @Test func parsesSteps() {
        #expect(SearchQuery.parse("updated:today")
            == .filtered(logins: [], labels: [], words: [], updated: .step(.today)))
        #expect(SearchQuery.parse("UPDATED:1W").updated == .step(.week))
        #expect(SearchQuery.parse("updated:3d").updated == .step(.threeDays))
        #expect(SearchQuery.parse("updated:1m").updated == .step(.month))
    }

    @Test func unknownValuePassesThrough() {
        let q = SearchQuery.parse("updated:soon fix")
        #expect(q.updated == .raw("soon"))
        #expect(q.words == ["fix"])
    }

    @Test func bareQualifierIsDropped() {
        #expect(SearchQuery.parse("updated:") == .empty)
    }

    @Test func pendingTokenIsExcluded() {
        let raw = "fix updated:to"
        let range = raw.range(of: "updated:to")!
        #expect(SearchQuery.parse(raw, excluding: range) == .text(["fix"]))
    }

    @Test func combinesWithOtherQualifiers() {
        let q = SearchQuery.parse("@ann is:open updated:3d")
        #expect(q.logins == ["ann"])
        #expect(q.states == [.open])
        #expect(q.updated == .step(.threeDays))
    }

    @Test func serverQuery() {
        let q = SearchEngine.remoteQuery(
            kind: "pr", scope: .org("initech"), logins: [], labels: [], updated: .step(.threeDays), words: [],
            now: now, calendar: calendar)
        #expect(q.contains("updated:>=2026-10-28T04:00:00Z"))
        #expect(q.contains("sort:updated-desc"))
    }

    @Test func serverDateCoversEastOfUTC() {
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let morning = sydney.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9))!
        #expect(UpdatedFilter.step(.today).serverQualifier(now: morning, calendar: sydney)
            == "updated:>=2026-10-29T13:00:00Z")
    }

    @Test func rawGoesAsWritten() {
        let q = SearchEngine.remoteQuery(
            kind: "issue", scope: .org("initech"), logins: [], labels: [], updated: .raw("soon"), words: [],
            now: now, calendar: calendar)
        #expect(q.contains("updated:soon"))
    }

    @Test func localFilterIsExact() {
        let q = SearchQuery.parse("updated:today")
        let lateYesterday = pr(1, updatedAt: at(2026, 10, 29, 23, 59))
        let midnight = pr(2, updatedAt: at(2026, 10, 30, 0, 0))
        #expect(!q.matches(lateYesterday, viewer: "me", now: now, calendar: calendar))
        #expect(q.matches(midnight, viewer: "me", now: now, calendar: calendar))
    }

    @Test func closedPRJudgedByCloseDate() {
        let merged = pr(1, state: .merged, updatedAt: at(2026, 10, 30, 9), closedAt: at(2026, 10, 20))
        let q = SearchQuery.parse("updated:1w")
        #expect(!q.matches(merged, viewer: "me", now: now, calendar: calendar))
    }

    @Test func issueWithNoDateNeverMatches() {
        let issue = BoardIssue(
            key: PRKey(repo: repo, number: 5), title: "Issue", url: URL(string: "https://github.com/x")!, isOpen: true)
        #expect(!SearchQuery.parse("updated:1m").matches(issue, viewer: "me", now: now, calendar: calendar))
    }

    @Test func rawMatchesNothingLocally() {
        let q = SearchQuery.parse("updated:soon")
        #expect(!q.matches(pr(1, updatedAt: now), viewer: "me", now: now, calendar: calendar))
    }

    @Test func contextText() {
        let text = SearchContext.text(
            logins: [], updated: .step(.threeDays), words: [], org: "initech", startedOnTab: nil)
        #expect(text.contains("updated:3d"))
        let label = SearchContext.filterDescription(
            logins: [], labels: [], states: [], updated: .step(.threeDays), words: [])
        #expect(label.contains("updated in the last 3 days"))
        let raw = SearchContext.filterDescription(
            logins: [], labels: [], states: [], updated: .raw("soon"), words: [])
        #expect(raw.contains("updated:soon"))
    }

    private func utc(_ text: String) -> Date { try! Date(text, strategy: .iso8601) }

    private func matches(_ value: String, _ updated: String) -> Bool {
        SearchQuery.parse("updated:" + value)
            .matches(pr(1, updatedAt: utc(updated)), viewer: "me", now: now, calendar: calendar)
    }

    @Test func greaterThanDayIsAfterItsEnd() {
        #expect(!matches(">2026-10-01", "2026-10-01T23:59:59Z"))
        #expect(matches(">2026-10-01", "2026-10-02T00:00:00Z"))
    }

    @Test func greaterOrEqualDayStartsAtMidnightUTC() {
        #expect(!matches(">=2026-10-01", "2026-09-30T23:59:59Z"))
        #expect(matches(">=2026-10-01", "2026-10-01T00:00:00Z"))
    }

    @Test func lessThanDayEndsBeforeIt() {
        #expect(matches("<2026-10-01", "2026-09-30T23:59:59Z"))
        #expect(!matches("<2026-10-01", "2026-10-01T00:00:00Z"))
    }

    @Test func lessOrEqualDayRunsThroughItsEnd() {
        #expect(matches("<=2026-10-01", "2026-10-01T23:59:59Z"))
        #expect(!matches("<=2026-10-01", "2026-10-02T00:00:00Z"))
    }

    @Test func bareDayIsTheWholeUTCDay() {
        #expect(!matches("2026-10-01", "2026-09-30T23:59:59Z"))
        #expect(matches("2026-10-01", "2026-10-01T00:00:00Z"))
        #expect(matches("2026-10-01", "2026-10-01T23:59:59Z"))
        #expect(!matches("2026-10-01", "2026-10-02T00:00:00Z"))
    }

    @Test func dayRangeIsInclusiveAtBothEnds() {
        #expect(!matches("2026-10-01..2026-10-03", "2026-09-30T23:59:59Z"))
        #expect(matches("2026-10-01..2026-10-03", "2026-10-01T00:00:00Z"))
        #expect(matches("2026-10-01..2026-10-03", "2026-10-03T23:59:59Z"))
        #expect(!matches("2026-10-01..2026-10-03", "2026-10-04T00:00:00Z"))
    }

    @Test func openEndedRanges() {
        #expect(matches("2026-10-01..*", "2027-01-01T00:00:00Z"))
        #expect(!matches("2026-10-01..*", "2026-09-30T23:59:59Z"))
        #expect(matches("*..2026-10-01", "2020-01-01T00:00:00Z"))
        #expect(!matches("*..2026-10-01", "2026-10-02T00:00:00Z"))
    }

    @Test func instantIsExact() {
        #expect(!matches(">=2026-10-27T14:00:00Z", "2026-10-27T13:59:59Z"))
        #expect(matches(">=2026-10-27T14:00:00Z", "2026-10-27T14:00:00Z"))
        #expect(!matches(">2026-10-27T14:00:00Z", "2026-10-27T14:00:00Z"))
        #expect(matches(">2026-10-27T10:00:00-04:00", "2026-10-27T14:00:01Z"))
    }

    @Test func dateFormsServerQueryIsVerbatim() {
        let q = SearchEngine.remoteQuery(
            kind: "pr", scope: .org("initech"), logins: [], labels: [],
            updated: SearchQuery.parse("updated:2026-10-01..2026-10-07").updated, words: [], now: now, calendar: calendar)
        #expect(q.contains("updated:2026-10-01..2026-10-07"))
    }

    @Test func malformedDatesStayRaw() {
        #expect(SearchQuery.parse("updated:2026-13-45").updated == .raw("2026-13-45"))
        #expect(SearchQuery.parse("updated:>=").updated == .raw(">="))
        #expect(SearchQuery.parse("updated:*..*").updated == .raw("*..*"))
    }

    @Test func tabCountIsNotZeroedByDateForm() {
        let tabs = BuiltTabs(
            review: TabContents(rows: []),
            mine: TabContents(rows: [Row(pr: pr(1, updatedAt: utc("2026-10-02T00:00:00Z")), dimmed: false, counted: true)]),
            team: TabContents(rows: []), recentlyClosed: [], hiddenApprovedCount: 0)
        let counts = SearchNarrowing.counts(
            SearchQuery.parse("updated:>2026-10-01"), prTabs: [.mine], tabs: tabs, issueTabs: nil, focus: nil,
            viewer: "me")
        #expect(counts[.pullRequests(.mine)] == .current(1))
    }
}
