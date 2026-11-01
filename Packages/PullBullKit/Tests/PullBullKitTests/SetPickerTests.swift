import Foundation
import Testing
@testable import PullBullKit

@Suite struct SetPickerTests {
    let key = PRKey(repo: "acme/widgets", number: 412)

    func label(_ name: String, color: String = "ededed") -> SetCandidate {
        SetCandidate(id: "LA_\(name)", name: name, color: color)
    }

    func person(_ login: String) -> SetCandidate {
        SetCandidate(id: "U_\(login)", name: login, avatarURL: URL(string: "https://avatars.example/\(login)"))
    }

    func labelPicker(current: [String]) -> SetPicker {
        SetPicker(field: .labels, key: key, current: current, viewer: "me", permission: .ready)
    }

    func peoplePicker(current: [String], viewer: String = "me") -> SetPicker {
        SetPicker(field: .assignees, key: key, current: current, viewer: viewer, permission: .ready)
    }

    func names(_ picker: SetPicker) -> [String] { picker.rows.map(\.candidate.name) }
    func ticked(_ picker: SetPicker) -> [String] { picker.rows.filter(\.isChecked).map(\.candidate.name) }

    @Test func stillLoadingHasNoChange() {
        let picker = labelPicker(current: ["bug"])
        #expect(picker.isLoading)
        #expect(picker.rows.isEmpty)
        #expect(picker.change == nil)
        #expect(picker.title == "acme/widgets#412")
    }

    @Test func tickedFirstThenViewerThenTheRest() {
        var picker = peoplePicker(current: ["zed", "Ann"])
        let all = ["bob", "me", "ann", "zed", "Cy"].map(person)
        picker.load(SetCandidates(all: all, current: [], complete: true))
        #expect(names(picker) == ["zed", "ann", "me", "bob", "Cy"])
        #expect(ticked(picker) == ["zed", "ann"])
        #expect(!picker.isLoading)
    }

    @Test func labelsKeepGitHubsOrder() {
        var picker = labelPicker(current: ["docs"])
        let all = ["zeta", "bug", "docs", "alpha"].map { label($0) }
        picker.load(SetCandidates(all: all, current: [], complete: true))
        #expect(names(picker) == ["docs", "zeta", "bug", "alpha"])
    }

    @Test func currentFromGitHubJoinsTheCandidates() {
        var picker = labelPicker(current: ["old"])
        picker.load(SetCandidates(all: [label("bug")], current: [label("old")], complete: false))
        #expect(names(picker) == ["old", "bug"])
        #expect(ticked(picker) == ["old"])
        #expect(picker.rows[0].isEnabled)
        #expect(!picker.isComplete)
    }

    @Test func aCurrentValueWithoutCandidateIsTickedAndLocked() throws {
        var picker = labelPicker(current: ["ghost"])
        picker.load(SetCandidates(all: [label("bug")], current: [], complete: true))
        let row = try #require(picker.rows.first)
        #expect(row.id == "missing:ghost")
        #expect(row.isChecked)
        #expect(!row.isEnabled)
        picker.toggleSelected()
        #expect(picker.rows[0].isChecked)
        #expect(picker.change == nil)
    }

    @Test func aLaterCandidateReplacesItsPlaceholder() {
        var picker = labelPicker(current: ["bug", "Ghost"])
        picker.load(SetCandidates(all: [label("bug")], current: [], complete: false))
        picker.move(by: 1)
        #expect(picker.rows[picker.selection].id == "missing:Ghost")
        picker.load(SetCandidates(all: [label("bug"), label("ghost"), label("new")], current: [], complete: true))
        #expect(names(picker) == ["bug", "ghost", "new"])
        #expect(picker.rows[1].isChecked)
        #expect(picker.rows[1].isEnabled)
        #expect(picker.rows[1].id == "LA_ghost")
        #expect(picker.rows[picker.selection].id == "LA_ghost")
        #expect(picker.change == nil)
    }

