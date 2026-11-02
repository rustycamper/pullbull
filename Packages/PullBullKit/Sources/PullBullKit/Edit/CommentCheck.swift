import Foundation

/// Whether a post whose outcome was unknown landed, read from a detail fetched after it.
public enum CommentCheck {
    /// GitHub's clock may run behind the Mac's by up to this much.
    static let clockSkew: TimeInterval = 60

    /// The unknown-outcome check: a comment by `viewer` (case-insensitive), body == trimmed `text`,
    /// createdAt >= `since` (allow 60 s clock skew earlier). Line endings are compared as `\n` on both
    /// sides. The newest match when several do.
    public static func landed(_ text: String, by viewer: String, since: Date, in comments: [Comment]) -> Comment? {
        let sent = normalised(text)
        let earliest = since.addingTimeInterval(-clockSkew)
        return comments.last { comment in
            comment.author.caseInsensitiveCompare(viewer) == .orderedSame
                && comment.createdAt >= earliest
                && normalised(comment.body) == sent
        }
    }

    private static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
