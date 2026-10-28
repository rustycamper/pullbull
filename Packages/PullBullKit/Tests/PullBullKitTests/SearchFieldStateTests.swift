import Foundation
import Testing
@testable import PullBullKit

private func people(_ logins: [String]) -> PeopleIndex {
    PeopleIndex.build(Snapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_790_000_000),
        org: OrgContext(org: "o", viewer: "viewer", members: logins, myTeams: [], repos: []),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
        boardProject: nil, boardTitle: nil, boardError: nil,
        assignedIssues: nil, createdIssues: nil, boardStatusOptions: nil))
}

private let g = people(["geordi", "geordie", "gina", "alice"])

/// Types `text` with the caret at its end.
@discardableResult
private func type(_ text: String, into state: inout SearchFieldState, people: PeopleIndex = g) -> SearchQuery? {
    state.edit(text, caret: text.utf16.count, people: people)
}

@Suite struct SearchFieldStateTests {
    @Test func typingATokenOpensTheListWithoutSearching() {
        var state = SearchFieldState()
        #expect(type("@ge", into: &state) == nil)
        #expect(state.completion?.token.prefix == "ge")
        #expect(state.query == .empty)
    }

    // I2: a caret move may close the list, never open it, and never takes a completed name out of the query.
    @Test func caretOntoACompletedNameDoesNotOpenTheList() {
        var state = SearchFieldState()
        #expect(type("@alice ", into: &state) == .filtered(logins: ["alice"], labels: [], words: []))
        #expect(state.completion == nil)
        #expect(state.caretMoved(to: 6, people: g) == nil)
        #expect(state.completion == nil)
        #expect(state.query == .filtered(logins: ["alice"], labels: [], words: []))
    }

    @Test func caretOntoACompletedNameBeforeAWordKeepsTheQuery() {
        var state = SearchFieldState()
        type("@alice login", into: &state)
        #expect(state.caretMoved(to: 6, people: g) == nil)
        #expect(state.completion == nil)
        #expect(state.query == .filtered(logins: ["alice"], labels: [], words: ["login"]))
    }

    @Test func caretLeavingTheTokenClosesTheListAndCountsItAsTyped() {
        var state = SearchFieldState()
        type("login @ge", into: &state)
        #expect(state.completion != nil)
        #expect(state.caretMoved(to: 2, people: g) == .filtered(logins: ["ge"], labels: [], words: ["login"]))
        #expect(state.completion == nil)
    }

    @Test func caretStayingAtTheTokenEndKeepsTheSelection() {
        var state = SearchFieldState()
        type("@g", into: &state)
        state.move(by: 1)
        #expect(state.caretMoved(to: 2, people: g) == nil)
        #expect(state.completion?.selection == 1)
    }

    // I3: typing inside the pending token keeps the query, so the results don't change while you pick.
    @Test func typingInThePendingTokenDoesNotRerunTheSearch() {
        var state = SearchFieldState()
        #expect(type("login", into: &state) == .text(["login"]))
        #expect(type("login ", into: &state) == nil)
        #expect(type("login @", into: &state) == nil)
        #expect(type("login @g", into: &state) == nil)
        #expect(type("login @ge", into: &state) == nil)
        #expect(state.query == .text(["login"]))
    }

    @Test func theSameTextWithoutACaretRerunsTheSearch() {
        var state = SearchFieldState()
        type("login", into: &state)
        #expect(state.edit("login", caret: nil, people: g) == .text(["login"]))
    }

    // I1: closing (popover hidden, a detail opened) searches nothing; a lone pending token has no query.
    @Test func closingOnALonePendingTokenSearchesNothing() {
        var state = SearchFieldState()
        type("@ge", into: &state)
        state.close()
        #expect(state.completion == nil)
        #expect(state.query == .empty)
    }