    @Test func aLabelRenamedMidSessionKeepsOneRowPerID() {
        var picker = labelPicker(current: ["defect"])
        picker.load(SetCandidates(all: [SetCandidate(id: "LA_1", name: "bug", color: "ededed")], current: [], complete: false))
        #expect(names(picker) == ["defect", "bug"])
        picker.move(by: 1)
        #expect(picker.rows[picker.selection].id == "LA_1")
        picker.load(SetCandidates(
            all: [SetCandidate(id: "LA_1", name: "defect", color: "ff0000"), label("docs")], current: [], complete: true))
        #expect(Set(picker.rows.map(\.id)).count == picker.rows.count)
        #expect(names(picker) == ["defect", "docs"])
        #expect(ticked(picker) == ["defect"])
        #expect(picker.rows[picker.selection].id == "LA_1")
        #expect(picker.change == nil)
        picker.toggleSelected()
        #expect(ticked(picker) == [])
        guard case .labels(let added, let removed)? = picker.change else {
            Issue.record("expected a label change")
            return
        }
        #expect(added.isEmpty)
        #expect(removed.map(\.id) == ["LA_1"])
    }

    @Test func aLaterCandidateWithAKnownIDUpdatesItsRowInPlace() {
        var picker = labelPicker(current: [])
        picker.load(SetCandidates(all: [label("bug"), label("docs")], current: [], complete: false))
        picker.move(by: 1)
        picker.toggleSelected()
        picker.load(SetCandidates(
            all: [SetCandidate(id: "LA_docs", name: "documentation", color: "00ff00")], current: [], complete: true))
        #expect(names(picker) == ["bug", "documentation"])
        #expect(ticked(picker) == ["documentation"])
        #expect(picker.rows[picker.selection].id == "LA_docs")
    }

    @Test func aQueryAnswerLeavesIsCompleteAlone() {
        var picker = peoplePicker(current: [])
        picker.load(SetCandidates(all: [person("ann")], current: [], complete: false))
        #expect(!picker.isComplete)
        picker.load(SetCandidates(all: [person("bob")], current: [], complete: true), fromQuery: true)
        #expect(!picker.isComplete)
        #expect(names(picker) == ["ann", "bob"])
        picker.load(SetCandidates(all: [person("bob")], current: [], complete: true))
        #expect(picker.isComplete)
    }

    @Test func filterMatchesPartOfTheNameIgnoringCase() {
        var picker = labelPicker(current: [])
        picker.load(SetCandidates(all: ["Bug", "debug", "docs"].map { label($0) }, current: [], complete: true))
        picker.move(by: 2)
        picker.setFilter("BUG")
        #expect(names(picker) == ["Bug", "debug"])
        #expect(picker.selection == 0)
        #expect(picker.filter == "BUG")
        picker.setFilter("")
        #expect(picker.rows.count == 3)
    }

    @Test func toggleBackAndForthSendsNothing() {
        var picker = labelPicker(current: ["bug"])
        picker.load(SetCandidates(all: [label("bug"), label("docs")], current: [], complete: true))
        picker.toggleSelected()
        #expect(picker.change != nil)
        picker.toggleSelected()
        #expect(picker.change == nil)
        picker.move(by: 1)
        picker.toggleSelected()
        picker.toggleSelected()
        #expect(picker.change == nil)
    }

