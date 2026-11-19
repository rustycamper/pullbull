import Foundation
import Testing
@testable import PullBullKit

private func api(_ t: any GraphQLTransport) -> GitHubAPI { GitHubAPI(transport: t, auth: StaticTokenSource("t")) }

private func answer(_ payload: String) -> String {
    #"{"data":{"\#(payload)":{"subject":{"id":"IC_1","viewerCanReact":true,"reactionGroups":[{"content":"HOORAY","viewerHasReacted":true,"reactors":{"totalCount":2,"nodes":[{"login":"a"},{"login":"b"}]}}]}}}}"#
}

@Suite struct ReactionAPITests {
    @Test func addSendsSubjectAndContentAndReturnsTheGroups() async throws {
        let t = GraphQLQueue([answer("addReaction")])
        let reactions = try await api(t).addReaction(.hooray, to: "IC_1")
        let variables = try #require(t.sent.first?["variables"] as? [String: Any])
        #expect(variables["s"] as? String == "IC_1")
        #expect(variables["c"] as? String == "HOORAY")
        #expect((t.sent.first?["query"] as? String)?.contains("addReaction(") == true)
        #expect(reactions.subjectId == "IC_1")
        let group = try #require(reactions.groups.first { $0.content == .hooray })
        #expect(group.count == 2)
        #expect(group.viewerHasReacted)
    }

    @Test func removeSendsRemoveReaction() async throws {
        let t = GraphQLQueue([answer("removeReaction")])
        let reactions = try await api(t).removeReaction(.hooray, from: "IC_1")
        let variables = try #require(t.sent.first?["variables"] as? [String: Any])
        #expect(variables["s"] as? String == "IC_1")
        #expect(variables["c"] as? String == "HOORAY")
        #expect((t.sent.first?["query"] as? String)?.contains("removeReaction(") == true)
        #expect(reactions.subjectId == "IC_1")
    }

    @Test func aForbiddenErrorIsARefusal() async {
        let t = GraphQLQueue([#"{"errors":[{"type":"FORBIDDEN","message":"m"}]}"#])
        await #expect(throws: APIError.writeRefused("m")) { try await api(t).addReaction(.eyes, to: "IC_1") }
    }

    @Test func anInternalErrorStaysUnknown() async {
        let t = GraphQLQueue([#"{"data":{"addReaction":null},"errors":[{"type":"INTERNAL","message":"boom"}]}"#])
        await #expect(throws: APIError.graphQL("boom")) { try await api(t).addReaction(.eyes, to: "IC_1") }
    }

    @Test func aPayloadWithoutSubjectStaysUnknown() async {
        let t = GraphQLQueue([#"{"data":{"addReaction":{"subject":null}}}"#])
        await #expect(throws: APIError.self) { try await api(t).addReaction(.eyes, to: "IC_1") }
    }
}
