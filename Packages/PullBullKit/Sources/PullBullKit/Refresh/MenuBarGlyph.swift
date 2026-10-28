import Foundation

/// Which glyph the menu bar item draws. The three assets are the same size, so switching never moves
/// the count or the items beside it.
public enum MenuBarGlyph: Equatable, Sendable {
    case normal
    /// Slashed and dimmed: no connectivity.
    case offline
    /// The normal glyph with an exclamation badge: a failure the user can act on.
    case error
    /// The normal glyph, always dimmed: no account yet.
    case notSetUp

    /// `noAccount`: no account chosen yet, which is setup, not a failure, so it dims rather than badges.
    /// `signedOut`: the current app account's sign-in ended, which is a failure. A rate limit clears by
    /// itself, so it gets no badge either.
    public static func glyph(for error: RefreshError?, noAccount: Bool, signedOut: Bool) -> MenuBarGlyph {
        if error == .offline { return .offline }
        if signedOut { return .error }
        if noAccount { return .notSetUp }
        switch error {
        case nil, .rateLimited: return .normal
        case _ where error == StatusTooltip.noAccount: return .normal
        default: return .error
        }
    }

    /// Whether glyph and count draw dimmed: always offline, never with the badge (it must read at full
    /// strength), always before setup, and for the normal glyph when the data is stale or the Assigned
    /// count incomplete.
    public func dimmed(stale: Bool, issuesIncomplete: Bool) -> Bool {
        switch self {
        case .offline, .notSetUp: true
        case .error: false
        case .normal: stale || issuesIncomplete
        }
    }
}
