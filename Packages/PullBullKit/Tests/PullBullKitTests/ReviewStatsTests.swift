import Foundation
import Testing
@testable import PullBullKit

@Suite struct ReviewStatsTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let hour: TimeInterval = 3600
    var window: StatsWindow { StatsWindow(start: t0.addingTimeInterval(-86_400), end: t0.addingTimeInterval(10 * 86_400)) }

    func pr(author: String? = "dana", requests: [ReviewRequestEvent] = [], reviews: [MyReview]) -> ReviewedPR {
        ReviewedPR(repo: "acme/app", author: author, requests: requests, myReviews: reviews)
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
        let stats = make([pr(author: "Me", requests: [request(0, .user("me"))], reviews: [review(3)])])
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

    @Test func loadedFromCapped() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day0 = cal.startOfDay(for: t0)
        let w = StatsWindow(start: day0, end: day0.addingTimeInterval(7 * 86_400 - 1))
        func at(_ day: Int) -> MyReview { MyReview(submittedAt: day0.addingTimeInterval(Double(day) * 86_400 + 3600), pending: false) }
        let a = pr(reviews: [at(1), at(5)])
        let b = pr(reviews: [at(5)])
        let from = ReviewStats.loadedFrom([a, b], window: w, me: "me", calendar: cal)
        #expect(from == day0.addingTimeInterval(6 * 86_400))
        #expect(ReviewStats.loadedFrom([], window: w, me: "me", calendar: cal) == nil)
        #expect(ReviewStats.loadedFrom([pr(author: "me", reviews: [at(2)])], window: w, me: "me", calendar: cal) == nil)
    }
}
