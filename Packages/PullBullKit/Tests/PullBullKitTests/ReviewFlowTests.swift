import Foundation
import Testing
@testable import PullBullKit

@MainActor
private final class Calls {
    var events: [String] = []
    var cancelled = false
}

@MainActor
private func run(
    pinned: String = "abcdef1234567", head: Result<PRHead, any Error>, calls: Calls,
    cancelAfterRead: Bool = false, send: Result<Void, any Error> = .success(())
) async -> ReviewOutcome {
    await ReviewFlow.run(
        pinned: pinned, isCancelled: { calls.cancelled },
        readHead: {
            defer { if cancelAfterRead { calls.cancelled = true } }
            return try head.get()
        },
        willSend: { calls.events.append("willSend") },
        send: { commit in
            calls.events.append("send:\(commit)")
            try send.get()
        })
}

@MainActor @Suite struct ReviewFlowTests {
    @Test func matchingHeadSends() async {
        let calls = Calls()
        let outcome = await run(head: .success(PRHead(oid: "abcdef1234567", state: .open)), calls: calls)
        #expect(outcome == .sent)
        #expect(calls.events == ["willSend", "send:abcdef1234567"])
    }

    @Test func movedHeadNeverSends() async {
        let calls = Calls()
        let outcome = await run(head: .success(PRHead(oid: "ffffff", state: .open)), calls: calls)
        #expect(outcome == .headMoved)
        #expect(calls.events.isEmpty)
    }

    @Test func mergedAndClosedNeverSend() async {
        for (state, merged) in [(PRState.merged, true), (.closed, false)] {
            let calls = Calls()
            let outcome = await run(head: .success(PRHead(oid: "abcdef1234567", state: state)), calls: calls)
            #expect(outcome == .notOpen(merged: merged))
            #expect(calls.events.isEmpty)
        }
    }

    @Test func failedReadNeverSends() async {
        let calls = Calls()
        let outcome = await run(head: .failure(APIError.writeRefused("no")), calls: calls)
        #expect(outcome == .checkFailed("no"))
        #expect(calls.events.isEmpty)
    }

    @Test func unknownReadFailureUsesRefreshMessage() async {
        let calls = Calls()
        let error = APIError.network("x")
        let outcome = await run(head: .failure(error), calls: calls)
        #expect(outcome == .checkFailed(RefreshError(error).message))
    }

    @Test func cancelledDuringReadNeverSends() async {
        for head in [Result<PRHead, any Error>.success(PRHead(oid: "abcdef1234567", state: .open)),
                     .success(PRHead(oid: "ffffff", state: .open)),
                     .success(PRHead(oid: "abcdef1234567", state: .merged)),
                     .failure(APIError.writeRefused("no"))] {
            let calls = Calls()
            let outcome = await run(head: head, calls: calls, cancelAfterRead: true)
            #expect(outcome == .cancelled)
            #expect(calls.events.isEmpty)
        }
    }

    @Test func refusedSend() async {
        let calls = Calls()
        let outcome = await run(
            head: .success(PRHead(oid: "abcdef1234567", state: .open)), calls: calls,
            send: .failure(APIError.writeRefused("can only have one pending review")))
        #expect(outcome == .refused("can only have one pending review"))
        #expect(calls.events.count == 2)
    }

    @Test func unknownSend() async {
        let calls = Calls()
        let outcome = await run(
            head: .success(PRHead(oid: "abcdef1234567", state: .open)), calls: calls,
            send: .failure(APIError.network("timeout")))
        #expect(outcome == .unknown)
    }
}

@Suite struct ReviewCheckTests {
    private let since = Date(timeIntervalSince1970: 10_000)

    private func review(
        _ state: ReviewState = .approved, by author: String = "PB", at offset: TimeInterval? = 0
    ) -> Review {
        Review(author: author, state: state, submittedAt: offset.map { since.addingTimeInterval($0) })
    }

    @Test func landedMatchesStateLoginAndTime() {
        #expect(ReviewCheck.landed(.approve, by: "pb", since: since, in: [review()]) != nil)
        #expect(ReviewCheck.landed(.approve, by: "pb", since: since, in: [review(at: -59)]) != nil)
        #expect(ReviewCheck.landed(.approve, by: "pb", since: since, in: [review(at: -61)]) == nil)
        #expect(ReviewCheck.landed(.approve, by: "pb", since: since, in: [review(.pending)]) == nil)
        #expect(ReviewCheck.landed(.approve, by: "pb", since: since, in: [review(at: nil)]) == nil)
        #expect(ReviewCheck.landed(.approve, by: "pb", since: since, in: [review(.changesRequested)]) == nil)
        #expect(ReviewCheck.landed(.approve, by: "pb", since: since, in: [review(by: "other")]) == nil)
        #expect(ReviewCheck.landed(.requestChanges, by: "pb", since: since, in: [review(.changesRequested)]) != nil)
    }
}
