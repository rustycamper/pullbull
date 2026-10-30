import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_793_000_000)

private func pr(_ repo: String, _ number: Int = 1) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "someone",
        authorAvatarURL: nil, state: .open, isDraft: false, createdAt: now, updatedAt: now, closedAt: nil,
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
        latestReviews: [], reviewRequests: [], mergeable: nil)
}

private func issue(_ repo: String, _ number: Int = 2) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: true, updatedAt: now, status: nil)
}

private func snapshot(_ repos: [String]) -> Snapshot {
    Snapshot(
        fetchedAt: now,
        org: OrgContext(org: "acme", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: [], mine: repos.map { pr($0) }, team: [], recentlyClosed: [],
        boardIssues: repos.map { issue($0) })
}

private func choices(_ repos: [String]) -> [RepoChoice] {
    repos.map { RepoChoice(repo: $0, reviewCount: 0, openCount: 1) }
}

private func matches(_ raw: String, _ repo: String) -> Bool {
    SearchQuery.parse(raw).matches(pr(repo), viewer: "me", now: now, calendar: .current)
}

private func prQuery(_ raw: String, known: [String], focus: RepoFocus? = nil) throws -> String {
    let filter = try #require(SearchQuery.parse(raw).filter)
    return SearchEngine.remoteQuery(
        kind: "pr", scope: .org("acme"), focus: focus, filter: filter, repos: RepoIndex.build(snapshot(known)),
        now: now, calendar: .current)
}

private final class RecordingTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    var prBodies: [String] { lock.withLock { sent.filter { $0.contains("is:pr") } } }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sent.append(String(decoding: body, as: UTF8.self)) }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let page = #"{"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":false},"nodes":[]}}}"#
        return (Data(page.utf8), response)
    }
}

@Suite struct RepoQueryTests {
    @Test func matchesNameOrExact() {
        #expect(matches("repo:widgets", "acme/widgets"))
        #expect(matches("repo:widgets", "other/Widgets"))
        #expect(!matches("repo:widgets", "acme/widgets-ui"))
        #expect(matches("repo:acme/widgets", "acme/widgets"))
        #expect(matches("REPO:Acme/Widgets", "acme/widgets"))
        #expect(!matches("repo:acme/widgets", "other/widgets"))
    }

    @Test func positiveReposOr() {
        #expect(matches("repo:a repo:b", "acme/a"))
        #expect(matches("repo:a repo:b", "acme/b"))
        #expect(!matches("repo:a repo:b", "acme/c"))
    }

    @Test func negatedRepo() {
        #expect(!matches("-repo:widgets", "acme/widgets"))
        #expect(matches("-repo:widgets", "acme/gadgets"))
        #expect(!matches("-repo:a -repo:b", "acme/b"))
        #expect(matches("repo:a -repo:b", "acme/a"))
    }

    @Test func parsesTokens() {
        let filter = SearchQuery.parse("repo:widgets REPO:Widgets -repo:acme/web repo:").filter
        #expect(filter?.include.repos == [RepoToken(text: "widgets")])
        #expect(filter?.exclude.repos == [RepoToken(text: "acme/web")])
        #expect(filter?.tokens == ["repo:widgets", "-repo:acme/web"])
    }

    @Test func tokenMatching() {
        #expect(RepoToken(text: "widgets").matches(repo: "acme/Widgets"))
        #expect(RepoToken(text: "acme/widgets").matches(repo: "ACME/widgets"))
        #expect(!RepoToken(text: "widgets").matches(repo: "acme/widgets2"))
        #expect(RepoToken(text: "widgets").token == "repo:widgets")
    }

    @Test func indexResolves() {
        let one = RepoIndex.build(snapshot(["acme/widgets", "acme/web"]))
        #expect(one.resolve(RepoToken(text: "widgets")) == "acme/widgets")
        #expect(one.resolve(RepoToken(text: "acme/web")) == "acme/web")
        #expect(one.resolve(RepoToken(text: "zzz")) == nil)
        let two = RepoIndex.build(snapshot(["acme/widgets", "other/widgets"]))
        #expect(two.resolve(RepoToken(text: "widgets")) == nil)
        #expect(two.resolve(RepoToken(text: "other/widgets")) == "other/widgets")
    }

