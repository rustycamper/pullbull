import Foundation
import Testing
@testable import PullBullKit

@MainActor private final class Probe {
    var reads = 0, sends = 0, polls = 0, sleeps = 0, willSends = 0
    var uuids: [String] = [], intervals: [Duration] = []
}

@Suite @MainActor struct MergeFlowTests {
    private let key = PRKey(repo: "o/r", number: 88)

    private func info(status: MergeStatus = .clean, failing: Int = 0) -> MergeInfo {
        MergeInfo(
            nodeID: "PR_1", status: status, hasConflicts: false, usesMergeQueue: false, isStacked: false,
            isDraft: false, autoMerge: nil, canEnableAutoMerge: false, canDisableAutoMerge: false,
            canWrite: true, allowedMethods: [.squash], defaultMethod: .squash, base: "main",
            commitCount: 3, approvals: 1,
            tally: CheckTally(failing: failing, running: 0, total: 4), changesRequested: false)
    }

    private func read(
        head: String? = "abc", state: PRState? = .open, offer: MergeOffer = .action(.merge), failing: Int = 0
    ) -> MergeRead {
        MergeRead(
            detail: PRDetail(
                key: key, body: "", checks: [], reviews: [], comments: [], files: [], headOid: head, state: state,
                merge: info(failing: failing)),
            offer: offer)
    }

    private struct Boom: Error {}

    private func run(
        _ probe: Probe, shown: MergeRead? = nil, cancelled: @escaping () -> Bool = { false },
        reads: [Result<MergeRead, any Error>]? = nil,
        send: @escaping () async throws -> MergeRequestState = { .merged },
        polls: [Result<MergeRequestState, any Error>] = []
    ) async -> MergeOutcome {
        let shownFacts = (shown ?? read()).facts
        let answers = reads ?? [.success(read())]
        var pollQueue = polls
        return await MergeFlow.run(
            shown: shownFacts, isCancelled: cancelled,
            read: {
                let answer = answers[min(probe.reads, answers.count - 1)]
                probe.reads += 1
                return try answer.get()
            },
            willSend: { probe.willSends += 1 },
            send: {
                probe.sends += 1
                return try await send()
            },
            poll: { uuid in
                probe.polls += 1
                probe.uuids.append(uuid)
                if pollQueue.isEmpty { return .pending(uuid: "u") }
                return try pollQueue.removeFirst().get()
            },
            sleep: { interval in
                probe.sleeps += 1
                probe.intervals.append(interval)
            })
    }

    @Test func changedFactsSendNothing() async {
        let probe = Probe()
        let fresh = read(failing: 2)
        let outcome = await run(probe, reads: [.success(fresh)])
        #expect(outcome == .changed(fresh))
        #expect(probe.sends == 0 && probe.willSends == 0)
    }

    @Test func movedHeadSendsNothing() async {
        let probe = Probe()
        let outcome = await run(probe, reads: [.success(read(head: "def"))])
        #expect(outcome == .headMoved)
        #expect(probe.sends == 0)
    }

    @Test func anotherMergeWhileOpenSendsNothing() async {
        let probe = Probe()
        let outcome = await run(probe, reads: [.success(read(state: .merged, offer: .reason("x")))])
        #expect(outcome == .notOpen(merged: true))
        #expect(probe.willSends == 0 && probe.sends == 0)
    }

    @Test func aClosedPullRequestSendsNothing() async {
        let probe = Probe()
        let outcome = await run(probe, reads: [.success(read(state: .closed))])
        #expect(outcome == .notOpen(merged: false))
    }

    @Test func anOfferGoneSendsNothing() async {
        let probe = Probe()
        let gone = read(offer: .reason("Merge conflicts."))
        let outcome = await run(probe, reads: [.success(gone)])
        #expect(outcome == .changed(gone))
        #expect(probe.sends == 0)
    }

