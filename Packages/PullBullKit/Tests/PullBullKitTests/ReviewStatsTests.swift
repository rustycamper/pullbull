import Foundation
import Testing
@testable import PullBullKit

@Suite struct ReviewStatsTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let hour: TimeInterval = 3600
    var window: StatsWindow { StatsWindow(start: t0.addingTimeInterval(-86_400), end: t0.addingTimeInterval(10 * 86_400)) }

    func pr(
        author: String? = "dana", updatedAt: Date? = nil, requests: [ReviewRequestEvent] = [], reviews: [MyReview]
    ) -> ReviewedPR {
        ReviewedPR(repo: "acme/app", author: author, updatedAt: updatedAt, requests: requests, myReviews: reviews)
    }
    func review(_ offset: TimeInterval, pending: Bool = false) -> MyReview {
        MyReview(submittedAt: t0.addingTimeInterval(offset * hour), pending: pending)
    }
    func request(_ offset: TimeInterval, _ reviewer: Reviewer?) -> ReviewRequestEvent {
        ReviewRequestEvent(at: t0.addingTimeInterval(offset * hour), reviewer: reviewer)
    }
    func make(_ prs: [ReviewedPR], teams: Set<String> = []) -> ReviewStats {
        ReviewStats.make(prs, window: window, me: "me", myTeams: teams)
    }

    @Test func ownPRDropped() {
        let stats = make([pr(author: "Me", updatedAt: t0.addingTimeInterval(3 * hour),
                             requests: [request(0, .user("me"))], reviews: [review(3)])])
        #expect(stats.reviewDates.isEmpty)
        #expect(stats.turnarounds.isEmpty)
    }

    @Test func requestThenReview() {
        let stats = make([pr(requests: [request(0, .user("Me"))], reviews: [review(3)])])
        #expect(stats.turnarounds == [3 * hour])
    }

    @Test func teamRequest() {
        let stats = make([pr(requests: [request(0, .team(slug: "ios", name: "iOS"))], reviews: [review(2)])], teams: ["iOS"])
        #expect(stats.turnarounds == [2 * hour])
    }

    @Test func secondReviewNotSample() {
        let stats = make([pr(requests: [request(0, .user("me"))], reviews: [review(1), review(5)])])
        #expect(stats.turnarounds == [hour])
        #expect(stats.reviewDates.count == 2)
    }

    @Test func reRequest() {
        let stats = make([pr(requests: [request(0, .user("me")), request(10, .user("me"))],
                             reviews: [review(1), review(12)])])
        #expect(stats.turnarounds.sorted() == [hour, 2 * hour])
    }

    @Test func unaskedReview() {
        let stats = make([pr(reviews: [review(4)])])
        #expect(stats.reviewDates == [t0.addingTimeInterval(4 * hour)])
        #expect(stats.turnarounds.isEmpty)
    }

    @Test func requestToSomeoneElse() {
        let stats = make([pr(requests: [request(0, .user("dana")), request(0, nil)], reviews: [review(2)])])
        #expect(stats.turnarounds.isEmpty)
        #expect(stats.reviewDates.count == 1)
    }

    @Test func outsideWindow() {
        let before = MyReview(submittedAt: window.start.addingTimeInterval(-1), pending: false)
        let atStart = MyReview(submittedAt: window.start, pending: false)
        let stats = make([pr(reviews: [before, atStart])])
        #expect(stats.reviewDates == [window.start])
    }

    @Test func pendingIgnored() {
        let stats = make([pr(requests: [request(0, .user("me"))], reviews: [review(1, pending: true), review(2)])])
        #expect(stats.reviewDates.count == 1)
        #expect(stats.turnarounds == [2 * hour])
    }

    @Test func reviewInWindowOnPRUpdatedLaterCounts() {
        let later = window.end.addingTimeInterval(5 * 86_400)
        let stats = make([pr(updatedAt: later, requests: [request(0, .user("me"))], reviews: [review(2)])])
        #expect(stats.reviewDates == [t0.addingTimeInterval(2 * hour)])
        #expect(stats.turnarounds == [2 * hour])
    }

    var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// The day after the oldest loaded PR's update, whatever its reviews' dates.
    @Test func loadedFromOldestUpdate() {
        let day0 = utc.startOfDay(for: t0)
        func on(_ day: Double) -> Date { day0.addingTimeInterval(day * 86_400) }
        let newer = pr(updatedAt: on(5) + 3600, reviews: [MyReview(submittedAt: on(1), pending: false)])
        let older = pr(updatedAt: on(2) + 3600, reviews: [MyReview(submittedAt: on(2), pending: false)])
        #expect(ReviewStats.loadedFrom([newer, older], calendar: utc) == on(3))
    }

    @Test func loadedFromMidnightUpdateIsThatDay() {
        let day0 = utc.startOfDay(for: t0)
        let midnight = day0.addingTimeInterval(2 * 86_400)
        #expect(ReviewStats.loadedFrom([pr(updatedAt: midnight, reviews: [])], calendar: utc) == midnight)
    }

    @Test func loadedFromNothingLoadedIsNil() {
        #expect(ReviewStats.loadedFrom([], calendar: utc) == nil)
        #expect(ReviewStats.loadedFrom([pr(updatedAt: nil, reviews: [review(2)])], calendar: utc) == nil)
    }

    @Test func loadedFromLocalDay() {
        var sofia = Calendar(identifier: .gregorian)
        sofia.timeZone = TimeZone(identifier: "Europe/Sofia")!
        let updated = try! Decoding.date("2026-11-03T23:30:00Z")
        #expect(ReviewStats.loadedFrom([pr(updatedAt: updated, reviews: [])], calendar: sofia)
            == (try! Decoding.date("2026-11-04T22:00:00Z")))
    }
}
