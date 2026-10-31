import Foundation

/// An edit GitHub applied, as undo needs it.
public struct EditRecord: Equatable, Sendable {
    public let key: PRKey
    public let change: EditChange
    public let madeAt: Date
    /// The board item an `.added` Status edit created, which undo deletes.
    public let addedItemId: String?

    public init(key: PRKey, change: EditChange, madeAt: Date, addedItemId: String?) {
        self.key = key
        self.change = change
        self.madeAt = madeAt
        self.addedItemId = addedItemId
    }
}

/// ⌘Z for the last edit, for `window` seconds after it was made. Only the last edit, and only once.
public struct EditUndo: Equatable, Sendable {
    public static let window: TimeInterval = 10

    private var last: EditRecord?

    public init() {}

    /// Replaces any older edit; only the last one can be undone.
    public mutating func remember(_ record: EditRecord) {
        last = record
    }

    public func canUndo(now: Date) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last.madeAt) < Self.window
    }

    /// The last edit, when it is still within the window, and forgets it.
    public mutating func take(now: Date) -> EditRecord? {
        defer { last = nil }
        return canUndo(now: now) ? last : nil
    }
}
