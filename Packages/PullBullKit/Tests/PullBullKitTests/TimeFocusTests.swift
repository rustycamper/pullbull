import Foundation
import Testing
@testable import PullBullKit

@Suite struct TimeFocusTests {
    static let locale = Locale(identifier: "en_US")

    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    static let newYork = calendar("America/New_York")

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, in calendar: Calendar = newYork) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    static func pr(state: PRState = .open, updatedAt: Date, closedAt: Date? = nil) -> PullRequest {
        PullRequest(
            key: PRKey(repo: "o/a", number: 1), title: "t", url: URL(string: "https://x/1")!,
            author: "alice", authorAvatarURL: nil, state: state, isDraft: false,
            createdAt: updatedAt, updatedAt: updatedAt, closedAt: closedAt,
            headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
            lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
    }

    static func issue(isOpen: Bool = true, updatedAt: Date? = nil, closedAt: Date? = nil) -> BoardIssue {
        BoardIssue(
            key: PRKey(repo: "o/a", number: 1), title: "i", url: URL(string: "https://x/1")!,
            isOpen: isOpen, updatedAt: updatedAt, closedAt: closedAt)
    }

    @Test func stepStartsAtLocalMidnight() {
        let now = Self.date(2026, 10, 30, 15)
        func start(_ step: TimeStep) -> Date { step.start(now: now, calendar: Self.newYork) }
        #expect(start(.today) == Self.date(2026, 10, 30))
        #expect(start(.threeDays) == Self.date(2026, 10, 28))
        #expect(start(.week) == Self.date(2026, 10, 24))
        #expect(start(.month) == Self.date(2026, 10, 1))
    }

    @Test func stepStartAcrossDST() {
        let now = Self.date(2026, 11, 2, 9)
        let start = TimeStep.week.start(now: now, calendar: Self.newYork)
        #expect(start == Self.date(2026, 10, 27))
        #expect(Self.newYork.component(.hour, from: start) == 0)
    }

    @Test func stepStartFollowsTimeZone() {
        let now = Date(timeIntervalSince1970: 1_798_632_000)
        let auckland = TimeStep.today.start(now: now, calendar: Self.calendar("Pacific/Auckland"))
        let losAngeles = TimeStep.today.start(now: now, calendar: Self.calendar("America/Los_Angeles"))
        #expect(auckland != losAngeles)
    }

    @Test func tokensRoundTrip() {
        for step in TimeStep.allCases { #expect(TimeStep(token: step.token) == step) }
        #expect(TimeStep(token: "3D") == .threeDays)
        #expect(TimeStep(token: "2d") == nil)
        #expect(TimeStep(token: "") == nil)
    }

    @Test func activityDateByState() {
        let updated = Self.date(2026, 10, 20)
        let closed = Self.date(2026, 10, 25)
        #expect(ActivityDate.of(Self.pr(updatedAt: updated)) == updated)
        #expect(ActivityDate.of(Self.pr(state: .merged, updatedAt: updated, closedAt: closed)) == closed)
        #expect(ActivityDate.of(Self.pr(state: .closed, updatedAt: updated)) == updated)
        #expect(ActivityDate.of(Self.issue(updatedAt: updated)) == updated)
        #expect(ActivityDate.of(Self.issue(isOpen: false, updatedAt: updated, closedAt: closed)) == closed)
        #expect(ActivityDate.of(Self.issue()) == nil)
    }

    @Test func matchesAtTheBoundary() {
        let now = Self.date(2026, 10, 30, 15)
        let focus = TimeFocus(step: .week, now: now, calendar: Self.newYork)
        #expect(focus.matches(Self.pr(updatedAt: focus.start)))
        #expect(!focus.matches(Self.pr(updatedAt: focus.start.addingTimeInterval(-1))))
        #expect(focus.matches(Self.issue(updatedAt: focus.start)))
        #expect(!focus.matches(Self.issue(updatedAt: focus.start.addingTimeInterval(-1))))
        #expect(!focus.matches(Self.issue()))
    }

    @Test func stripText() {
        let now = Self.date(2026, 10, 30, 15)
        func text(_ step: TimeStep, now: Date = now) -> String {
            TimeFocus(step: step, now: now, calendar: Self.newYork)
                .stripText(now: now, calendar: Self.newYork, locale: Self.locale)
        }
        #expect(text(.today) == "Updated today")
        #expect(text(.threeDays) == "Updated in the last 3 days · since Wed")
        #expect(text(.week) == "Updated in the last week · since Oct 24")
        #expect(text(.month) == "Updated in the last month · since Oct 1")
        #expect(text(.month, now: Self.date(2027, 1, 10, 15)) == "Updated in the last month · since Dec 12, 2026")
    }

    @Test func stripTitles() {
        #expect(TimeStep.allCases.map(\.stripTitle) == ["Today", "Last 3 days", "Last week", "Last month"])
    }

    @Test func titles() {
        #expect(TimeStep.allCases.map(\.title) == ["today", "in the last 3 days", "in the last week", "in the last month"])
        #expect(TimeStep.allCases.map(\.menuTitle) == ["Today", "In the Last 3 Days", "In the Last Week", "In the Last Month"])
    }
}
