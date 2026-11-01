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

    @Test func aFailedRefetchKeepsTheCachedRows() {
        var picker = labelPicker(current: [])
        picker.load(SetCandidates(all: [label("bug")], current: [], complete: true))
        picker.failedToLoad("offline")
        #expect(picker.loadError == nil)
        #expect(!picker.isLoading)
        #expect(names(picker) == ["bug"])
    }
}
