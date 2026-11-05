import Foundation
import Testing
@testable import PullBullKit

@Suite struct ConversationEntryTests {
    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
    private func comment(_ body: String, _ seconds: Double) -> PullBullKit.Comment {
        PullBullKit.Comment(author: "ann", body: body, createdAt: at(seconds))
    }
    private func review(
        _ state: ReviewState, body: String? = "text", at seconds: Double? = 10, byBot: Bool? = nil
    ) -> Review {
        Review(author: "bob", state: state, submittedAt: seconds.map(at), byBot: byBot, body: body)
    }

    @Test func mergesByTime() {
        let entries = ConversationEntry.merged(
            comments: [comment("a", 5), comment("c", 15)], sendingIndex: nil,
            reviews: [review(.approved, body: "b", at: 10)])
        #expect(entries.map(\.comment.body) == ["a", "b", "c"])
        #expect(entries.map(\.tag) == [nil, .approved, nil])
    }

    @Test func sendingCommentStaysLast() {
        let entries = ConversationEntry.merged(
            comments: [comment("a", 5), comment("sending", 8)], sendingIndex: 1,
            reviews: [review(.approved, body: "b", at: 10)])
        #expect(entries.map(\.comment.body) == ["a", "b", "sending"])
        #expect(entries.map(\.isSending) == [false, false, true])
    }

    @Test func tagsFollowState() {
        let entries = ConversationEntry.merged(
            comments: [], sendingIndex: nil,
            reviews: [
                review(.approved, at: 1), review(.changesRequested, at: 2), review(.commented, at: 3),
            ])
        #expect(entries.map(\.tag) == [.approved, .changesRequested, .reviewed])
        #expect(entries.map { $0.tag?.rawValue } == ["Approved", "Changes requested", "Reviewed"])
    }

    @Test func leavesOutEmptyPendingAndDismissed() {
        let entries = ConversationEntry.merged(
            comments: [], sendingIndex: nil,
            reviews: [
                review(.approved, body: nil), review(.approved, body: "  \n "), review(.pending),
                review(.dismissed), review(.approved, at: nil),
            ])
        #expect(entries.isEmpty)
    }

    @Test func botReviewShows() {
        let entries = ConversationEntry.merged(
            comments: [], sendingIndex: nil, reviews: [review(.commented, byBot: true)])
        #expect(entries.count == 1)
        #expect(entries[0].comment.authorIsBot == true)
    }
}
