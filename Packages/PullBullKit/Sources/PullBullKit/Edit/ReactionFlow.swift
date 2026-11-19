import Foundation

public enum ReactionAnswer: Equatable, Sendable { case applied(Reactions), refused(String), unknown }

public enum ReactionStep: Equatable, Sendable {
    /// GitHub holds what was last asked: record the answer, write `Reactions` through.
    case done(Reactions)
    /// The last click asked for the other state: send that.
    case send(add: Bool)
    /// GitHub refused what was last asked: drop the override, show the refused line.
    case refused(String)
    /// GitHub refused, but the user has since asked for the state GitHub kept: drop the override quietly.
    case dropQuietly
    /// The outcome is unknown: mark answered, fetch the detail once.
    case confirm
    /// Unknown, and the confirm didn't show what was asked: drop the override, show the unconfirmed line.
    case unconfirmed
}

/// Decides what follows a reaction write. A click made while one is in flight is sent after the answer.
public enum ReactionFlow {
    /// `sent` is what was sent; `wanted` is what the latest click asks for.
    public static func next(sent add: Bool, answer: ReactionAnswer, wanted: Bool) -> ReactionStep {
        switch answer {
        case .applied(let reactions): wanted == add ? .done(reactions) : .send(add: wanted)
        case .refused(let reason): wanted == add ? .refused(reason) : .dropQuietly
        case .unknown: .confirm
        }
    }

    /// After the confirm fetch. `fetched` is the subject's reactions in the fetched detail, nil when the
    /// fetch failed. `wanted` is read again after the fetch, since a click can land while it runs.
    public static func afterConfirm(
        _ fetched: Reactions?, content: ReactionContent, sent add: Bool, wanted: Bool
    ) -> ReactionStep {
        guard let fetched else { return .unconfirmed }
        if fetched.viewerHasReacted(content) == wanted { return .dropQuietly }
        return wanted != add ? .send(add: wanted) : .unconfirmed
    }
}