    @Test func sentWhenResolved() throws {
        #expect(
            try prQuery("repo:widgets", known: ["acme/widgets"])
                == "org:acme is:pr repo:acme/widgets sort:updated-desc")
        let both = ["acme/widgets", "other/widgets"]
        #expect(try prQuery("repo:widgets", known: both) == "org:acme is:pr sort:updated-desc")
        #expect(
            try prQuery("repo:other/widgets", known: both) == "org:acme is:pr repo:other/widgets sort:updated-desc")
        #expect(
            try prQuery("-repo:widgets", known: ["acme/widgets"])
                == "org:acme is:pr -repo:acme/widgets sort:updated-desc")
        #expect(try prQuery("-repo:widgets", known: both) == "org:acme is:pr sort:updated-desc")
    }

    @Test func positivePartsPrecedeTitleWords() throws {
        #expect(
            try prQuery("fix repo:a -repo:b", known: ["acme/a", "acme/b"])
                == #"org:acme is:pr repo:acme/a in:title "fix" -repo:acme/b sort:updated-desc"#)
    }

    @Test func unresolvedOfSeveralSendsNone() throws {
        let q = try prQuery("repo:a repo:zzz", known: ["acme/a"])
        #expect(q == "org:acme is:pr sort:updated-desc")
        #expect(
            try prQuery("repo:a repo:b", known: ["acme/a", "acme/b"])
                == "org:acme is:pr repo:acme/a repo:acme/b sort:updated-desc")
        #expect(try prQuery("repo:a repo:acme/a", known: ["acme/a"]) == "org:acme is:pr repo:acme/a sort:updated-desc")
    }

    @Test func focusKeepsItsOwnRepo() throws {
        let q = try prQuery("repo:a -repo:b", known: ["acme/a", "acme/b"], focus: RepoFocus(repo: "acme/a"))
        #expect(q == "repo:acme/a is:pr -repo:acme/b sort:updated-desc")
    }

    @Test func engineSendsTheResolvedRepo() async {
        let transport = RecordingTransport()
        let engine = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        for await _ in engine.results(.parse("repo:widgets"), snap: snapshot(["acme/widgets", "acme/web"])) {}
        #expect(transport.prBodies.count == 1)
        #expect(transport.prBodies.first?.replacingOccurrences(of: "\\/", with: "/").contains("repo:acme/widgets") == true)
    }

    @Test func engineSendsNothingForAnUnresolvedRepo() async {
        let transport = RecordingTransport()
        let engine = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        for await _ in engine.results(.parse("repo:zzz"), snap: snapshot(["acme/widgets"])) {}
        #expect(transport.prBodies.isEmpty)
    }

    @Test func completionFromChoices() throws {
        let index = RepoIndex(choices: choices(["acme/widgets", "acme/web"]))
        let text = "repo:w"
        let open = try #require(
            SearchCompletion.open(
                text: text, caret: text.utf16.count, dismissedStart: nil, people: .empty, labels: .empty, repos: index))
        guard case .repos(let list) = open else { Issue.record("not a repo list"); return }
        #expect(Set(list.candidates.map(\.repo)) == ["acme/widgets", "acme/web"])
        let web = try #require(index.candidates(prefix: "web").first)
        #expect(web.repo == "acme/web")
        let picked = try #require(
            RepoCompletion(token: list.token, candidates: [web], selection: 0).accepted(in: text))
        #expect(picked.text == "repo:web ")

        let shared = RepoIndex(choices: choices(["acme/widgets", "acme/web", "other/web"]))
        let acmeWeb = try #require(shared.candidates(prefix: "acme/web").first)
        #expect(acmeWeb.insertText == "repo:acme/web")
        let again = try #require(
            RepoCompletion(token: list.token, candidates: [acmeWeb], selection: 0).accepted(in: text))
        #expect(again.text == "repo:acme/web ")
    }

    @Test func completionAfterDashKeepsIt() throws {
        let index = RepoIndex(choices: choices(["acme/widgets"]))
        var field = SearchFieldState()
        field.edit("fix -repo:wid", caret: 13, people: .empty, repos: index)
        let completion = try #require(field.repoCompletion)
        #expect(completion.candidates.map(\.repo) == ["acme/widgets"])
        #expect(completion.accepted(in: "fix -repo:wid")?.text == "fix -repo:widgets ")
    }

    @Test func rankingPrefersNamePrefixThenCount() {
        let index = RepoIndex(choices: [
            RepoChoice(repo: "acme/api-web", reviewCount: 0, openCount: 9),
            RepoChoice(repo: "acme/web", reviewCount: 0, openCount: 1),
            RepoChoice(repo: "acme/webhooks", reviewCount: 0, openCount: 5),
        ])
        #expect(index.candidates(prefix: "web").map(\.repo) == ["acme/web", "acme/webhooks", "acme/api-web"])
    }

    @Test func savedSearchKeepsRepo() throws {
        var field = SearchFieldState()
        let query = field.apply(
            SavedSearch(name: "w", query: "repo:widgets is:open"), people: .empty, labels: .empty)
        #expect(query?.filter?.include.repos == [RepoToken(text: "widgets")])
        #expect(field.text.hasPrefix("repo:widgets"))
    }

    @Test func speech() throws {
        let index = RepoIndex(choices: choices(["acme/widgets"]))
        let c = try #require(index.candidates(prefix: "w").first)
        #expect(CompletionSpeech.label(c) == "acme/widgets, on 1 item")
        #expect(CompletionSpeech.completed(c) == "Showing items in acme/widgets")
    }
}
