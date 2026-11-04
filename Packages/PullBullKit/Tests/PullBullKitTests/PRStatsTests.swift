import Foundation
import Testing
@testable import PullBullKit

@Suite struct PRStatsTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let hour: TimeInterval = 3600

    static func review(_ author: String, at: Date? = t0 + 2 * hour, bot: Bool = false, pending: Bool = false,
                       avatar: URL? = nil) -> OpenedPRReview {
        OpenedPRReview(author: author, avatarURL: avatar, byBot: bot, submittedAt: at, pending: pending)
    }

    static func pr(_ reviews: [OpenedPRReview] = [], draft: Bool = false, open: Bool = true, ready: Date? = t0)
        -> OpenedPR {
        OpenedPR(createdAt: t0 - hour, isDraft: draft, isOpen: open, readyAt: ready, reviews: reviews)
    }

    @Test func waitRunsFromReadyToFirstReview() {
        let stats = FirstReviewStats.make([Self.pr([Self.review("dana")])], me: "me")
        #expect(stats.waits == [2 * Self.hour])
        #expect(stats.stillWaiting == 0)
    }

    @Test func earliestReviewWins() {
        let stats = FirstReviewStats.make(
            [Self.pr([Self.review("erin", at: Self.t0 + 5 * Self.hour), Self.review("dana")])], me: "me")
        #expect(stats.waits == [2 * Self.hour])
    }

    @Test func botOnlyStillWaits() {
        let stats = FirstReviewStats.make([Self.pr([Self.review("copilot", bot: true)])], me: "me")
        #expect(stats.waits.isEmpty)
        #expect(stats.stillWaiting == 1)
    }

    @Test func ownReviewOnlyStillWaits() {
        let stats = FirstReviewStats.make([Self.pr([Self.review("ME")])], me: "me")
        #expect(stats.stillWaiting == 1)
    }

    @Test func pendingOrUndatedReviewDoesNotCount() {
        let stats = FirstReviewStats.make(
            [Self.pr([Self.review("dana", pending: true), Self.review("erin", at: nil)])], me: "me")
        #expect(stats.waits.isEmpty)
        #expect(stats.stillWaiting == 1)
    }

    @Test func reviewBeforeReadyIsNeitherSampleNorWaiting() {
        let stats = FirstReviewStats.make([Self.pr([Self.review("dana", at: Self.t0 - 30 * 60)])], me: "me")
        #expect(stats.waits.isEmpty)
        #expect(stats.stillWaiting == 0)
    }

    @Test func draftIsNeither() {
        let stats = FirstReviewStats.make([Self.pr(draft: true)], me: "me")
        #expect(stats.waits.isEmpty)
        #expect(stats.stillWaiting == 0)
    }

    @Test func mergedWithoutReviewIsNeither() {
        let stats = FirstReviewStats.make([Self.pr(open: false)], me: "me")
        #expect(stats.waits.isEmpty)
        #expect(stats.stillWaiting == 0)
    }

    @Test func creationStartsTheWaitWithoutReadyAt() {
        let stats = FirstReviewStats.make([Self.pr([Self.review("dana")], ready: nil)], me: "me")
        #expect(stats.waits == [3 * Self.hour])
    }

    // MARK: Top reviewers

    @Test func countsDistinctPRsAndSkipsBotsAndMe() {
        let avatar = URL(string: "https://example.com/d.png")
        let one = Self.pr([Self.review("dana", avatar: avatar), Self.review("dana"), Self.review("erin"),
                           Self.review("bot", bot: true)])
        let two = Self.pr([Self.review("Dana"), Self.review("bot", bot: true), Self.review("me")])
        let top = TopReviewers.make([one, two], me: "ME")
        #expect(top == [TopReviewer(login: "dana", avatarURL: avatar, prCount: 2),
                        TopReviewer(login: "erin", avatarURL: nil, prCount: 1)])
    }

    @Test func tiesGoByLoginIgnoringCase() {
        let top = TopReviewers.make([Self.pr([Self.review("Bob"), Self.review("al")])], me: "me")
        #expect(top.map(\.login) == ["al", "Bob"])
    }

    @Test func limitsToThree() {
        let logins = ["a", "b", "c", "d", "e"]
        let top = TopReviewers.make([Self.pr(logins.map { Self.review($0) })], me: "me")
        #expect(top.map(\.login) == ["a", "b", "c"])
    }

    // MARK: Merge times

    @Test func mergeTimeIsMergedMinusCreated() {
        let times = MergeTimes.make([MergedPR(createdAt: Self.t0, mergedAt: Self.t0 + 5 * Self.hour)])
        #expect(times == [5 * Self.hour])
    }
}
