import Foundation

/// Which issues can have their board Status set from PullBull, and what a pick changes.
public enum StatusEdit {
    /// The shown board has Status options, and the issue is on it or in a repo its owner owns (an org
    /// board takes that org's issues; a personal board, its user's own).
    public static func isOffered(_ key: PRKey, in snapshot: Snapshot) -> Bool {
        guard snapshot.boardStatus == .available, snapshot.boardStatusOptions?.isEmpty == false,
              let owner = snapshot.board?.owner else { return false }
        if snapshot.boardIssues.contains(where: { $0.key == key }) { return true }
        let repoOwner = key.repo.split(separator: "/").first.map(String.init) ?? ""
        return repoOwner.caseInsensitiveCompare(owner.login) == .orderedSame
    }

    /// The edit that moves the issue to `status` (nil clears it); nil when Status isn't offered, when
    /// nothing would change, or when clearing an issue that isn't on the board.
    public static func change(for key: PRKey, to status: BoardStatusValue?, in snapshot: Snapshot) -> EditChange? {
        guard isOffered(key, in: snapshot) else { return nil }
        let card = snapshot.boardIssues.first { $0.key == key }
        if card == nil && status == nil { return nil }
        let change = EditChange.status(from: card?.status, to: status, placement: card == nil ? .added : .already)
        return change.isEmpty ? nil : change
    }
}
