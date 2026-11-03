import Foundation
import Testing
@testable import PullBullKit

@Suite struct PRScopeTests {
    @Test func chipsAreAllNeedsYouMineTeamAndTeamNeedsAnOrg() {
        #expect(PRScope.shown(in: .org("o")) == [.all, .review, .mine, .team])
        #expect(PRScope.shown(in: .personal(login: "me")) == [.all, .review, .mine])
        #expect(PRScope.allCases.map(\.title) == ["All", "Needs you", "Mine", "Team"])
    }

    @Test func clickingTheSelectedChipGoesBackToAll() {
        #expect(PRScope.all.picking(.mine) == .mine)
        #expect(PRScope.mine.picking(.mine) == .all)
        #expect(PRScope.mine.picking(.team) == .team)
        #expect(PRScope.all.picking(.all) == .all)
    }

    @Test func arrowsMoveAlongTheChipsShown() {
        let shown = PRScope.shown(in: .personal(login: "me"))
        #expect(ListNavigation.tab(PRScope.all, movedBy: 1, among: shown) == .review)
        #expect(ListNavigation.tab(PRScope.mine, movedBy: 1, among: shown) == .mine)
        #expect(ListNavigation.tab(PRScope.all, movedBy: -1, among: shown) == .all)
    }

    @Test func aScopeMapsToItsList() {
        #expect(PRScope.all.tab == nil)
        #expect(PRScope.allCases.compactMap(\.tab) == PRTab.allCases)
        #expect(PRTab.allCases.map(PRScope.init) == [.review, .mine, .team])
    }

    @Test func oldTabSortsCarryOverAndAllStartsRecentlyUpdated() throws {
        let s = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"sorts":{"review":"oldestFirst","mine":"waitingLongest","team":"oldestFirst"}}"#.utf8))
        #expect(s.sort(for: PRScope.review) == .oldestFirst)
        #expect(s.sort(for: PRScope.mine) == .waitingLongest)
        #expect(s.sort(for: PRScope.team) == .oldestFirst)
        #expect(s.sort(for: PRScope.all) == .recentlyUpdated)
        #expect(s.sort(for: PRTab.review) == .oldestFirst)
    }

    @Test func allsSortIsKeptUnderAll() throws {
        var s = AppSettings()
        s.setSort(.waitingLongest, for: PRScope.all)
        #expect(s.sorts["all"] == .waitingLongest)
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(loaded.sort(for: PRScope.all) == .waitingLongest)
        #expect(loaded.sort(for: PRScope.review) == .recentlyUpdated)
    }

    @Test func everyScopeOffersThePRChoices() {
        for scope in PRScope.allCases {
            #expect(ListSort.choices(for: scope) == [.recentlyUpdated, .waitingLongest, .oldestFirst])
        }
        var s = AppSettings()
        s.sorts["all"] = .newestFirst
        #expect(s.sort(for: PRScope.all) == .recentlyUpdated)
    }
}
