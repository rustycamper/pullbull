import Foundation
import Testing
@testable import PullBullKit

private let updated = Date(timeIntervalSince1970: 1_800_000_000)

private func issue(_ n: Int, updatedAt: Date? = updated) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: "o/r", number: n), title: "i\(n)", url: URL(string: "https://x/\(n)")!,
        isOpen: true, updatedAt: updatedAt)
}

private func detail(_ row: BoardIssue) -> IssueDetail {
    IssueDetail(key: row.key, issue: row, body: "", commentTotal: 0, lastComments: [], linkedPRs: [])
}

private func tabs(
    _ groups: [IssueGroup], loaded: Bool = true, error: String? = nil
) -> BuiltIssueTabs {
    BuiltIssueTabs(
        assigned: IssueTabContents(groups: groups), created: IssueTabContents(groups: []), board: nil,
        statusKnown: false, assignedLoaded: loaded, assignedError: error)
}

@Suite struct IssuePrefetchTests {
    @Test func currentWhenUpdatedAtMatches() {
        #expect(detail(issue(1)).isCurrent(for: issue(1)))
    }

    @Test func staleWhenIssueUpdatedSince() {
        #expect(!detail(issue(1)).isCurrent(for: issue(1, updatedAt: updated + 60)))
    }

    @Test func staleWhenFreshnessUnknown() {
        #expect(!detail(issue(1, updatedAt: nil)).isCurrent(for: issue(1)))
        #expect(!detail(issue(1, updatedAt: nil)).isCurrent(for: issue(1, updatedAt: nil)))
        #expect(!detail(issue(1)).isCurrent(for: issue(1, updatedAt: nil)))
    }

    @Test func prefetchesCountedIssuesInListOrder() {
        let built = tabs([
            IssueGroup(kind: .repo("o/b"), issues: [issue(3), issue(1)], counted: true),
            IssueGroup(kind: .repo("o/a"), issues: [issue(2)], counted: true),
            IssueGroup(kind: .done, issues: [issue(4)], counted: false),
        ])
        #expect(built.assignedToPrefetch.map(\.key.number) == [3, 1, 2])
    }

    @Test func prefetchIsCappedAtFifty() {
        let built = tabs([
            IssueGroup(kind: .notOnBoard, issues: (1...60).map { issue($0) }, counted: true),
            IssueGroup(kind: .all, issues: [issue(61)], counted: true),
        ])
        #expect(BuiltIssueTabs.prefetchCap == 50)
        #expect(built.assignedToPrefetch.map(\.key.number) == Array(1...50))
    }

    /// A failed or never-run Assigned search has nothing to prefetch, even with a last good list kept.
    @Test func nothingToPrefetchWhenTheSearchFailedOrNeverRan() {
        let groups = [IssueGroup(kind: .all, issues: [issue(1)], counted: true)]
        #expect(tabs(groups, error: "Offline").assignedToPrefetch.isEmpty)
        #expect(tabs([], loaded: false).assignedToPrefetch.isEmpty)
    }

    @Test func storeKeepsTheRowFreshness() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir)
        try await store.saveIssueDetail(detail(issue(1)), account: "me")
        let back = try #require(await store.loadIssueDetail(issue(1).key, account: "me"))
        #expect(back.isCurrent(for: issue(1)))
    }
}
