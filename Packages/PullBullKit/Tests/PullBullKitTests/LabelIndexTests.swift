import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let repo = "initech/gadgets"

private func pr(_ number: Int, labels: [String], state: PRState = .open) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "PR",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "someone",
        authorAvatarURL: nil, state: state, isDraft: false, createdAt: t0, updatedAt: t0, closedAt: nil,
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [], labels: labels)
}

private func issue(_ number: Int, labels: [String], isOpen: Bool = true) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: "Issue",
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: isOpen, labels: labels)
}

private func snapshot(
    review: [PullRequest] = [], team: [PullRequest] = [], board: [BoardIssue] = [], assigned: [BoardIssue]? = nil
) -> Snapshot {
    Snapshot(
        fetchedAt: t0,
        org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
        reviewCandidates: review, mine: [], team: team, recentlyClosed: [], boardIssues: board,
        boardProject: nil, boardTitle: nil, boardError: nil,
        assignedIssues: assigned, createdIssues: nil, boardStatusOptions: nil)
}

private func names(_ index: LabelIndex, _ prefix: String, limit: Int = 6) -> [String] {
    index.candidates(prefix: prefix, limit: limit).map(\.name)
}

@Suite struct LabelIndexTests {
    @Test func emptyWithoutData() {
        #expect(LabelIndex.empty.candidates(prefix: "").isEmpty)
        #expect(!LabelIndex.empty.contains("bug"))
    }

    @Test func collectsFromPRsAndIssuesDedupedIgnoringCase() {
        let index = LabelIndex.build(snapshot(
            team: [pr(1, labels: ["Bug", "backend"])], board: [issue(2, labels: ["bug", "good first issue"])]))
        #expect(Set(names(index, "")) == ["Bug", "backend", "good first issue"])
        #expect(index.contains("BUG"))
        #expect(index.display("bug") == "Bug")
        #expect(!index.contains("frontend"))
    }

    @Test func rankingTiers() {
        let index = LabelIndex.build(snapshot(board: [issue(1, labels: ["ui", "ui-kit", "needs ui", "build"])]))
        #expect(names(index, "ui") == ["ui", "ui-kit", "needs ui", "build"])
    }

    @Test func openCountOrdersWithinATier() {
        let index = LabelIndex.build(snapshot(
            review: [pr(1, labels: ["bravo"]), pr(2, labels: ["bravo"]), pr(3, labels: ["alpha"], state: .merged)],
            board: [issue(4, labels: ["alpha"], isOpen: false), issue(5, labels: ["bravo", "alpha"])]))
        let all = index.candidates(prefix: "")
        #expect(all.map(\.name) == ["bravo", "alpha"])
        #expect(all.map(\.openCount) == [3, 1])
    }

    @Test func samePRInTwoListsCountsOnce() {
        let index = LabelIndex.build(snapshot(review: [pr(1, labels: ["x"])], team: [pr(1, labels: ["x"])]))
        #expect(index.candidates(prefix: "x").first?.openCount == 1)
    }

    @Test func limit() {
        let index = LabelIndex.build(snapshot(board: [issue(1, labels: (1...9).map { "l\($0)" })]))
        #expect(index.candidates(prefix: "l").count == 6)
        #expect(index.candidates(prefix: "l", limit: 2).count == 2)
    }

    @Test func insertTextQuotesSpaces() {
        #expect(LabelCandidate(name: "bug", openCount: 0).insertText == "~bug")
        #expect(LabelCandidate(name: "good first issue", openCount: 0).insertText == #"~"good first issue""#)
    }
}
