import Foundation
import Testing
@testable import PullBullKit

private struct ScriptedTransport: GraphQLTransport {
    let handler: @Sendable () throws -> Data
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let data = try handler()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

/// Records every request. Issue searches (bodies containing `is:issue`) get `issueReply`, or fail
/// with `failIssues`; every other request gets `reply`.
private final class RecordingTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    private let reply: String
    private let issueReply: String
    private let failIssues: Bool
    init(reply: String, issueReply: String = searchResponse([]), failIssues: Bool = false) {
        self.reply = reply
        self.issueReply = issueReply
        self.failIssues = failIssues
    }
    var bodies: [String] { lock.withLock { sent } }
    var prBodies: [String] { bodies.filter { $0.contains("is:pr") } }
    var issueBodies: [String] { bodies.filter { $0.contains("is:issue") } }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let text = String(decoding: body, as: UTF8.self)
        lock.withLock { sent.append(text) }
        let isIssueSearch = text.contains("is:issue")
        if isIssueSearch && failIssues { throw APIError.network("offline") }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!
        return (Data((isIssueSearch ? issueReply : reply).utf8), response)
    }
}

/// Fails every PR search; issue searches get `issueReply`.
private struct FailingPRTransport: GraphQLTransport {
    var issueReply = searchResponse([])
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        guard String(decoding: body, as: UTF8.self).contains("is:issue") else { throw APIError.network("offline") }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!
        return (Data(issueReply.utf8), response)
    }
}

private final class SuspendingTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var started = false
    var observedCancellation: Bool { lock.withLock { cancelled } }
    var didStart: Bool { lock.withLock { started } }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { started = true }
        do { try await Task.sleep(for: .seconds(10)) } catch {
            lock.withLock { cancelled = true }
            throw error
        }
        throw APIError.network("unreachable")
    }
}

private func engine(_ handler: @escaping @Sendable () throws -> Data) -> SearchEngine {
    SearchEngine(api: GitHubAPI(transport: ScriptedTransport(handler: handler), auth: StaticTokenSource("test-token")))
}

private func json(_ text: String) -> @Sendable () throws -> Data { { Data(text.utf8) } }

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let repo = "initech/gadgets"

private func pr(
    _ number: Int, _ title: String = "PR", state: PRState = .open,
    updated: TimeInterval = 0, closed: TimeInterval? = nil, in repoName: String = repo
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repoName, number: number), title: title,
        url: URL(string: "https://github.com/\(repoName)/pull/\(number)")!, author: "alice",
        authorAvatarURL: nil, state: state, isDraft: false, createdAt: t0,
        updatedAt: t0.addingTimeInterval(updated), closedAt: closed.map { t0.addingTimeInterval($0) },
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

private func issue(
    _ number: Int, _ title: String = "Issue", open: Bool = true, updated: TimeInterval? = nil,
    status: String? = nil, in repoName: String = repo
) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repoName, number: number), title: title,
        url: URL(string: "https://github.com/\(repoName)/issues/\(number)")!, isOpen: open,
        updatedAt: updated.map { t0.addingTimeInterval($0) },
        status: status.map { BoardStatusValue(optionId: "opt-\($0)", name: $0) })
}

/// The board's Status options, matching `issue(status:)`'s option ids.
private let statusOptions = ["Todo", "In progress"].map { StatusOption(id: "opt-\($0)", name: $0) }

private func snapshot(
    review: [PullRequest] = [], mine: [PullRequest] = [], team: [PullRequest] = [],
    closed: [PullRequest] = [], issues: [BoardIssue] = [], assigned: [BoardIssue]? = nil,
    created: [BoardIssue]? = nil, boardProject: Int? = 3, boardError: String? = nil
) -> Snapshot {
    Snapshot(
        fetchedAt: t0,
        org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
        reviewCandidates: review, mine: mine, team: team, recentlyClosed: closed, boardIssues: issues,
        boardProject: boardProject, boardTitle: boardProject == nil ? nil : "Team Board", boardError: boardError,
        assignedIssues: assigned, createdIssues: created, boardStatusOptions: boardProject == nil ? nil : statusOptions)
}

/// An engine whose PR searches get `reply` and whose issue searches get an empty page.
private func prSearchEngine(_ reply: String) -> SearchEngine {
    SearchEngine(api: GitHubAPI(transport: RecordingTransport(reply: reply), auth: StaticTokenSource("test-token")))
}

private func issueLookup(_ number: Int, title: String) -> String {
    let fields = issueFields(number, title: title, state: "OPEN", updated: "2026-10-25T10:00:00Z")
    return #"{"data":{"r0":{"issueOrPullRequest":{"__typename":"Issue","# + fields + "}}}}"
}

/// An issue node's fields, without braces.
private func issueFields(_ number: Int, title: String, state: String, updated: String) -> String {
    """
    "number":\(number),"title":"\(title)","url":"https://github.com/\(repo)/issues/\(number)",\
    "state":"\(state)","updatedAt":"\(updated)","repository":{"nameWithOwner":"\(repo)"}
    """
}

private func issueNode(_ number: Int, title: String, state: String = "OPEN", updated: String) -> String {
    "{\(issueFields(number, title: title, state: state, updated: updated))}"
}

private func prNode(_ number: Int, title: String, state: String, updated: String, closedAt: String?) -> String {
    let closed = closedAt.map { "\"\($0)\"" } ?? "null"
    return """
    {"__typename":"PullRequest","number":\(number),"title":"\(title)","url":"https://github.com/\(repo)/pull/\(number)",\
    "isDraft":false,"state":"\(state)","createdAt":"2026-10-20T09:00:00Z","updatedAt":"\(updated)","closedAt":\(closed),\
    "headRefName":"a","baseRefName":"main","repository":{"nameWithOwner":"\(repo)"},\
    "author":{"login":"alice","avatarUrl":null},"comments":{"totalCount":0,"nodes":[]},\
    "commits":{"nodes":[]},"latestReviews":{"nodes":[]},"reviewRequests":{"nodes":[]}}
    """
}

private func searchResponse(_ nodes: [String]) -> String {
    """
    {"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":false},"nodes":[\(nodes.joined(separator: ","))]}}}
    """
}

private func collect(_ stream: AsyncStream<SearchResults>) async -> [SearchResults] {
    var all: [SearchResults] = []
    for await value in stream { all.append(value) }
    return all
}

