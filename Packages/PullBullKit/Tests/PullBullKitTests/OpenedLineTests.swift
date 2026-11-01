import Foundation
import Testing
@testable import PullBullKit

@Suite struct OpenedLineTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func namesTheLastUpdateTheRowShows() {
        let now = t0 + 4 * 86_400
        #expect(OpenedLine.text(author: "rado", opened: t0, updated: now - 3600, now: now)
            == "rado opened 4d ago · updated 1h ago")
    }

    @Test func leavesOutAnUpdateThatSaysTheSame() {
        let now = t0 + 4.5 * 86_400
        #expect(OpenedLine.text(author: "rado", opened: t0, updated: t0 + 600, now: now) == "rado opened 4d ago")
        #expect(OpenedLine.text(author: "rado", opened: t0, updated: t0 + 20, now: t0 + 30) == "rado opened just now")
    }

    /// A merged or closed item's row shows when it ended, so its page does too, in place of the update.
    @Test func anEndedItemNamesWhenItEnded() {
        let now = t0 + 20 * 86_400
        #expect(OpenedLine.text(author: "rado", opened: t0, updated: now - 3600, ended: "merged Oct 12", now: now)
            == "rado opened 20d ago · merged Oct 12")
        #expect(OpenedLine.text(author: "rado", opened: nil, updated: nil, ended: "closed", now: now)
            == "rado opened · closed")
    }

    /// Issues can lack either date (`BoardIssue`'s are optional).
    @Test func missingDatesLeaveTheirPartOut() {
        let now = t0 + 4 * 86_400
        #expect(OpenedLine.text(author: "rado", opened: nil, updated: nil, now: now) == "rado opened")
        #expect(OpenedLine.text(author: "rado", opened: nil, updated: now - 3600, now: now)
            == "rado opened · updated 1h ago")
        #expect(OpenedLine.text(author: "rado", opened: t0, updated: nil, now: now) == "rado opened 4d ago")
    }
}
