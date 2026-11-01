import Foundation
import Testing
@testable import PullBullKit

/// Answers each request in turn and records the queries.
private final class QueueTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Data]
    private var sent: [Data] = []

    init(_ json: [String]) { queue = json.map { Data($0.utf8) } }

    var bodies: [[String: Any]] {
        lock.withLock { sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let data = lock.withLock {
            sent.append(body)
            return queue.removeFirst()
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

private func api(_ transport: QueueTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"))
}

private let key = PRKey(repo: "acme/widgets", number: 7)

/// Author al; suggested sue; assignable al, bob, sue; requested carol and team backend; reviews by bob
/// (approved), carol (commented), dave (changes requested, not assignable) and the bot copilot.
private func people(owner: String = "Organization", more: Bool = false) -> String {
    #"""
    {"data":{"repository":{
      "owner":{"__typename":"\#(owner)"},
      "item":{
        "author":{"login":"al"},
        "suggestedReviewers":[{"reviewer":{"id":"U_sue","login":"sue","avatarUrl":"https://a/sue"}}],
        "reviewRequests":{"nodes":[
          {"requestedReviewer":{"__typename":"User","id":"U_carol","login":"carol","avatarUrl":"https://a/carol"}},
          {"requestedReviewer":{"__typename":"Team","slug":"backend","name":"Back End"}}]},
        "latestReviews":{"nodes":[
          {"author":{"__typename":"User","id":"U_bob","login":"bob","avatarUrl":"https://a/bob"},"state":"APPROVED"},
          {"author":{"__typename":"User","id":"U_carol","login":"carol","avatarUrl":"https://a/carol"},"state":"COMMENTED"},
          {"author":{"__typename":"User","id":"U_dave","login":"dave","avatarUrl":"https://a/dave"},"state":"CHANGES_REQUESTED"},
          {"author":{"__typename":"Bot","login":"copilot","avatarUrl":"https://a/bot"},"state":"COMMENTED"}]}},
      "assignableUsers":{"nodes":[
        {"id":"U_al","login":"al","avatarUrl":"https://a/al"},
        {"id":"U_bob","login":"bob","avatarUrl":"https://a/bob"},
        {"id":"U_sue","login":"sue","avatarUrl":"https://a/sue"}],
        "pageInfo":{"hasNextPage":\#(more)}}}}}
    """#
}

private func teams(_ names: [(String, String)], next: String? = nil) -> String {
    let nodes = names.map { #"{"slug":"\#($0.0)","name":"\#($0.1)"}"# }.joined(separator: ",")
    let info = next.map { #"{"hasNextPage":true,"endCursor":"\#($0)"}"# } ?? #"{"hasNextPage":false,"endCursor":null}"#
    return #"{"data":{"organization":{"teams":{"nodes":[\#(nodes)],"pageInfo":\#(info)}}}}"#
}

private let noTeams = #"{"data":{"organization":null},"errors":[{"type":"FORBIDDEN","message":"read:org"}]}"#

@Suite struct ReviewerCandidateTests {
    @Test func reviewerCandidatesExcludeAuthorAndBots() async throws {
        let result = try await api(QueueTransport([people(), teams([])])).reviewerCandidates(for: key, query: nil)
        let names = (result.picker.all + result.picker.current).map(\.name)
        #expect(!names.contains("al"))
        #expect(!names.contains("copilot"))
    }

    @Test func pastReviewersOutsideAssignableListed() async throws {
        let result = try await api(QueueTransport([people(), teams([])])).reviewerCandidates(for: key, query: nil)
        let dave = try #require(result.picker.all.first { $0.name == "dave" })
        #expect(dave.verdict == .changesRequested)
        #expect(dave.id == "U_dave")
        #expect(result.picker.all.first { $0.name == "bob" }?.verdict == .approved)
    }

    @Test func reRequestedReviewerKeepsVerdict() async throws {
        let result = try await api(QueueTransport([people(), teams([])])).reviewerCandidates(for: key, query: nil)
        #expect(result.picker.current.map(\.name) == ["carol", "Back End"])
        #expect(result.picker.current[0].verdict == .commented)
        #expect(result.picker.current[1].team == "backend")
        #expect(!result.picker.all.contains { $0.key == "carol" })
    }

    @Test func eachReviewerListedOnce() async throws {
        let result = try await api(QueueTransport([people(), teams([("backend", "Back End"), ("ops", "Ops")])]))
            .reviewerCandidates(for: key, query: nil)
        let keys = (result.picker.all + result.picker.current).map(\.key)
        #expect(keys.count == Set(keys).count)
    }

    @Test func peopleKeepNodeIDs() async throws {
        let result = try await api(QueueTransport([people(), teams([])])).reviewerCandidates(for: key, query: nil)
        #expect(result.people.map(\.id) == ["U_al", "U_bob", "U_sue"])
        #expect(result.people.allSatisfy { $0.verdict == nil && !$0.isSuggested })
    }

    @Test func suggestedReviewersMarked() async throws {
        let result = try await api(QueueTransport([people(), teams([])])).reviewerCandidates(for: key, query: nil)
        #expect(result.picker.all.first { $0.name == "sue" }?.isSuggested == true)
        #expect(result.picker.all.first { $0.name == "bob" }?.isSuggested == false)
    }

    @Test func teamsListedAndPaged() async throws {
        let t = QueueTransport([people(), teams([("backend", "Back End")], next: "c1"), teams([("ops", "Ops")])])
        let result = try await api(t).reviewerCandidates(for: key, query: nil)
        #expect(result.teams?.map(\.name) == ["Back End", "Ops"])
        #expect(result.teams?.first?.team == "backend")
        #expect(result.picker.all.filter { $0.team != nil }.map(\.name) == ["Ops"])
        #expect(result.picker.complete)
        #expect((t.bodies[2]["variables"] as? [String: Any])?["after"] as? String == "c1")
    }

    @Test func teamsFailSilently() async throws {
        let result = try await api(QueueTransport([people(), noTeams])).reviewerCandidates(for: key, query: nil)
        #expect(result.teams == nil)
        #expect(result.picker.current.contains { $0.team == "backend" })
    }

    @Test func userOwnedRepoAsksNoTeams() async throws {
        let t = QueueTransport([people(owner: "User")])
        let result = try await api(t).reviewerCandidates(for: key, query: nil)
        #expect(t.bodies.count == 1)
        #expect(result.teams == nil)
    }

    @Test func morePeopleMeansIncomplete() async throws {
        let result = try await api(QueueTransport([people(more: true), teams([])])).reviewerCandidates(for: key, query: nil)
        #expect(!result.picker.complete)
    }

    @Test func theFilterGoesToPeopleAndTeams() async throws {
        let t = QueueTransport([people(), teams([])])
        _ = try await api(t).reviewerCandidates(for: key, query: "bo")
        #expect((t.bodies[0]["variables"] as? [String: Any])?["q"] as? String == "bo")
        #expect((t.bodies[1]["variables"] as? [String: Any])?["q"] as? String == "bo")
    }

    @Test func candidateKeysFollowReviewerKeys() {
        #expect(SetCandidate(id: "U_a", name: "Alice").key == Reviewer.user("Alice").key)
        #expect(SetCandidate(id: "x", name: "Back End", team: "BackEnd").key == "team:backend")
    }
}
