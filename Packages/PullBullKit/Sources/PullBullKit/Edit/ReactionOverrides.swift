import Foundation

/// One reaction on one subject: the target of a click.
public struct ReactionTarget: Hashable, Sendable {
    public let subjectId: String
    public let content: ReactionContent

    public init(subjectId: String, content: ReactionContent) {
        self.subjectId = subjectId
        self.content = content
    }
}

/// Reactions clicked here that the stored detail may not show yet. One entry per target: a newer click replaces it.
public struct ReactionOverrides: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let add: Bool
        let key: PRKey
        let madeAt: Date
        var answeredAt: Date?
    }

    private var entries: [ReactionTarget: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    /// The state the latest click asked for, or nil.
    public func wanted(_ target: ReactionTarget) -> Bool? { entries[target]?.add }

    /// A click: replaces any entry for `target`, unanswered. Prunes entries past `EditOverrides.lifetime`.
    public mutating func record(_ target: ReactionTarget, add: Bool, on key: PRKey, at now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.madeAt) < EditOverrides.lifetime }
        entries[target] = Entry(add: add, key: key, madeAt: now, answeredAt: nil)
    }

    /// GitHub answered (or the outcome became unknown) for `target` at `date`.
    public mutating func answered(_ target: ReactionTarget, at date: Date) {
        entries[target]?.answeredAt = date
    }

    public mutating func drop(_ target: ReactionTarget) {
        entries[target] = nil
    }

    /// `reactions` with every entry on its subject that is still in force laid over it. `fetchedAt` is
    /// the stored detail's stamp. An entry is in force while `now - madeAt < EditOverrides.lifetime`, and
    /// either it is unanswered, or `fetchedAt` is nil or not later than its answer. A detail fetch that
    /// started after the answer shows GitHub's state. If an older fetch lands after it, the entry is in
    /// force again. Nothing is removed on a fetch, so fetch order can't undo a click.
    public func apply(to reactions: Reactions?, fetchedAt: Date?, now: Date) -> Reactions? {
        guard var result = reactions else { return nil }
        for (target, entry) in entries where target.subjectId == result.subjectId {
            guard now.timeIntervalSince(entry.madeAt) < EditOverrides.lifetime else { continue }
            if let answeredAt = entry.answeredAt, let fetchedAt, fetchedAt > answeredAt { continue }
            result = result.laying(target.content, add: entry.add)
        }
        return result
    }
}
