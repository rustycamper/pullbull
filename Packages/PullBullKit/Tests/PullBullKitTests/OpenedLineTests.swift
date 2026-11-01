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
}
