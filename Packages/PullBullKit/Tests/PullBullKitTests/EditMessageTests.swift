import Testing
@testable import PullBullKit

@Suite struct ReviewMessageTests {
    private let key = PRKey(repo: "acme/app", number: 88)

    @Test func reviewLines() {
        #expect(EditMessage.reviewRefused(on: key, reason: "nope") == "Couldn't review #88: nope")
        #expect(EditMessage.reviewUnconfirmed(on: key)
            == "Couldn't confirm your review of #88. Check the Reviewers section before sending again.")
        #expect(EditMessage.reviewHeadMoved(on: key)
            == "New commits on #88 since you started reviewing. Look again, then review.")
        #expect(EditMessage.reviewNotOpen(on: key, merged: true) == "#88 was merged.")
        #expect(EditMessage.reviewNotOpen(on: key, merged: false) == "#88 was closed.")
    }
}

@Suite struct MergeMessageTests {
    private let key = PRKey(repo: "acme/app", number: 88)

    @Test func mergeLinesReadAsWritten() {
        #expect(EditMessage.mergeRefused(on: key, reason: "nope") == "Couldn't merge #88: nope")
        #expect(EditMessage.mergeCheckFailed(on: key, reason: "offline") == "Couldn't check #88 before merging: offline")
        #expect(EditMessage.mergeUnconfirmed(on: key)
            == "Couldn't confirm the merge of #88. Check it before trying again.")
        #expect(EditMessage.mergeHeadMoved(on: key) == "New commits on #88 since you opened this. Look again, then merge.")
        #expect(EditMessage.autoMergeCancelRefused(on: key, reason: "nope") == "Couldn't cancel auto-merge on #88: nope")
        #expect(EditMessage.autoMergeCancelUnconfirmed(on: key)
            == "Couldn't confirm auto-merge was cancelled on #88. Check it on GitHub.")
    }
}
