import Testing
@testable import PullBullKit

private func key(_ n: Int, repo: String = "o/a") -> PRKey { PRKey(repo: repo, number: n) }

@Suite struct SearchPickTests {
    // MARK: Nothing picked

    @Test func wordsHighlightNothing() {
        let pick = SearchPick.none.updated(kept: nil, query: .text(["login"]), keys: [key(1), key(2)])
        #expect(pick == .none)
    }

    @Test func filteredQueryWithANumberHighlightsNothing() {
        let filter = SearchFilter(include: SearchTerms(states: [.open], numbers: [7]))
        let pick = SearchPick.none.updated(kept: nil, query: .filtered(filter), keys: [key(7)])
        #expect(pick == .none)
    }

    @Test func numberWithOneMatchImpliesIt() {
        let pick = SearchPick.none.updated(kept: nil, query: .number(7), keys: [key(7)])
        #expect(pick == SearchPick(key: key(7), implied: true))
    }

    @Test func linkWithOneMatchImpliesIt() {
        let pick = SearchPick.none.updated(kept: nil, query: .item(repo: "o/a", number: 7), keys: [key(7)])
        #expect(pick == SearchPick(key: key(7), implied: true))
    }

    @Test func numberWithSeveralMatchesHighlightsNothing() {
        let pick = SearchPick.none.updated(kept: nil, query: .number(7), keys: [key(7), key(7, repo: "o/b")])
        #expect(pick == .none)
    }

    @Test func impliedMatchGoesWhenASecondArrives() {
        let first = SearchPick.none.updated(kept: nil, query: .number(7), keys: [key(7)])
        let later = first.updated(kept: nil, query: .number(7), keys: [key(7), key(7, repo: "o/b")])
        #expect(later == .none)
    }

    @Test func numberWithNoMatchHighlightsNothing() {
        #expect(SearchPick.none.updated(kept: nil, query: .number(7), keys: []) == .none)
    }

    // MARK: Picked

    @Test func pickStaysWhileShown() {
        let pick = SearchPick.picked(key(2)).updated(kept: nil, query: .text(["a"]), keys: [key(1), key(2)])
        #expect(pick == .picked(key(2)))
    }

    @Test func pickedNumberMatchStaysWhenASecondArrives() {
        let pick = SearchPick.picked(key(7)).updated(
            kept: nil, query: .number(7), keys: [key(7), key(7, repo: "o/b")])
        #expect(pick == .picked(key(7)))
    }

    @Test func pickNoLongerShownGoes() {
        let pick = SearchPick.picked(key(3)).updated(kept: nil, query: .text(["a"]), keys: [key(1), key(2)])
        #expect(pick == .none)
    }

    @Test func pickNoLongerShownFallsBackToTheNumbersOnlyMatch() {
        let pick = SearchPick.picked(key(3)).updated(kept: nil, query: .number(7), keys: [key(7)])
        #expect(pick == SearchPick(key: key(7), implied: true))
    }

    @Test func pickedNilIsNone() {
        #expect(SearchPick.picked(nil) == .none)
    }

    // MARK: Kept through Back

    @Test func keptResultWinsWhenShown() {
        let pick = SearchPick.picked(key(1)).updated(kept: key(2), query: .text(["a"]), keys: [key(1), key(2)])
        #expect(pick == .picked(key(2)))
    }

    @Test func keptResultNotYetShownLeavesThePick() {
        let pick = SearchPick.picked(key(1)).updated(kept: key(9), query: .text(["a"]), keys: [key(1), key(2)])
        #expect(pick == .picked(key(1)))
    }
}
