import Foundation

/// What the popover says when an edit fails, in whole or in part.
public enum EditMessage {
    public static func failure(_ change: EditChange, on key: PRKey, error: any Error) -> String {
        failure(change, on: key, reason: reason(for: error))
    }

    /// Which part of a label, assignee or reviewer change GitHub didn't apply; nil when it applied both.
    public static func partial(_ change: EditChange, on key: PRKey, result: SetChangeResult) -> String? {
        if result.addApplied && result.removeApplied { return nil }
        let reason = result.refusal ?? "GitHub didn't apply it"
        guard result.addApplied || result.removeApplied else { return failure(change, on: key, reason: reason) }
        let added: String, removed: String
        switch change {
        case .labels(let a, let r):
            (added, removed) = (a.map(\.name).joined(separator: ", "), r.map(\.name).joined(separator: ", "))
        case .assignees(let a, let r):
            (added, removed) = (a.map(\.login).joined(separator: ", "), r.map(\.login).joined(separator: ", "))
        case .reviewers(let a, let r):
            let (asked, removedNames) = (a.map(\.displayName).joined(separator: ", "), r.map(\.displayName).joined(separator: ", "))
            return result.addApplied
                ? "Asked \(asked) to review #\(key.number), but couldn't remove \(removedNames): \(reason)"
                : "Removed \(removedNames) from #\(key.number), but couldn't ask \(asked): \(reason)"
        case .status, .review, .merged, .autoMerge:
            return failure(change, on: key, reason: reason)
        }
        let number = "#\(key.number)"
        return result.addApplied
            ? "Added \(added) to \(number), but couldn't remove \(removed): \(reason)"
            : "Removed \(removed) from \(number), but couldn't add \(added): \(reason)"
    }

    private static func failure(_ change: EditChange, on key: PRKey, reason: String) -> String {
        let number = "#\(key.number)"
        let what = switch change {
        case .status(_, _, .added): "add \(number) to the board"
        case .status(_, _, .removed): "remove \(number) from the board"
        case .status(_, nil, _): "clear Status on \(number)"
        case .status: "set Status on \(number)"
        case .labels: "change labels on \(number)"
        case .assignees: "change assignees on \(number)"
        case .reviewers: "change reviewers on \(number)"
        case .review: "review \(number)"
        case .merged: "merge \(number)"
        case .autoMerge(enabled: true, _): "set auto-merge on \(number)"
        case .autoMerge(enabled: false, _): "cancel auto-merge on \(number)"
        }
        return "Couldn't \(what): \(reason)"
    }

    /// A comment GitHub refused; `reason` is GitHub's words, or PullBull's when it never got there.
    public static func commentRefused(on key: PRKey, reason: String) -> String {
        "Couldn't comment on #\(key.number): \(reason)"
    }

    /// A comment whose post had no clear answer, and that a fresh detail doesn't hold.
    public static func commentUnconfirmed(on key: PRKey) -> String {
        "Couldn't confirm your comment on #\(key.number). Check the Conversation before sending again."
    }

    /// A review GitHub refused; `reason` is GitHub's words, or PullBull's when it never got there.
    public static func reviewRefused(on key: PRKey, reason: String) -> String {
        "Couldn't review #\(key.number): \(reason)"
    }

    /// A review whose write had no clear answer, and that a fresh detail doesn't hold.
    public static func reviewUnconfirmed(on key: PRKey) -> String {
        "Couldn't confirm your review of #\(key.number). Check the Reviewers section before sending again."
    }

    public static func reviewHeadMoved(on key: PRKey) -> String {
        "New commits on #\(key.number) since you started reviewing. Look again, then review."
    }

    public static func reviewNotOpen(on key: PRKey, merged: Bool) -> String {
        "#\(key.number) was \(merged ? "merged" : "closed")."
    }

    public static func mergeRefused(on key: PRKey, reason: String) -> String {
        "Couldn't merge #\(key.number): \(reason)"
    }

    public static func mergeCheckFailed(on key: PRKey, reason: String) -> String {
        "Couldn't check #\(key.number) before merging: \(reason)"
    }

    public static func mergeUnconfirmed(on key: PRKey) -> String {
        "Couldn't confirm the merge of #\(key.number). Check it before trying again."
    }

    public static func mergeHeadMoved(on key: PRKey) -> String {
        "New commits on #\(key.number) since you opened this. Look again, then merge."
    }

    /// GitHub turned the send down as the PR had changed, with no panel left open to show it.
    public static func mergeChanged(on key: PRKey) -> String {
        "#\(key.number) changed before it could merge. Look again, then merge."
    }

    public static func autoMergeCancelRefused(on key: PRKey, reason: String) -> String {
        "Couldn't cancel auto-merge on #\(key.number): \(reason)"
    }

    public static func autoMergeCancelUnconfirmed(on key: PRKey) -> String {
        "Couldn't confirm auto-merge was cancelled on #\(key.number). Check it on GitHub."
    }

    /// GitHub's own words when it refused the write; the refresh wording for anything else.
    private static func reason(for error: any Error) -> String {
        if case APIError.writeRefused(let message) = error { return message }
        return RefreshError(error).message
    }
}