    @Test func noOfferShownAndReadStillSendsNothing() async {
        let probe = Probe()
        let none = read(offer: .reason("Merge conflicts."))
        let outcome = await run(probe, shown: none, reads: [.success(none)])
        #expect(outcome == .changed(none))
        #expect(probe.sends == 0)
    }

    @Test func cancelDuringTheReadSendsNothing() async {
        let probe = Probe()
        let outcome = await run(probe, cancelled: { probe.reads > 0 })
        #expect(outcome == .cancelled)
        #expect(probe.sends == 0)
    }

    @Test func aReadThatThrowsIsACheckFailure() async {
        let probe = Probe()
        let outcome = await run(probe, reads: [.failure(APIError.writeRefused("no access"))])
        #expect(outcome == .checkFailed("no access"))
        #expect(probe.sends == 0)
    }

    @Test func mergedNeedsNoPoll() async {
        let probe = Probe()
        #expect(await run(probe) == .merged)
        #expect(probe.willSends == 1 && probe.sends == 1 && probe.polls == 0)
    }

    @Test func autoMergeSetNeedsNoPoll() async {
        let probe = Probe()
        let outcome = await run(probe, send: { .autoMergeSet })
        #expect(outcome == .autoMergeSet)
        #expect(probe.polls == 0)
    }

    @Test func enqueuedIsUnknown() async {
        let probe = Probe()
        #expect(await run(probe, send: { .enqueued }) == .unknown)
    }

    @Test func pollsUntilMerged() async {
        let probe = Probe()
        let outcome = await run(
            probe, send: { .pending(uuid: "u") }, polls: [.success(.pending(uuid: "u")), .success(.merged)])
        #expect(outcome == .merged)
        #expect(probe.polls == 2 && probe.sleeps == 2 && probe.sends == 1)
        #expect(probe.uuids == ["u", "u"])
        #expect(probe.intervals == [MergeFlow.pollInterval, MergeFlow.pollInterval])
    }