@Suite struct SearchEngineTests {
    /// An `updated:`-only query is not skipped by the empty-token guard.
    @Test func updatedAloneAsksGitHub() async {
        let transport = RecordingTransport(reply: searchResponse([]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        _ = await collect(e.results(.parse("updated:3d"), snap: snapshot()))
        #expect(transport.prBodies.contains { $0.contains("updated:>=") })
    }

    /// GitHub decides a raw `updated:` value, so the rows it returns are kept.
    @Test func rawUpdatedKeepsGitHubsRows() async throws {
        let node = prNode(9, title: "Pool", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
        let transport = RecordingTransport(reply: searchResponse([node]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let done = try #require(await collect(e.results(.parse("updated:>2026-10-01"), snap: snapshot())).last)
        #expect(transport.prBodies.contains { $0.contains("updated:>2026-10-01") })
        #expect(done.openPRs.map(\.key.number) == [9])
    }

    /// No org: title searches cover the user's repositories, and a number is looked up in the repos they own.
    @Test func personalScopeSearchesTheUsersRepos() async {
        var snap = snapshot()
        snap.org = .personal(login: "me", repos: ["dotfiles"], reposComplete: true)
        let transport = RecordingTransport(reply: searchResponse([]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        _ = await collect(e.results(.text(["pool"]), snap: snap))
        #expect(transport.prBodies.contains { $0.contains(#"user:me is:pr in:title \"pool\" sort:updated-desc"#) })
        #expect(transport.issueBodies.contains { $0.contains(#"user:me is:issue in:title \"pool\" sort:updated-desc"#) })
        #expect(!transport.bodies.contains { $0.contains("org:") })

        let lookup = RecordingTransport(reply: #"{"data":{}}"#)
        let numbers = SearchEngine(api: GitHubAPI(transport: lookup, auth: StaticTokenSource("test-token")))
        _ = await collect(numbers.results(.number(231), snap: snap))
        let body = try! #require(lookup.bodies.first)
        #expect(body.contains(#""org":"me""#))
        #expect(body.contains(#"name:\"dotfiles\""#))
    }

    // MARK: Repo focus

    private static let ui = RepoFocus(repo: "initech/widgets")

    @Test func focusedRemoteQueryUsesRepoQualifier() {
        let query = SearchEngine.remoteQuery(
            kind: "pr", scope: .org("initech"), focus: Self.ui, logins: ["me"], labels: [], words: ["fix"])
        #expect(query == #"repo:initech/widgets is:pr involves:@me in:title "fix" sort:updated-desc"#)
        let personal = SearchEngine.remoteQuery(
            kind: "issue", scope: .personal(login: "me"), focus: RepoFocus(repo: "me/dotfiles"), logins: [],
            labels: [], words: ["pool"])
        #expect(personal == #"repo:me/dotfiles is:issue in:title "pool" sort:updated-desc"#)
    }

    @Test func focusedSearchesAskGitHubForTheRepoOnly() async {
        let transport = RecordingTransport(reply: searchResponse([]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        _ = await collect(e.results(.parse("~bug pool"), snap: snapshot(), focus: Self.ui))
        // JSON escapes the slash.
        let unescaped = { (bodies: [String]) in bodies.map { $0.replacingOccurrences(of: "\\/", with: "/") } }
        #expect(unescaped(transport.prBodies).contains { $0.contains("repo:initech/widgets is:pr label:") })
        #expect(unescaped(transport.issueBodies).contains { $0.contains("repo:initech/widgets is:issue label:") })
        #expect(!transport.bodies.contains { $0.contains("org:") })
    }

    /// `#123` asks only the focused repository, under its own owner.
    @Test func focusedNumberLookupQueriesOnlyThatRepo() async {
        let lookup = RecordingTransport(reply: #"{"data":{}}"#)
        let e = SearchEngine(api: GitHubAPI(transport: lookup, auth: StaticTokenSource("test-token")))
        _ = await collect(e.results(.number(231), snap: snapshot(), focus: Self.ui))
        let body = try! #require(lookup.bodies.first)
        #expect(body.contains(#""org":"initech""#))
        #expect(body.contains(#"name:\"widgets\""#))
        #expect(!body.contains(#"name:\"gadgets\""#))
        #expect(!body.contains("r1:"))

        let elsewhere = RecordingTransport(reply: #"{"data":{}}"#)
        let other = SearchEngine(api: GitHubAPI(transport: elsewhere, auth: StaticTokenSource("test-token")))
        _ = await collect(other.results(.number(5), snap: snapshot(), focus: RepoFocus(repo: "someone/else")))
        let otherBody = try! #require(elsewhere.bodies.first)
        #expect(otherBody.contains(#""org":"someone""#))
        #expect(otherBody.contains(#"name:\"else\""#))
    }

    @Test func focusedLocalMatchesKeepToTheRepo() {
        let snap = snapshot(
            mine: [pr(1, "pool fix"), pr(2, "pool fix", in: "initech/widgets")],
            issues: [issue(3, "pool leak"), issue(4, "pool leak", in: "initech/widgets")])
        let e = engine(json(searchResponse([])))
        let focused = e.local(.text(["pool"]), in: snap, focus: Self.ui)
        #expect(focused.openPRs.map(\.key.number) == [2])
        #expect(focused.issues.map(\.key.number) == [4])
        let all = e.local(.text(["pool"]), in: snap)
        #expect(all.openPRs.map(\.key.number).sorted() == [1, 2])
        #expect(all.issues.map(\.key.number).sorted() == [3, 4])
    }

    /// GitHub's rows outside the focus (a stale or odd answer) are dropped too.
    @Test func focusedRemoteRowsKeepToTheRepo() async {
        let outside = prNode(7, title: "Pool", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
        let done = try! #require(await collect(prSearchEngine(searchResponse([outside]))
            .results(.text(["pool"]), snap: snapshot(), focus: Self.ui)).last)
        #expect(done.openPRs.isEmpty)
    }

    // MARK: Pasted links

    private static let link = SearchQuery.parse("https://github.com/initech/gadgets/pull/231/files")

    private static func lookupReply(_ number: Int) -> String {
        """
        {"data":{"r0":{"issueOrPullRequest":\(prNode(
            number, title: "Far away", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil))}}}
        """
    }

    /// A link asks only its own repository, under its owner, whatever the focus.
    @Test func linkLooksUpItsRepoIgnoringTheFocus() async {
        let transport = RecordingTransport(reply: Self.lookupReply(231))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let done = try! #require(await collect(e.results(Self.link, snap: snapshot(), focus: Self.ui)).last)
        #expect(done.openPRs.map(\.key) == [PRKey(repo: repo, number: 231)])
        #expect(done.phase == .done)
        #expect(transport.bodies.count == 1)
        let body = try! #require(transport.bodies.first)
        #expect(body.contains(#""org":"initech""#))
        #expect(body.contains(#"name:\"gadgets\""#))
        #expect(!body.contains(#"name:\"widgets\""#))
        #expect(!body.contains("r1:"))
    }

    @Test func linkMatchesLocallyByRepoAndNumber() {
        let snap = snapshot(
            mine: [pr(231), pr(231, in: "initech/widgets")],
            issues: [issue(5), issue(5, in: "initech/widgets")])
        let e = engine(json("{}"))
        let found = e.local(Self.link, in: snap, focus: Self.ui)
        #expect(found.openPRs.map(\.key) == [PRKey(repo: repo, number: 231)])
        #expect(found.issues.isEmpty)
        let shorthand = e.local(.parse("INITECH/Widgets#5"), in: snap)
        #expect(shorthand.issues.map(\.key) == [PRKey(repo: "initech/widgets", number: 5)])
        #expect(shorthand.openPRs.isEmpty)
    }

    /// GitHub's row for another number (an odd answer) is dropped.
    @Test func linkKeepsOnlyThatItemFromGitHub() async {
        let e = engine(json(Self.lookupReply(232)))
        let done = try! #require(await collect(e.results(Self.link, snap: snapshot())).last)
        #expect(done.isEmpty)
        #expect(done.emptyMessage(org: "initech", query: Self.link, scope: .org("initech"), mode: .pullRequests)
            == "No PR #231 in initech/gadgets")
    }

    /// A link outside the scope asks GitHub nothing and says why it found nothing.
    @Test func linkOutsideTheScopeIsNotLookedUp() async {
        let q = SearchQuery.parse("https://github.com/someone/else/issues/9")
        let results = await collect(engine { throw APIError.network("must not be called") }
            .results(q, snap: snapshot()))
        let done = try! #require(results.last)
        #expect(done.phase == .done)
        #expect(done.emptyMessage(org: "initech", query: q, scope: .org("initech"), mode: .pullRequests)
            == "PullBull searches initech only, not someone/else")
        #expect(done.emptyMessage(org: "your repos", query: q, scope: .personal(login: "me"), mode: .pullRequests)
            == "PullBull searches your repos only, not someone/else")
        #expect(done.emptyMessage(org: "initech", query: q, mode: .pullRequests) == "No PR #9 in someone/else")
    }

    @Test func parseNumberForms() {
        #expect(SearchQuery.parse("412") == .number(412))
        #expect(SearchQuery.parse("#412") == .number(412))
        #expect(SearchQuery.parse(" #412 ") == .number(412))
        #expect(SearchQuery.parse("412 fix") == .text(["412", "fix"]))
        #expect(SearchQuery.parse("") == .empty)
        #expect(SearchQuery.parse("   ") == .empty)
        #expect(SearchQuery.parse("Fix  Bug") == .text(["fix", "bug"]))
    }

    @Test func parseEdgeCases() {
        #expect(SearchQuery.parse("#") == .empty)
        #expect(SearchQuery.parse("#   ") == .empty)
        #expect(SearchQuery.parse("0") == .number(0))
        #expect(SearchQuery.parse("007") == .number(7))
        #expect(SearchQuery.parse("-5") == .text(["-5"]))
        #expect(SearchQuery.parse("99999999999999999999") == .text(["99999999999999999999"]))
    }

    /// An installation limited to selected repos: remote matches elsewhere are dropped, and a number is
    /// looked up only in the selected repos.
    @Test func personalSelectionLimitsRemoteResults() async {
        var snap = snapshot()
        snap.org = .personal(login: "initech", repos: ["gadgets", "other"], reposComplete: true)
        snap = snap.limited(to: .personal(login: "initech", repos: ["initech/gadgets"]))
        let outside = prNode(7, title: "Pool", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
            .replacingOccurrences(of: repo, with: "someone/else")
        let inside = prNode(8, title: "Pool", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
        let transport = RecordingTransport(reply: searchResponse([outside, inside]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let done = try! #require(await collect(e.results(.text(["pool"]), snap: snap)).last)
        #expect(done.openPRs.map(\.key.number) == [8])
        #expect(transport.prBodies.contains { $0.contains("user:initech is:pr") })

        let lookup = RecordingTransport(reply: #"{"data":{}}"#)
        let numbers = SearchEngine(api: GitHubAPI(transport: lookup, auth: StaticTokenSource("test-token")))
        _ = await collect(numbers.results(.number(231), snap: snap))
        let body = try! #require(lookup.bodies.first)
        #expect(body.contains(#"name:\"gadgets\""#))
        #expect(!body.contains(#"name:\"other\""#))
    }

    @Test func remoteTextQuotesEveryWord() async {
        let transport = RecordingTransport(reply: searchResponse([]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let q = SearchQuery.parse("feat: fix(api) lab:x -foo \"bar")
        _ = await collect(e.results(q, snap: snapshot()))
        let body = try! #require(transport.prBodies.first)
        #expect(body.contains(#"org:initech is:pr in:title \"feat:\" \"fix(api)\" \"lab:x\" \"-foo\" \"bar\""#))
        let issueBody = try! #require(transport.issueBodies.first)
        #expect(issueBody.contains(
            #"org:initech is:issue in:title \"feat:\" \"fix(api)\" \"lab:x\" \"-foo\" \"bar\" sort:updated-desc"#))
    }

    private func authored(_ node: String, by login: String) -> String {
        node.replacingOccurrences(of: #""author":{"login":"alice""#, with: #""author":{"login":"\#(login)""#)
    }

    @Test func remotePeopleQueryString() async {
        func bodies(_ raw: String) async -> (pr: String, issue: String) {
            let transport = RecordingTransport(reply: searchResponse([]))
            let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
            _ = await collect(e.results(SearchQuery.parse(raw), snap: snapshot()))
            return (transport.prBodies.first ?? "", transport.issueBodies.first ?? "")
        }
        let words = await bodies("@alice login")
        #expect(words.pr.contains(#"org:initech is:pr involves:alice in:title \"login\" sort:updated-desc"#))
        #expect(words.issue.contains(#"org:initech is:issue involves:alice in:title \"login\" sort:updated-desc"#))
        let alone = await bodies("@alice")
        #expect(alone.pr.contains(#"org:initech is:pr involves:alice sort:updated-desc"#))
        #expect(!alone.pr.contains("in:title"))
        #expect(alone.issue.contains(#"org:initech is:issue involves:alice sort:updated-desc"#))
        let me = await bodies("@me")
        #expect(me.pr.contains(#"org:initech is:pr involves:@me sort:updated-desc"#))
        let two = await bodies("@a @b")
        #expect(two.pr.contains("involves:a "))
        #expect(!two.pr.contains("involves:b"))
    }

    /// No org: `@` searches the user's repos with `user:`, never `org:`.
    @Test func personalPeopleQueryString() async {
        var snap = snapshot()
        snap.org = .personal(login: "me", repos: ["dotfiles"], reposComplete: true)
        let transport = RecordingTransport(reply: searchResponse([]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        _ = await collect(e.results(SearchQuery.parse("@alice login"), snap: snap))
        #expect(transport.prBodies.contains {
            $0.contains(#"user:me is:pr involves:alice in:title \"login\" sort:updated-desc"#)
        })
        #expect(transport.issueBodies.contains {
            $0.contains(#"user:me is:issue involves:alice in:title \"login\" sort:updated-desc"#)
        })
        #expect(!transport.bodies.contains { $0.contains("org:") })
    }

    /// An installation limited to selected repos: `@` matches elsewhere are dropped, PRs and issues alike.
    @Test func personalSelectionLimitsRemotePeopleResults() async {
        var snap = snapshot()
        snap.org = .personal(login: "initech", repos: ["gadgets", "other"], reposComplete: true)
        snap = snap.limited(to: .personal(login: "initech", repos: ["initech/gadgets"]))
        let outside = prNode(7, title: "Pool", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
            .replacingOccurrences(of: repo, with: "someone/else")
        let inside = prNode(8, title: "Pool", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
        func authoredIssue(_ number: Int, in repoName: String) -> String {
            issueNode(number, title: "Pool", updated: "2026-10-25T10:00:00Z")
                .replacingOccurrences(of: repo, with: repoName)
                .replacingOccurrences(of: "}}", with: #"},"author":{"login":"alice"}}"#)
        }
        let transport = RecordingTransport(
            reply: searchResponse([outside, inside]),
            issueReply: searchResponse([authoredIssue(17, in: "someone/else"), authoredIssue(18, in: repo)]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let q = SearchQuery.filtered(logins: ["alice"], labels: [], words: [])
        let done = try! #require(await collect(e.results(q, snap: snap)).last)
        #expect(done.phase == .done)
        #expect(done.openPRs.map(\.key.number) == [8])
        #expect(done.issues.map(\.key.number) == [18])
        #expect(transport.prBodies.contains { $0.contains("user:initech is:pr involves:alice") })
    }

    @Test func remoteRecheckDropsInvisibleMatches() async {
        let body = searchResponse([
            prNode(1, title: "one", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
            authored(prNode(2, title: "two", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil), by: "carol"),
        ])
        let results = await collect(prSearchEngine(body).results(.filtered(logins: ["alice"], labels: [], words: []), snap: snapshot()))
        #expect(results.last?.phase == .done)
        #expect(results.last?.openPRs.map(\.key.number) == [1])
    }

    @Test func remoteRecheckIgnoresCase() async {
        let body = searchResponse([
            authored(prNode(1, title: "one", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil), by: "Alice")
        ])
        let results = await collect(prSearchEngine(body).results(.filtered(logins: ["alice"], labels: [], words: []), snap: snapshot()))
        #expect(results.last?.openPRs.map(\.key.number) == [1])
    }

    @Test func remoteAndAcrossPeople() async {
        let body = searchResponse([
            prNode(1, title: "one", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
        ])
        let results = await collect(
            prSearchEngine(body).results(.filtered(logins: ["alice", "bob"], labels: [], words: []), snap: snapshot()))
        #expect(results.last?.openPRs.isEmpty == true)
    }

    @Test func localBotItemsSurviveEmptyRemote() async {
        let base = pr(5, "bump deps")
        let bot = PullRequest(
            key: base.key, title: base.title, url: base.url, author: "dependabot", authorAvatarURL: nil,
            state: .open, isDraft: false, createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "a",
            baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: [], reviewRequests: [])
        let results = await collect(
            prSearchEngine(searchResponse([])).results(
                .filtered(logins: ["dependabot"], labels: [], words: []), snap: snapshot(team: [bot])))
        #expect(results.last?.phase == .done)
        #expect(results.last?.openPRs.map(\.key.number) == [5])
    }

    @Test func unknownUserReadsAsNoMatch() async throws {
        let url = try #require(Bundle.module.url(forResource: "search_unknown_user", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try String(contentsOf: url, encoding: .utf8)
        let transport = RecordingTransport(reply: fixture, issueReply: fixture)
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
        let q = SearchQuery.filtered(logins: ["alicee"], labels: [], words: [])
        let done = try #require(await collect(e.results(q, snap: snapshot())).last)
        #expect(done.phase == .done)
        #expect(done.isEmpty)
        #expect(done.emptyMessage(org: "initech", query: q, mode: .pullRequests) == "No pull requests with @alicee")
    }

    @Test func outOfRangeNumbersSkipNetwork() async {
        let failing = engine { throw APIError.network("must not be called") }
        for n in [0, -1, 3_000_000_000, Int(Int32.max) + 1] {
            let results = await collect(failing.results(.number(n), snap: snapshot()))
            #expect(results.last?.phase == .done)
            #expect(results.last?.isEmpty == true)
        }
    }

    @Test func remoteTextDropsNonMatchingResults() async {
        let body = searchResponse([
            prNode(20, title: "webhook retry", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
            prNode(21, title: "webhook only", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
        ])
        let results = await collect(prSearchEngine(body).results(.text(["webhook", "retry"]), snap: snapshot()))
        #expect(results.last?.openPRs.map(\.key.number) == [20])
        #expect(results.last?.issues.isEmpty == true)
    }

    @Test func consumerCancellationReachesTransport() async throws {
        let transport = SuspendingTransport()
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let consumer = Task { await collect(e.results(.number(5), snap: snapshot())) }
        while !transport.didStart { try await Task.sleep(for: .milliseconds(5)) }
        consumer.cancel()
        _ = await consumer.value
        for _ in 0..<200 where !transport.observedCancellation { try await Task.sleep(for: .milliseconds(10)) }
        #expect(transport.observedCancellation)
    }

    @Test func localNumberExact() {
        let snap = snapshot(
            mine: [pr(412), pr(4120), pr(1412)], closed: [pr(412 + 1000, state: .merged, closed: 1)],
            issues: [issue(412), issue(41)])
        let r = engine(json("{}")).local(.number(412), in: snap)
        #expect(r.openPRs.map(\.key.number) == [412])
        #expect(r.closedPRs.isEmpty)
        #expect(r.issues.map(\.key.number) == [412])
        #expect(r.phase == .searching)
    }

    @Test func textAnyOrderCaseInsensitive() {
        let snap = snapshot(
            review: [pr(1, "Add webhook retry backoff")], mine: [pr(2, "Unrelated")],
            issues: [issue(3, "Webhook backoff bug")])
        let r = engine(json("{}")).local(SearchQuery.parse("Backoff webhook"), in: snap)
        #expect(r.openPRs.map(\.key.number) == [1])
        #expect(r.issues.map(\.key.number) == [3])
    }

    @Test func localOrderingAndDedupe() {
        let snap = snapshot(
            review: [pr(1, "x", updated: 10)], mine: [pr(2, "x", updated: 20), pr(1, "x", updated: 10)],
            team: [pr(3, "x", updated: 15)],
            closed: [pr(4, "x", state: .merged, closed: 5), pr(5, "x", state: .closed, closed: 9)],
            issues: [issue(6, "x", open: false), issue(7, "x", open: true)])
        let r = engine(json("{}")).local(.text(["x"]), in: snap)
        #expect(r.openPRs.map(\.key.number) == [2, 3, 1])
        #expect(r.closedPRs.map(\.key.number) == [5, 4])
        #expect(r.issues.map(\.key.number) == [7, 6])
    }

    @Test func remoteMergesWithoutDuplicates() async {
        let local = pr(10, "Add webhook retry", updated: 0)
        let snap = snapshot(mine: [local])
        let body = searchResponse([
            prNode(10, title: "Add webhook retry REMOTE", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
            prNode(11, title: "Old webhook fix", state: "MERGED", updated: "2026-09-01T10:00:00Z",
                   closedAt: "2026-09-01T10:00:00Z"),
        ])
        let results = await collect(prSearchEngine(body).results(SearchQuery.parse("webhook"), snap: snap))
        #expect(results.first?.phase == .searching)
        #expect(results.first?.openPRs.map(\.title) == ["Add webhook retry"])
        let last = try! #require(results.last)
        #expect(last.phase == .done)
        #expect(last.openPRs.map(\.key.number) == [10])
        #expect(last.openPRs.first?.title == "Add webhook retry REMOTE")
        #expect(last.closedPRs.map(\.key.number) == [11])
        #expect(last.issues.isEmpty)
    }

    @Test func remoteFailureIsExplicit() async {
        let snap = snapshot(mine: [pr(10, "webhook")])
        let failing = engine { throw APIError.network("offline") }
        let results = await collect(failing.results(.text(["webhook"]), snap: snap))
        let last = try! #require(results.last)
        #expect(last.phase == .failedRemote("Couldn't reach GitHub, showing local results only"))
        #expect(last.openPRs.map(\.key.number) == [10])
    }

    @Test func nonNetworkAPIErrorAlsoFailsRemote() async {
        let failing = engine { throw APIError.unauthorized }
        let results = await collect(failing.results(.number(1), snap: snapshot(mine: [pr(1)])))
        #expect(results.last?.phase == .failedRemote("Couldn't reach GitHub, showing local results only"))
        #expect(results.last?.openPRs.map(\.key.number) == [1])
    }

    @Test func emptyMessageOnlyWhenDone() {
        let searching = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .searching)
        #expect(searching.emptyMessage(org: "initech", query: .number(9999), mode: .pullRequests) == nil)
        let failed = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .failedRemote("x"))
        #expect(failed.emptyMessage(org: "initech", query: .number(9999), mode: .pullRequests) == nil)
        let done = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(done.emptyMessage(org: "initech", query: .number(9999), mode: .pullRequests) == "No PR #9999 in initech")
        #expect(done.emptyMessage(org: "initech", query: .text(["foo"]), mode: .pullRequests) == "No pull requests match “foo”")
        #expect(done.emptyMessage(org: "initech", query: .text(["foo", "bar"]), mode: .pullRequests) == "No pull requests match “foo bar”")
        #expect(done.emptyMessage(org: "initech", query: .empty, mode: .pullRequests) == nil)
        let nonEmpty = SearchResults(openPRs: [pr(1)], closedPRs: [], issues: [], phase: .done)
        #expect(nonEmpty.emptyMessage(org: "initech", query: .number(1), mode: .pullRequests) == nil)
    }

    @Test func emptyQueryMakesNoRemoteCall() async {
        let results = await collect(engine { throw APIError.network("must not be called") }
            .results(.empty, snap: snapshot(mine: [pr(1)])))
        #expect(results.count == 1)
        #expect(results[0].phase == .done)
        #expect(results[0].isEmpty)
        #expect(results[0].emptyMessage(org: "initech", query: .empty, mode: .pullRequests) == nil)
    }

    @Test func remoteNumberLookupAddsPR() async {
        let lookupBody = """
        {"data":{"r0":{"issueOrPullRequest":\(prNode(
            9999, title: "Far away", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil))}}}
        """
        let results = await collect(engine(json(lookupBody)).results(.number(9999), snap: snapshot()))
        #expect(results.last?.openPRs.map(\.key.number) == [9999])
        #expect(results.last?.phase == .done)
    }

    @Test func cancellationEndsQuietly() async {
        let slow = engine { throw CancellationError() }
        let results = await collect(slow.results(.number(1), snap: snapshot()))
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.phase == .searching })
    }

    // MARK: Org issues

    @Test func lookupKeepsOffBoardIssues() async {
        let snap = snapshot(issues: [issue(5, "Board")])
        let results = await collect(engine(json(issueLookup(412, title: "Off the board"))).results(.number(412), snap: snap))
        let last = try! #require(results.last)
        #expect(last.phase == .done)
        #expect(last.issues.map(\.key.number) == [412])
        #expect(last.emptyMessage(org: "initech", query: .number(412), mode: .pullRequests) == nil)
    }

    @Test func lookupCopyTakesBoardStatus() async {
        let snap = snapshot(issues: [issue(412, "Old title", status: "In progress")])
        let results = await collect(engine(json(issueLookup(412, title: "Fresh title"))).results(.number(412), snap: snap))
        let found = try! #require(results.last?.issues.first)
        #expect(found.title == "Fresh title")
        #expect(found.status?.name == "In progress")
    }

    @Test func localMatchesAssignedAndCreated() {
        let snap = snapshot(
            issues: [issue(231, "Webhook pool", updated: 20, status: "In progress")],
            assigned: [issue(231, "Webhook pool", updated: 20), issue(7, "Unrelated")],
            created: [issue(52, "Webhook docs", updated: 10)])
        let r = engine(json("{}")).local(.text(["webhook"]), in: snap)
        #expect(r.issues.map(\.key.number) == [231, 52])
        #expect(r.issues.first?.status?.name == "In progress")
    }

    @Test func remoteTextSearchesOrgIssues() async {
        let issues = searchResponse([
            issueNode(90, title: "Pool leak", state: "CLOSED", updated: "2026-10-26T10:00:00Z"),
            issueNode(231, title: "Webhook pool exhausted", updated: "2026-10-20T10:00:00Z"),
            issueNode(3, title: "Unrelated", updated: "2026-10-26T10:00:00Z"),
        ])
        let transport = RecordingTransport(reply: searchResponse([]), issueReply: issues)
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let results = await collect(e.results(.text(["pool"]), snap: snapshot()))
        #expect(transport.bodies.contains { $0.contains(#"org:initech is:issue in:title \"pool\" sort:updated-desc"#) })
        let done = try! #require(results.last)
        #expect(done.phase == .done)
        #expect(done.issues.map(\.key.number) == [231, 90])
        #expect(done.openIssues.map(\.key.number) == [231])
        #expect(done.closedIssues.map(\.key.number) == [90])
    }

    @Test func issueSearchTruncationCounts() async {
        let more = """
        {"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":true},"nodes":[\(issueNode(
            8, title: "fix it", updated: "2026-10-25T10:00:00Z"))]}}}
        """
        let transport = RecordingTransport(reply: searchResponse([]), issueReply: more)
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let results = await collect(e.results(.text(["fix"]), snap: snapshot()))
        #expect(transport.issueBodies.count == 1)
        #expect(transport.issueBodies[0].contains(#""first":100"#))
        #expect(results.last?.truncated == true)
    }

    @Test func issueSearchFailureKeepsRemotePRs() async {
        let remotePR = prNode(20, title: "webhook retry", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
        let transport = RecordingTransport(reply: searchResponse([remotePR]), failIssues: true)
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let snap = snapshot(mine: [pr(10, "webhook")], assigned: [issue(11, "webhook")])
        let last = try! #require(await collect(e.results(.text(["webhook"]), snap: snap)).last)
        #expect(last.phase == .failedRemote("Couldn't search issues on GitHub, showing local issues only"))
        #expect(Set(last.openPRs.map(\.key.number)) == [10, 20])
        #expect(last.issues.map(\.key.number) == [11])
    }

    @Test func prSearchFailureKeepsRemoteIssues() async {
        let remoteIssue = issueNode(21, title: "webhook drops", updated: "2026-10-25T10:00:00Z")
        let transport = FailingPRTransport(issueReply: searchResponse([remoteIssue]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let snap = snapshot(mine: [pr(10, "webhook")], assigned: [issue(11, "webhook")])
        let last = try! #require(await collect(e.results(.text(["webhook"]), snap: snap)).last)
        #expect(last.phase == .failedRemote("Couldn't search pull requests on GitHub, showing local pull requests only"))
        // PR matches fall back to local ones; the org issue search is kept.
        #expect(last.openPRs.map(\.key.number) == [10])
        #expect(Set(last.issues.map(\.key.number)) == [11, 21])
    }

    @Test func prSearchFailureTruncationFollowsIssues() async {
        let more = """
        {"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":true},"nodes":[\(issueNode(
            8, title: "fix it", updated: "2026-10-25T10:00:00Z"))]}}}
        """
        let e = SearchEngine(api: GitHubAPI(transport: FailingPRTransport(issueReply: more), auth: StaticTokenSource("test-token")))
        let last = try! #require(await collect(e.results(.text(["fix"]), snap: snapshot())).last)
        #expect(last.truncated)
        #expect(last.issues.map(\.key.number) == [8])
    }

    @Test func bothTitleSearchesFailingFailsRemote() async {
        let e = engine { throw APIError.network("offline") }
        let snap = snapshot(mine: [pr(10, "webhook")], assigned: [issue(11, "webhook")])
        let last = try! #require(await collect(e.results(.text(["webhook"]), snap: snap)).last)
        #expect(last.phase == .failedRemote("Couldn't reach GitHub, showing local results only"))
        #expect(last.openPRs.map(\.key.number) == [10])
        #expect(last.issues.map(\.key.number) == [11])
    }

    @Test func issueSearchFailureTruncationFollowsPRs() async {
        let more = """
        {"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":true},"nodes":[\(prNode(
            30, title: "fix it", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil))]}}}
        """
        let transport = RecordingTransport(reply: more, failIssues: true)
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let last = try! #require(await collect(e.results(.text(["fix"]), snap: snapshot())).last)
        #expect(last.truncated)
        #expect(last.openPRs.map(\.key.number) == [30])
    }

    // MARK: Cached issue copies

    @Test func newerListCopyWinsOverStaleBoardCopy() {
        // The board was last read while #5 was closed; it was reopened since and is fresh in Assigned.
        let snap = snapshot(
            issues: [issue(5, "pool leak", open: false, updated: 10, status: "In progress")],
            assigned: [issue(5, "Pool leak reopened", open: true, updated: 50)])
        let r = engine(json("{}")).local(.text(["pool"]), in: snap)
        let found = try! #require(r.issues.first)
        #expect(r.issues.count == 1)
        #expect(found.isOpen)
        #expect(found.title == "Pool leak reopened")
        // The Status still comes from the board copy.
        #expect(found.status?.name == "In progress")
        #expect(r.openIssues.map(\.key.number) == [5])
    }

    @Test func cachedIssuePicksLikeSearch() {
        // Board copy stale and closed; Assigned has it reopened and retitled; Created is older still.
        let snap = snapshot(
            issues: [issue(5, "pool leak", open: false, updated: 10, status: "In progress"), issue(6, "board only", status: "Todo")],
            assigned: [issue(5, "pool leak fixed", updated: 20)],
            created: [issue(5, "pool", open: false, updated: 5), issue(7, "created only", updated: 1)])
        let picked = SearchEngine.cachedIssue(PRKey(repo: repo, number: 5), in: snap)
        #expect(picked?.isOpen == true)
        #expect(picked?.title == "pool leak fixed")
        #expect(picked?.status?.name == "In progress")
        #expect(picked == SearchEngine(api: GitHubAPI(transport: FailingPRTransport(), auth: StaticTokenSource("test-token")))
            .local(.number(5), in: snap).issues.first)
        #expect(SearchEngine.cachedIssue(PRKey(repo: repo, number: 6), in: snap)?.status?.name == "Todo")
        #expect(SearchEngine.cachedIssue(PRKey(repo: repo, number: 7), in: snap)?.title == "created only")
        #expect(SearchEngine.cachedIssue(PRKey(repo: repo, number: 8), in: snap) == nil)
        // While the board can't be read, its Status is not shown.
        let unavailable = snapshot(issues: [issue(6, "board only", status: "Todo")], boardError: "Offline")
        #expect(SearchEngine.cachedIssue(PRKey(repo: repo, number: 6), in: unavailable)?.status == nil)
    }

    @Test func boardCopyWinsWhenNotOlder() {
        let snap = snapshot(
            issues: [issue(5, "Board title", updated: 50, status: "Todo")],
            assigned: [issue(5, "List title", updated: 50)], created: [issue(5, "Undated")])
        let found = try! #require(engine(json("{}")).local(.number(5), in: snap).issues.first)
        #expect(found.title == "Board title")
        #expect(found.status?.name == "Todo")
    }

    @Test func issueInAssignedAndCreatedListedOnce() {
        let snap = snapshot(
            assigned: [issue(7, "webhook", updated: 10)], created: [issue(7, "webhook newer", updated: 20)])
        let r = engine(json("{}")).local(.text(["webhook"]), in: snap)
        #expect(r.issues.map(\.key.number) == [7])
        #expect(r.issues.first?.title == "webhook newer")
        #expect(r.issues.first?.status == nil)
    }

    @Test func sameStateIssuesSortByUpdatedNilLast() {
        let snap = snapshot(
            assigned: [
                issue(1, "x"), issue(2, "x", updated: 10), issue(3, "x", updated: 30),
                issue(4, "x", open: false, updated: 5), issue(5, "x", open: false), issue(6, "x", open: false, updated: 40),
            ])
        let r = engine(json("{}")).local(.text(["x"]), in: snap)
        #expect(r.issues.map(\.key.number) == [3, 2, 1, 6, 4, 5])
    }

    @Test func statusHiddenWhileBoardUnavailable() {
        let snap = snapshot(
            issues: [issue(5, "pool", status: "In progress")], boardError: "Token is missing a required scope")
        let found = try! #require(engine(json("{}")).local(.text(["pool"]), in: snap).issues.first)
        #expect(found.status == nil)
    }

    @Test func statusHiddenForDeletedOption() {
        let snap = snapshot(issues: [issue(5, "pool", status: "Blocked")])
        let found = try! #require(engine(json("{}")).local(.text(["pool"]), in: snap).issues.first)
        #expect(found.status == nil)
    }

    @Test func remoteCopyStatusHiddenWhileBoardUnavailable() async {
        let snap = snapshot(
            issues: [issue(412, "Old title", status: "In progress")], boardError: "Token is missing a required scope")
        let results = await collect(engine(json(issueLookup(412, title: "Fresh title"))).results(.number(412), snap: snap))
        let found = try! #require(results.last?.issues.first)
        #expect(found.title == "Fresh title")
        #expect(found.status == nil)
    }

    /// Search follows the mode: each mode orders only its own kind, open before closed.
    @Test func orderedKeysKeepOnlyTheModesKind() {
        let openPR = PRKey(repo: repo, number: 1), closedPR = PRKey(repo: repo, number: 2)
        let openIssue = PRKey(repo: repo, number: 3), closedIssue = PRKey(repo: repo, number: 4)
        let r = SearchResults(
            openPRs: [pr(1)], closedPRs: [pr(2, state: .merged, closed: 1)],
            issues: [issue(3), issue(4, open: false)], phase: .done)
        #expect(r.orderedKeys(mode: .issues) == [openIssue, closedIssue])
        #expect(r.orderedKeys(mode: .pullRequests) == [openPR, closedPR])
        #expect(!r.isEmpty(in: .issues))
        let onlyPRs = SearchResults(openPRs: [pr(1)], closedPRs: [], issues: [], phase: .done)
        #expect(onlyPRs.isEmpty(in: .issues))
        #expect(!onlyPRs.isEmpty(in: .pullRequests))
    }

    @Test func emptyMessagesNameTheModesKind() async {
        let lookupNothing = #"{"data":{"r0":{"issueOrPullRequest":null}}}"#
        // With no board chosen, issues are still searched, so Issues mode still says so.
        for snap in [snapshot(), snapshot(boardProject: nil)] {
            let last = try! #require(await collect(engine(json(lookupNothing)).results(.number(9999), snap: snap)).last)
            #expect(last.emptyMessage(org: "initech", query: .number(9999), mode: .pullRequests) == "No PR #9999 in initech")
            #expect(last.emptyMessage(org: "initech", query: .number(9999), mode: .issues) == "No issue #9999 in initech")
        }
        let done = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(done.emptyMessage(org: "initech", query: .text(["pool", "leak"]), mode: .pullRequests) == "No pull requests match “pool leak”")
        #expect(done.emptyMessage(org: "initech", query: .text(["pool", "leak"]), mode: .issues) == "No issues match “pool leak”")
        #expect(done.emptyMessage(org: "o", query: .parse("@alice"), mode: .issues) == "No issues with @alice")
        #expect(done.emptyMessage(org: "o", query: .parse("@alice fix"), mode: .issues) == "No issues with @alice match “fix”")
        #expect(done.emptyMessage(org: "o", query: .parse("o/r#12"), mode: .issues) == "No issue #12 in o/r")
        // A link outside the scope reads the same in either mode.
        #expect(done.emptyMessage(org: "o", query: .parse("x/y#12"), scope: .org("o"), mode: .issues)
            == "PullBull searches o only, not x/y")
    }

    /// Matches of only the other kind: no empty message, the fallback line instead, once searching is over.
    @Test func otherKindsMatchesGiveTheFallbackLine() {
        let twoIssues = SearchResults(openPRs: [], closedPRs: [], issues: [issue(3), issue(4, open: false)], phase: .done)
        #expect(twoIssues.emptyMessage(org: "o", query: .text(["pool"]), mode: .pullRequests) == nil)
        let fallback = try! #require(twoIssues.crossModeFallback(mode: .pullRequests, query: .text(["pool"])))
        #expect(fallback.target == .issues)
        #expect(fallback.text == "2 issues match · ⌘2")
        #expect(fallback.accessibilityLabel == "2 issues match. Show issues, Command-2")
        #expect(twoIssues.crossModeFallback(mode: .issues, query: .text(["pool"])) == nil)

        let oneIssue = SearchResults(openPRs: [], closedPRs: [], issues: [issue(3)], phase: .done)
        #expect(oneIssue.crossModeFallback(mode: .pullRequests, query: .text(["pool"]))?.text == "1 issue matches · ⌘2")

        let onePR = SearchResults(openPRs: [], closedPRs: [pr(2, state: .closed, closed: 1)], issues: [], phase: .done)
        #expect(onePR.crossModeFallback(mode: .issues, query: .parse("@alice"))?.text == "1 pull request matches · ⌘1")
        let threePRs = SearchResults(openPRs: [pr(1), pr(5)], closedPRs: [pr(2, state: .merged, closed: 1)], issues: [], phase: .done)
        let toPRs = try! #require(threePRs.crossModeFallback(mode: .issues, query: .text(["fix"])))
        #expect(toPRs.target == .pullRequests)
        #expect(toPRs.text == "3 pull requests match · ⌘1")
        #expect(toPRs.accessibilityLabel == "3 pull requests match. Show pull requests, Command-1")
    }

    @Test func numberLookupOfTheOtherKindSaysWhatItIs() {
        let anIssue = SearchResults(openPRs: [], closedPRs: [], issues: [issue(123)], phase: .done)
        #expect(anIssue.crossModeFallback(mode: .pullRequests, query: .number(123))?.text == "#123 is an issue · ⌘2")
        #expect(anIssue.crossModeFallback(mode: .pullRequests, query: .parse("initech/gadgets#123"))?.text
            == "#123 is an issue · ⌘2")
        let aPR = SearchResults(openPRs: [pr(123)], closedPRs: [], issues: [], phase: .done)
        #expect(aPR.crossModeFallback(mode: .issues, query: .number(123))?.text == "#123 is a pull request · ⌘1")
        #expect(aPR.crossModeFallback(mode: .issues, query: .parse("https://github.com/initech/gadgets/pull/123"))?.text
            == "#123 is a pull request · ⌘1")
        // The same number in two repositories is counted.
        let twoRepos = SearchResults(
            openPRs: [], closedPRs: [], issues: [issue(123), issue(123, in: "initech/widgets")], phase: .done)
        #expect(twoRepos.crossModeFallback(mode: .pullRequests, query: .number(123))?.text == "2 issues match · ⌘2")
    }

    /// Nothing extra while the answer is still coming; after a failed GitHub search the local matches count.
    @Test func fallbackWaitsForTheSearchToFinish() {
        let searching = SearchResults(openPRs: [], closedPRs: [], issues: [issue(3)], phase: .searching)
        #expect(searching.crossModeFallback(mode: .pullRequests, query: .text(["pool"])) == nil)
        #expect(searching.emptyMessage(org: "o", query: .text(["pool"]), mode: .pullRequests) == nil)
        let none = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(none.crossModeFallback(mode: .pullRequests, query: .text(["pool"])) == nil)
    }

    /// One kind's failed title search is that mode's failure only; the other mode shows its answer as done.
    @Test func aFailedSearchOfOneKindFailsOnlyItsMode() {
        let issuesFailed = SearchResults(
            openPRs: [], closedPRs: [], issues: [issue(3)], phase: .failedRemote(SearchEngine.issueFailureMessage))
        #expect(issuesFailed.failure(in: .issues) == SearchEngine.issueFailureMessage)
        #expect(issuesFailed.failure(in: .pullRequests) == nil)
        #expect(issuesFailed.phase(in: .pullRequests) == .done)
        // PR mode: the issues are unknown, so no fallback; the PR answer is empty and says so.
        #expect(issuesFailed.crossModeFallback(mode: .pullRequests, query: .text(["pool"])) == nil)
        #expect(issuesFailed.emptyMessage(org: "o", query: .text(["pool"]), mode: .pullRequests)
            == "No pull requests match “pool”")
        // Issues mode: its own failure stands.
        #expect(issuesFailed.emptyMessage(org: "o", query: .text(["pool"]), mode: .issues) == nil)

        let prsFailed = SearchResults(
            openPRs: [pr(1)], closedPRs: [], issues: [], phase: .failedRemote(SearchEngine.prFailureMessage))
        #expect(prsFailed.failure(in: .pullRequests) == SearchEngine.prFailureMessage)
        #expect(prsFailed.failure(in: .issues) == nil)
        #expect(prsFailed.phase(in: .issues) == .done)
        #expect(prsFailed.crossModeFallback(mode: .issues, query: .text(["fix"])) == nil)
        #expect(prsFailed.emptyMessage(org: "o", query: .text(["fix"]), mode: .issues) == "No issues match “fix”")

        // The mode's own search failed, the other kind's is whole: the fallback still points to it.
        let prsFailedIssuesFound = SearchResults(
            openPRs: [], closedPRs: [], issues: [issue(3)], phase: .failedRemote(SearchEngine.prFailureMessage))
        #expect(prsFailedIssuesFound.crossModeFallback(mode: .pullRequests, query: .text(["pool"]))?.text
            == "1 issue matches · ⌘2")

        // GitHub not reached at all fails both modes, and neither kind's matches are known.
        let unreachable = SearchResults(
            openPRs: [], closedPRs: [], issues: [issue(3)], phase: .failedRemote(SearchEngine.remoteFailureMessage))
        #expect(unreachable.failure(in: .pullRequests) == SearchEngine.remoteFailureMessage)
        #expect(unreachable.failure(in: .issues) == SearchEngine.remoteFailureMessage)
        #expect(unreachable.crossModeFallback(mode: .pullRequests, query: .text(["pool"])) == nil)
        #expect(unreachable.emptyMessage(org: "o", query: .text(["pool"]), mode: .pullRequests) == nil)
    }

    /// No issue is merged or a draft: Issues mode points to the pull requests that are, or says none is.
    @Test func mergedInIssuesModePointsToPullRequests() {
        let merged = pr(2, state: .merged, closed: 1)
        let snap = snapshot(closed: [merged], issues: [issue(3, open: false)])
        var results = engine(json("{}")).local(.parse("is:merged"), in: snap)
        results.phase = .done
        #expect(results.orderedKeys(mode: .issues).isEmpty)
        #expect(results.emptyMessage(org: "o", query: .parse("is:merged"), mode: .issues) == nil)
        #expect(results.crossModeFallback(mode: .issues, query: .parse("is:merged"))?.text == "1 pull request matches · ⌘1")

        var nothing = engine(json("{}")).local(.parse("is:draft"), in: snap)
        nothing.phase = .done
        #expect(nothing.crossModeFallback(mode: .issues, query: .parse("is:draft")) == nil)
        #expect(nothing.emptyMessage(org: "o", query: .parse("is:draft"), mode: .issues) == "No issues with is:draft")
    }

    // MARK: Remote text page cap

    @Test func remoteTextAsksForOnePageOfAHundredAndSaysSo() async {
        let next = """
        {"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":true},"nodes":[\(prNode(
            30, title: "fix it", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil))]}}}
        """
        let transport = RecordingTransport(reply: next)
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let results = await collect(e.results(.text(["fix"]), snap: snapshot()))
        #expect(transport.prBodies.count == 1)
        #expect(transport.prBodies[0].contains("sort:updated-desc"))
        #expect(transport.prBodies[0].contains(#""first":100"#))
        let last = try! #require(results.last)
        #expect(last.phase == .done)
        #expect(last.truncated)
        #expect(last.truncationNote == "Showing the 100 most recent matches of each kind")
    }

    @Test func remoteTextUnderCapIsNotTruncated() async {
        let results = await collect(prSearchEngine(searchResponse([])).results(.text(["fix"]), snap: snapshot()))
        #expect(results.last?.truncated == false)
        #expect(results.last?.truncationNote == nil)
    }
    // MARK: Labels

    private func labelled(_ p: PullRequest, _ labels: [String]) -> PullRequest {
        PullRequest(
            key: p.key, title: p.title, url: p.url, author: p.author, authorAvatarURL: p.authorAvatarURL,
            state: p.state, isDraft: p.isDraft, createdAt: p.createdAt, updatedAt: p.updatedAt, closedAt: p.closedAt,
            headRef: p.headRef, baseRef: p.baseRef, ci: p.ci, headCommitDate: p.headCommitDate,
            commentCount: p.commentCount, lastCommentAuthor: p.lastCommentAuthor, latestReviews: p.latestReviews,
            reviewRequests: p.reviewRequests, labels: labels)
    }

    private func labelled(_ i: BoardIssue, _ labels: [String]) -> BoardIssue {
        BoardIssue(key: i.key, title: i.title, url: i.url, isOpen: i.isOpen, labels: labels)
    }

    @Test func localLabelMatchesPRsAndIssuesIgnoringCase() {
        let snap = snapshot(
            team: [labelled(pr(1, "Fix login"), ["Bug"]), labelled(pr(2, "Fix logout"), ["ui"])],
            issues: [labelled(issue(3, "Login 500s"), ["bug", "backend"]), labelled(issue(4, "Docs"), ["docs"])])
        let r = engine(json("{}")).local(SearchQuery.parse("~bug"), in: snap)
        #expect(r.openPRs.map(\.key.number) == [1])
        #expect(r.issues.map(\.key.number) == [3])
    }

    @Test func labelsAndWithWordsPeopleAndEachOther() {
        let snap = snapshot(
            team: [labelled(pr(1, "Fix login"), ["bug"]), labelled(pr(2, "Fix logout"), ["bug", "ui"])],
            issues: [labelled(issue(3, "Login 500s"), ["bug", "ui"])])
        let e = engine(json("{}"))
        #expect(e.local(SearchQuery.parse("~bug login"), in: snap).openPRs.map(\.key.number) == [1])
        #expect(e.local(SearchQuery.parse("~bug ~ui"), in: snap).openPRs.map(\.key.number) == [2])
        #expect(e.local(SearchQuery.parse("~bug ~ui"), in: snap).issues.map(\.key.number) == [3])
        #expect(e.local(SearchQuery.parse("~bug @alice"), in: snap).openPRs.map(\.key.number) == [1, 2])
        #expect(e.local(SearchQuery.parse("~bug @bob"), in: snap).isEmpty)
    }

    @Test func labelMatchIsTheWholeName() {
        let snap = snapshot(issues: [labelled(issue(3, "x"), ["good first issue"])])
        let e = engine(json("{}"))
        #expect(e.local(SearchQuery.parse("~good"), in: snap).isEmpty)
        #expect(e.local(SearchQuery.parse(#"~"Good First Issue""#), in: snap).issues.map(\.key.number) == [3])
        #expect(e.local(SearchQuery.parse(#"label:"good first issue""#), in: snap).issues.map(\.key.number) == [3])
    }

    @Test func remoteLabelQueryString() async {
        func bodies(_ raw: String) async -> (pr: String, issue: String) {
            let transport = RecordingTransport(reply: searchResponse([]))
            let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
            _ = await collect(e.results(SearchQuery.parse(raw), snap: snapshot()))
            return (transport.prBodies.first ?? "", transport.issueBodies.first ?? "")
        }
        let alone = await bodies("~bug")
        #expect(alone.pr.contains(#"org:initech is:pr label:\"bug\" sort:updated-desc"#))
        #expect(alone.issue.contains(#"org:initech is:issue label:\"bug\" sort:updated-desc"#))
        let all = await bodies(#"@alice ~"good first issue" ~ui login"#)
        #expect(all.pr.contains(
            #"org:initech is:pr involves:alice label:\"good first issue\" label:\"ui\" in:title \"login\" sort:updated-desc"#))
    }

    /// No org, limited to selected repos: `~` searches with `user:` and drops matches elsewhere.
    @Test func personalLabelSearch() async {
        var snap = snapshot()
        snap.org = .personal(login: "initech", repos: ["gadgets", "other"], reposComplete: true)
        snap = snap.limited(to: .personal(login: "initech", repos: ["initech/gadgets"]))
        let bug = #","labels":{"nodes":[{"name":"bug"}]}}"#
        func labelledPR(_ number: Int, in repoName: String) -> String {
            String(prNode(number, title: "Pool", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
                .replacingOccurrences(of: repo, with: repoName).dropLast()) + bug
        }
        func labelledIssue(_ number: Int, in repoName: String) -> String {
            String(issueNode(number, title: "Pool", updated: "2026-10-25T10:00:00Z")
                .replacingOccurrences(of: repo, with: repoName).dropLast()) + bug
        }
        let transport = RecordingTransport(
            reply: searchResponse([labelledPR(7, in: "someone/else"), labelledPR(8, in: repo)]),
            issueReply: searchResponse([labelledIssue(17, in: "someone/else"), labelledIssue(18, in: repo)]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
        let done = try! #require(await collect(e.results(SearchQuery.parse("~bug"), snap: snap)).last)
        #expect(done.phase == .done)
        #expect(done.openPRs.map(\.key.number) == [8])
        #expect(done.issues.map(\.key.number) == [18])
        #expect(transport.prBodies.contains { $0.contains(#"user:initech is:pr label:\"bug\" sort:updated-desc"#) })
        #expect(transport.issueBodies.contains {
            $0.contains(#"user:initech is:issue label:\"bug\" sort:updated-desc"#)
        })
        #expect(!transport.bodies.contains { $0.contains("org:") })
    }

    @Test func remoteRecheckDropsRowsWithoutTheLabel() async {
        let labelledNode = prNode(1, title: "one", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
            .replacingOccurrences(of: #""reviewRequests":{"nodes":[]}"#,
                                  with: #""reviewRequests":{"nodes":[]},"labels":{"nodes":[{"name":"Bug"}]}"#)
        let body = searchResponse([
            labelledNode, prNode(2, title: "two", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
        ])
        let results = await collect(prSearchEngine(body).results(SearchQuery.parse("~bug"), snap: snapshot()))
        #expect(results.last?.phase == .done)
        #expect(results.last?.openPRs.map(\.key.number) == [1])
    }

    @Test func labelEmptyMessages() {
        let done = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(done.emptyMessage(org: "o", query: SearchQuery.parse("~bug"), mode: .pullRequests) == "No pull requests with ~bug")
        #expect(done.emptyMessage(org: "o", query: SearchQuery.parse(#"@a ~"good first issue" fix"#), mode: .pullRequests)
            == #"No pull requests with @a and ~"good first issue" match “fix”"#)
    }

    // MARK: States

    private func drafted(_ p: PullRequest) -> PullRequest {
        PullRequest(
            key: p.key, title: p.title, url: p.url, author: p.author, authorAvatarURL: p.authorAvatarURL,
            state: p.state, isDraft: true, createdAt: p.createdAt, updatedAt: p.updatedAt, closedAt: p.closedAt,
            headRef: p.headRef, baseRef: p.baseRef, ci: p.ci, headCommitDate: p.headCommitDate,
            commentCount: p.commentCount, lastCommentAuthor: p.lastCommentAuthor, latestReviews: p.latestReviews,
            reviewRequests: p.reviewRequests, labels: p.labels)
    }

    /// Open PR 1, draft PR 2, closed PR 3, merged PR 4; open issue 5, closed issue 6.
    private func stateSnapshot() -> Snapshot {
        snapshot(
            team: [pr(1, "Fix login"), drafted(pr(2, "Fix logout"))],
            closed: [pr(3, "Fix login", state: .closed, closed: 10), pr(4, "Fix login", state: .merged, closed: 20)],
            issues: [issue(5, "Login 500s"), issue(6, "Login 404s", open: false)])
    }

    private func numbers(_ r: SearchResults) -> [Int] {
        (r.openPRs + r.closedPRs).map(\.key.number) + r.issues.map(\.key.number)
    }

    @Test func localStateMatches() {
        let e = engine(json("{}"))
        let snap = stateSnapshot()
        #expect(numbers(e.local(SearchQuery.parse("is:open"), in: snap)) == [1, 2, 5])
        #expect(numbers(e.local(SearchQuery.parse("is:closed"), in: snap)) == [4, 3, 6])
        #expect(numbers(e.local(SearchQuery.parse("is:merged"), in: snap)) == [4])
        #expect(numbers(e.local(SearchQuery.parse("is:draft"), in: snap)) == [2])
    }

    @Test func statesAndWithWordsPeopleAndEachOther() {
        let e = engine(json("{}"))
        let snap = stateSnapshot()
        #expect(numbers(e.local(SearchQuery.parse("is:open login"), in: snap)) == [1, 5])
        #expect(numbers(e.local(SearchQuery.parse("is:open is:draft"), in: snap)) == [2])
        #expect(numbers(e.local(SearchQuery.parse("is:closed @alice"), in: snap)) == [4, 3])
        #expect(e.local(SearchQuery.parse("is:open is:merged"), in: snap).isEmpty)
        #expect(e.local(SearchQuery.parse("is:merged @bob"), in: snap).isEmpty)
    }

    @Test func remoteStateQueryString() async {
        func bodies(_ raw: String) async -> (pr: [String], issue: [String]) {
            let transport = RecordingTransport(reply: searchResponse([]))
            let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
            _ = await collect(e.results(SearchQuery.parse(raw), snap: snapshot()))
            return (transport.prBodies, transport.issueBodies)
        }
        let open = await bodies("is:open")
        #expect(open.pr.first?.contains("org:initech is:pr is:open sort:updated-desc") == true)
        #expect(open.issue.first?.contains("org:initech is:issue is:open sort:updated-desc") == true)
        let closed = await bodies("@alice ~bug is:closed login")
        #expect(closed.pr.first?.contains(
            #"org:initech is:pr is:closed involves:alice label:\"bug\" in:title \"login\" sort:updated-desc"#) == true)
        #expect(closed.issue.first?.contains(#"org:initech is:issue is:closed involves:alice"#) == true)
    }

    @Test func mergedAndDraftSkipTheIssueSearch() async {
        for raw in ["is:merged", "is:draft fix", "is:open is:draft"] {
            let transport = RecordingTransport(reply: searchResponse([]))
            let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
            let done = await collect(e.results(SearchQuery.parse(raw), snap: snapshot())).last
            #expect(done?.phase == .done)
            #expect(transport.issueBodies.isEmpty)
            #expect(transport.prBodies.count == 1)
        }
        let transport = RecordingTransport(reply: searchResponse([]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
        _ = await collect(e.results(SearchQuery.parse("is:merged"), snap: snapshot()))
        #expect(transport.prBodies.first?.contains("is:pr is:merged sort:updated-desc") == true)
    }

    /// With no issue search, a failed PR search is GitHub unreachable, not a failure of one kind.
    @Test func mergedWithAFailedPRSearchFallsBackToLocal() async {
        let e = SearchEngine(api: GitHubAPI(transport: FailingPRTransport(), auth: StaticTokenSource("t")))
        let done = await collect(e.results(SearchQuery.parse("is:merged"), snap: stateSnapshot())).last
        #expect(done?.phase == .failedRemote(SearchEngine.remoteFailureMessage))
        #expect(done.map(numbers) == [4])
    }

    @Test func remoteRecheckDropsRowsInAnotherState() async {
        let body = searchResponse([
            prNode(1, title: "one", state: "MERGED", updated: "2026-10-25T10:00:00Z", closedAt: "2026-10-25T10:00:00Z"),
            prNode(2, title: "two", state: "CLOSED", updated: "2026-10-25T10:00:00Z", closedAt: "2026-10-25T10:00:00Z"),
            prNode(3, title: "three", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
        ])
        let merged = await collect(prSearchEngine(body).results(SearchQuery.parse("is:merged"), snap: snapshot()))
        #expect(merged.last?.phase == .done)
        #expect(merged.last.map(numbers) == [1])
        let closed = await collect(prSearchEngine(body).results(SearchQuery.parse("is:closed"), snap: snapshot()))
        #expect(closed.last.map { $0.closedPRs.map(\.key.number).sorted() } == [1, 2])
        #expect(closed.last?.openPRs.isEmpty == true)
        let draftBody = searchResponse([
            prNode(5, title: "five", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil)
                .replacingOccurrences(of: #""isDraft":false"#, with: #""isDraft":true"#),
            prNode(6, title: "six", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
        ])
        let drafts = await collect(prSearchEngine(draftBody).results(SearchQuery.parse("is:draft"), snap: snapshot()))
        #expect(drafts.last.map(numbers) == [5])
    }

    @Test func remoteIssuesAreRecheckedByState() async {
        let transport = RecordingTransport(
            reply: searchResponse([]),
            issueReply: searchResponse([
                issueNode(7, title: "seven", updated: "2026-10-25T10:00:00Z"),
                issueNode(8, title: "eight", state: "CLOSED", updated: "2026-10-25T10:00:00Z"),
            ]))
        let e = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("t")))
        let done = await collect(e.results(SearchQuery.parse("is:closed"), snap: snapshot())).last
        #expect(done?.issues.map(\.key.number) == [8])
    }
}

/// Counts requests; every one gets `reply`, or fails while `failing` is set.
private final class SwitchableTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent = 0
    private var current: String
    private var fails = false
    init(reply: String) { current = reply }
    var requests: Int { lock.withLock { sent } }
    var reply: String {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
    var failing: Bool {
        get { lock.withLock { fails } }
        set { lock.withLock { fails = newValue } }
    }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let (reply, fails) = lock.withLock { () -> (String, Bool) in
            sent += 1
            return (current, self.fails)
        }
        if fails { throw APIError.network("offline") }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!
        return (Data(reply.utf8), response)
    }
}

private let viewer = AccountRef(login: "me", source: .gh)

/// `iso` as an offset from `t0`, for `pr(updated:)`.
private func offset(_ iso: String) -> TimeInterval {
    try! Date(iso, strategy: .iso8601).timeIntervalSince(t0)
}

@Suite struct SearchEngineCacheTests {
    private let clock = ManualNow(t0.addingTimeInterval(60))
    private let transport = SwitchableTransport(reply: searchResponse([
        prNode(20, title: "webhook retry", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil),
    ]))
    private var cache: SearchCache { SearchCache(capacity: SearchCache.capacity, now: { [clock] in clock.now }) }
    private var engine: SearchEngine {
        SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
    }

    private func run(
        _ raw: String, snap: Snapshot = snapshot(), cache: SearchCache, debounce: Duration = .zero
    ) async -> (first: SearchResults, updates: [SearchResults]) {
        let run = engine.results(SearchQuery.parse(raw), snap: snap, account: viewer, cache: cache, debounce: debounce)
        return (run.first, await collect(run.updates))
    }

    @Test func missFetchesAndStores() async {
        let cache = cache
        let miss = await run("webhook", cache: cache)
        #expect(miss.first.phase == .searching)
        #expect(miss.updates.last?.phase == .done)
        #expect(miss.updates.last?.openPRs.map(\.key.number) == [20])
        #expect(transport.requests == 2)
        #expect(cache.count == 1)
    }

    @Test func repeatWithinTwoMinutesMakesNoRequest() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        clock.advance(by: 119)
        let hit = await run("webhook", cache: cache, debounce: .seconds(60))
        #expect(transport.requests == 2)
        #expect(hit.first.phase == .done)
        #expect(hit.first.openPRs.map(\.key.number) == [20])
        #expect(hit.updates.isEmpty)
    }

    @Test func otherWordOrderAndCaseHit() async {
        let cache = cache
        _ = await run("webhook retry", cache: cache)
        let hit = await run("  Retry   WEBHOOK", cache: cache)
        #expect(transport.requests == 2)
        #expect(hit.first.phase == .done)
        #expect(hit.first.openPRs.map(\.key.number) == [20])
    }

    @Test func numberLookupHitsWithOrWithoutHash() async {
        transport.reply = """
        {"data":{"r0":{"issueOrPullRequest":\(prNode(
            412, title: "Far away", state: "OPEN", updated: "2026-10-25T10:00:00Z", closedAt: nil))}}}
        """
        let cache = cache
        _ = await run("#412", cache: cache)
        #expect(transport.requests == 1)
        let hit = await run("412", cache: cache)
        #expect(transport.requests == 1)
        #expect(hit.first.openPRs.map(\.key.number) == [412])
    }

    @Test func staleShowsCachedThenRefetchesOnce() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        clock.advance(by: 120)
        transport.reply = searchResponse([
            prNode(21, title: "webhook backoff", state: "OPEN", updated: "2026-10-26T10:00:00Z", closedAt: nil),
        ])
        let stale = await run("webhook", cache: cache)
        #expect(stale.first.phase == .searching)
        #expect(stale.first.openPRs.map(\.key.number) == [20])
        #expect(transport.requests == 4)
        #expect(stale.updates.map(\.phase) == [.done])
        #expect(stale.updates.last?.openPRs.map(\.key.number) == [21])
        let again = await run("webhook", cache: cache)
        #expect(transport.requests == 4)
        #expect(again.first.openPRs.map(\.key.number) == [21])
    }

    @Test func olderThanTenMinutesIsAMiss() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        clock.advance(by: 600)
        let miss = await run("webhook", cache: cache)
        #expect(miss.first.openPRs.isEmpty)
        #expect(miss.first.phase == .searching)
        #expect(transport.requests == 4)
    }

    @Test func failedRefetchKeepsCachedResults() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        clock.advance(by: 300)
        transport.failing = true
        let stale = await run("webhook", cache: cache)
        #expect(stale.updates.map(\.phase) == [.done])
        #expect(stale.updates.last?.openPRs.map(\.key.number) == [20])
        transport.failing = false
        guard case .stale = cache.lookup(SearchCache.Key(account: viewer, scope: snapshot().scope, query: .text(["webhook"])))
        else { Issue.record("the cached answer should stay"); return }
    }

    /// The same text focused and unfocused are two answers, each fetched once.
    @Test func focusIsPartOfTheCacheKey() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        #expect(transport.requests == 2)
        let focus = RepoFocus(repo: "initech/widgets")
        let focused = engine.results(.text(["webhook"]), snap: snapshot(), account: viewer, cache: cache, focus: focus)
        _ = await collect(focused.updates)
        #expect(focused.first.phase == .searching)
        #expect(transport.requests == 4)
        let again = engine.results(.text(["webhook"]), snap: snapshot(), account: viewer, cache: cache, focus: focus)
        #expect(again.first.phase == .done)
        // GitHub's row is in gadgets, outside the focus.
        #expect(again.first.openPRs.isEmpty)
        #expect(transport.requests == 4)
        let unfocused = await run("webhook", cache: cache)
        #expect(unfocused.first.phase == .done)
        #expect(unfocused.first.openPRs.map(\.key.number) == [20])
    }

    @Test func failedFetchWithoutCacheFailsAsBefore() async {
        transport.failing = true
        let cache = cache
        let miss = await run("webhook", snap: snapshot(mine: [pr(10, "webhook")]), cache: cache)
        #expect(miss.updates.last?.phase == .failedRemote("Couldn't reach GitHub, showing local results only"))
        #expect(miss.updates.last?.openPRs.map(\.key.number) == [10])
        #expect(cache.count == 0)
    }

    @Test func partlyFailedFetchIsNotStored() async {
        let cache = cache
        let e = SearchEngine(api: GitHubAPI(
            transport: RecordingTransport(reply: searchResponse([]), failIssues: true), auth: StaticTokenSource("t")))
        let run = e.results(.text(["webhook"]), snap: snapshot(), account: viewer, cache: cache)
        let updates = await collect(run.updates)
        #expect(updates.last?.phase == .failedRemote("Couldn't search issues on GitHub, showing local issues only"))
        #expect(cache.count == 0)
    }

    @Test func newerSnapshotCopyBeatsCachedRow() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        // The snapshot, refreshed since, has a later copy of #20: it shows, and the cached one doesn't.
        let newer = pr(20, "webhook retry v2", updated: offset("2026-10-26T10:00:00Z"))
        let hit = await run("webhook", snap: snapshot(mine: [newer]), cache: cache)
        #expect(hit.first.openPRs.map(\.title) == ["webhook retry v2"])
        // A later copy that no longer matches hides the cached row too.
        let renamed = pr(20, "Retry policy", updated: offset("2026-10-26T10:00:00Z"))
        let gone = await run("webhook", snap: snapshot(mine: [renamed]), cache: cache)
        #expect(gone.first.openPRs.isEmpty)
    }

    @Test func cachedRowBeatsOlderSnapshotCopy() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        let hit = await run("webhook", snap: snapshot(mine: [pr(20, "webhook old")]), cache: cache)
        #expect(hit.first.openPRs.map(\.title) == ["webhook retry"])
    }

    @Test func tieGoesToTheLaterFetch() async {
        let cache = cache
        _ = await run("webhook", cache: cache)
        let same = pr(20, "webhook same time", updated: offset("2026-10-25T10:00:00Z"))
        var snap = snapshot(mine: [same])
        #expect(await run("webhook", snap: snap, cache: cache).first.openPRs.map(\.title) == ["webhook retry"])
        snap.fetchedAt = clock.now.addingTimeInterval(1)
        #expect(await run("webhook", snap: snap, cache: cache).first.openPRs.map(\.title) == ["webhook same time"])
    }

    @Test func cachedIssueTakesTheCurrentBoardStatus() async {
        transport.reply = searchResponse([issueNode(412, title: "webhook", updated: "2026-10-25T10:00:00Z")])
        let cache = cache
        _ = await run("webhook", snap: snapshot(issues: [issue(412, "webhook", status: "Todo")]), cache: cache)
        let hit = await run("webhook", snap: snapshot(issues: [issue(412, "webhook", status: "In progress")]), cache: cache)
        #expect(hit.first.issues.first?.status?.name == "In progress")
    }

    @Test func emptyQueryIsDoneAtOnce() async {
        let result = await run("", cache: cache)
        #expect(result.first.phase == .done)
        #expect(result.updates.isEmpty)
        #expect(transport.requests == 0)
    }

    @Test func cancellingDuringTheDebounceSendsNothing() async throws {
        let run = engine.results(.text(["webhook"]), snap: snapshot(), account: viewer, cache: cache, debounce: .seconds(30))
        let consumer = Task { await collect(run.updates) }
        try await Task.sleep(for: .milliseconds(20))
        consumer.cancel()
        _ = await consumer.value
        #expect(transport.requests == 0)
    }

    /// Search results and the issue detail edit from this copy, so it keeps the board copy's node IDs.
    @Test func cachedIssueKeepsNodeIds() {
        let card = BoardIssue(
            key: editKey(412), title: "t", url: URL(string: "https://github.com/o/r/issues/412")!, isOpen: true,
            boardItemId: 7, nodeId: "I_1", boardItemNodeId: "PVTI_1")
        let cached = SearchEngine.cachedIssue(editKey(412), in: editSnapshot(board: [card]))
        #expect(cached?.nodeId == "I_1")
        #expect(cached?.boardItemNodeId == "PVTI_1")
    }
}
