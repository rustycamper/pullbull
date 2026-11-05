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
