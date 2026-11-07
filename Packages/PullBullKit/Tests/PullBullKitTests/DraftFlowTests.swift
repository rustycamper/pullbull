import Foundation
import Testing
@testable import PullBullKit

@Suite @MainActor struct DraftFlowTests {
    private let key = PRKey(repo: "o/r", number: 88)

    private struct ReadFailed: Error {}

    private func detail(isDraft: Bool) -> PRDetail {
        let merge = MergeInfo(
            nodeID: "PR_1", status: .clean, hasConflicts: false, usesMergeQueue: false, isStacked: false,
            isDraft: isDraft, autoMerge: nil, canEnableAutoMerge: false, canDisableAutoMerge: false,
            canWrite: true, allowedMethods: [.squash], defaultMethod: .squash, base: "main",
            commitCount: 3, approvals: 1, tally: CheckTally(failing: 0, running: 0, total: 4), changesRequested: false)
        return PRDetail(
            key: key, body: "", checks: [], reviews: [], comments: [], files: [], headOid: "abc", state: .open, merge: merge)
    }

    private final class Counts {
        var sends = 0, reads = 0
        var sleeps: [Duration] = []
    }

    /// `reads` is what each read gives, in order; nil throws. The last one repeats.
    private func run(
        toDraft: Bool = false, send: Result<Bool, any Error>, reads: [Bool?] = [false]
    ) async -> (outcome: DraftOutcome, read: PRDetail?, counts: Counts) {
        let counts = Counts()
        let result = await DraftFlow.run(
            toDraft: toDraft,
            send: {
                counts.sends += 1
                return try send.get()
            },
            read: {
                let index = min(counts.reads, reads.count - 1)
                counts.reads += 1
                guard let isDraft = reads[index] else { throw ReadFailed() }
                return detail(isDraft: isDraft)
            },
            sleep: { counts.sleeps.append($0) })
        return (result.outcome, result.read, counts)
    }

    @Test func aMatchingAnswerIsDoneWithoutARead() async {
        let result = await run(send: .success(false))
        #expect(result.outcome == .done)
        #expect(result.counts.reads == 0)
        #expect(result.read == nil)
    }

    @Test func aMismatchedAnswerConfirmsWithUpToThreeReads() async {
        let result = await run(send: .success(true), reads: [true, true, false])
        #expect(result.outcome == .done)
        #expect(result.counts.reads == 3)
        #expect(result.counts.sleeps == [MergeFlow.unknownReadGap, MergeFlow.unknownReadGap])
    }

    @Test func aMismatchedAnswerNeverShownIsUnknownAfterThreeReads() async {
        let result = await run(send: .success(true), reads: [true])
        #expect(result.outcome == .unknown)
        #expect(result.counts.reads == 3)
        #expect(result.read?.merge?.isDraft == true)
    }

    @Test func aRefusalWhoseReadShowsTheAskedStateIsDone() async {
        let result = await run(send: .failure(APIError.writeRefused("nope")), reads: [false])
        #expect(result.outcome == .done)
        #expect(result.read != nil)
    }

    @Test func aRefusalWhoseReadDoesNotShowItIsRefusedWithGitHubsReason() async {
        let result = await run(send: .failure(APIError.writeRefused("nope")), reads: [true])
        #expect(result.outcome == .refused("nope"))
    }

    @Test func anIntegrationRefusalReadsAsNotReachable() async {
        let result = await run(
            send: .failure(APIError.writeRefused("Resource not accessible by integration")), reads: [true])
        #expect(result.outcome == .refused(MergeFlow.notReachable))
    }

    @Test func aRefusalReadsOnce() async {
        let result = await run(send: .failure(APIError.writeRefused("nope")), reads: [true])
        #expect(result.counts.reads == 1)
        #expect(result.counts.sleeps.isEmpty)
    }

    @Test func aRefusalWhoseReadFailsIsStillRefused() async {
        let result = await run(send: .failure(APIError.writeRefused("nope")), reads: [nil])
        #expect(result.outcome == .refused("nope"))
        #expect(result.read == nil)
    }

    @Test func anUnknownAnswerWhoseReadsFailIsUnknown() async {
        let result = await run(send: .failure(CommentTransportError(code: .timedOut)), reads: [nil])
        #expect(result.outcome == .unknown)
        #expect(result.read == nil)
        #expect(result.counts.reads == 3)
    }

    @Test func aConvertToDraftChecksForDraft() async {
        let result = await run(toDraft: true, send: .success(false), reads: [true])
        #expect(result.outcome == .done)
        #expect(result.counts.reads == 1)
    }

    @Test func itNeverSendsTwice() async {
        for send in [
            Result<Bool, any Error>.success(true), .success(false),
            .failure(APIError.writeRefused("nope")), .failure(CommentTransportError(code: .timedOut)),
        ] {
            let result = await run(send: send, reads: [true])
            #expect(result.counts.sends == 1)
        }
    }
}
