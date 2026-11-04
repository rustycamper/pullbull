import Foundation
import Testing
@testable import PullBullKit

@Suite struct RightNowTests {
    static let now = ReviewWaitTests.now
    static let day = ReviewWaitTests.day

    static func row(_ number: Int, requested: TimeInterval? = nil, reviews: [Review] = [], draft: Bool = false,
                    counted: Bool = true) -> Row {
        let at = requested.map { now - $0 * day }
        let base = ReviewWaitTests.pr(at.map { [(.user("me"), $0)] } ?? [], reviews: reviews, isDraft: draft,
                                      ready: at == nil ? now - 2 * day : nil)
        let pr = PullRequest(
            key: PRKey(repo: "org/repo", number: number), title: base.title, url: base.url, author: base.author,
            authorAvatarURL: nil, state: base.state, isDraft: base.isDraft, createdAt: now - 2 * day,
            updatedAt: now, closedAt: nil, headRef: "h", baseRef: "main", ci: .success, headCommitDate: nil,
            commentCount: 0, lastCommentAuthor: nil, latestReviews: base.latestReviews,
            reviewRequests: base.reviewRequests, reviewRequestTimes: base.reviewRequestTimes,
            readyForReviewAt: base.readyForReviewAt)
        return Row(pr: pr, dimmed: false, counted: counted)
    }

    static func pick(review: [Row] = [], mine: [Row] = []) -> RightNow {
        RightNow.pick(review: review, mine: mine, me: "me", myTeams: [], now: now)
    }

    @Test func waitingOnMeIsTheOldestCountedRequest() {
        let picked = Self.pick(review: [
            Self.row(1, requested: 3), Self.row(2, requested: 5), Self.row(3, requested: 9, counted: false),
        ])
        #expect(picked.waitingOnMe?.row.id.number == 2)
        #expect(picked.waitingOnMe?.wait.age == "5d")
    }

    @Test func tieKeepsListOrder() {
        let picked = Self.pick(review: [Self.row(1, requested: 4), Self.row(2, requested: 4)])
        #expect(picked.waitingOnMe?.row.id.number == 1)
    }

    @Test func myLongestSkipsHumanReviewedAndDrafts() {
        let human = Review(author: "dana", state: .commented, submittedAt: Self.now - Self.day)
        let bot = Review(author: "copilot", state: .commented, submittedAt: Self.now - Self.day, byBot: true)
        let mine = [
            Self.row(1, requested: 6, reviews: [human]),
            Self.row(2),
            Self.row(3, draft: true),
            Self.row(4, reviews: [bot]),
        ]
        let picked = Self.pick(mine: mine)
        #expect(picked.myLongest?.row.id.number == 2)
        #expect(picked.myLongest?.wait.who == "No reviewer")
    }

    @Test func emptyInputsGiveNothing() {
        let picked = Self.pick()
        #expect(picked.waitingOnMe == nil)
        #expect(picked.myLongest == nil)
    }

    @Test func keysListTheRowsShownTopToBottom() {
        let picked = Self.pick(review: [Self.row(1, requested: 3)], mine: [Self.row(2)])
        #expect(picked.keys.map(\.number) == [1, 2])
        #expect(picked.item(for: PRKey(repo: "org/repo", number: 2))?.row.id.number == 2)
        #expect(picked.item(for: PRKey(repo: "org/repo", number: 3)) == nil)
    }

    @Test func keysSkipAMissingRow() {
        #expect(Self.pick(mine: [Self.row(2)]).keys.map(\.number) == [2])
        #expect(Self.pick(review: [Self.row(1, requested: 3)]).keys.map(\.number) == [1])
        #expect(Self.pick().keys.isEmpty)
    }

    @Test func aPRInBothRowsIsOneStop() {
        let both = Self.pick(review: [Self.row(1, requested: 3)]).waitingOnMe
        let rightNow = RightNow(waitingOnMe: both, myLongest: both)
        #expect(rightNow.keys.map(\.number) == [1])
    }

    @Test func selectionStepsBetweenTheRowsWithoutWrapping() {
        let keys = Self.pick(review: [Self.row(1, requested: 3)], mine: [Self.row(2)]).keys
        #expect(ListNavigation.move(nil, by: 1, in: keys)?.number == 1)
        #expect(ListNavigation.move(nil, by: -1, in: keys)?.number == 2)
        #expect(ListNavigation.move(keys[0], by: 1, in: keys)?.number == 2)
        #expect(ListNavigation.move(keys[1], by: 1, in: keys)?.number == 2)
        #expect(ListNavigation.move(keys[0], by: -1, in: keys)?.number == 1)
        #expect(ListNavigation.move(nil, by: 1, in: []) == nil)
    }
}