    @Test func closingWithWordsLeavesTheTokenForTheNextRerun() {
        var state = SearchFieldState()
        type("login @ge", into: &state)
        state.close()
        #expect(state.query == .text(["login"]))
        #expect(state.isStale)
        #expect(state.edit("login @ge", caret: nil, people: g) == .filtered(logins: ["ge"], labels: [], words: ["login"]))
        #expect(!state.isStale)
    }

    @Test func dismissCountsTheTokenAsTypedAndKeepsItClosed() {
        var state = SearchFieldState()
        type("login @ge", into: &state)
        #expect(state.dismiss() == .filtered(logins: ["ge"], labels: [], words: ["login"]))
        #expect(type("login @geo", into: &state) == .filtered(logins: ["geo"], labels: [], words: ["login"]))
        #expect(state.completion == nil)
    }

    // M7.2: text that replaces the dismissed token with a fresh "@" opens the list again.
    @Test func aFreshAtAfterDismissingReopens() {
        var state = SearchFieldState()
        type("@ge", into: &state)
        state.dismiss()
        type("@", into: &state)
        #expect(state.completion?.token.prefix == "")
    }

    @Test func backspacingToTheAtReopens() {
        var state = SearchFieldState()
        type("@ge", into: &state)
        state.dismiss()
        type("@g", into: &state)
        #expect(state.completion == nil)
        type("@", into: &state)
        #expect(state.completion != nil)
    }

    @Test func forgetDropsListAndDismissal() {
        var state = SearchFieldState()
        type("@ge", into: &state)
        state.dismiss()
        state.forgetCompletion()
        type("@geo", into: &state)
        #expect(state.completion != nil)
    }

    // M2: a refresh that changes the candidates keeps the selected person when still listed.
    @Test func refreshKeepsTheSelectedPerson() {
        var state = SearchFieldState()
        let before = people(["geordi", "geordie", "gina"])
        type("@g", into: &state, people: before)
        state.move(by: 1)
        let chosen = state.completion?.selectedCandidate?.login
        state.refresh(people: people(["gabe", "geordi", "geordie", "gina"]))
        #expect(state.completion?.selectedCandidate?.login == chosen)
        #expect(state.completion?.candidates.count == 4)
    }

    @Test func refreshFallsBackToTheFirstRowWhenThePersonLeft() {
        var state = SearchFieldState()
        type("@g", into: &state, people: people(["geordi", "geordie", "gina"]))
        state.move(by: 2)
        state.refresh(people: people(["geordi", "geordie"]))
        #expect(state.completion?.selection == 0)
    }
}

@Suite struct CompletionAnnouncementTests {
    private func open(_ text: String, _ index: PeopleIndex) -> PersonCompletion? {
        PersonCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil, people: index)
    }

    @Test func newTokenAnnouncesOpen() {
        let new = open("@g", g)
        #expect(CompletionSpeech.change(from: nil, to: new, loaded: true)
            == "3 people. Up and down arrows to choose, Return to complete.")
    }

    @Test func movingAnnouncesTheSelection() throws {
        let old = try #require(open("@g", g))
        #expect(CompletionSpeech.change(from: old, to: old.moved(by: 1), loaded: true)
            == CompletionSpeech.selected(old.moved(by: 1)))
    }

    @Test func narrowingToNoOneAnnouncesNoMatch() {
        #expect(CompletionSpeech.change(from: open("@g", g), to: open("@gz", g), loaded: true)
            == "No matching people. Return to search anyway.")
    }

    // M7.1: back from no one to candidates on the same token.
    @Test func wideningFromNoOneAnnouncesOpen() {
        #expect(CompletionSpeech.change(from: open("@gz", g), to: open("@g", g), loaded: true)
            == "3 people. Up and down arrows to choose, Return to complete.")
    }

    @Test func narrowingWithinCandidatesIsQuiet() {
        #expect(CompletionSpeech.change(from: open("@g", g), to: open("@ge", g), loaded: true) == nil)
        #expect(CompletionSpeech.change(from: open("@g", g), to: nil, loaded: true) == nil)
    }
}
