import Foundation

public enum ReviewOutcome: Equatable, Sendable {
    case sent, cancelled, headMoved
    case notOpen(merged: Bool)
    /// The head couldn't be read, so nothing was sent; the reason is for the failure line.
    case checkFailed(String)
    /// GitHub refused the review, or it never left; the reason is for the failure line.
    case refused(String)
    /// The write had no clear answer; a fresh detail decides.
    case unknown
}

/// Reads the head, then sends only when it is still the commit the reader looked at.
public enum ReviewFlow {
    @MainActor public static func run(
        pinned: String, isCancelled: () -> Bool,
        readHead: @MainActor () async throws -> PRHead,
        willSend: () -> Void,
        send: @MainActor (_ commit: String) async throws -> Void
    ) async -> ReviewOutcome {
        let head: PRHead
        do {
            head = try await readHead()
        } catch {
            if isCancelled() { return .cancelled }
            switch CommentFailure.classify(error) {
            case .refused(let reason): return .checkFailed(reason)
            case .unknown: return .checkFailed(RefreshError(error).message)
            }
        }
        if isCancelled() { return .cancelled }
        guard head.state == .open else { return .notOpen(merged: head.state == .merged) }
        guard head.oid == pinned else { return .headMoved }
        willSend()
        do {
            try await send(pinned)
            return .sent
        } catch {
            switch CommentFailure.classify(error) {
            case .refused(let reason): return .refused(reason)
            case .unknown: return .unknown
            }
        }
    }
}

public enum ReviewCheck {
    /// The unknown-outcome check: a review by `viewer` (case-insensitive) in the verdict's state,
    /// submitted no earlier than `since` less the clock skew.
    public static func landed(_ verdict: ReviewVerdict, by viewer: String, since: Date, in reviews: [Review]) -> Review? {
        let earliest = since.addingTimeInterval(-CommentCheck.clockSkew)
        return reviews.last { review in
            review.state == verdict.state
                && review.author.caseInsensitiveCompare(viewer) == .orderedSame
                && (review.submittedAt.map { $0 >= earliest } ?? false)
        }
    }
}
