import Foundation
import Testing
@testable import PullBullKit

@Suite struct IssueScopeTests {
    @Test func theScopesAreAllAssignedCreatedBoard() {
        #expect(IssueScope.allCases.map(\.title) == ["All", "Assigned", "Created", "Board"])
        #expect(IssueScope.all.rawValue == "issuesAll")
        #expect(IssueScope(.board) == .board)
        #expect(IssueScope.all.tab == nil)
        #expect(IssueScope.allCases.compactMap(\.tab) == IssueTab.allCases)
    }

    @Test func pickingTheSelectedChipGoesBackToAll() {
        #expect(IssueScope.board.picking(.board) == .all)
        #expect(IssueScope.all.picking(.created) == .created)
    }

    @Test func allsSortKeyDoesNotCollideWithPRAll() {
        var s = AppSettings()
        s.sorts["all"] = .oldestFirst
        #expect(s.sort(for: IssueScope.all, boardAvailable: true) == .recentlyUpdated)
        s.setSort(.newestFirst, for: IssueScope.all)
        #expect(s.sorts["issuesAll"] == .newestFirst)
        #expect(s.sort(for: PRScope.all) == .oldestFirst)
    }

    @Test func boardStatusIsOfferedOnlyWithABoard() {
        #expect(ListSort.choices(for: IssueScope.all, boardAvailable: true)
            == [.recentlyUpdated, .newestFirst, .oldestFirst, .boardStatus])
        #expect(ListSort.choices(for: IssueScope.all, boardAvailable: false)
            == [.recentlyUpdated, .newestFirst, .oldestFirst])
        #expect(!ListSort.choices(for: IssueTab.board).contains(.boardStatus))
        #expect(ListSort.boardStatus.title == "Board status")
        var s = AppSettings()
        s.setSort(.boardStatus, for: IssueScope.all)
        #expect(s.sort(for: IssueScope.all, boardAvailable: false) == .recentlyUpdated)
        #expect(s.sort(for: IssueScope.all, boardAvailable: true) == .boardStatus)
    }

    @Test func tabScopesKeepTheirSorts() {
        var s = AppSettings()
        s.sorts["created"] = .oldestFirst
        #expect(s.sort(for: IssueScope.created, boardAvailable: false) == .oldestFirst)
    }
}
