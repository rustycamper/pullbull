import Testing
@testable import PullBullKit

@Suite struct DraftGateTests {
    private func info(draft: Bool = false, autoMerge: AutoMerge? = nil, canWrite: Bool? = true) -> MergeInfo {
        MergeInfo(
            nodeID: "PR_1", status: .clean, hasConflicts: false, usesMergeQueue: false, isStacked: false,
            isDraft: draft, autoMerge: autoMerge, canEnableAutoMerge: false, canDisableAutoMerge: false,
            canWrite: canWrite, allowedMethods: [.squash], defaultMethod: .squash, base: "main",
            commitCount: 1, approvals: 0, tally: CheckTally(failing: 0, running: 0, total: 0),
            changesRequested: false)
    }

    private func offer(
        _ info: MergeInfo?, state: PRState? = .open, author: String? = "alice", viewer: String? = "me",
        permission: EditPermission = .ready
    ) -> DraftOffer {
        DraftGate.offer(state: state, info: info, author: author, viewer: viewer, permission: permission)
    }

    @Test func authorWithoutWriteGetsMarkReady() {
        #expect(offer(info(draft: true, canWrite: false), author: "Me") == .markReady(autoMergeSet: false))
    }

    @Test func writerOnSomeoneElsesDraftGetsMarkReady() {
        #expect(offer(info(draft: true, canWrite: true)) == .markReady(autoMergeSet: false))
    }

    @Test func readerNotAuthorGetsNothing() {
        #expect(offer(info(draft: true, canWrite: false)) == .hidden)
        #expect(offer(info(draft: false, canWrite: false)) == .hidden)
    }

    @Test func unknownPermissionCountsAsAllowed() {
        #expect(offer(info(draft: true, canWrite: nil)) == .markReady(autoMergeSet: false))
    }

    @Test func closedAndMergedGetNothing() {
        #expect(offer(info(draft: true), state: .closed) == .hidden)
        #expect(offer(info(draft: false), state: .merged) == .hidden)
        #expect(offer(info(draft: true), state: nil) == .hidden)
    }

    @Test func noMergeInfoGetsNothing() {
        #expect(offer(nil) == .hidden)
        #expect(offer(info(draft: true), author: nil) == .hidden)
        #expect(offer(info(draft: true), viewer: nil) == .hidden)
    }

    @Test func aDraftWithAutoMergeSaysSo() {
        #expect(offer(info(draft: true, autoMerge: AutoMerge(enabledBy: "bob"))) == .markReady(autoMergeSet: true))
    }

    @Test func openNotDraftGetsConvert() {
        #expect(offer(info(draft: false)) == .convert)
    }

    @Test func missingPermissionOnADraftShowsTheNote() {
        #expect(offer(info(draft: true), permission: .unavailable) == .permission(.unavailable))
    }

    @Test func missingPermissionOnAnOpenPRHidesConvert() {
        #expect(offer(info(draft: false), permission: .unavailable) == .hidden)
    }
}
