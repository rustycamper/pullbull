import Foundation
import Testing
@testable import PullBullKit

private func open(_ text: String) -> UpdatedCompletion? {
    UpdatedCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil)
}

@Suite struct UpdatedCompletionTests {
    @Test func tokenAtCaret() {
        #expect(PendingToken.at(caret: 8, in: "updated:")
            == PendingToken(start: 0, end: 8, prefix: "", kind: .updated))
        #expect(PendingToken.at(caret: 13, in: "fix UPDATED:1")
            == PendingToken(start: 4, end: 13, prefix: "1", kind: .updated))
    }

    @Test func typingQualifierListsAllSteps() throws {
        #expect(try #require(open("updated:")).candidates.map(\.step) == [.today, .threeDays, .week, .month])
    }

    @Test func prefixNarrows() throws {
        #expect(try #require(open("updated:1")).candidates.map(\.step) == [.week, .month])
        #expect(try #require(open("updated:T")).candidates.map(\.step) == [.today])
    }

    @Test func acceptWritesToken() throws {
        let completion = try #require(open("fix updated:")).moved(by: 1)
        let result = try #require(completion.accepted(in: "fix updated:"))
        #expect(result.text == "fix updated:3d ")
        #expect(result.caret == result.text.utf16.count)
    }

    @Test func noMatchIsEmpty() throws {
        #expect(try #require(open("updated:9")).candidates.isEmpty)
    }

    @Test func otherTokensOpenNoStepList() {
        #expect(open("is:") == nil)
        #expect(open("updated") == nil)
        #expect(open("updated:3d") != nil)
        #expect(StateCompletion.open(text: "updated:", caret: 8, dismissedStart: nil) == nil)
    }

    @Test func candidateText() {
        #expect(TimeStepCandidate(step: .threeDays).insertText == "updated:3d")
        #expect(TimeStepCandidate(step: .threeDays).id == "threeDays")
    }

    @Test func searchCompletionOpensItAfterStatus() throws {
        let text = "updated:1"
        let completion = try #require(SearchCompletion.open(
            text: text, caret: text.utf16.count, dismissedStart: nil, people: .empty, labels: .empty))
        guard case .updated(let steps) = completion else { Issue.record("not updated"); return }
        #expect(steps.candidates.map(\.step) == [.week, .month])
        #expect(completion.hasCandidates)
        #expect(completion.moved(by: 1).selectedID == "month")
    }

    @Test func fieldStateExposesIt() {
        var state = SearchFieldState()
        state.edit("updated:", caret: 8, people: .empty)
        #expect(state.updatedCompletion?.candidates.count == 4)
        #expect(state.stateCompletion == nil)
    }

    @Test func ghostAcceptOpensTheList() throws {
        var state = SearchFieldState()
        state.edit("up", caret: 2, people: .empty)
        let ghost = try #require(state.ghost(statuses: .empty))
        let accepted = try #require(ghost.accepted(in: "up"))
        #expect(accepted.text == "updated:")
        state.edit(accepted.text, caret: accepted.caret, people: .empty)
        #expect(state.updatedCompletion?.candidates.count == 4)
    }

    @Test func speech() throws {
        let all = try #require(open("updated:"))
        #expect(CompletionSpeech.opened(all) == "4 steps. Up and down arrows to choose, Return to complete.")
        #expect(CompletionSpeech.opened(try #require(open("updated:9"))) == "No matching steps. Return to search anyway.")
        #expect(CompletionSpeech.selected(all.moved(by: 1)) == "updated:3d, in the last 3 days, 2 of 4")
        #expect(CompletionSpeech.completed(TimeStepCandidate(step: .week)) == "Showing items updated in the last week")
        #expect(CompletionSpeech.change(from: nil, to: .updated(all), loaded: false)
            == "4 steps. Up and down arrows to choose, Return to complete.")
    }
}
