import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let repo = "initech/gadgets"

private func pr(
    _ number: Int, _ title: String = "PR", author: String = "someone",
    reviews: [Review] = [], requests: [Reviewer] = []
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: title,
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: author,
        authorAvatarURL: nil, state: .open, isDraft: false, createdAt: t0, updatedAt: t0, closedAt: nil,
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: reviews, reviewRequests: requests)
}

private func issue(
    _ number: Int, _ title: String = "Issue", author: String? = nil, assignees: [String] = []
) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: title,
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: true, author: author,
        assignees: assignees.map { Assignee(login: $0, avatarURL: nil) })
}

private func review(_ author: String, _ state: ReviewState) -> Review {
    Review(author: author, state: state, submittedAt: t0)
}

private func snapshot(
    review: [PullRequest] = [], mine: [PullRequest] = [], team: [PullRequest] = [],
    issues: [BoardIssue] = []
) -> Snapshot {
    Snapshot(
        fetchedAt: t0,
        org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
        reviewCandidates: review, mine: mine, team: team, recentlyClosed: [], boardIssues: issues,
        boardProject: nil, boardTitle: nil, boardError: nil,
        assignedIssues: nil, createdIssues: nil, boardStatusOptions: nil)
}

private let engine = SearchEngine(api: GitHubAPI(transport: NoTransport(), auth: StaticTokenSource("t")))

private struct NoTransport: GraphQLTransport {
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        throw APIError.network("unused")
    }
}

@Suite struct PersonMatchTests {
    @Test func everyPRRole() {
        #expect(PersonMatch.roles(of: pr(1, author: "alice"), login: "alice", viewer: "v") == [.author])
        #expect(PersonMatch.roles(of: pr(1, requests: [.user("alice")]), login: "alice", viewer: "v") == [.requested])
        for state in [ReviewState.commented, .dismissed, .pending, .approved, .changesRequested] {
            let p = pr(1, reviews: [review("alice", state)])
            #expect(PersonMatch.roles(of: p, login: "alice", viewer: "v") == [.reviewed(state)])
        }
    }

    @Test func everyIssueRole() {
        #expect(PersonMatch.roles(of: issue(1, author: "alice"), login: "alice", viewer: "v") == [.author])
        #expect(PersonMatch.roles(of: issue(1, assignees: ["alice"]), login: "alice", viewer: "v") == [.assignee])
    }

    @Test func matchesIgnoringCase() {
        #expect(PersonMatch.roles(of: pr(1, author: "alice"), login: "ALICE", viewer: "me") == [.author])
        #expect(PersonMatch.roles(of: issue(1, assignees: ["Alice"]), login: "aLICE", viewer: "me") == [.assignee])
    }

    @Test func meIsTheViewer() {
        #expect(PersonMatch.roles(of: pr(1, author: "devon"), login: "me", viewer: "devon") == [.author])
        #expect(PersonMatch.roles(of: issue(1, author: "devon"), login: "me", viewer: "devon") == [.author])
    }

    @Test func teamRequestNeverMatchesUser() {
        let p = pr(1, requests: [.team("alice")])
        #expect(PersonMatch.roles(of: p, login: "alice", viewer: "v").isEmpty)
    }

    @Test func nilIssueAuthorNeverMatches() {
        let i = issue(1, author: nil)
        #expect(PersonMatch.roles(of: i, login: "ghost", viewer: "v").isEmpty)
        #expect(PersonMatch.roles(of: i, login: "alice", viewer: "v").isEmpty)
    }

    @Test func labels() {
        #expect(PersonMatch.label(for: [.author, .reviewed(.approved)], author: nil) == "approved")
        #expect(PersonMatch.label(for: [.reviewed(.changesRequested), .requested], author: nil) == "changes requested")
        #expect(PersonMatch.label(for: [.reviewed(.commented)], author: nil) == "reviewer")
        #expect(PersonMatch.label(for: [.reviewed(.dismissed)], author: nil) == "reviewer")
        #expect(PersonMatch.label(for: [.requested], author: nil) == "review requested")
        #expect(PersonMatch.label(for: [.assignee, .author], author: "alice") == "assigned")
        #expect(PersonMatch.label(for: [.author], author: "alice") == "by alice")
        #expect(PersonMatch.label(for: [.author], author: nil) == nil)
        #expect(PersonMatch.label(for: [], author: nil) == nil)
    }

    @Test func localPeopleAndWords() {
        let alices = pr(1, "Fix login", author: "alice")
        let reviewed = pr(2, "Fix login", author: "bob", reviews: [review("alice", .commented)])
        let carols = pr(3, "Fix login", author: "carol")
        let assigned = issue(4, "Login 500", assignees: ["alice"])
        let snap = snapshot(review: [alices, reviewed], team: [carols], issues: [assigned])
        let results = engine.local(SearchQuery.parse("@alice login"), in: snap)
        #expect(Set(results.openPRs.map(\.key.number)) == [1, 2])
        #expect(results.issues.map(\.key.number) == [4])
    }

    @Test func localTwoPeopleAnd() {
        let both = pr(1, author: "alice", reviews: [review("bob", .approved)])
        let onlyAlice = pr(2, author: "alice")
        let snap = snapshot(mine: [both, onlyAlice])
        let results = engine.local(SearchQuery.parse("@alice @bob"), in: snap)
        #expect(results.openPRs.map(\.key.number) == [1])
    }

    @Test func emptyMessages() {
        func message(_ raw: String) -> String? {
            let results = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
            return results.emptyMessage(org: "initech", query: SearchQuery.parse(raw), mode: .pullRequests)
        }
        #expect(message("@alice") == "No pull requests with @alice")
        #expect(message("@alice @bob") == "No pull requests with @alice and @bob")
        #expect(message("@a @b @c") == "No pull requests with @a, @b and @c")
        #expect(message("@alice login") == "No pull requests with @alice match “login”")
        #expect(message("@Alice @me") == "No pull requests with @Alice and @me")
    }

    @Test func peopleSearchLeavesCountsAlone() {
        var settings = AppSettings()
        settings.badge = .all
        let snap = snapshot(
            review: [pr(1, requests: [.user("me")])], mine: [pr(2, author: "me")],
            team: [pr(3, author: "alice")], issues: [issue(4, author: "alice")])
        func measure() -> (Int, [Int], [Int], [Int]) {
            let built = TabBuilder.build(snap, settings: settings, now: t0)
            let issues = IssueTabBuilder.build(snap, settings: settings, now: t0)
            return (
                Badge.count(prs: built, issues: issues, settings: settings),
                built.review.rows.map(\.pr.key.number), built.mine.rows.map(\.pr.key.number),
                built.team.rows.map(\.pr.key.number))
        }
        let before = measure()
        _ = engine.local(SearchQuery.parse("@alice"), in: snap)
        let after = measure()
        #expect(before == after)
    }
}
