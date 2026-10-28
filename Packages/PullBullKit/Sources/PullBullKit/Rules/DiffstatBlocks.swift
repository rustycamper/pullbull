import Foundation

/// GitHub's five-block diffstat bar: how many blocks are additions, deletions and neutral.
/// Under five changed lines, each line is one block and the rest stay neutral; otherwise the blocks split
/// by share of changed lines, and a side with any lines gets at least one block.
public struct DiffstatBlocks: Equatable, Sendable {
    public static let total = 5

    public let additions: Int
    public let deletions: Int
    public var neutral: Int { Self.total - additions - deletions }

    public init(additions: Int, deletions: Int) {
        let added = max(0, additions)
        let deleted = max(0, deletions)
        let changed = added + deleted
        guard changed > 0 else {
            self.additions = 0
            self.deletions = 0
            return
        }
        if changed < Self.total {
            self.additions = added
            self.deletions = deleted
            return
        }
        let share = (Double(Self.total) * Double(added) / Double(changed)).rounded()
        let low = added > 0 ? 1 : 0
        let high = deleted > 0 ? Self.total - 1 : Self.total
        self.additions = min(max(Int(share), low), high)
        self.deletions = Self.total - self.additions
    }
}
