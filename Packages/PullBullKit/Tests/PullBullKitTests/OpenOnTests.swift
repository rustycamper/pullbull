import Foundation
import Testing
@testable import PullBullKit

private func decode(_ json: String) throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
}
private func settings(
    org: String? = "o", openOn: OpenOn = .all, lastScope: PRScope = .all
) -> AppSettings {
    var s = AppSettings()
    s.account = "me"
    s.org = org
    s.openOn = openOn
    s.lastScope = lastScope
    return s
}

@Suite struct OpenOnTests {
    @Test func theChoicesAreAllLastUsedNeedsYouMineTeam() {
        #expect(OpenOn.allCases.map(\.title) == ["All", "Last used", "Needs you", "Mine", "Team"])
        #expect(AppSettings().openOn == .all)
    }

    @Test func eachChoiceOpensOnItsScope() {
        #expect(settings(openOn: .all, lastScope: .mine).scopeOnOpen == .all)
        #expect(settings(openOn: .review).scopeOnOpen == .review)
        #expect(settings(openOn: .mine).scopeOnOpen == .mine)
        #expect(settings(openOn: .team).scopeOnOpen == .team)
        #expect(settings(openOn: .lastUsed, lastScope: .mine).scopeOnOpen == .mine)
        #expect(settings(openOn: .lastUsed).scopeOnOpen == .all)
    }

    @Test func aScopeWhoseChipIsntShownOpensOnAll() {
        #expect(settings(org: nil, openOn: .team).scopeOnOpen == .all)
        #expect(settings(org: nil, openOn: .lastUsed, lastScope: .team).scopeOnOpen == .all)
        // The choice is kept: the org coming back opens on Team again.
        var back = settings(org: nil, openOn: .team)
        back.org = "o"
        #expect(back.scopeOnOpen == .team)
    }

    @Test func theChipsFollowTheAccountsScope() {
        #expect(settings().prChips == [.all, .review, .mine, .team])
        #expect(settings().prSearchTabs == [.review, .mine, .team])
        #expect(settings(org: nil).prChips == [.all, .review, .mine])
    }

    @Test func teamIsOfferedOnlyWithAnOrgUnlessItIsTheChoice() {
        #expect(settings().openOnChoices == OpenOn.allCases)
        #expect(settings(org: nil).openOnChoices == [.all, .lastUsed, .review, .mine])
        #expect(settings(org: nil, openOn: .team).openOnChoices == OpenOn.allCases)
    }

    @Test func aCloseRecordsTheChipShownWhateverTheChoice() {
        for choice in OpenOn.allCases {
            var s = settings(openOn: choice)
            s.recordLastScope(.mine)
            #expect(s.lastScope == .mine)
        }
        var lastUsed = settings(openOn: .lastUsed, lastScope: .mine)
        lastUsed.recordLastScope(.team)
        #expect(lastUsed.scopeOnOpen == .team)
    }

    @Test func withNoAccountTeamIsOffered() {
        let s = AppSettings()
        #expect(s.openOnChoices == OpenOn.allCases)
        #expect(s.prChips == PRScope.allCases)
    }

    @Test func settingsWithLastTabOpenOnAllAndDropIt() throws {
        let old = try decode(#"{"account":"me","org":"o","lastTab":"team","sorts":{"mine":"oldestFirst"}}"#)
        #expect(old.openOn == .all && old.lastScope == .all)
        #expect(old.scopeOnOpen == .all)
        #expect(old.sort(for: PRScope.mine) == .oldestFirst)
        let saved = try #require(String(data: JSONEncoder().encode(old), encoding: .utf8))
        #expect(!saved.contains("lastTab"))
    }

    @Test func theOpenOnChoiceAndTheLastScopeRoundTrip() throws {
        var s = settings(openOn: .lastUsed, lastScope: .team)
        s.projectOwner = .org("o")
        let loaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(loaded == s)
        #expect(loaded.openOn == .lastUsed && loaded.lastScope == .team)
    }

    @Test func anUnreadableValueFallsBackForThatFieldOnly() throws {
        let s = try decode(#"{"account":"me","openOn":"inbox","lastScope":"board","compact":true}"#)
        #expect(s.openOn == .all && s.lastScope == .all)
        #expect(s.account == "me" && s.compact)
    }
}
