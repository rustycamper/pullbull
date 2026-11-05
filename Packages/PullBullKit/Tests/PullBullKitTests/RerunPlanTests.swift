import Foundation
import Testing
@testable import PullBullKit

private func run(
    _ name: String, _ conclusion: String, suite: String = "COMPLETED", run id: Int64? = nil,
    url: String? = nil
) -> Check {
    Check(
        name: name, state: .failure, url: (url ?? id.map(actions)).flatMap(URL.init(string:)),
        conclusion: conclusion, suiteStatus: suite)
}

private func actions(_ id: Int64) -> String { "https://github.com/o/r/actions/runs/\(id)/job/1" }

private final class PagesStub: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String]
    private var sent: [String] = []
    init(_ pages: [String]) { queue = pages }
    var bodies: [String] { lock.withLock { sent } }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let json = lock.withLock {
            sent.append(String(decoding: body, as: UTF8.self))
            return queue.removeFirst()
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }
}

private func page(_ nodes: String, next: String?) -> String {
    let info = next.map { #"{"hasNextPage":true,"endCursor":"\#($0)"}"# } ?? #"{"hasNextPage":false,"endCursor":null}"#
    return #"{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"pageInfo":\#(info),"nodes":[\#(nodes)]}}}}]}}}}}"#
}

private func node(_ name: String, run id: Int) -> String {
    #"{"__typename":"CheckRun","name":"\#(name)","conclusion":"FAILURE","status":"COMPLETED","detailsUrl":"https://github.com/o/r/actions/runs/\#(id)/job/1","checkSuite":{"status":"COMPLETED"}}"#
}

@Suite struct RerunPlanTests {
    @Test func failureTimedOutAndCancelledCount() {
        let plan = RerunPlan(checks: [
            run("a", "FAILURE", run: 1), run("b", "TIMED_OUT", run: 2), run("c", "CANCELLED", run: 3),
        ])
        #expect(plan.runIDs == [1, 2, 3])
        #expect(!plan.isEmpty)
    }

    @Test func actionRequiredAndStartupFailureDont() {
        let plan = RerunPlan(checks: [
            run("a", "ACTION_REQUIRED", run: 1), run("b", "STARTUP_FAILURE", run: 2), run("c", "SUCCESS", run: 3),
        ])
        #expect(plan.isEmpty)
    }

    @Test func aRunStillGoingIsLeftOut() {
        let plan = RerunPlan(checks: [
            run("a", "FAILURE", suite: "IN_PROGRESS", run: 1), run("b", "FAILURE", suite: "QUEUED", run: 2),
            run("c", "FAILURE", run: 3),
        ])
        #expect(plan.runIDs == [3])
    }

    @Test func externalChecksAreLeftOut() {
        let plan = RerunPlan(checks: [
            Check(name: "ci/circle", state: .failure, url: URL(string: "https://circleci.com/gh/o/r/12")),
            run("app", "FAILURE", url: "https://app.example/checks/9"),
            run("real", "FAILURE", run: 5),
        ])
        #expect(plan.runIDs == [5])
    }

    @Test func onlyExternalFailuresIsEmpty() {
        let plan = RerunPlan(checks: [
            Check(name: "ci/circle", state: .failure, url: nil),
            run("app", "FAILURE", url: "https://app.example/checks/9"),
        ])
        #expect(plan.isEmpty)
        #expect(plan.runIDs == [])
    }

    @Test func runIDComesFromTheDetailsURL() {
        let url = URL(string: "https://github.com/o/r/actions/runs/42093340598/job/1")
        #expect(RerunPlan.runID(from: url) == 42_093_340_598)
        #expect(RerunPlan.runID(from: URL(string: "https://github.com/o/r/actions/runs/7")) == 7)
        #expect(RerunPlan.runID(from: URL(string: "https://github.com/o/r/pull/7")) == nil)
        #expect(RerunPlan.runID(from: URL(string: "https://x.example/actions/runs/abc")) == nil)
        #expect(RerunPlan.runID(from: nil) == nil)
        let plan = RerunPlan(checks: [run("a", "FAILURE", url: actions(42_093_340_598))])
        #expect(plan.runIDs == [42_093_340_598])
    }

    @Test func aFailedCheckWithNoRunIDInItsURLIsLeftOut() {
        let plan = RerunPlan(checks: [run("a", "FAILURE", url: "https://example.com/details")])
        #expect(plan.isEmpty)
    }

    @Test func theDetailQueryDoesNotAskForWorkflowRun() {
        #expect(!Queries.detail.contains("workflowRun"))
        #expect(!Queries.allChecks.contains("workflowRun"))
    }

    @Test func oneEntryPerRun() {
        let plan = RerunPlan(checks: [
            run("a", "FAILURE", run: 4), run("b", "TIMED_OUT", run: 4), run("c", "FAILURE", run: 2),
            run("d", "FAILURE", url: actions(4)),
        ])
        #expect(plan.runIDs == [4, 2])
    }

    @Test func allChecksPagesPastFifty() async throws {
        let first = (0..<100).map { node("job\($0)", run: 1) }.joined(separator: ",")
        let stub = PagesStub([page(first, next: "C1"), page(node("late", run: 8), next: nil)])
        let api = GitHubAPI(transport: stub, auth: StaticTokenSource("t"))
        let checks = try await api.allChecks(PRKey(repo: "o/r", number: 3))
        #expect(checks.count == 101)
        #expect(checks.last?.name == "late")
        #expect(checks.last.flatMap { RerunPlan.runID(from: $0.url) } == 8)
        #expect(checks.last?.conclusion == "FAILURE")
        #expect(checks.last?.suiteStatus == "COMPLETED")
        #expect(stub.bodies.count == 2)
        #expect(!stub.bodies[0].contains("\"after\":"))
        #expect(stub.bodies[1].contains("\"after\":\"C1\""))
    }

    @Test func rerunPostsToTheRunWithAnEmptyBody() async throws {
        let t = RESTQueue([(201, "{}")])
        try await GitHubAPI(transport: t, auth: StaticTokenSource("t"))
            .rerunFailedJobs(PRKey(repo: "o/r", number: 3), runID: 42_093_340_598)
        #expect(t.sent.count == 1)
        #expect(t.sent[0].method == "POST")
        #expect(t.sent[0].path == "/repos/o/r/actions/runs/42093340598/rerun-failed-jobs")
        #expect(t.sent[0].body.isEmpty)
    }

    @Test func rerunRefusalIsAWriteRefusal() async {
        let t = RESTQueue([(403, #"{"message":"Resource not accessible by integration"}"#)])
        await #expect(throws: APIError.writeRefused("Resource not accessible by integration")) {
            try await GitHubAPI(transport: t, auth: StaticTokenSource("t"))
                .rerunFailedJobs(PRKey(repo: "o/r", number: 3), runID: 1)
        }
    }
}
