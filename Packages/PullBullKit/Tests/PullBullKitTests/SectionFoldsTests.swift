import Foundation
import Testing
@testable import PullBullKit

@Suite struct SectionFoldsTests {
    @Test func recentlyClosedAndTeamStartFolded() {
        #expect(PRSection.allCases.filter(SectionFolds().isFolded) == [.recentlyClosed, .team])
    }

    @Test func aToggleFoldsOrOpensAndSurvivesASave() throws {
        var s = AppSettings()
        s.sectionFolds.toggle(.team)
        s.sectionFolds.toggle(.needsReview)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(PRSection.allCases.filter(loaded.sectionFolds.isFolded) == [.needsReview, .recentlyClosed])
    }

    @Test func settingsFromBeforeSectionsGetTheDefaults() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"account":"me","lastTab":"team"}"#.utf8))
        #expect(old.sectionFolds == SectionFolds())
        let odd = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"sectionFolds":{"team":"yes","waiting":true}}"#.utf8))
        #expect(PRSection.allCases.filter(odd.sectionFolds.isFolded) == [.waiting, .recentlyClosed, .team])
    }

    @Test func nothingShowsFoldedWhileSearchingOrInASingleSectionScope() {
        let folds = SectionFolds()
        #expect(folds.shownFolded(in: .all, searching: false) == [.recentlyClosed, .team])
        #expect(folds.shownFolded(in: .mine, searching: false) == [.recentlyClosed])
        #expect(folds.shownFolded(in: .team, searching: false) == [])
        #expect(folds.shownFolded(in: .review, searching: false) == [])
        #expect(folds.shownFolded(in: .all, searching: true) == [])
    }

    @Test func allAndMineAreNotGroupedByRepo() {
        var s = AppSettings()
        #expect(PRGrouping.forScope(.all, settings: s, repoFocused: false) == .none)
        #expect(PRGrouping.forScope(.mine, settings: s, repoFocused: false) == .none)
        #expect(PRGrouping.forScope(.review, settings: s, repoFocused: false) == .repository)
        #expect(PRGrouping.forScope(.review, settings: s, repoFocused: true) == .none)
        s.groupTeamByAuthor = true
        #expect(PRGrouping.forScope(.team, settings: s, repoFocused: true) == .author)
        #expect(PRGrouping.forScope(.all, settings: s, repoFocused: false) == .none)
    }
}
