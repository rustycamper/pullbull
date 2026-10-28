import Foundation
import Testing
@testable import PullBullKit

private func labels(_ names: [String]) -> LabelIndex {
    let issue = BoardIssue(
        key: PRKey(repo: "o/r", number: 1), title: "t", url: URL(string: "https://x/1")!, isOpen: true,
        labels: names)
    return LabelIndex.build(Snapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_790_000_000),
        org: OrgContext(org: "o", viewer: "viewer", members: ["geordi"], myTeams: [], repos: []),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [issue],
        boardProject: nil, boardTitle: nil, boardError: nil,
        assignedIssues: nil, createdIssues: nil, boardStatusOptions: nil))
}

private let l = labels(["bug", "backend", "good first issue"])

@discardableResult
private func type(_ text: String, into state: inout SearchFieldState) -> SearchQuery? {
    state.edit(text, caret: text.utf16.count, people: .empty, labels: l)
}

private func open(_ text: String, _ index: LabelIndex = l) -> LabelCompletion? {
    LabelCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil, labels: index)
}

@Suite struct LabelTokenTests {
    @Test func tokenAtCaret() {
        #expect(PendingToken.at(caret: 9, in: "login ~bu") == PendingToken(start: 6, end: 9, prefix: "bu", kind: .label))
        #expect(PendingToken.at(caret: 1, in: "~")?.kind == .label)
        #expect(PendingToken.at(caret: 1, in: "～")?.kind == .label)
        #expect(PendingToken.at(caret: 3, in: "@ge")?.kind == .person)
    }

    @Test func quotedTokenSpansSpaces() {
        let text = #"fix ~"good fi"#
        #expect(PendingToken.at(caret: text.utf16.count, in: text)
            == PendingToken(start: 4, end: text.utf16.count, prefix: "good fi", kind: .label))
    }

    @Test func personAfterAnOpenQuoteIsPending() {
        let text = #"~"good first @al"#
        #expect(PendingToken.at(caret: text.utf16.count, in: text)
            == PendingToken(start: 13, end: text.utf16.count, prefix: "al", kind: .person))
    }

    @Test func openQuoteStillPendingWhileTyping() {
        let text = #"~"needs tri"#
        #expect(PendingToken.at(caret: text.utf16.count, in: text)?.prefix == "needs tri")
    }

    @Test func closedQuoteIsNotPending() {
        let text = #"~"good first issue""#
        #expect(PendingToken.at(caret: text.utf16.count, in: text) == nil)
    }

    @Test func caretInsideRunIsNotPending() {
        #expect(PendingToken.at(caret: 2, in: "~bug") == nil)
    }

    @Test func aliasOpensNoList() {
        #expect(PendingToken.at(caret: 8, in: "label:bu") == nil)
    }

    @Test func startsToken() {
        #expect(PendingToken.startsToken(at: 0, in: "~bug"))
        #expect(PendingToken.startsToken(at: 4, in: "fix ～bug"))
        #expect(!PendingToken.startsToken(at: 1, in: "a~bug"))
    }
}

@Suite struct LabelCompletionTests {
    @Test func candidatesFollowThePrefix() throws {
        let completion = try #require(open("~b"))
        #expect(completion.candidates.map(\.name) == ["backend", "bug"])
        #expect(try #require(open(#"~"good"#)).candidates.map(\.name) == ["good first issue"])
    }

    @Test func personTokenOpensNoLabelList() {
        #expect(open("@b") == nil)
        #expect(PersonCompletion.open(text: "~b", caret: 2, dismissedStart: nil, people: .empty) == nil)
    }

    @Test func acceptInsertsAQuotedNameWhenItHasSpaces() throws {
        let text = "fix ~go"
        let completion = try #require(open(text))
        let result = try #require(completion.accepted(in: text))
        #expect(result.text == #"fix ~"good first issue" "#)
        #expect(result.caret == result.text.utf16.count)
    }

    @Test func acceptReplacesAnOpenQuote() throws {
        let text = #"~"good f login"#
        let completion = try #require(LabelCompletion.open(text: text, caret: 8, dismissedStart: nil, labels: l))
        let result = try #require(completion.accepted(in: text))
        #expect(result.text == #"~"good first issue" login"#)
    }

