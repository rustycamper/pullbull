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
    /// The edit `begin` returned last; only its answer can arm ⌘Z.
    private var last: UUID?
    /// The board the edits were made on, from the last fetch.
    private var board: BoardRef?

    public init() {}

    /// Shows `change` at once. It becomes the last edit, so the one before can no longer be undone.
    public mutating func begin(_ change: EditChange, on key: PRKey, at now: Date, carrying copy: PullRequest? = nil) -> UUID {
        failure = nil
        undo = EditUndo()
        let id = overrides.record(change, on: key, at: now, carrying: copy)
        last = id
        return id
    }

    /// Shows the viewer's submitted review at once. Unlike `begin` it leaves ⌘Z and the failure line alone.
    public mutating func recordReview(_ change: EditChange, on key: PRKey, at now: Date) -> UUID {
        overrides.record(change, on: key, at: now)
    }

    /// Takes a review back off the screen, as when GitHub refused it. The failure line is the caller's.
    public mutating func dropReview(_ id: UUID) {
        overrides.drop(id)
    }

    /// GitHub applied the edit `id`; ⌘Z can now take it back when it's still the last edit. Not called
    /// for an undo, which isn't undoable.
    public mutating func applied(_ id: UUID, _ record: EditRecord) {
        guard id == last else { return }
        undo.remember(record)
    }

    /// GitHub refused or couldn't be reached: take the edit back off the screen and say why.
    public mutating func failed(_ id: UUID, change: EditChange, on key: PRKey, url: URL, error: any Error) {
        overrides.drop(id)
        failure = EditFailure(text: EditMessage.failure(change, on: key, error: error), url: url)
    }

    /// GitHub applied part of edit `id`: the refused half leaves the screen, the failure line says
    /// which half, and ⌘Z (when `id` is still the last edit, and it isn't an undo) takes back only the
    /// applied half.
    public mutating func partlyApplied(
        _ id: UUID, change: EditChange, result: SetChangeResult, on key: PRKey, url: URL, isUndo: Bool,
        at now: Date
    ) {
        let applied = change.keeping(result)
        overrides.replace(id, with: applied)
        failure = EditMessage.partial(change, on: key, result: result).map { EditFailure(text: $0, url: url) }
        if !isUndo, id == last, !applied.isEmpty {
            undo.remember(EditRecord(key: key, change: applied, madeAt: now, addedItemId: nil))
        }
    }

    /// The search text changed: ⌘Z undoes typing from now on, not the edit before it.
    public mutating func typed() {
        undo = EditUndo()
        last = nil
    }

    public func canUndo(now: Date) -> Bool {
        undo.canUndo(now: now)
    }

    public mutating func takeUndo(now: Date) -> EditRecord? {
        undo.take(now: now)
    }

    /// Shows a failure that isn't an edit's, such as a comment's. Leaves ⌘Z and the last edit as they were.
    public mutating func showFailure(_ failure: EditFailure) {
        self.failure = failure
    }

    public mutating func dismissFailure() {
        failure = nil
    }

    /// Ends the edits `fetched` agrees with, but for reviews on `held`, whose keys come back when their
    /// detail needs reading again. A fetch of another board drops them all, and the undo.
    @discardableResult
    public mutating func reconcile(with fetched: Snapshot, now: Date, holdingReviews held: Set<PRKey> = []) -> Set<PRKey> {
        if let board, fetched.board != board {
            self = EditSession()
            self.board = fetched.board
            return []
        }
        board = fetched.board
        return overrides.reconcile(with: fetched, now: now, holdingReviews: held)
    }
}
