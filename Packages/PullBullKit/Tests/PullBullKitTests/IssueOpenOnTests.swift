import Foundation
import Testing
@testable import PullBullKit

private func decode(_ json: String) throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
}
private func settings(openOn: IssueOpenOn = .all, lastScope: IssueScope = .all) -> AppSettings {
    var s = AppSettings()
    s.issueOpenOn = openOn
    s.lastIssueScope = lastScope
    return s
}

@Suite struct IssueOpenOnTests {
    @Test func theChoicesAreAllLastUsedAssignedCreatedBoard() {
        #expect(IssueOpenOn.allCases.map(\.title) == ["All", "Last used", "Assigned", "Created", "Board"])
    }

    @Test func aNewInstallOpensOnAll() throws {
        #expect(AppSettings().issueScopeOnOpen == .all)
        let saved = try JSONEncoder().encode(AppSettings())
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: saved)
        #expect(reloaded.issueOpenOn == .all)
        #expect(reloaded.issueScopeOnOpen == .all)
    }

    @Test func anUpgradeKeepsTheLastTab() throws {
        let s = try decode(#"{"account":"me","lastIssueTab":"board"}"#)
        #expect(s.issueOpenOn == .lastUsed)
        #expect(s.issueScopeOnOpen == .board)
        let saved = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(!saved.contains("lastIssueTab"))
        #expect(saved.contains("lastIssueScope"))
    }

    @Test func anUpgradeFromAssignedReopensOnAssigned() throws {
        let s = try decode(#"{"account":"me","lastIssueTab":"assigned"}"#)
        #expect(s.issueOpenOn == .lastUsed)
        #expect(s.issueScopeOnOpen == .assigned)
    }

    @Test func eachChoiceOpensOnItsScope() {
        #expect(settings(openOn: .all, lastScope: .board).issueScopeOnOpen == .all)
        #expect(settings(openOn: .assigned).issueScopeOnOpen == .assigned)
        #expect(settings(openOn: .created).issueScopeOnOpen == .created)
        #expect(settings(openOn: .board).issueScopeOnOpen == .board)
        #expect(settings(openOn: .lastUsed, lastScope: .created).issueScopeOnOpen == .created)
        #expect(settings(openOn: .lastUsed).issueScopeOnOpen == .all)
    }

    @Test func aCloseRecordsTheScope() {
        var s = settings(openOn: .assigned)
        s.recordLastIssueScope(.board)
        #expect(s.lastIssueScope == .board)
        #expect(s.issueScopeOnOpen == .assigned)
        s.issueOpenOn = .lastUsed
        #expect(s.issueScopeOnOpen == .board)
    }

    @Test func theChoiceAndLastScopeRoundTrip() throws {
        let s = settings(openOn: .created, lastScope: .board)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.issueOpenOn == .created)
        #expect(back.lastIssueScope == .board)
        #expect(back == s)
    }

    @Test func anUnreadableValueFallsBackForThatFieldOnly() throws {
        let s = try decode(#"{"account":"me","issueOpenOn":"inbox","lastIssueScope":"created"}"#)
        #expect(s.issueOpenOn == .all)
        #expect(s.lastIssueScope == .created)
        #expect(s.account == "me")
    }
}
