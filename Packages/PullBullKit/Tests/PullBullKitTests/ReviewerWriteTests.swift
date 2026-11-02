import Foundation
import Testing
@testable import PullBullKit

private let k7 = PRKey(repo: "o/r", number: 7)
private let path = "/repos/o/r/pulls/7/requested_reviewers"
private let backend = Reviewer.team(slug: "backend", name: "Back End")
private let collaborators = #"{"message":"Reviews may only be requested from collaborators."}"#

private func api(_ t: RESTQueue) -> GitHubAPI { GitHubAPI(transport: t, auth: StaticTokenSource("t")) }

@Suite struct ReviewerWriteTests {
    @Test func restRequestShape() throws {
        let body = Data(#"{"reviewers":[]}"#.utf8)
        let request = URLSessionTransport.restRequest("DELETE", path: path, body: body, token: "tok")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/o/r/pulls/7/requested_reviewers")
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody == body)
    }

    @Test func addPostsLoginsAndSlugs() async throws {
        let t = RESTQueue([(201, "{}")])
        let result = try await api(t).changeReviewers(of: k7, adding: [.user("alice"), backend], removing: [])
        #expect(result == SetChangeResult(addApplied: true, removeApplied: true, refusal: nil))
        #expect(t.sent.count == 1)
        #expect(t.sent[0].method == "POST")
        #expect(t.sent[0].path == path)
        #expect(t.sent[0].body["reviewers"] as? [String] == ["alice"])
        #expect(t.sent[0].body["team_reviewers"] as? [String] == ["backend"])
    }

    @Test func teamOnlyRemovalSendsEmptyReviewers() async throws {
        let t = RESTQueue([(200, "{}")])
        _ = try await api(t).changeReviewers(of: k7, adding: [], removing: [backend])
        #expect(t.sent.map(\.method) == ["DELETE"])
        #expect(t.sent[0].body["reviewers"] as? [String] == [])
        #expect(t.sent[0].body["team_reviewers"] as? [String] == ["backend"])
    }

    @Test func personOnlyRemovalSendsNoTeams() async throws {
        let t = RESTQueue([(200, "{}")])
        _ = try await api(t).changeReviewers(of: k7, adding: [], removing: [.user("bob")])
        #expect(t.sent[0].body["reviewers"] as? [String] == ["bob"])
        #expect(t.sent[0].body["team_reviewers"] == nil)
    }

    @Test func addThenRemove() async throws {
        let t = RESTQueue([(201, "{}"), (200, "{}")])
        let result = try await api(t).changeReviewers(of: k7, adding: [.user("alice")], removing: [.user("bob")])
        #expect(t.sent.map(\.method) == ["POST", "DELETE"])
        #expect(result.addApplied && result.removeApplied)
    }

    @Test func refusedAddStillRemoves() async throws {
        let t = RESTQueue([(422, collaborators), (200, "{}")])
        let result = try await api(t).changeReviewers(of: k7, adding: [.user("alice")], removing: [.user("bob")])
        #expect(result == SetChangeResult(
            addApplied: false, removeApplied: true, refusal: "Reviews may only be requested from collaborators."))
    }

    @Test func failedRemoveAfterAddIsPartial() async throws {
        let t = RESTQueue([(201, "{}"), (500, "{}")])
        let result = try await api(t).changeReviewers(of: k7, adding: [.user("alice")], removing: [.user("bob")])
        #expect(result.addApplied)
        #expect(!result.removeApplied)
        #expect(result.refusal != nil)
    }

    @Test func forbiddenKeepsGitHubsMessage() async {
        let t = RESTQueue([(403, #"{"message":"Resource not accessible by integration"}"#)])
        await #expect(throws: APIError.writeRefused("Resource not accessible by integration")) {
            try await api(t).changeReviewers(of: k7, adding: [.user("alice")], removing: [])
        }
    }

    @Test func refusedAddUsesErrorsMessage() async {
        let t = RESTQueue([(422, #"{"message":"Validation Failed","errors":[{"message":"Reviewer can't be the author"}]}"#)])
        await #expect(throws: APIError.writeRefused("Reviewer can't be the author")) {
            try await api(t).changeReviewers(of: k7, adding: [.user("alice")], removing: [])
        }
    }

    @Test func bothRefusedThrows() async {
        let t = RESTQueue([(422, collaborators), (422, #"{"message":"other"}"#)])
        await #expect(throws: APIError.writeRefused("Reviews may only be requested from collaborators.")) {
            try await api(t).changeReviewers(of: k7, adding: [.user("alice")], removing: [.user("bob")])
        }
    }

    @Test func unauthorizedThrows() async {
        let t = RESTQueue([(401, "{}")])
        await #expect(throws: APIError.unauthorized) {
            try await api(t).changeReviewers(of: k7, adding: [.user("alice")], removing: [.user("bob")])
        }
        #expect(t.sent.count == 1)
    }

    @Test func nothingToSendSendsNothing() async throws {
        let t = RESTQueue([])
        let result = try await api(t).changeReviewers(of: k7, adding: [], removing: [])
        #expect(result.addApplied && result.removeApplied)
        #expect(t.sent.isEmpty)
    }
}
