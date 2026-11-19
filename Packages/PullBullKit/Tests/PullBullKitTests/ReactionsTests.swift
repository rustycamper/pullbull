import Foundation
import Testing
@testable import PullBullKit

@Suite struct ReactionsTests {
    private func group(
        _ content: ReactionContent, count: Int, reacted: Bool = false, reactors: [String] = []
    ) -> ReactionGroup {
        ReactionGroup(content: content, count: count, viewerHasReacted: reacted, reactors: reactors)
    }

    @Test func emojiAndNamesFollowGitHubsOrder() {
        #expect(ReactionContent.allCases.map(\.emoji) == ["👍", "👎", "😄", "🎉", "😕", "❤️", "🚀", "👀"])
        #expect(ReactionContent.eyes.name == "Eyes")
        #expect(ReactionContent.thumbsUp.name == "Thumbs up")
    }

    @Test func tooltipExamples() {
        #expect(
            group(.thumbsUp, count: 3, reacted: true, reactors: ["me", "bob", "frank"]).tooltip(viewer: "Me")
                == "You, bob and frank reacted with 👍")
        #expect(
            group(.thumbsUp, count: 5, reacted: true).tooltip(viewer: "me")
                == "You and 4 others reacted with 👍")
        #expect(
            group(.hooray, count: 2, reactors: ["alice"]).tooltip(viewer: "me")
                == "alice and 1 other reacted with 🎉")
        #expect(
            group(.eyes, count: 4, reactors: ["a", "b", "c"]).tooltip(viewer: nil)
                == "a, b, c and 1 other reacted with 👀")
        #expect(group(.rocket, count: 2).tooltip(viewer: "me") == "2 people reacted with 🚀")
        #expect(
            group(.thumbsUp, count: 2, reactors: ["me", "bob", "frank"]).tooltip(viewer: "me")
                == "bob and frank reacted with 👍")
    }

    @Test func accessibilityLabelSaysIncludingYou() {
        #expect(group(.thumbsUp, count: 3, reacted: true).accessibilityLabel == "👍 3, including you")
        #expect(group(.hooray, count: 1).accessibilityLabel == "🎉 1")
    }

    @Test func shownDropsZeroCounts() {
        let reactions = Reactions(
            subjectId: "S", groups: [group(.thumbsUp, count: 0), group(.heart, count: 2, reacted: true)],
            viewerCanReact: true)
        #expect(reactions.shown.map(\.content) == [.heart])
        #expect(reactions.viewerHasReacted(.heart))
        #expect(!reactions.viewerHasReacted(.thumbsUp))
        #expect(!reactions.viewerHasReacted(.eyes))
    }

    @Test func anOldCachedDetailDecodesWithoutReactions() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let commentJSON = #"{"id":"C1","author":"alice","authorIsBot":false,"body":"hi","createdAt":1700000000}"#
        let reviewJSON = #"{"author":"bob","state":"approved","submittedAt":1700000100,"body":"ok"}"#

        let comment = try decoder.decode(PullBullKit.Comment.self, from: Data(commentJSON.utf8))
        #expect(comment.reactions == nil)
        let review = try decoder.decode(Review.self, from: Data(reviewJSON.utf8))
        #expect(review.id == nil)
        #expect(review.reactions == nil)

        let prJSON = """
            {"key":{"repo":"o/r","number":1},"body":"desc","checks":[],
             "reviews":[\(reviewJSON)],"comments":[\(commentJSON)],"files":[]}
            """
        let pr = try decoder.decode(PRDetail.self, from: Data(prJSON.utf8))
        #expect(pr.reactions == nil)
        #expect(pr.fetchedAt == nil)
        #expect(pr.comments.count == 1 && pr.comments[0].reactions == nil)
        #expect(pr.reviews.count == 1 && pr.reviews[0].id == nil && pr.reviews[0].reactions == nil)

        let issueJSON = """
            {"key":{"repo":"o/r","number":2},
             "issue":{"key":{"repo":"o/r","number":2},"title":"T","url":"https://github.com/o/r/issues/2","isOpen":true},
             "body":"desc","commentTotal":1,"lastComments":[\(commentJSON)],"linkedPRs":[]}
            """
        let issue = try decoder.decode(IssueDetail.self, from: Data(issueJSON.utf8))
        #expect(issue.reactions == nil)
        #expect(issue.fetchedAt == nil)
        #expect(issue.lastComments.count == 1 && issue.lastComments[0].reactions == nil)
    }

    @Test func reviewEqualityIgnoresIdAndReactions() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Review(author: "bob", state: .approved, submittedAt: date)
        let b = Review(
            author: "bob", state: .approved, submittedAt: date, id: "R1",
            reactions: Reactions(subjectId: "R1", groups: [group(.heart, count: 1)], viewerCanReact: true))
        let c = Review(author: "bob", state: .commented, submittedAt: date)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect([a].contains(b))
        #expect(a != c)
    }
}
