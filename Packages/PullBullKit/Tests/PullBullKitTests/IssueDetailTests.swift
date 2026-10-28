import Foundation
import Testing
@testable import PullBullKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func response(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!, statusCode: status,
        httpVersion: nil, headerFields: [:])!
}

private final class StubTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Data, HTTPURLResponse)]
    private var sent: [Data] = []

    init(_ responses: [(Data, HTTPURLResponse)]) { queue = responses }

    var bodies: [String] {
        lock.withLock { sent.map { String(decoding: $0, as: UTF8.self) } }
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            sent.append(body)
            return queue.removeFirst()
        }
    }
}

private func api(_ transport: StubTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"))
}

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Suite struct IssueDetailTests {
    private let key = PRKey(repo: "initech/gadgets", number: 231)

    @Test func issueDetailParses() async throws {
        let stub = StubTransport([(try fixture("issue_detail"), response(200))])
        let d = try await api(stub).issueDetail(key)
        #expect(d.key == key)
        #expect(d.commentTotal == 5)
        #expect(d.lastComments.map(\.author) == ["dev-a", "devon"])
        #expect(d.earlierCommentCount == 3)
        #expect(d.linkedPRs.first?.key == PRKey(repo: "initech/gadgets", number: 412))
        #expect(d.linkedPRs.first?.ci == .pending)
        #expect(d.issue.labels == ["bug", "backend"])
        #expect(d.issue.title == "Example issue title")
        #expect(d.issue.author == "dev-b")
        #expect(d.issue.isOpen)
        #expect(d.issue.status == nil)
        #expect(d.issue.assignees.map(\.login) == ["devon", "dev-a"])
        #expect(d.body.hasPrefix("Example description."))
        // A null author is "ghost", a null rollup is no CI; null and incomplete nodes are skipped.
        #expect(d.linkedPRs.count == 2)
        let merged = try #require(d.linkedPRs.last)
        #expect(merged.key == PRKey(repo: "initech/widgets", number: 88))
        #expect(merged.state == .merged)
        #expect(merged.author == "ghost")
        #expect(merged.ci == CIState.none)
        #expect(merged.url == URL(string: "https://github.com/initech/widgets/pull/88"))
        // A draft linked PR keeps the draft glyph; a missing isDraft is not a draft.
        #expect(d.linkedPRs.first?.isDraft == true)
        #expect(d.linkedPRs.first?.glyph == .draft)
        #expect(!merged.isDraft)
        #expect(merged.glyph == .merged)

        let body = try #require(stub.bodies.first)
        #expect(body.contains("closedByPullRequestsReferences(first:5, includeClosedPrs:true)"))
        #expect(body.contains("number title url state isDraft author{login}"))
        #expect(body.contains("fragment issueRowFields on Issue"))
        // The fragment selects comments{totalCount}; an unaliased comments(last:2) is a field conflict.
        #expect(body.contains("lastComments: comments(last:2)"))
        #expect(body.contains("\"owner\":\"initech\""))
        #expect(body.contains("\"name\":\"gadgets\""))
        #expect(body.contains("\"n\":231"))
        #expect(!body.contains("mutation"))
    }

    @Test func cachedLinkedPRWithoutIsDraftDecodes() throws {
        let pr = LinkedPR(
            key: PRKey(repo: "o/r", number: 7), title: "t", url: URL(string: "https://github.com/o/r/pull/7")!,
            state: .open, author: "a", ci: .skipped, isDraft: true)
        let data = try JSONEncoder().encode(pr)
        #expect(try JSONDecoder().decode(LinkedPR.self, from: data) == pr)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["isDraft"] = nil
        let old = try JSONDecoder().decode(LinkedPR.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!old.isDraft)
        #expect(old.glyph == .open)
        #expect(old.ci == .skipped)
    }

    @Test func missingIssueThrows() async throws {
        let stub = StubTransport([(Data(#"{"data":{"repository":{"issue":null}}}"#.utf8), response(200))])
        await #expect(throws: APIError.graphQL("issue initech/gadgets#231 not found")) {
            try await api(stub).issueDetail(key)
        }
    }

    /// A PR or issue GitHub no longer resolves reads as not found; other failures don't.
    @Test func missingItemIsNotFound() async throws {
        let missing: [(Data, HTTPURLResponse)] = [
            (Data(#"{"data":{"repository":{"issue":null}}}"#.utf8), response(200)),
            (Data(#"{"data":{"repository":null},"errors":[{"type":"NOT_FOUND"}]}"#.utf8), response(200)),
            (Data("{}".utf8), response(502)),
        ]
        let stub = StubTransport(missing)
        do {
            _ = try await api(stub).issueDetail(key)
            Issue.record("expected a throw")
        } catch {
            #expect((error as? APIError)?.isNotFound == true)
        }
        do {
            _ = try await api(stub).detail(key)
            Issue.record("expected a throw")
        } catch {
            #expect((error as? APIError)?.isNotFound == true)
        }
        do {
            _ = try await api(stub).detail(key)
            Issue.record("expected a throw")
        } catch {
            #expect((error as? APIError)?.isNotFound == false)
        }
    }

    @Test func noCommentsMeansNoEarlierCount() {
        let issue = BoardIssue(key: key, title: "t", url: URL(string: "https://github.com/o/r/issues/1")!, isOpen: true)
        let d = IssueDetail(key: key, issue: issue, body: "", commentTotal: 0, lastComments: [], linkedPRs: [])
        #expect(d.earlierCommentCount == 0)
    }

    @Test func issueDetailRoundTripKeyedByAccount() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        let d = try await api(StubTransport([(try fixture("issue_detail"), response(200))])).issueDetail(key)
        #expect(await store.loadIssueDetail(key, account: "a") == nil)
        try await store.saveIssueDetail(d, account: "a")
        #expect(await store.loadIssueDetail(key, account: "a") == d)
        #expect(await store.loadIssueDetail(key, account: "b") == nil)
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("details/a/issues/initech_gadgets_231.json").path))
        // A PR detail with the same key is a different file, and neither reads as the other.
        #expect(await store.loadDetail(key, account: "a") == nil)
        let pr = PRDetail(key: key, body: "pr", checks: [], reviews: [], comments: [], files: [])
        try await store.saveDetail(pr, account: "a")
        #expect(await store.loadIssueDetail(key, account: "a") == d)
        #expect(await store.loadDetail(key, account: "a")?.body == "pr")
    }

    @Test func footerLinkFollowsTab() {
        #expect(GitHubLinks.footer(mode: .pullRequests, issueTab: .board, org: "o", board: .org("o", 3), boardTitle: "B").url
            == GitHubLinks.pulls)
        #expect(GitHubLinks.footer(mode: .pullRequests, issueTab: .board, org: "o", board: .org("o", 3), boardTitle: "B").title
            == "PRs on GitHub")
        #expect(GitHubLinks.footer(mode: .issues, issueTab: .assigned, org: "o", board: .org("o", 3), boardTitle: "B").title
            == "Assigned on GitHub")
        #expect(GitHubLinks.footer(mode: .issues, issueTab: .assigned, org: "o", board: .org("o", 3), boardTitle: "B").url
            == URL(string: "https://github.com/search?q=is%3Aissue%20is%3Aopen%20assignee%3A%40me%20org%3Ao&type=issues")!)
        #expect(GitHubLinks.footer(mode: .issues, issueTab: .created, org: "o", board: .org("o", 3), boardTitle: "B")
            == ("Created on GitHub",
                URL(string: "https://github.com/search?q=is%3Aissue%20is%3Aopen%20author%3A%40me%20org%3Ao&type=issues")!))
        #expect(GitHubLinks.footer(mode: .issues, issueTab: .board, org: "initech", board: .org("initech", 3), boardTitle: "Team Board")
            == ("Team Board", URL(string: "https://github.com/orgs/initech/projects/3")!))
    }

    @Test func footerLinkFollowsPRTab() {
        func link(_ tab: PRTab, org: String? = "initech") -> (title: String, url: URL) {
            GitHubLinks.footer(mode: .pullRequests, prTab: tab, issueTab: .assigned, org: org, board: nil, boardTitle: nil)
        }
        #expect(link(.review) == ("Review requests on GitHub", URL(string: "https://github.com/pulls/review-requested")!))
        #expect(link(.mine) == ("PRs on GitHub", GitHubLinks.pulls))
        #expect(link(.team) == ("initech PRs on GitHub",
                                URL(string: "https://github.com/pulls?q=is%3Apr%20is%3Aopen%20org%3Ainitech")!))
        // Personal scope: Review and Mine are the same pages; Team isn't shown, and falls back to Mine's.
        #expect(link(.review, org: nil).url == URL(string: "https://github.com/pulls/review-requested")!)
        #expect(link(.mine, org: nil).url == GitHubLinks.pulls)
        #expect(link(.team, org: nil) == ("PRs on GitHub", GitHubLinks.pulls))
    }

    @Test func personalIssuesFooterKeepsTheDashboardPages() {
        #expect(GitHubLinks.footer(mode: .issues, issueTab: .assigned, org: nil, board: nil, boardTitle: nil)
            == ("Assigned on GitHub", GitHubLinks.issuesAssigned))
        #expect(GitHubLinks.footer(mode: .issues, issueTab: .created, org: nil, board: nil, boardTitle: nil)
            == ("Issues on GitHub", GitHubLinks.issues))
    }

    @Test func footerFocusWinsOverEveryTab() {
        let focus = RepoFocus(repo: "o/widgets")
        for tab in PRTab.allCases {
            let link = GitHubLinks.footer(
                mode: .pullRequests, prTab: tab, issueTab: .board, org: "o", board: nil, boardTitle: nil, focus: focus)
            #expect(link == ("widgets PRs", URL(string: "https://github.com/o/widgets/pulls")!))
        }
        for tab in [IssueTab.assigned, .created] {
            let link = GitHubLinks.footer(
                mode: .issues, issueTab: tab, org: "o", board: nil, boardTitle: nil, focus: focus)
            #expect(link == ("widgets issues", URL(string: "https://github.com/o/widgets/issues")!))
        }
    }

    @Test func searchLinksEncodeTheQuery() {
        // Spaces, `:`, `@`, quotes, `<`, `>`, `/` and `+` (GitHub reads a raw one as a space) are escaped,
        // non-ASCII as its UTF-8 bytes; `-._~` stay as they are.
        #expect(GitHubLinks.searching(GitHubLinks.pulls, for: "is:pr label:\"a+b\" <x> o/r-1._~").absoluteString
            == "https://github.com/pulls?q=is%3Apr%20label%3A%22a%2Bb%22%20%3Cx%3E%20o%2Fr-1._~")
        #expect(GitHubLinks.issueSearch("label:café @me").absoluteString
            == "https://github.com/search?q=label%3Acaf%C3%A9%20%40me&type=issues")
    }

    @Test func footerLinkFollowsFocus() {
        let focus = RepoFocus(repo: "o/widgets")
        let pulls = GitHubLinks.footer(
            mode: .pullRequests, issueTab: .assigned, org: "o", board: .org("o", 3), boardTitle: "B", focus: focus)
        #expect(pulls.url == URL(string: "https://github.com/o/widgets/pulls")!)
        #expect(pulls.title == "widgets PRs")
        for tab in [IssueTab.assigned, .created] {
            let issues = GitHubLinks.footer(
                mode: .issues, issueTab: tab, org: "o", board: .org("o", 3), boardTitle: "B", focus: focus)
            #expect(issues.url == URL(string: "https://github.com/o/widgets/issues")!)
            #expect(issues.title == "widgets issues")
        }
        let board = GitHubLinks.footer(
            mode: .issues, issueTab: .board, org: "o", board: .org("o", 3), boardTitle: "B", focus: focus)
        #expect(board.url == URL(string: "https://github.com/orgs/o/projects/3")!)
        #expect(board.title == "B")
        #expect(GitHubLinks.footer(
            mode: .pullRequests, issueTab: .board, org: "o", board: .org("o", 3), boardTitle: "B", focus: nil)
            == ("PRs on GitHub", GitHubLinks.pulls))
    }

    @Test func footerNamesAmbiguousFocusWithOwner() {
        let choices = [
            RepoChoice(repo: "o/lib", reviewCount: 0, openCount: 1),
            RepoChoice(repo: "x/lib", reviewCount: 0, openCount: 1),
        ]
        let pulls = GitHubLinks.footer(
            mode: .pullRequests, issueTab: .assigned, org: "o", board: nil, boardTitle: nil,
            focus: RepoFocus(repo: "x/lib"), choices: choices)
        #expect(pulls.title == "x/lib PRs")
        let issues = GitHubLinks.footer(
            mode: .issues, issueTab: .created, org: "o", board: nil, boardTitle: nil,
            focus: RepoFocus(repo: "o/lib"), choices: choices)
        #expect(issues.title == "o/lib issues")
    }

    @Test func boardFooterWithoutBoardFallsBackToIssues() {
        let noNumber = GitHubLinks.footer(mode: .issues, issueTab: .board, org: "o", board: nil, boardTitle: "B")
        #expect(noNumber.url == GitHubLinks.issues)
        #expect(noNumber.title == "Issues on GitHub")
        // No-org mode links to the user's own board.
        let personal = GitHubLinks.footer(mode: .issues, issueTab: .board, org: nil, board: .user("me", 3), boardTitle: "B")
        #expect(personal == ("B", URL(string: "https://github.com/users/me/projects/3")!))
        // A board without a known title (it can't be read) still links to the board, under a short name.
        for title in [nil, " "] as [String?] {
            let untitled = GitHubLinks.footer(mode: .issues, issueTab: .board, org: "o", board: .org("o", 3), boardTitle: title)
            #expect(untitled.url == URL(string: "https://github.com/orgs/o/projects/3"))
            #expect(untitled.title == GitHubLinks.boardShortTitle)
            #expect(untitled.title == "Board")
        }
    }

    @Test func boardItemLink() {
        #expect(GitHubLinks.boardItem(.org("initech", 3), itemId: 1001)
            == URL(string: "https://github.com/orgs/initech/projects/3?pane=issue&itemId=1001"))
        #expect(GitHubLinks.boardItem(.org("initech", 3), itemId: nil)
            == URL(string: "https://github.com/orgs/initech/projects/3"))
        #expect(GitHubLinks.board(.org("initech", 3)).absoluteString
            == "https://github.com/orgs/initech/projects/3")
    }

    @Test func personalBoardLinksUseTheUsersPath() {
        #expect(GitHubLinks.board(.user("rustycamper", 3)).absoluteString
            == "https://github.com/users/rustycamper/projects/3")
        #expect(GitHubLinks.boardItem(.user("rustycamper", 3), itemId: 284822570)
            == URL(string: "https://github.com/users/rustycamper/projects/3?pane=issue&itemId=284822570"))
    }
}
