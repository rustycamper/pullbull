import Foundation
import Testing
@testable import PullBullKit

private actor Script: HTTPTransport {
    enum Step: Sendable {
        case reply(String)
        case hang(TestClock)
        case fail(URLError)
    }

    private var steps: [Step]
    private(set) var bodies: [String] = []

    init(_ steps: [Step]) { self.steps = steps }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        bodies.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self).replacingOccurrences(of: "\\/", with: "/"))
        let step = try #require(steps.first, "unexpected request")
        steps.removeFirst()
        switch step {
        case .reply(let json):
            return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        case .fail(let error):
            throw error
        case .hang(let clock):
            try await clock.sleep(for: .seconds(3600))
            throw URLError(.timedOut)
        }
    }
}

private func json(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func toolReply(_ name: String, _ input: [String: Any]) -> Script.Step {
    .reply(json([
        "id": "m", "type": "message", "role": "assistant", "stop_reason": "tool_use",
        "content": [["type": "tool_use", "id": "tu", "name": name, "input": input]],
    ]))
}

private func show(_ keys: [String]) -> Script.Step {
    toolReply("show_results", ["results": keys.map { ["key": $0, "why": "fits"] }, "answer": "Here."])
}

private func searchLocal(_ query: String) -> Script.Step { toolReply("search_local", ["query": query]) }

private func item(_ repo: String, _ number: Int, title: String = "login bug") -> AskItem {
    AskIndexTests.item(repo, number, title: title)
}

private let context = AskContext(scopeName: "acme", isOrg: true, today: Date(timeIntervalSince1970: 1_793_275_200))

private func makeSession(
    _ steps: [Script.Step], items: [AskItem], excluded: Set<String> = [], scope: FetchScope = .org("acme"),
    clock: TestClock = TestClock()
) async throws -> (AskSession, Script) {
    let index = try AskIndex(fileURL: AskIndexTests.tempURL())
    try await index.upsert(items)
    let script = Script(steps)
    let client = AskClient(apiKey: "k", model: .default, transport: script, clock: clock)
    return (AskSession(index: index, client: client, context: context, excluded: excluded, scope: scope), script)
}

@Suite struct AskSessionTests {
    @Test func focusedRepoFiltersRetrieval() async throws {
        let (session, script) = try await makeSession(
            [show(["acme/web#1"])], items: [item("acme/web", 1), item("acme/api", 2)])
        _ = try await session.run("login", focusedRepo: "acme/web", stillSyncing: nil)
        let body = try #require(await script.bodies.first)
        #expect(body.contains("acme/web#1"))
        #expect(!body.contains("acme/api#2"))
    }

    @Test func candidatesRecheckedAgainstExcludeAndCovers() async throws {
        let (session, script) = try await makeSession(
            [show(["acme/web#1"])],
            items: [item("acme/web", 1), item("acme/old", 2), item("Acme/Mixed", 3), item("other/x", 4)],
            excluded: ["acme/old", "acme/mixed"], scope: .personal(login: "acme", repos: ["acme/web", "acme/old", "acme/mixed"]))
        _ = try await session.run("login", focusedRepo: nil, stillSyncing: nil)
        let body = try #require(await script.bodies.first)
        #expect(body.contains("acme/web#1"))
        #expect(!body.contains("acme/old#2"))
        #expect(!body.contains("Acme/Mixed#3"))
        #expect(!body.contains("other/x#4"))
    }

    @Test func moreExcludesShown() async throws {
        let corpus = (1...25).map { item("acme/web", $0) } + [item("acme/web", 100, title: "login retry")]
        let (session, script) = try await makeSession(
            [searchLocal("login"), show(["acme/web#100"])], items: corpus)
        let outcome = try await session.run("login", focusedRepo: nil, stillSyncing: nil)
        let bodies = await script.bodies
        #expect(bodies.count == 2)
        func numbers(_ text: Substring) -> Set<Int> {
            Set(text.matches(of: /acme\/web#(\d+)/).compactMap { Int($0.output.1) }).subtracting([123])
        }
        let first = numbers(bodies[0][...])
        #expect(first.count == AskSession.firstCards)
        // The follow-up request carries each first-batch card once (the opening message), so the tool result repeats none.
        let all = bodies[1].matches(of: /acme\/web#(\d+)/).compactMap { Int($0.output.1) }.filter { $0 != 123 }
        for number in first { #expect(all.filter { $0 == number }.count == 1) }
        #expect(!Set(all).subtracting(first).isEmpty)
        guard case .answered(_, _, let rows, _) = outcome else { Issue.record("expected answered"); return }
        #expect(rows.map(\.key.number) == [100])
    }

    @Test func rowsFollowResultOrder() async throws {
        let (session, _) = try await makeSession(
            [show(["acme/web#3", "acme/web#1", "acme/web#2", "acme/web#99"])],
            items: [item("acme/web", 1), item("acme/web", 2), item("acme/web", 3)])
        let outcome = try await session.run("login", focusedRepo: nil, stillSyncing: 4)
        guard case .answered(let question, let answer, let rows, let syncing) = outcome else {
            Issue.record("expected answered"); return
        }
        #expect(question == "login")
        #expect(answer.answer == "Here.")
        #expect(rows.map(\.key.number) == [3, 1, 2])
        #expect(syncing == 4)
    }

    @Test func clientErrorBecomesFailed() async throws {
        let (session, _) = try await makeSession(
            [.reply(json(["id": "m", "type": "message", "role": "assistant", "stop_reason": "refusal", "content": []]))],
            items: [item("acme/web", 1)])
        let outcome = try await session.run("login", focusedRepo: nil, stillSyncing: nil)
        #expect(outcome == .failed(question: "login", .refusal))
    }

    @Test func cancelledRunReturnsNothingVisible() async throws {
        let clock = TestClock()
        let (session, script) = try await makeSession([.hang(clock)], items: [item("acme/web", 1)], clock: clock)
        let task = Task { try await session.run("login", focusedRepo: nil, stillSyncing: nil) }
        while await script.bodies.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func urlErrorCancelledIsRethrown() async throws {
        let (session, _) = try await makeSession([.fail(URLError(.cancelled))], items: [item("acme/web", 1)])
        await #expect(throws: URLError.self) { try await session.run("login", focusedRepo: nil, stillSyncing: nil) }
    }
}
