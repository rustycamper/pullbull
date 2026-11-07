import Foundation
@testable import PullBullKit

/// Fixtures for edit tests: issues and PRs in repo o/r, and snapshots that hold them.
func editKey(_ number: Int) -> PRKey { PRKey(repo: "o/r", number: number) }

func editIssue(
    _ number: Int, labels: [String] = [], assignees: [String] = [], status: BoardStatusValue? = nil, isOpen: Bool = true
) -> BoardIssue {
    BoardIssue(
        key: editKey(number), title: "Issue \(number)", url: URL(string: "https://github.com/o/r/issues/\(number)")!,
        isOpen: isOpen, labels: labels, labelColors: labels.map { _ in nil },
        assignees: assignees.map { Assignee(login: $0, avatarURL: nil) }, status: status)
}

func editPR(
    _ number: Int, labels: [String] = [], assignees: [String] = [], author: String = "al", state: PRState = .open,
    reviews: [Review] = [], requests: [Reviewer] = [], requestTimes: [String: Date] = [:], headOid: String? = nil,
    isDraft: Bool = false, readyForReviewAt: Date? = nil
) -> PullRequest {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    return PullRequest(
        key: editKey(number), title: "PR \(number)", url: URL(string: "https://github.com/o/r/pull/\(number)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: isDraft, createdAt: at, updatedAt: at, closedAt: nil,
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
        latestReviews: reviews, reviewRequests: requests, headCommitOid: headOid, labels: labels, labelColors: labels.map { _ in nil },
        assignees: assignees.map { Assignee(login: $0, avatarURL: nil) }, reviewRequestTimes: requestTimes,
        readyForReviewAt: readyForReviewAt)
}

func editSnapshot(
    board: [BoardIssue] = [], assigned: [BoardIssue]? = [], created: [BoardIssue]? = [], mine: [PullRequest] = [],
    viewer: String = "me", options: [StatusOption]? = nil, boardProject: Int? = 1,
    boardOwner: BoardOwner? = .org("o"), boardIds: BoardIds? = nil,
    review: [PullRequest] = [], team: [PullRequest] = [], myTeams: Set<String> = [], closed: [PullRequest] = []
) -> Snapshot {
    Snapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
        org: OrgContext(org: "o", viewer: viewer, members: [], myTeams: myTeams, repos: []),
        reviewCandidates: review, mine: mine, team: team, recentlyClosed: closed, boardIssues: board,
        boardProject: boardProject,
        assignedIssues: assigned, createdIssues: created, boardStatusOptions: options, boardOwner: boardOwner,
        boardIds: boardIds)
}
