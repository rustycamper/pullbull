import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let repo = "initech/gadgets"

private func pr(
    _ number: Int, author: String = "someone", avatar: URL? = nil, state: PRState = .open,
    reviews: [Review] = [], requests: [Reviewer] = []
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "PR",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: author,
        authorAvatarURL: avatar, state: state, isDraft: false, createdAt: t0, updatedAt: t0, closedAt: nil,
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: reviews, reviewRequests: requests)
}

private func issue(
    _ number: Int, author: String? = nil, assignees: [Assignee] = [], isOpen: Bool = true, updatedAt: Date? = nil
) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: "Issue",
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: isOpen, author: author,
        updatedAt: updatedAt, assignees: assignees)
}

private func snapshot(
    members: [String] = [], viewer: String = "Me-Viewer", review: [PullRequest] = [],
    mine: [PullRequest] = [], team: [PullRequest] = [], board: [BoardIssue] = [],
    assigned: [BoardIssue]? = nil, created: [BoardIssue]? = nil
) -> Snapshot {
    Snapshot(
        fetchedAt: t0,
        org: OrgContext(org: "initech", viewer: viewer, members: members, myTeams: [], repos: ["gadgets"]),
        reviewCandidates: review, mine: mine, team: team, recentlyClosed: [], boardIssues: board,
        boardProject: nil, boardTitle: nil, boardError: nil,
        assignedIssues: assigned, createdIssues: created, boardStatusOptions: nil)
}

private func logins(_ index: PeopleIndex, _ prefix: String, limit: Int = 6) -> [String] {
    index.candidates(prefix: prefix, limit: limit).map(\.login)
}

@Suite struct PeopleIndexTests {
    @Test func dedupesAcrossListsAndCase() {
        let index = PeopleIndex.build(snapshot(
            team: [pr(1, author: "Alice")], board: [issue(2, assignees: [Assignee(login: "alice", avatarURL: nil)])]))
        #expect(logins(index, "ali") == ["Alice"])
    }

    @Test func sourcesAndAvatar() {
        let prAvatar = URL(string: "https://a/pr.png")!
        let assigneeAvatar = URL(string: "https://a/as.png")!
        let index = PeopleIndex.build(snapshot(
            members: ["mem"],
            review: [pr(1, author: "pra", avatar: prAvatar, reviews: [Review(author: "rev", state: .approved, submittedAt: t0)],
                        requests: [.user("req"), .team("core")])],
            board: [issue(2, author: "iss", assignees: [Assignee(login: "pra", avatarURL: assigneeAvatar),
                                                         Assignee(login: "asg", avatarURL: assigneeAvatar)])]))
        let all = Set(logins(index, "", limit: 50))
        #expect(all == ["Me-Viewer", "mem", "pra", "rev", "req", "iss", "asg"])
        #expect(index.candidates(prefix: "pra")[0].avatarURL == prAvatar)
        #expect(index.candidates(prefix: "asg")[0].avatarURL == assigneeAvatar)
        #expect(index.candidates(prefix: "mem")[0].avatarURL == nil)
        #expect(index.candidates(prefix: "mem")[0].isMember)
    }

    @Test func ghostIsNotACandidate() {
        let index = PeopleIndex.build(snapshot(team: [pr(1, author: "ghost")]))
        #expect(index.candidates(prefix: "gh").isEmpty)
    }

    @Test func rankingTiers() {
        let index = PeopleIndex.build(snapshot(
            members: ["stgeorge", "ana-geo", "geordi", "geo"]))
        #expect(logins(index, "geo") == ["geo", "geordi", "ana-geo", "stgeorge"])
    }

    @Test func withinTierOrder() {
        let shared = PeopleIndex.build(snapshot(
            members: ["x-member", "x-alpha-member"],
            team: [pr(1, author: "x-busy"), pr(2, author: "x-busy"), pr(3, author: "x-b"), pr(4, author: "x-a")]))
        #expect(logins(shared, "x-") == ["x-busy", "x-a", "x-b", "x-alpha-member", "x-member"])
        let tieZero = PeopleIndex.build(snapshot(members: ["t-zmember"], team: [pr(1, author: "t-anon", state: .closed)]))
        #expect(logins(tieZero, "t-") == ["t-zmember", "t-anon"])
    }

