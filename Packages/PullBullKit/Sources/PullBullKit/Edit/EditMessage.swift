import Foundation

/// What the popover says when an edit fails, in whole or in part.
public enum EditMessage {
    public static func failure(_ change: EditChange, on key: PRKey, error: any Error) -> String {
        failure(change, on: key, reason: reason(for: error))
    }

    /// Which part of a label or assignee change GitHub didn't apply; nil when it applied both.
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
        case .status:
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
        }
        return "Couldn't \(what): \(reason)"
    }

    /// GitHub's own words when it refused the write; the refresh wording for anything else.
    private static func reason(for error: any Error) -> String {
        if case APIError.writeRefused(let message) = error { return message }
        return RefreshError(error).message
    }
}
