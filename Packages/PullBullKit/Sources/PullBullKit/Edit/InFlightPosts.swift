import Foundation

/// Comment posts whose outcome isn't final yet, per account and item. Unlike `PostedComments`, an account
/// or org change keeps them, so switching away and back mid-post can't send the same draft twice.
public struct InFlightPosts: Equatable, Sendable {
    private struct Slot: Hashable, Sendable {
        let account: String
        let key: PRKey
    }

    private var slots: Set<Slot> = []

    public init() {}

    /// `account` is a login, case ignored.
    public mutating func insert(account: String, key: PRKey) {
        slots.insert(Slot(account: account.lowercased(), key: key))
    }

    public mutating func remove(account: String, key: PRKey) {
        slots.remove(Slot(account: account.lowercased(), key: key))
    }

    public func contains(account: String, key: PRKey) -> Bool {
        slots.contains(Slot(account: account.lowercased(), key: key))
    }
}
