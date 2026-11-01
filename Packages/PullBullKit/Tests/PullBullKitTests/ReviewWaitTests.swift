import Foundation
import Testing
@testable import PullBullKit

@Suite struct ReviewWaitTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400
    static let now = t0 + 5 * day
    static let ios = Reviewer.team(slug: "ios", name: "iOS")

    static func pr(
        _ requests: [(Reviewer, Date?)] = [], reviews: [Review] = [], isDraft: Bool = false,
        state: PRState = .open, repo: String = "org/repo", ready: Date? = nil
    ) -> PullRequest {
        var times: [String: Date] = [:]
        for (reviewer, at) in requests { times[reviewer.key] = at }
        return PullRequest(
            key: PRKey(repo: repo, number: 1), title: "t", url: URL(string: "https://github.com/org/repo/pull/1")!,
            author: "al", authorAvatarURL: nil, state: state, isDraft: isDraft,
            createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main",
            ci: .success, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: reviews, reviewRequests: requests.map(\.0),
            reviewRequestTimes: times, readyForReviewAt: ready)
    }

    static func wait(_ pr: PullRequest, me: String = "me", myTeams: Set<String> = [], review: Bool = false)
        -> ReviewWait? {
        ReviewWait.make(for: pr, me: me, myTeams: myTeams, reviewLayout: review, now: now)
    }

    // MARK: Pending requests

    @Test func oldestPendingNamedWithItsAge() {
        let w = Self.wait(Self.pr([(.user("georgi"), Self.t0 + 2 * Self.day), (Self.ios, Self.t0 + Self.day)]))
        #expect(w?.who == "@org/ios +1")
        #expect(w?.age == "4d")
        #expect(w?.text == "@org/ios +1 4d")
    }

    @Test func singlePendingHasNoPlus() {
        let w = Self.wait(Self.pr([(.user("dana"), Self.t0)]))
        #expect(w?.who == "@dana")
        #expect(w?.age == "5d")
    }

    @Test func viewersOwnRequestReadsYou() {
        #expect(Self.wait(Self.pr([(.user("ME"), Self.t0)]))?.who == "You")
    }

    @Test func teamWithoutOwnerUsesTheBareSlug() {
        #expect(Self.wait(Self.pr([(Self.ios, Self.t0)], repo: ""))?.who == "@ios")
    }

    @Test func labelListsEveryReviewerOldestFirst() {
        let w = Self.wait(Self.pr([(.user("georgi"), Self.t0 + 2 * Self.day), (Self.ios, Self.t0 + Self.day)]))
        #expect(w?.label == "Waiting on review: @org/ios 4 days, @georgi 3 days")
    }

    @Test func anyUnknownTimeHidesTheAge() {
        let w = Self.wait(Self.pr([(.user("georgi"), Self.t0), (.user("dana"), nil)]))
        #expect(w?.who == "@georgi +1")
        #expect(w?.age == nil)
        #expect(w?.text == "@georgi +1")
        #expect(w?.label == "Waiting on review: @georgi, @dana")
    }

    @Test func pendingRequestsShowEvenAfterAReview() {
        let approved = Review(author: "bob", state: .approved, submittedAt: Self.t0)
        #expect(Self.wait(Self.pr([(.user("dana"), Self.t0)], reviews: [approved]))?.who == "@dana")
    }

    // MARK: No reviewer

    @Test func noReviewerCountsFromReady() {
        let w = Self.wait(Self.pr(ready: Self.t0 + 3 * Self.day))
        #expect(w?.who == "No reviewer")
        #expect(w?.age == "2d")
        #expect(w?.label == "No reviewer requested, ready for 2 days")
    }

    @Test func noReviewerFallsBackToCreated() {
        #expect(Self.wait(Self.pr())?.age == "5d")
    }

    @Test func submittedReviewMeansNoWait() {
        let commented = Review(author: "bob", state: .commented, submittedAt: Self.t0)
        #expect(Self.wait(Self.pr(reviews: [commented])) == nil)
        let dismissed = Review(author: "bob", state: .dismissed, submittedAt: Self.t0)
        #expect(Self.wait(Self.pr(reviews: [dismissed])) == nil)
    }

    @Test func botReviewDoesNotCountAsReviewed() {
        let copilot = Review(author: "copilot-pull-request-reviewer", state: .commented, submittedAt: Self.t0, byBot: true)
        #expect(Self.wait(Self.pr(reviews: [copilot]))?.who == "No reviewer")
    }

    @Test func pendingDraftReviewDoesNotCount() {
        let pending = Review(author: "bob", state: .pending, submittedAt: nil)
        #expect(Self.wait(Self.pr(reviews: [pending]))?.who == "No reviewer")
    }

    @Test func draftsAndClosedShowNothing() {
        #expect(Self.wait(Self.pr(isDraft: true)) == nil)
        #expect(Self.wait(Self.pr([(.user("dana"), Self.t0)], state: .merged)) == nil)
        #expect(Self.wait(Self.pr(state: .closed)) == nil)
    }

    // MARK: Review layout

    @Test func reviewLayoutShortForm() {
        let w = Self.wait(Self.pr([(.user("Me"), Self.t0 + 3 * Self.day)]), review: true)
        #expect(w == ReviewWait(who: nil, age: "2d", label: "Requested from you 2 days ago"))
        #expect(w?.text == "2d")
    }

    @Test func reviewLayoutTeamRequest() {
        let w = Self.wait(Self.pr([(Self.ios, Self.t0 + 3 * Self.day)]), myTeams: ["ios"], review: true)
        #expect(w == ReviewWait(who: nil, age: "2d", label: "Requested from @org/ios 2 days ago"))
    }

    @Test func reviewLayoutOwnRequestBeatsOlderTeam() {
        let w = Self.wait(
            Self.pr([(Self.ios, Self.t0 + Self.day), (.user("me"), Self.t0 + 4 * Self.day)]),
            myTeams: ["ios"], review: true)
        #expect(w?.age == "1d")
    }

    @Test func reviewLayoutWithoutRequestToMeUsesFullForm() {
        let w = Self.wait(Self.pr([(.user("dana"), Self.t0)]), review: true)
        #expect(w?.who == "@dana")
        #expect(w?.age == "5d")
        #expect(Self.wait(Self.pr(), review: true)?.who == "No reviewer")
    }

    @Test func reviewLayoutUnknownOwnTimeShowsNothing() {
        #expect(Self.wait(Self.pr([(.user("me"), nil)]), review: true) == nil)
    }
}