    @Test func failedPollIsARefusal() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read())], send: { .pending(uuid: "u") },
            polls: [.success(.failed("Required check is expected."))])
        #expect(outcome == .refused("Required check is expected."))
    }

    @Test func failedSendIsARefusal() async {
        let probe = Probe()
        let outcome = await run(probe, send: { .failed("Pull request is closed.") })
        #expect(outcome == .refused("Pull request is closed."))
    }

    @Test func aPollLimitIsUnknown() async {
        let probe = Probe()
        let outcome = await run(probe, send: { .pending(uuid: "u") })
        #expect(outcome == .unknown)
        #expect(probe.polls == MergeFlow.pollLimit)
        #expect(probe.sends == 1)
    }

    @Test func everyPollThrowIsUnknownNotAResend() async {
        let errors: [any Error] = [
            APIError.notFound("gone"), APIError.writeRefused("no"), APIError.unauthorized,
            APIError.rateLimited(resetAt: nil), Boom(),
        ]
        for error in errors {
            let probe = Probe()
            let outcome = await run(probe, send: { .pending(uuid: "u") }, polls: [.failure(error)])
            #expect(outcome == .unknown)
            #expect(probe.sends == 1)
        }
    }

    @Test func aSleepThatThrowsIsUnknown() async {
        let probe = Probe()
        let outcome = await MergeFlow.run(
            shown: read().facts, isCancelled: { false }, read: { read() }, willSend: {},
            send: { probe.sends += 1; return .pending(uuid: "u") }, poll: { _ in .merged },
            sleep: { _ in throw CancellationError() })
        #expect(outcome == .unknown)
        #expect(probe.sends == 1)
    }

    @Test func transportFailureOnSendIsUnknown() async {
        let probe = Probe()
        let outcome = await run(probe, send: { throw CommentTransportError(code: .timedOut) })
        #expect(outcome == .unknown)
    }

    @Test func refusalCarriesGitHubsReason() async {
        let probe = Probe()
        let outcome = await run(probe, send: { throw APIError.writeRefused("Pull request is not mergeable") })
        #expect(outcome == .refused("Pull request is not mergeable"))
        #expect(probe.reads == 2)
    }

    @Test func aRefusalAfterTheHeadMovedReadsAsMoved() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read()), .success(read(head: "def"))],
            send: { throw APIError.writeRefused("Pull request head branch was modified.") })
        #expect(outcome == .headMoved)
    }

    @Test func aFailedPollAfterTheHeadMovedReadsAsMoved() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read()), .success(read(head: "def"))], send: { .pending(uuid: "u") },
            polls: [.success(.failed("Anything at all."))])
        #expect(outcome == .headMoved)
    }

    @Test func aRefusalWhoseReadThrowsKeepsGitHubsWords() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read()), .failure(Boom())],
            send: { throw APIError.writeRefused("Pull request is not mergeable") })
        #expect(outcome == .refused("Pull request is not mergeable"))
    }

    @Test func aFailedPollOnAMergedPRReadsAsMerged() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read()), .success(read(state: .merged))], send: { .pending(uuid: "u") },
            polls: [.success(.failed("Pull request is already merged."))])
        #expect(outcome == .notOpen(merged: true))
    }

    @Test func aClosedPRWithAMovedHeadReadsAsClosed() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read()), .success(read(head: "def", state: .closed))],
            send: { throw APIError.writeRefused("Pull request is closed.") })
        #expect(outcome == .notOpen(merged: false))
    }

    @Test func aMergedPRBeatsCleanStatus() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read()), .success(read(state: .merged))],
            send: { throw APIError.writeRefused("Pull request Pull request is in clean status") })
        #expect(outcome == .notOpen(merged: true))
    }

    @Test func aReadWithNoHeadIsNotAMovedHead() async {
        let probe = Probe()
        let outcome = await run(
            probe, reads: [.success(read()), .success(read(head: nil))],
            send: { throw APIError.writeRefused("Pull request is not mergeable") })
        #expect(outcome == .refused("Pull request is not mergeable"))
    }

    @Test func cleanStatusRefusalBecomesARead() async {
        let probe = Probe()
        let fresh = read()
        let blocked = read(offer: .action(.mergeWhenReady))
        let outcome = await run(
            probe, shown: blocked, reads: [.success(blocked), .success(fresh)],
            send: { throw APIError.writeRefused("Pull request Pull request is in clean status") })
        #expect(outcome == .changed(fresh))
    }

    @Test func aRepositoryLeftOutReadsClearly() async {
        let probe = Probe()
        let outcome = await run(probe, send: { throw APIError.writeRefused("Resource not accessible by integration") })
        #expect(outcome == .refused("PullBull can't reach this repository. Add it to the install on GitHub."))
    }

    @Test func cancelSucceeds() async {
        let outcome = await MergeFlow.cancelAutoMerge(send: {}, stillSet: { Issue.record("asked"); return true })
        #expect(outcome == .cancelled)
    }

    @Test func cancelRefusedSaysWhy() async {
        let outcome = await MergeFlow.cancelAutoMerge(
            send: { throw APIError.writeRefused("Auto merge is not enabled") }, stillSet: { true })
        #expect(outcome == .refused("Auto merge is not enabled"))
    }

    @Test func cancelUnknownThenGoneIsCancelled() async {
        let outcome = await MergeFlow.cancelAutoMerge(
            send: { throw CommentTransportError(code: .timedOut) }, stillSet: { false })
        #expect(outcome == .cancelled)
    }

    @Test func cancelUnknownThenStillSetIsUnknown() async {
        let outcome = await MergeFlow.cancelAutoMerge(
            send: { throw CommentTransportError(code: .timedOut) }, stillSet: { true })
        #expect(outcome == .unknown)
    }

    @Test func cancelUnknownThenACheckThatThrowsIsUnknown() async {
        let outcome = await MergeFlow.cancelAutoMerge(
            send: { throw CommentTransportError(code: .timedOut) }, stillSet: { throw Boom() })
        #expect(outcome == .unknown)
    }
}
