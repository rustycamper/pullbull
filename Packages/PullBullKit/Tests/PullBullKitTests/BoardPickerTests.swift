import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let me = AccountRef(login: "me", source: .gh)
private let acme = BoardOwner.org("acme")

private func summary(_ number: Int, _ title: String, owner: BoardOwner = acme) -> BoardSummary {
    BoardSummary(board: BoardRef(owner: owner, number: number), title: title)
}

private let roadmap = summary(1, "Roadmap")
private let bugs = summary(4, "Bugs")

// MARK: - Choices

@Suite struct BoardChoicesTests {
    @Test func listsTheBoardsAsLoaded() {
        #expect(BoardSummary.choices([roadmap, bugs], current: bugs.board) == [roadmap, bugs])
    }

    /// A chosen board the list lacks (deleted, or not readable) is still offered, by number, first.
    @Test func keepsACurrentBoardTheListLacks() {
        let choices = BoardSummary.choices([roadmap], current: .org("acme", 9))
        #expect(choices == [summary(9, "#9"), roadmap])
    }

    @Test func noCurrentBoardAddsNothing() {
        #expect(BoardSummary.choices([], current: nil).isEmpty)
    }
}

// MARK: - List cache

@Suite struct BoardListTests {
    @Test func neverAskedNeedsLoad() {
        let list = BoardList()
        #expect(list.state(account: me, owner: acme) == nil)
        #expect(list.needsLoad(account: me, owner: acme, now: t0))
    }

    @Test func loadingDoesNotLoadAgain() {
        var list = BoardList()
        list.began(account: me, owner: acme)
        #expect(list.state(account: me, owner: acme) == .loading)
        #expect(!list.needsLoad(account: me, owner: acme, now: t0))
    }

    @Test func loadedListIsFreshForFiveMinutes() {
        var list = BoardList()
        list.began(account: me, owner: acme)
        list.loaded([roadmap], account: me, owner: acme, at: t0)
        #expect(list.state(account: me, owner: acme) == .loaded([roadmap]))
        #expect(!list.needsLoad(account: me, owner: acme, now: t0.addingTimeInterval(299)))
        #expect(list.needsLoad(account: me, owner: acme, now: t0.addingTimeInterval(300)))
    }

    /// A reload keeps the boards on screen; a failed reload keeps them too, and tries again next time.
    @Test func reloadKeepsTheBoards() {
        var list = BoardList()
        list.loaded([roadmap], account: me, owner: acme, at: t0)
        list.began(account: me, owner: acme)
        #expect(list.state(account: me, owner: acme) == .loaded([roadmap]))
        #expect(!list.needsLoad(account: me, owner: acme, now: t0.addingTimeInterval(600)))
        list.failed("Offline", account: me, owner: acme)
        #expect(list.state(account: me, owner: acme) == .loaded([roadmap]))
        #expect(list.needsLoad(account: me, owner: acme, now: t0.addingTimeInterval(600)))
    }

    @Test func failureWithNothingLoadedIsShownAndRetried() {
        var list = BoardList()
        list.began(account: me, owner: acme)
        list.failed("Offline", account: me, owner: acme)
        #expect(list.state(account: me, owner: acme) == .failed("Offline"))
        #expect(list.needsLoad(account: me, owner: acme, now: t0))
    }

    /// Kept per account and owner; the owner's login matches without regard to case.
    @Test func keyedByAccountAndOwner() {
        var list = BoardList()
        list.loaded([roadmap], account: me, owner: acme, at: t0)
        #expect(list.state(account: me, owner: .org("ACME")) == .loaded([roadmap]))
        #expect(list.state(account: me, owner: .user("acme")) == nil)
        #expect(list.state(account: AccountRef(login: "me", source: .gitHubApp), owner: acme) == nil)
    }
}

// MARK: - Menu

@Suite struct BoardPickerTests {
    @Test func itemsWhileLoading() {
        #expect(BoardPicker.items(nil, current: nil, owner: acme) == [.loading])
        #expect(BoardPicker.items(.loading, current: bugs.board, owner: acme) == [.loading])
        #expect(BoardMenuItem.loading.title == "Loading Boards…")
    }

    @Test func itemsWhenTheOwnerHasNone() {
        let items = BoardPicker.items(.loaded([]), current: nil, owner: .user("octocat"))
        #expect(items == [.empty(owner: "octocat")])
        #expect(items.first?.title == "No Projects Boards for octocat")
    }

    @Test func itemsWhenTheListFailed() {
        let items = BoardPicker.items(.failed("Offline"), current: nil, owner: acme)
        #expect(items == [.failed("Offline")])
        #expect(items.first?.title == "Couldn't Load Boards")
    }

    @Test func itemsCheckTheCurrentBoard() {
        let items = BoardPicker.items(.loaded([roadmap, bugs]), current: .org("ACME", 4), owner: acme)
        #expect(items == [
            .board(roadmap.board, label: "Roadmap", isCurrent: false),
            .board(bugs.board, label: "Bugs", isCurrent: true),
        ])
    }

    @Test func itemsKeepACurrentBoardTheListLacks() {
        let items = BoardPicker.items(.loaded([roadmap]), current: .org("acme", 9), owner: acme)
        #expect(items == [
            .board(.org("acme", 9), label: "Board #9", isCurrent: true),
            .board(roadmap.board, label: "Roadmap", isCurrent: false),
        ])
    }

    @Test func labelsTellDuplicateAndBlankTitlesApart() {
        let boards = [summary(1, "Roadmap"), summary(2, "roadmap "), summary(3, "  "), summary(5, "Bugs")]
        #expect(boards.map { BoardPicker.label(of: $0, among: boards) }
            == ["Roadmap #1", "roadmap #2", "Board #3", "Bugs"])
    }

    @Test func titleNamesTheChosenBoard() {
        #expect(BoardPicker.title(current: nil, state: .loaded([roadmap]), fetchedTitle: nil) == "Choose a Board")
        #expect(BoardPicker.title(current: bugs.board, state: .loaded([roadmap, bugs]), fetchedTitle: "Old") == "Bugs")
        #expect(BoardPicker.title(current: bugs.board, state: nil, fetchedTitle: "Bugs") == "Bugs")
        #expect(BoardPicker.title(current: bugs.board, state: .loading, fetchedTitle: " ") == "Board #4")
        #expect(BoardPicker.title(current: bugs.board, state: .failed("x"), fetchedTitle: nil) == "Board #4")
        #expect(BoardPicker.title(current: .org("acme", 9), state: .loaded([roadmap]), fetchedTitle: nil) == "Board #9")
    }

    /// Hidden while the Board tab explains missing access; shown with no board and when its fetch failed.
    @Test func offeredOnlyWhileTheBoardIsReadable() {
        let scopes = RefreshError(APIError.insufficientScopes).message
        let offered = { (canRead: Bool, personal: PersonalBoardAccess?, error: String?, checking: Bool) in
            BoardPicker.isOffered(
                canReadProjects: canRead, personalAccess: personal, boardError: error, checkingAccess: checking)
        }
        #expect(offered(true, nil, nil, false))
        #expect(offered(true, .ready, nil, false))
        #expect(offered(true, nil, "Couldn't find board", false))
        #expect(!offered(false, nil, nil, false))
        #expect(!offered(true, nil, scopes, false))
        #expect(!offered(true, nil, nil, true))
        #expect(!offered(false, .useGhLogin("me"), nil, false))
        #expect(!offered(true, .addScope(command: "gh auth refresh"), nil, false))
        #expect(!offered(false, .logIn(command: "gh auth login"), nil, false))
    }
}
