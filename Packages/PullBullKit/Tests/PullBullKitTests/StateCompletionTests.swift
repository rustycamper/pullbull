import Foundation
import Testing
@testable import PullBullKit

@discardableResult
private func type(_ text: String, into state: inout SearchFieldState) -> SearchQuery? {
    state.edit(text, caret: text.utf16.count, people: .empty)
}

private func open(_ text: String) -> StateCompletion? {
    StateCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil)
}

@Suite struct StateTokenTests {
    @Test func tokenAtCaret() {
        #expect(PendingToken.at(caret: 3, in: "is:") == PendingToken(start: 0, end: 3, prefix: "", kind: .state))
        #expect(PendingToken.at(caret: 11, in: "login IS:Op")
            == PendingToken(start: 6, end: 11, prefix: "Op", kind: .state))
    }

    @Test func notAToken() {
        #expect(PendingToken.at(caret: 2, in: "is") == nil)
        #expect(PendingToken.at(caret: 7, in: "this:op") == nil)
        #expect(PendingToken.at(caret: 2, in: "is:open") == nil)
    }

    @Test func startsToken() {
        #expect(PendingToken.startsToken(at: 0, in: "is:open"))
        #expect(PendingToken.startsToken(at: 4, in: "fix Is:open", kind: .state))
        #expect(!PendingToken.startsToken(at: 0, in: "is:open", kind: .label))
        #expect(!PendingToken.startsToken(at: 2, in: "this:open"))
        #expect(!PendingToken.startsToken(at: 0, in: "is"))
    }
}

@Suite struct StateCompletionTests {
    @Test func bareQualifierListsEveryState() throws {
        #expect(try #require(open("is:")).candidates.map(\.value) == StateFilter.allCases.map(IsValue.state) + ItemCondition.allCases.map(IsValue.condition))
    }

    @Test func candidatesFollowThePrefix() throws {
        #expect(try #require(open("is:M")).candidates.map(\.value) == [.state(.merged)])
        #expect(try #require(open("is:open")).candidates.map(\.value) == [.state(.open)])
        #expect(try #require(open("is:x")).candidates.isEmpty)
    }

    @Test func otherTokensOpenNoStateList() {
        #expect(open("~bug") == nil)
        #expect(open("@al") == nil)
        #expect(LabelCompletion.open(text: "is:", caret: 3, dismissedStart: nil, labels: .empty) == nil)
    }

    @Test func acceptInsertsTheQualifier() throws {
        let completion = try #require(open("fix is:me"))
        let result = try #require(completion.accepted(in: "fix is:me"))
        #expect(result.text == "fix is:merged ")
        #expect(result.caret == result.text.utf16.count)
    }

    @Test func candidateText() {
        #expect(StateCandidate(value: .state(.draft)).insertText == "is:draft")
        #expect(StateCandidate(value: .state(.draft)).id == "draft")
        #expect(StateFilter.closed.token == "is:closed")
    }

    @Test func speech() throws {
        let all = try #require(open("is:"))
        #expect(CompletionSpeech.opened(all) == "9 states. Up and down arrows to choose, Return to complete.")
        #expect(CompletionSpeech.opened(try #require(open("is:x"))) == "No matching states. Return to search anyway.")
        #expect(CompletionSpeech.selected(all.moved(by: 2)) == "merged, merged PRs, 3 of 9")
        #expect(CompletionSpeech.completed(StateCandidate(value: .state(.open))) == "Showing open items")
        #expect(CompletionSpeech.change(from: nil, to: .states(all), loaded: false)
            == "9 states. Up and down arrows to choose, Return to complete.")
    }
}

@Suite struct StateFieldStateTests {
    @Test func typingTheQualifierOpensTheStateList() {
        var state = SearchFieldState()
        #expect(type("is:", into: &state) == nil)
        #expect(state.stateCompletion?.candidates.count == 9)
        #expect(state.searchCompletion?.token.kind == .state)
        #expect(state.completion == nil && state.labelCompletion == nil)
    }

    @Test func pickingAStateSearchesIt() throws {
        var state = SearchFieldState()
        type("fix is:", into: &state)
        state.move(by: 2)
        let accepted = try #require(state.searchCompletion?.accepted(in: state.text))
        #expect(accepted.text == "fix is:merged ")
        let query = state.edit(accepted.text, caret: accepted.caret, people: .empty)
        #expect(query == .filtered(logins: [], labels: [], words: ["fix"], states: [.merged]))
        #expect(state.searchCompletion == nil)
    }

    @Test func dismissingAnUnknownValueSearchesItAsAWord() {
        var state = SearchFieldState()
        type("is:foo", into: &state)
        #expect(state.stateCompletion?.candidates.isEmpty == true)
        #expect(state.dismiss() == .text(["is:foo"]))
        #expect(type("is:foox", into: &state) == .text(["is:foox"]))
        #expect(state.searchCompletion == nil)
    }

    @Test func aDismissalEndsWhenTheValueIsDeleted() {
        var state = SearchFieldState()
        type("is:o", into: &state)
        state.dismiss()
        type("is:", into: &state)
        #expect(state.stateCompletion?.candidates.count == 9)
    }
}
