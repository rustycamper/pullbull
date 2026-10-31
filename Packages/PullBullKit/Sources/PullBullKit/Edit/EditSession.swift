import Foundation

/// The line shown above the footer when an edit failed.
public struct EditFailure: Equatable, Sendable {
    public let text: String
    /// The item on GitHub, for **Open on GitHub**.
    public let url: URL

    public init(text: String, url: URL) {
        self.text = text
        self.url = url
    }
}

/// The edits PullBull is showing before GitHub agrees, the one ⌘Z can take back, and the last failure.
public struct EditSession: Equatable, Sendable {
    public private(set) var overrides = EditOverrides()
    /// Shown until dismissed or the next edit.
    public private(set) var failure: EditFailure?
    private var undo = EditUndo()

    public init() {}

    /// Shows `change` at once. It becomes the last edit, so the one before can no longer be undone.
    public mutating func begin(_ change: EditChange, on key: PRKey, at now: Date) -> UUID {
        failure = nil
        undo = EditUndo()
        return overrides.record(change, on: key, at: now)
    }

    /// GitHub applied the last edit; ⌘Z can now take it back. Not called for an undo, which isn't undoable.
    public mutating func applied(_ record: EditRecord) {
        undo.remember(record)
    }

    /// GitHub refused or couldn't be reached: take the edit back off the screen and say why.
    public mutating func failed(_ id: UUID, change: EditChange, on key: PRKey, url: URL, error: any Error) {
        overrides.drop(id)
        failure = EditFailure(text: EditMessage.failure(change, on: key, error: error), url: url)
    }

    public func canUndo(now: Date) -> Bool {
        undo.canUndo(now: now)
    }

    public mutating func takeUndo(now: Date) -> EditRecord? {
        undo.take(now: now)
    }

    public mutating func dismissFailure() {
        failure = nil
    }

    public mutating func reconcile(with fetched: Snapshot, now: Date) {
        overrides.reconcile(with: fetched, now: now)
    }
}