    @Test func changeListsAddedAndRemovedInRowOrder() {
        var picker = labelPicker(current: ["bug"])
        picker.load(SetCandidates(
            all: [label("bug", color: "d73a4a"), label("docs", color: "0075ca")], current: [], complete: true))
        picker.toggleSelected()
        picker.move(by: 1)
        picker.toggleSelected()
        #expect(picker.change == .labels(
            added: [LabelRef(id: "LA_docs", name: "docs", color: "0075ca")],
            removed: [LabelRef(id: "LA_bug", name: "bug", color: "d73a4a")]))
    }

    @Test func peopleChangeUsesPersonRefs() {
        var picker = peoplePicker(current: [])
        picker.load(SetCandidates(all: [person("ann")], current: [], complete: true))
        picker.toggleSelected()
        #expect(picker.change == .assignees(
            added: [PersonRef(id: "U_ann", login: "ann", avatarURL: URL(string: "https://avatars.example/ann"))],
            removed: []))
    }

    @Test func assigneesStopAtTen() {
        let logins = (0..<12).map { String(format: "u%02d", $0) }
        var picker = peoplePicker(current: Array(logins.prefix(9)), viewer: "nobody")
        picker.load(SetCandidates(all: logins.map(person), current: [], complete: true))
        #expect(picker.rows.allSatisfy { $0.isEnabled })
        picker.move(by: 9)
        picker.toggleSelected()
        #expect(picker.rows.filter(\.isChecked).count == 10)
        #expect(picker.rows.filter { !$0.isChecked }.allSatisfy { !$0.isEnabled })
        picker.move(by: 1)
        picker.toggleSelected()
        #expect(picker.rows.filter(\.isChecked).count == 10)
        picker.move(by: -1)
        picker.toggleSelected()
        #expect(picker.rows.filter(\.isChecked).count == 9)
        #expect(picker.rows.allSatisfy { $0.isEnabled })
    }

    @Test func aLaterLoadKeepsTicksOrderAndSelection() {
        var picker = labelPicker(current: ["bug"])
        picker.load(SetCandidates(all: [label("bug"), label("docs")], current: [], complete: false))
        picker.move(by: 1)
        picker.toggleSelected()
        picker.load(SetCandidates(
            all: [label("zzz"), label("docs"), label("bug"), label("aaa")], current: [], complete: true))
        #expect(names(picker) == ["bug", "docs", "zzz", "aaa"])
        #expect(ticked(picker) == ["bug", "docs"])
        #expect(picker.rows[picker.selection].id == "LA_docs")
    }

    @Test func aFailedLoadWithoutRowsSaysWhy() {
        var picker = labelPicker(current: ["bug"])
        picker.failedToLoad("offline")
        #expect(picker.loadError == "offline")
        #expect(!picker.isLoading)
        #expect(picker.rows.isEmpty)
        #expect(picker.change == nil)
    }

    @Test func aLoadAfterAFailedFirstLoadBuildsTheRows() {
        var picker = labelPicker(current: ["bug"])
        picker.failedToLoad("offline")
        picker.load(SetCandidates(all: [label("docs"), label("bug")], current: [], complete: true))
        #expect(names(picker) == ["bug", "docs"])
        #expect(ticked(picker) == ["bug"])
        #expect(picker.loadError == nil)
        #expect(!picker.isLoading)
        #expect(picker.change == nil)
    }

    @Test func aFailedRefetchKeepsTheCachedRows() {
        var picker = labelPicker(current: [])
        picker.load(SetCandidates(all: [label("bug")], current: [], complete: true))
        picker.failedToLoad("offline")
        #expect(picker.loadError == nil)
        #expect(!picker.isLoading)
        #expect(names(picker) == ["bug"])
    }

    // MARK: Reviewers

    func team(_ slug: String, _ name: String) -> SetCandidate {
        SetCandidate(id: "team:\(slug)", name: name, team: slug)
    }

    func reviewer(_ login: String, verdict: ReviewState? = nil, suggested: Bool = false) -> SetCandidate {
        SetCandidate(id: "U_\(login)", name: login, verdict: verdict, isSuggested: suggested)
    }

    func reviewersPicker(requested: [Reviewer] = [.user("carol"), .team(slug: "backend", name: "Back End")])
        -> SetPicker {
        SetPicker(reviewersOf: key, requested: requested, viewer: "me", permission: .ready)
    }

    /// Carol and Back End requested; bob reviewed; sue suggested; amy, zed and the viewer assignable; team Ops.
    var reviewerAnswer: SetCandidates {
        SetCandidates(
            all: [reviewer("bob", verdict: .approved), reviewer("sue", suggested: true),
                  reviewer("zed"), reviewer("me"), reviewer("amy"), team("ops", "Ops")],
            current: [reviewer("carol", verdict: .commented), team("backend", "Back End")],
            complete: true)
    }

    @Test func reviewerRowOrder() {
        var picker = reviewersPicker()
        picker.load(reviewerAnswer)
        #expect(names(picker) == ["carol", "Back End", "bob", "me", "sue", "amy", "zed", "Ops"])
        #expect(ticked(picker) == ["carol", "Back End"])
        #expect(picker.rows.first { $0.candidate.name == "carol" }?.candidate.verdict == .commented)
    }

    @Test func networkAnswerReordersUntouchedRows() {
        var picker = reviewersPicker()
        picker.load(SetCandidates(all: ["amy", "bob", "me", "sue", "zed"].map(person), current: [], complete: true))
        picker.load(reviewerAnswer)
        #expect(names(picker) == ["carol", "Back End", "bob", "me", "sue", "amy", "zed", "Ops"])
    }

    @Test func noReorderAfterATick() {
        var picker = reviewersPicker()
        picker.load(SetCandidates(all: ["amy", "bob", "me", "sue", "zed"].map(person), current: [], complete: true))
        let before = names(picker)
        picker.move(by: 2)
        picker.toggleSelected()
        picker.load(reviewerAnswer)
        #expect(Array(names(picker).prefix(before.count)) == before)
        #expect(names(picker).last == "Ops")
    }

    @Test func tickingPastReviewerAdds() {
        var picker = reviewersPicker()
        picker.load(reviewerAnswer)
        picker.move(by: 2)
        picker.toggleSelected()
        #expect(picker.change == .reviewers(added: [.user("bob")], removed: []))
    }

    @Test func untickRemovesAndToggleBackSendsNothing() {
        var picker = reviewersPicker()
        picker.load(reviewerAnswer)
        picker.move(by: 1)
        picker.toggleSelected()
        #expect(picker.change == .reviewers(added: [], removed: [.team(slug: "backend", name: "Back End")]))
        picker.toggleSelected()
        #expect(picker.change == nil)
    }

    @Test func missingRequestedTeamShowsByName() {
        var picker = reviewersPicker(requested: [.team(slug: "backend", name: "Back End")])
        picker.load(SetCandidates(all: [person("amy")], current: [], complete: true))
        let row = picker.rows[0]
        #expect(row.candidate.name == "Back End")
        #expect(row.candidate.team == "backend")
        #expect(row.isChecked && row.isEnabled)
        picker.toggleSelected()
        #expect(picker.change == .reviewers(added: [], removed: [.team(slug: "backend", name: "Back End")]))
    }

    /// Provisional until the check against GitHub: no cap is documented.
    @Test func noReviewerCap() {
        let many = (1...12).map { Reviewer.user("p\($0)") }
        var picker = reviewersPicker(requested: many)
        picker.load(SetCandidates(all: (1...12).map { person("p\($0)") } + [person("amy")], current: [], complete: true))
        #expect(picker.rows.allSatisfy { $0.isEnabled })
    }

    @Test func teamAndPersonWithSameNameBothShow() {
        var picker = reviewersPicker(requested: [])
        picker.load(SetCandidates(all: [person("ops"), team("ops", "ops")], current: [], complete: true))
        #expect(names(picker) == ["ops", "ops"])
    }

    @Test func assigneeAndLabelMatchingIsUnchanged() {
        var picker = peoplePicker(current: ["Ann"])
        picker.load(SetCandidates(all: [person("ann")], current: [], complete: true))
        #expect(ticked(picker) == ["ann"])
        #expect(picker.rows[0].isEnabled)
    }
}