    @Test func viewerFirstOnEmptyPrefix() {
        let index = PeopleIndex.build(snapshot(members: ["Me-Viewer", "zed", "amy"]))
        let first = index.candidates(prefix: "")[0]
        #expect(first.isViewer)
        #expect(first.insertText == "@me")
        #expect(first.login == "Me-Viewer")
        #expect(logins(index, "m").contains("Me-Viewer"))
        #expect(logins(index, "", limit: 50).filter { $0.lowercased() == "me-viewer" }.count == 1)
    }

    @Test func limitSix() {
        let index = PeopleIndex.build(snapshot(members: (1...10).map { "user\($0)" }))
        #expect(index.candidates(prefix: "user").count == 6)
        #expect(index.candidates(prefix: "user", limit: 3).count == 3)
    }

    @Test func openCountCountsOpenItemsOnce() {
        let shared = pr(1, author: "dana")
        let closed = pr(2, author: "dana", state: .closed)
        let index = PeopleIndex.build(snapshot(
            review: [shared], team: [shared, closed], board: [issue(3, author: "dana")],
            assigned: [issue(3, author: "dana")]))
        #expect(index.candidates(prefix: "dana")[0].openCount == 2)
        let onlyClosed = PeopleIndex.build(snapshot(team: [closed]))
        #expect(onlyClosed.candidates(prefix: "dana")[0].openCount == 0)
    }

    @Test func containsAndDisplay() {
        let index = PeopleIndex.build(snapshot(team: [pr(1, author: "Alice")]))
        #expect(index.contains("ALICE"))
        #expect(index.contains("me"))
        #expect(!index.contains("nobody"))
        #expect(index.display("alice") == "Alice")
        #expect(index.display("nobody") == "nobody")
        #expect(PeopleIndex.empty.contains("me") == false)
    }

    @Test func viewerMatchesMeOnlyByExactOrPrefix() {
        let index = PeopleIndex.build(snapshot(viewer: "bob"))
        #expect(logins(index, "me") == ["bob"])
        #expect(logins(index, "m") == ["bob"])
        #expect(logins(index, "e").isEmpty)
    }

    /// Counts read the copy search shows (`SearchEngine.cachedIssues`), so a count never names an item
    /// `@erin` can't find. Every copy still names candidates.
    @Test func openCountUsesTheCopySearchShows() {
        let board = issue(5, author: "other")
        let assigned = issue(5, author: "other", assignees: [Assignee(login: "erin", avatarURL: nil)])
        // No dates: search keeps the board copy, where erin has no role.
        let undated = PeopleIndex.build(snapshot(board: [board], assigned: [assigned]))
        #expect(undated.candidates(prefix: "erin")[0].openCount == 0)
        // The newer Assigned copy is the one search shows.
        let newer = issue(5, author: "other", assignees: [Assignee(login: "erin", avatarURL: nil)], updatedAt: Date(timeIntervalSince1970: 2_000))
        let older = issue(5, author: "other", updatedAt: Date(timeIntervalSince1970: 1_000))
        let dated = PeopleIndex.build(snapshot(board: [older], assigned: [newer]))
        #expect(dated.candidates(prefix: "erin")[0].openCount == 1)
        // A stale open copy doesn't count once the newer copy is closed.
        let closed = issue(6, author: "erin", isOpen: false, updatedAt: Date(timeIntervalSince1970: 2_000))
        let staleOpen = issue(6, author: "erin", updatedAt: Date(timeIntervalSince1970: 1_000))
        let reopened = PeopleIndex.build(snapshot(board: [staleOpen], assigned: [closed]))
        #expect(reopened.candidates(prefix: "erin")[0].openCount == 0)
    }
}

@Suite struct PeopleIndexAvatarTests {
    private let url = URL(string: "https://avatars.example.com/alice.png")!
    private let viewerURL = URL(string: "https://avatars.example.com/viewer.png")!

    @Test func knownLoginReturnsItsURL() {
        let index = PeopleIndex.build(snapshot(team: [pr(1, author: "alice", avatar: url)]))
        #expect(index.avatarURL("alice") == url)
        #expect(index.avatarURL("nobody") == nil)
    }

    @Test func lookupIsCaseInsensitive() {
        let index = PeopleIndex.build(snapshot(team: [pr(1, author: "alice", avatar: url)]))
        #expect(index.avatarURL("ALICE") == url)
    }

    @Test func meResolvesToViewerAvatar() {
        let index = PeopleIndex.build(snapshot(viewer: "Viewer", mine: [pr(1, author: "Viewer", avatar: viewerURL)]))
        #expect(index.avatarURL("me") == viewerURL)
        #expect(index.avatarURL("ME") == viewerURL)
    }
}

