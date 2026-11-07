import Foundation

/// Failure lines for accounts that aren't running, by login, shown when each runs again. A merge or draft
/// flip answered after a switch lands here. One line per item, the newest about it, oldest item first, so
/// two failures on different PRs don't replace each other.
public struct HeldFailures: Sendable {
    private var lines: [String: [EditFailure]] = [:]

    public init() {}

    public mutating func hold(_ failure: EditFailure, for login: String) {
        lines[login, default: []].removeAll { $0.key == failure.key }
        lines[login, default: []].append(failure)
    }

    /// The login's lines, oldest first, which are no longer held.
    public mutating func take(for login: String) -> [EditFailure] {
        lines.removeValue(forKey: login) ?? []
    }
}
