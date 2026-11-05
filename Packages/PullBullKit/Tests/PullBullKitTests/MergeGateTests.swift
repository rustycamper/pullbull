import Testing
@testable import PullBullKit

@Suite struct MergeGateTests {
    private func info(
        status: MergeStatus = .clean, conflicts: Bool = false, queue: Bool = false, stacked: Bool = false,
        draft: Bool = false, autoMerge: AutoMerge? = nil, canEnable: Bool = false, canDisable: Bool = false,
        canWrite: Bool? = true, methods: [MergeMethod] = [.squash]
    ) -> MergeInfo {
        MergeInfo(
            nodeID: "PR_1", status: status, hasConflicts: conflicts, usesMergeQueue: queue, isStacked: stacked,
            isDraft: draft, autoMerge: autoMerge, canEnableAutoMerge: canEnable, canDisableAutoMerge: canDisable,
            canWrite: canWrite, allowedMethods: methods, defaultMethod: methods.first, base: "main",
            commitCount: 1, approvals: 0, tally: CheckTally(failing: 0, running: 0, total: 0),
            changesRequested: false)
    }

    private func offer(
        _ info: MergeInfo?, state: PRState? = .open, viewer: String? = "me", permission: EditPermission = .ready
    ) -> MergeOffer {
        MergeGate.offer(state: state, info: info, viewer: viewer, permission: permission)
    }

    @Test func stackGivesItsLine() {
        #expect(offer(info(stacked: true)) == .reason("Part of a stack. Merge it on GitHub."))
    }

    @Test func queueGivesItsLine() {
        #expect(offer(info(queue: true)) == .reason("Uses a merge queue. Add it on GitHub."))
    }

    @Test func viewerAutoMergeOffersCancel() {
        let auto = AutoMerge(enabledBy: "me")
        #expect(offer(info(autoMerge: auto, canDisable: true)) == .cancelAutoMerge)
    }

    @Test func viewerAutoMergeOffersCancelOnlyWhenGitHubAllows() {
        let auto = AutoMerge(enabledBy: "me")
        #expect(offer(info(autoMerge: auto, canDisable: false)) == .reason("Auto-merge set by @me. Change it on GitHub."))
    }

    @Test func someoneElsesAutoMergeNamesThem() {
        let auto = AutoMerge(enabledBy: "sam")
        #expect(offer(info(autoMerge: auto, canDisable: true)) == .reason("Auto-merge set by @sam. Change it on GitHub."))
    }

    @Test func autoMergeWithNoNameSaysSo() {
        let auto = AutoMerge(enabledBy: nil)
        #expect(offer(info(autoMerge: auto)) == .reason("Auto-merge is set. Change it on GitHub."))
    }

    @Test func aViewersAutoMergeOverlayOffersCancel() {
        let auto = AutoMerge(enabledBy: "me")
        #expect(offer(info(status: .blocked, autoMerge: auto, canDisable: true)) == .cancelAutoMerge)
    }

    @Test func cleanUnstableAndHooksOfferMerge() {
        for status in [MergeStatus.clean, .unstable, .hasHooks] {
            #expect(offer(info(status: status)) == .action(.merge))
        }
    }

    @Test func blockedWithAutoMergeOffersMergeWhenReady() {
        #expect(offer(info(status: .blocked, canEnable: true)) == .action(.mergeWhenReady))
    }

    @Test func conflictsGiveTheirLine() {
        let line = MergeOffer.reason("Merge conflicts. Resolve them on GitHub.")
        #expect(offer(info(status: .dirty)) == line)
        #expect(offer(info(status: .behind, conflicts: true)) == line)
    }

    @Test func conflictsOutrankBlocked() {
        #expect(offer(info(status: .blocked, conflicts: true, canEnable: false))
            == .reason("Merge conflicts. Resolve them on GitHub."))
    }

    @Test func behindGivesItsLine() {
        #expect(offer(info(status: .behind)) == .reason("Behind the base branch. Update it on GitHub."))
    }

    @Test func blockedWithoutAutoMergeGivesTheRulesLine() {
        #expect(offer(info(status: .blocked, canEnable: false)) == .reason("This branch's rules aren't met yet."))
    }

    @Test func unknownWaits() {
        #expect(offer(info(status: .unknown)) == .waiting)
    }

    @Test func closedDraftOrNoWriteAccessIsHidden() {
        #expect(offer(info(), state: .closed) == .hidden)
        #expect(offer(info(), state: .merged) == .hidden)
        #expect(offer(info(draft: true)) == .hidden)
        #expect(offer(info(canWrite: false)) == .hidden)
    }

    @Test func unknownWriteAccessStillOffers() {
        #expect(offer(info(canWrite: nil)) == .action(.merge))
    }

    @Test func cachedDetailIsHidden() {
        #expect(offer(nil) == .hidden)
    }

    @Test func stackOutranksEverything() {
        let auto = AutoMerge(enabledBy: "me")
        #expect(offer(info(queue: true, stacked: true, autoMerge: auto, canDisable: true))
            == .reason("Part of a stack. Merge it on GitHub."))
    }

    @Test func queueOutranksCleanAndAutoMerge() {
        let auto = AutoMerge(enabledBy: "me")
        #expect(offer(info(queue: true, autoMerge: auto, canDisable: true))
            == .reason("Uses a merge queue. Add it on GitHub."))
        #expect(offer(info(status: .clean, queue: true)) == .reason("Uses a merge queue. Add it on GitHub."))
    }

    @Test func aMergeOnItsWayOffersNothing() {
        #expect(offer(info(status: .clean), state: .merged) == .hidden)
    }

    @Test func retriesUnknownAndAStaleBlockedOnly() {
        #expect(MergeRetry.shouldRetry(info(status: .unknown), afterReview: false))
        #expect(MergeRetry.shouldRetry(info(status: .unknown), afterReview: true))
        #expect(!MergeRetry.shouldRetry(info(status: .blocked), afterReview: false))
        #expect(MergeRetry.shouldRetry(info(status: .blocked), afterReview: true))
        #expect(!MergeRetry.shouldRetry(info(status: .clean), afterReview: true))
        #expect(!MergeRetry.shouldRetry(nil, afterReview: true))
        #expect(MergeRetry.limit == 3)
        #expect(MergeRetry.interval == .seconds(2))
    }

    @Test func oldPermissionsReplaceTheButtonOnly() {
        let needs = EditPermission.needsAppApproval(owner: "acme", isOrganization: true, url: nil)
        #expect(offer(info(status: .clean), permission: needs) == .permission(needs))
        #expect(offer(info(status: .blocked, canEnable: true), permission: needs) == .permission(needs))
        let auto = AutoMerge(enabledBy: "me")
        #expect(offer(info(autoMerge: auto, canDisable: true), permission: needs) == .permission(needs))
        #expect(offer(info(status: .dirty), permission: needs) == .reason("Merge conflicts. Resolve them on GitHub."))
        #expect(offer(info(stacked: true), permission: needs) == .reason("Part of a stack. Merge it on GitHub."))
    }

    @Test func noInstallIsAPermissionLine() {
        #expect(offer(info(status: .clean), permission: .unavailable) == .permission(.unavailable))
    }

    @Test func noMethodLeftGivesTheRulesLine() {
        #expect(offer(info(status: .clean, methods: [])) == .reason("This branch's rules aren't met yet."))
    }
}
