import Foundation
import Testing
@testable import PullBullKit

@Suite struct StatsScreenTextTests {
    private func parts(_ text: String) -> [String] {
        StatValue(text: text, spoken: text).parts.map { $0.isUnit ? "<\($0.text)>" : $0.text }
    }

    @Test func valuePartsSetUnitsApart() {
        #expect(parts("3 h 10 m") == ["3", "<h>", "10", "<m>"])
        #expect(parts("2 d") == ["2", "<d>"])
        #expect(parts("< 1 m") == ["<<>", "1", "<m>"])
    }

    @Test func countsAndUnknownAreOneFigure() {
        #expect(parts("12") == ["12"])
        #expect(parts("137+") == ["137+"])
        #expect(parts("–") == ["–"])
    }

    @Test func periodSpanAndSummary() {
        #expect(StatsPeriod.allCases.map(\.span) == ["Last 7 days", "Last 30 days", "Last 90 days"])
        #expect(StatsPeriod.week.summary == "Today and the 6 days before")
        #expect(StatsPeriod.quarter.summary == "Today and the 89 days before")
    }

    @Test func cardPlaceholders() {
        #expect(StatsCard.reviews.placeholderSpeech(loading: true) == "Your reviews, loading")
        #expect(StatsCard.issues.placeholderSpeech(loading: false) == "Issues, not available")
        #expect(StatsCard.pullRequests.title == "Your pull requests")
    }

    @Test func footerNamesTheAccountAndScope() {
        #expect(StatsFooter.text(login: "dana", org: "acme", capNote: nil) == "From GitHub, for dana in acme")
        #expect(StatsFooter.text(login: "dana", org: nil, capNote: nil) == "From GitHub, for dana in your repositories")
        #expect(StatsFooter.text(login: "dana", org: "acme", capNote: "· from latest 100")
            == "From GitHub, for dana in acme · from latest 100")
    }

    @Test func footerHelpSaysHowOld() {
        let now = Date(timeIntervalSince1970: 1_760_443_200)
        #expect(StatsFooter.help(fetchedAt: now.addingTimeInterval(-240), now: now)
            == "Updated 4 minutes ago. Only repositories PullBull can see.")
        #expect(StatsFooter.help(fetchedAt: nil, now: now) == "Only repositories PullBull can see.")
    }
}
