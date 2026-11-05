import Foundation

/// The verdict a review row carries in the Conversation.
public enum ReviewTag: String, Sendable {
    case approved = "Approved"
    case changesRequested = "Changes requested"
    case reviewed = "Reviewed"
}

/// One row of a Conversation: a comment, or a review's text shown as one.
public struct ConversationEntry: Equatable, Sendable {
    public let comment: Comment
    /// Set on a review's row; nil on a comment.
    public let tag: ReviewTag?
    /// A comment posted from here that GitHub hasn't answered for yet.
    public let isSending: Bool

    /// `comments` (oldest first) with the reviews that have text laid among them by time. Pending and
    /// dismissed reviews, reviews without text and reviews not yet submitted are left out. The comment
    /// still sending, at `sendingIndex`, stays last.
    public static func merged(comments: [Comment], sendingIndex: Int?, reviews: [Review]) -> [ConversationEntry] {
        var timed: [ConversationEntry] = []
        var sending: [ConversationEntry] = []
        for (index, comment) in comments.enumerated() {
            let isSending = index == sendingIndex
            let entry = ConversationEntry(comment: comment, tag: nil, isSending: isSending)
            if isSending { sending.append(entry) } else { timed.append(entry) }
        }
        for review in reviews {
            guard let submittedAt = review.submittedAt, let tag = tag(for: review.state),
                  let text = review.body?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
            else { continue }
            let comment = Comment(author: review.author, authorIsBot: review.byBot, body: text, createdAt: submittedAt)
            timed.append(ConversationEntry(comment: comment, tag: tag, isSending: false))
        }
        // Stable, so a comment and a review at the same moment keep the comments first.
        let ordered = timed.enumerated().sorted {
            ($0.element.comment.createdAt, $0.offset) < ($1.element.comment.createdAt, $1.offset)
        }.map(\.element)
        return ordered + sending
    }

    private static func tag(for state: ReviewState) -> ReviewTag? {
        switch state {
        case .approved: .approved
        case .changesRequested: .changesRequested
        case .commented: .reviewed
        case .pending, .dismissed: nil
        }
    }
}