    @Test func acceptPlainName() throws {
        let completion = try #require(open("~bu"))
        let result = try #require(completion.accepted(in: "~bu"))
        #expect(result.text == "~bug ")
    }
}

@Suite struct LabelFieldStateTests {
    @Test func typingALabelTokenOpensTheLabelList() {
        var state = SearchFieldState()
        #expect(type("~b", into: &state) == nil)
        #expect(state.labelCompletion?.token.prefix == "b")
        #expect(state.completion == nil)
        #expect(state.searchCompletion?.token.kind == .label)
    }

    @Test func typingInThePendingLabelKeepsTheQuery() {
        var state = SearchFieldState()
        #expect(type("login", into: &state) == .text(["login"]))
        #expect(type("login ~", into: &state) == nil)
        #expect(type("login ~bu", into: &state) == nil)
        #expect(state.query == .text(["login"]))
    }

    @Test func dismissCountsTheLabelAsTyped() {
        var state = SearchFieldState()
        type("login ~bu", into: &state)
        #expect(state.dismiss() == .filtered(logins: [], labels: ["bu"], words: ["login"]))
        #expect(state.searchCompletion == nil)
    }

    // A dismissal holds only for the sigil it closed: `@ge` dismissed, then edited to `~ge`, opens labels.
    @Test func dismissingAPersonDoesNotKeepALabelListClosed() {
        var state = SearchFieldState()
        state.edit("@ge", caret: 3, people: .empty, labels: l)
        state.dismiss()
        type("~ge", into: &state)
        #expect(state.labelCompletion?.token.prefix == "ge")
        state.dismiss()
        type("~geo", into: &state)
        #expect(state.labelCompletion == nil)
    }

    @Test func movingSelectsAnotherLabel() {
        var state = SearchFieldState()
        type("~b", into: &state)
        state.move(by: 1)
        #expect(state.labelCompletion?.selectedCandidate?.name == "bug")
    }

    @Test func switchingFromAPersonToALabelSwapsTheList() {
        var state = SearchFieldState()
        state.edit("@g", caret: 2, people: .empty, labels: l)
        #expect(state.completion != nil)
        type("@g ~b", into: &state)
        #expect(state.completion == nil)
        #expect(state.labelCompletion != nil)
    }

    @Test func refreshKeepsTheSelectedLabel() {
        var state = SearchFieldState()
        type("~b", into: &state)
        state.move(by: 1)
        state.refresh(people: .empty, labels: labels(["bug", "backend", "blocked"]))
        #expect(state.labelCompletion?.selectedCandidate?.name == "bug")
        #expect(state.labelCompletion?.candidates.count == 3)
    }
}

@Suite struct LabelSpeechTests {
    @Test func opened() throws {
        #expect(CompletionSpeech.opened(try #require(open("~b")), loaded: true)
            == "2 labels. Up and down arrows to choose, Return to complete.")
        #expect(CompletionSpeech.opened(try #require(open("~bug")), loaded: true)
            == "1 label. Up and down arrows to choose, Return to complete.")
        #expect(CompletionSpeech.opened(try #require(open("~zz")), loaded: true)
            == "No matching labels. Return to search anyway.")
        #expect(CompletionSpeech.opened(try #require(open("~", .empty)), loaded: false)
            == "Labels appear once PullBull has loaded")
    }

    @Test func rowAndCompleted() {
        #expect(CompletionSpeech.label(LabelCandidate(name: "bug", openCount: 3)) == "bug, on 3 items")
        #expect(CompletionSpeech.label(LabelCandidate(name: "bug", openCount: 0)) == "bug")
        #expect(CompletionSpeech.completed(LabelCandidate(name: "bug", openCount: 1)) == "Showing items labelled bug")
    }

    @Test func changeAcrossKinds() throws {
        let label = SearchCompletion.labels(try #require(open("~b")))
        let person = SearchCompletion.people(try #require(
            PersonCompletion.open(text: "@", caret: 1, dismissedStart: nil, people: .empty)))
        #expect(CompletionSpeech.change(from: person, to: label, loaded: true)
            == "2 labels. Up and down arrows to choose, Return to complete.")
        #expect(CompletionSpeech.change(from: label, to: label.moved(by: 1), loaded: true)
            == "bug, on 1 item, 2 of 2")
        #expect(CompletionSpeech.change(from: label, to: nil, loaded: true) == nil)
    }
}
