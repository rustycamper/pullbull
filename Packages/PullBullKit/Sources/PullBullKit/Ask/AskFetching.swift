import Foundation

/// One page of the Ask index search: its items, GitHub's total result count and the cursor for the next
/// page (nil on the last).
public struct AskPage: Sendable {
    public let items: [AskItem]
    public let total: Int
    public let next: String?

    public init(items: [AskItem], total: Int, next: String?) {
        self.items = items
        self.total = total
        self.next = next
    }
}

/// Where the Ask index gets its PRs and issues from.
public protocol AskFetching: Sendable {
    func askPage(query: String, after: String?) async throws -> AskPage
}

extension GitHubAPI: AskFetching {}
