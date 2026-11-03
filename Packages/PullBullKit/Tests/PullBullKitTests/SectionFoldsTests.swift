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

    @Test func restOfTheBoardStartsFolded() {
        let folds = SectionFolds()
        #expect(IssueSection.allCases.filter(folds.isFolded) == [.restOfBoard])
        var toggled = folds
        toggled.toggle(.restOfBoard)
        #expect(!toggled.isFolded(.restOfBoard))
        #expect(toggled.isFolded(PRSection.team))
        toggled.toggle(.assignedToYou)
        #expect(toggled.isFolded(.assignedToYou))
        #expect(!toggled.isFolded(PRSection.needsReview))
    }

    @Test func nothingFoldsWhileSearching() {
        let issue = BoardIssue(key: PRKey(repo: "o/a", number: 1), title: "i", url: URL(string: "https://x/1")!, isOpen: true)
        let list = IssueList(
            sections: [
                IssueListSection(section: .assignedToYou, issues: [issue], state: .rows),
                IssueListSection(section: .restOfBoard, issues: [issue], state: .rows),
            ],
            status: [:], nothingAssigned: false, isEmpty: false)
        let folds = SectionFolds()
        #expect(folds.shownFolded(issues: list, searching: false) == [.restOfBoard])
        #expect(folds.shownFolded(issues: list, searching: true) == [])
        var open = folds
        open.toggle(.restOfBoard)
        open.toggle(.youOpened)
        #expect(open.shownFolded(issues: list, searching: false) == [])
    }
}
