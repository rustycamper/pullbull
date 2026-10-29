import Foundation
import Testing
@testable import PullBullKit

private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!, statusCode: status,
        httpVersion: nil, headerFields: headers)!
}

private final class StubTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Data, HTTPURLResponse)]
    private var sent: [Data] = []

    init(_ responses: [(Data, HTTPURLResponse)]) { queue = responses }

    var bodies: [Data] { lock.withLock { sent } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            sent.append(body)
            return queue.removeFirst()
        }
    }
}

private func api(_ transport: StubTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"), now: { Date() })
}

private func fixtureData() throws -> Data {
    let url = try #require(Bundle.module.url(
        forResource: "ask-search-page", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct AskFetchTests {
    @Test func askPageDecodesPRAndIssue() async throws {
        let stub = StubTransport([(try fixtureData(), response(200))])
        let page = try await api(stub).askPage(query: "org:acme", after: nil)
        #expect(page.items.map(\.kind) == [.pr, .pr, .issue])
        #expect(page.items.map(\.state) == ["merged", "draft", "open"])
        #expect(page.items.allSatisfy { $0.key.repo == "acme/web" })
        #expect(page.items.map(\.key.number) == [7, 8, 9])
        #expect(page.items[0].labels == ["bug", "ui"])
        #expect(page.items[0].author == "alice")
        #expect(page.items[0].baseRef == "main")
        #expect(page.items[0].mergedAt == Date(timeIntervalSince1970: 1_791_192_600))
        #expect(page.items[1].author == nil)
        #expect(page.items[2].baseRef == nil)
        #expect(page.items[2].body == "After reconnect.")
        #expect(page.total == 137)
        #expect(page.next == "A1")
    }

    @Test func askPageNextIsNilOnLastPage() async throws {
        let json = #"{"data":{"search":{"issueCount":0,"pageInfo":{"endCursor":"Z","hasNextPage":false},"nodes":[]}}}"#
        let stub = StubTransport([(Data(json.utf8), response(200))])
        let page = try await api(stub).askPage(query: "q", after: "A0")
        #expect(page.items.isEmpty)
        #expect(page.next == nil)
    }

    @Test func askPageSendsQueryAndPageSize50() async throws {
        let stub = StubTransport([(try fixtureData(), response(200))])
        _ = try await api(stub).askPage(query: "org:acme updated:>2026-10-01", after: "C1")
        let body = try #require(stub.bodies.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try #require(object["variables"] as? [String: Any])
        #expect(variables["q"] as? String == "org:acme updated:>2026-10-01")
        #expect(variables["first"] as? Int == 50)
        #expect(variables["after"] as? String == "C1")
    }

    @Test func askPageRateLimitThrows() async {
        let headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1793050000"]
        let stub = StubTransport([(Data("{}".utf8), response(403, headers: headers))])
        await #expect(throws: APIError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_793_050_000))) {
            try await api(stub).askPage(query: "q", after: nil)
        }
    }
}
