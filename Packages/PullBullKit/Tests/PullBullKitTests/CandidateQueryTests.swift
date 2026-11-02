import Foundation
import Testing
@testable import PullBullKit

/// Answers each request in turn and records the bodies.
private final class QueueTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Data]
    private var statuses: [Int]
    private var sent: [Data] = []

    /// `statuses`: the HTTP status of each answer in turn; 200 past the end.
    init(_ json: [String], statuses: [Int] = []) {
        queue = json.map { Data($0.utf8) }
        self.statuses = statuses
    }

    var bodies: [[String: Any]] {
        lock.withLock { sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let (data, status) = lock.withLock {
            sent.append(body)
            return (queue.removeFirst(), statuses.isEmpty ? 200 : statuses.removeFirst())
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

private func api(_ transport: QueueTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"))
}

private let key = PRKey(repo: "acme/widgets", number: 7)

private func variables(_ body: [String: Any]) -> [String: Any] { body["variables"] as? [String: Any] ?? [:] }

@Suite struct CandidateQueryTests {
    @Test func labelsReadEveryPageInNameOrder() async throws {
        let t = QueueTransport([
            #"""
            {"data":{"repository":{
              "item":{"labels":{"nodes":[{"id":"LA_bug","name":"bug","color":"d73a4a","description":"Broken"}]}},
              "labels":{"nodes":[
                {"id":"LA_bug","name":"bug","color":"d73a4a","description":"Broken"},
                {"id":"LA_docs","name":"docs","color":"0075ca","description":null}],
              "pageInfo":{"hasNextPage":true,"endCursor":"c1"}}}}}
            """#,
            #"""
            {"data":{"repository":{
              "labels":{"nodes":[{"id":"LA_triage","name":"triage","color":"ededed","description":null}],
              "pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
            """#,
        ])
        let result = try await api(t).labelCandidates(for: key)
        #expect(result.all.map(\.name) == ["bug", "docs", "triage"])
        #expect(result.current.map(\.id) == ["LA_bug"])
        #expect(result.complete)
        #expect(result.all[0].color == "d73a4a")
        #expect(result.all[0].detail == "Broken")
        #expect(result.all[1].detail == nil)
        #expect(t.bodies.count == 2)
        #expect(variables(t.bodies[1])["after"] as? String == "c1")
        let query = try #require(t.bodies[0]["query"] as? String)
        #expect(query.contains("orderBy:{field:NAME,direction:ASC}"))
    }

    @Test func labelsStopAtTheLastPage() async throws {
        let page = #"""
        {"data":{"repository":{"labels":{"nodes":[{"id":"LA_a","name":"a","color":"000000","description":null}],
        "pageInfo":{"hasNextPage":true,"endCursor":"c"}}}}}
        """#
        let t = QueueTransport(Array(repeating: page, count: GitHubAPI.maxLabelPages))
        let result = try await api(t).labelCandidates(for: key)
        #expect(t.bodies.count == GitHubAPI.maxLabelPages)
        #expect(!result.complete)
    }

    @Test func assigneesReadTheFirstHundredAndTheIssuesOwn() async throws {
        let t = QueueTransport([
            #"""
            {"data":{"repository":{
              "item":{"assignees":{"nodes":[{"id":"U_carol","login":"carol","avatarUrl":"https://a.test/c.png"}]}},
              "assignableUsers":{"nodes":[
                {"id":"U_alice","login":"alice","avatarUrl":"https://a.test/a.png"},
                {"id":"U_bob","login":"bob","avatarUrl":"https://a.test/b.png"}],
              "pageInfo":{"hasNextPage":true}}}}}
            """#
        ])
        let result = try await api(t).assigneeCandidates(for: key, query: nil)
        #expect(result.all.map(\.name) == ["alice", "bob"])
        #expect(result.current.map(\.name) == ["carol"])
        #expect(result.all[0].avatarURL == URL(string: "https://a.test/a.png"))
        #expect(!result.complete)
        let sent = variables(try #require(t.bodies.first))
        #expect(sent["q"] == nil)
        #expect(sent["first"] == nil)
        #expect(sent["owner"] as? String == "acme")
        #expect(sent["name"] as? String == "widgets")
        #expect(sent["n"] as? Int == 7)
    }

    @Test func assigneeQuerySendsTheFilter() async throws {
        let t = QueueTransport([
            #"{"data":{"repository":{"item":{"assignees":{"nodes":[]}},"assignableUsers":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}}"#
        ])
        let result = try await api(t).assigneeCandidates(for: key, query: "al")
        #expect(variables(try #require(t.bodies.first))["q"] as? String == "al")
        #expect(result.complete)
    }

    @Test func aMissingItemHasNoCurrentValues() async throws {
        let t = QueueTransport([
            #"""
            {"data":{"repository":{"item":null,
              "assignableUsers":{"nodes":[{"id":"U_alice","login":"alice","avatarUrl":"https://a.test/a.png"}],
              "pageInfo":{"hasNextPage":false}}}}}
            """#
        ])
        let result = try await api(t).assigneeCandidates(for: key, query: nil)
        #expect(result.current.isEmpty)
        #expect(result.all.map(\.name) == ["alice"])
        #expect(result.complete)
    }

    @Test func candidatesReadAPullRequestsOwnValues() async throws {
        let t = QueueTransport([
            #"""
            {"data":{"repository":{
              "item":{"assignees":{"nodes":[{"id":"U_carol","login":"carol","avatarUrl":null}]}},
              "assignableUsers":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}}
            """#,
            #"""
            {"data":{"repository":{
              "item":{"labels":{"nodes":[{"id":"LA_bug","name":"bug","color":"d73a4a","description":null}]}},
              "labels":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}
            """#,
        ])
        #expect(try await api(t).assigneeCandidates(for: key, query: nil).current.map(\.name) == ["carol"])
        #expect(try await api(t).labelCandidates(for: key).current.map(\.id) == ["LA_bug"])
        for body in t.bodies {
            let query = try #require(body["query"] as? String)
            #expect(query.contains("item: issueOrPullRequest(number:$n)"))
            #expect(query.contains("... on PullRequest{"))
            #expect(!query.contains("issue(number:"))
        }
    }

    @Test func laterLabelPagesSkipTheIssue() async throws {
        let t = QueueTransport([
            #"{"data":{"repository":{"labels":{"nodes":[],"pageInfo":{"hasNextPage":true,"endCursor":"c1"}}}}}"#,
            #"{"data":{"repository":{"labels":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#,
        ])
        _ = try await api(t).labelCandidates(for: key)
        let first = variables(t.bodies[0])
        let second = variables(t.bodies[1])
        #expect(first["withIssue"] as? Bool == true)
        #expect(first["after"] == nil)
        #expect(second["withIssue"] as? Bool == false)
    }

    @Test func mentionableCandidatesSendOwnerNameAndQuery() async throws {
        let t = QueueTransport([
            #"""
            {"data":{"repository":{"mentionableUsers":{"nodes":[
              {"id":"U_a","login":"alice","avatarUrl":"https://a.test/a.png"}],
              "pageInfo":{"hasNextPage":true}}}}}
            """#,
            #"{"data":{"repository":{"mentionableUsers":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}}"#,
        ])
        let result = try await api(t).mentionableCandidates(repo: "acme/widgets", query: "al")
        #expect(result.all.map(\.name) == ["alice"])
        #expect(result.all[0].avatarURL == URL(string: "https://a.test/a.png"))
        #expect(!result.complete)
        let sent = variables(try #require(t.bodies.first))
        #expect(sent["owner"] as? String == "acme")
        #expect(sent["name"] as? String == "widgets")
        #expect(sent["q"] as? String == "al")
        let empty = try await api(t).mentionableCandidates(repo: "acme/widgets", query: "")
        #expect(empty.complete)
        #expect(variables(t.bodies[1])["q"] == nil)
    }

    @Test func teamsAreNilWhenGitHubAnswersWithoutThem() async throws {
        let t = QueueTransport([
            #"{"data":{"organization":{"teams":null}},"errors":[{"type":"INSUFFICIENT_SCOPES","message":"read:org"}]}"#
        ])
        #expect(try await api(t).teams(owner: "acme", query: nil) == nil)
        let ok = QueueTransport([
            #"{"data":{"organization":{"teams":{"nodes":[{"slug":"backend","name":"Back End"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#
        ])
        let teams = try #require(try await api(ok).teams(owner: "acme", query: nil))
        #expect(teams.map(\.team) == ["backend"])
    }

    @Test func teamsAreNilForAUsersAccount() async throws {
        let t = QueueTransport([
            #"{"data":{"organization":null},"errors":[{"type":"NOT_FOUND","message":"Could not resolve to an Organization"}]}"#
        ])
        #expect(try await api(t).teams(owner: "alice", query: nil) == nil)
    }

    /// GitHub couldn't be asked: thrown, so the @ list asks again on the next focus.
    @Test func teamsThrowWhenGitHubIsNotReached() async throws {
        let t = QueueTransport([#"{"message":"Bad Gateway"}"#], statuses: [502])
        await #expect(throws: APIError.server(502)) {
            _ = try await api(t).teams(owner: "acme", query: nil)
        }
    }

    /// An error with no data, or a page that isn't GitHub's, isn't an answer: thrown, so it isn't kept
    /// as "no teams" for the session.
    @Test func teamsThrowWithoutAnAnswer() async throws {
        let failed = QueueTransport([#"{"errors":[{"message":"Something went wrong while executing your query."}]}"#])
        await #expect(throws: APIError.graphQL("Something went wrong while executing your query.")) {
            _ = try await api(failed).teams(owner: "acme", query: nil)
        }
        let portal = QueueTransport(["<html>Sign in to Wi-Fi</html>"])
        await #expect(throws: APIError.graphQL("malformed response")) {
            _ = try await api(portal).teams(owner: "acme", query: nil)
        }
    }

    @Test func aMissingRepositoryThrowsNotFound() async throws {
        let t = QueueTransport([#"{"data":{"repository":null}}"#])
        await #expect(throws: APIError.notFound("acme/widgets not found")) {
            _ = try await api(t).labelCandidates(for: key)
        }
    }
}
