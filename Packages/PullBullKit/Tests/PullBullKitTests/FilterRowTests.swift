import Testing
@testable import PullBullKit

@Suite struct FilterRowTests {
    @Test func unfocusedShowsAllRepos() {
        let row = FilterRow.make(searching: false, listsBuilt: true, focusName: nil, boardTitle: nil)
        #expect(row == FilterRow(repoTitle: "All repos", isFocused: false, boardTitle: nil))
    }

    @Test func focusedShowsTheRepoName() {
        let row = FilterRow.make(searching: false, listsBuilt: true, focusName: "widgets", boardTitle: nil)
        #expect(row == FilterRow(repoTitle: "widgets", isFocused: true, boardTitle: nil))
    }

    @Test func boardTabAddsTheBoardPart() {
        let row = FilterRow.make(searching: false, listsBuilt: true, focusName: nil, boardTitle: "Roadmap")
        #expect(row?.boardTitle == "Roadmap")
        #expect(row?.repoTitle == "All repos")
    }

    /// Search keeps the repo part, so ✕ clears the focus there too; search isn't board-scoped.
    @Test func searchShowsTheRepoPartOnly() {
        let all = FilterRow.make(searching: true, listsBuilt: true, focusName: nil, boardTitle: "Roadmap")
        #expect(all == FilterRow(repoTitle: "All repos", isFocused: false, boardTitle: nil))
        let focused = FilterRow.make(searching: true, listsBuilt: true, focusName: "widgets", boardTitle: "Roadmap")
        #expect(focused == FilterRow(repoTitle: "widgets", isFocused: true, boardTitle: nil))
        #expect(FilterRow.make(searching: true, listsBuilt: false, focusName: nil, boardTitle: nil) == nil)
    }

    /// The loading or error state has nothing to filter; a focus keeps the row so ✕ stays in reach.
    @Test func unbuiltListsShowTheRowOnlyWithAFocus() {
        #expect(FilterRow.make(searching: false, listsBuilt: false, focusName: nil, boardTitle: nil) == nil)
        let row = FilterRow.make(searching: false, listsBuilt: false, focusName: "widgets", boardTitle: "Roadmap")
        #expect(row == FilterRow(repoTitle: "widgets", isFocused: true, boardTitle: nil))
    }

    @Test func spokenLabels() {
        let all = FilterRow(repoTitle: "All repos", isFocused: false, boardTitle: "Roadmap")
        #expect(all.repoSpokenLabel(tally: "2 of 4 in Review") == "Showing all repositories")
        #expect(all.boardSpokenLabel == "Board, Roadmap")
        let focused = FilterRow(repoTitle: "widgets", isFocused: true, boardTitle: nil)
        #expect(focused.repoSpokenLabel(tally: "2 of 4 in Review") == "Showing only widgets. 2 of 4 in Review.")
        #expect(focused.repoSpokenLabel(tally: nil) == "Showing only widgets.")
        #expect(focused.boardSpokenLabel == nil)
    }

    @Test func tally() {
        #expect(FilterRow.tally(2, of: 4, in: "Review") == "2 of 4 in Review")
    }
}
