import Foundation
import Testing
@testable import PullBullKit

private func people(_ logins: [String]) -> PeopleIndex {
    PeopleIndex.build(Snapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_790_000_000),
        org: OrgContext(org: "o", viewer: "viewer", members: logins, myTeams: [], repos: []),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
        boardProject: nil, boardTitle: nil, boardError: nil,
        assignedIssues: nil, createdIssues: nil, boardStatusOptions: nil))
}

private let geordi = people(["geordi"])

@Suite struct PersonCompletionTests {
    @Test func startsToken() {
        #expect(PendingToken.startsToken(at: 0, in: "@ge"))
        #expect(PendingToken.startsToken(at: 0, in: "＠ge"))
        #expect(PendingToken.startsToken(at: 6, in: "login @ge"))
        #expect(!PendingToken.startsToken(at: 3, in: "a@ge"))
        #expect(!PendingToken.startsToken(at: 0, in: "bug"))
        #expect(!PendingToken.startsToken(at: 1, in: "😀@"))
        #expect(!PendingToken.startsToken(at: 9, in: "login @ge"))
        #expect(!PendingToken.startsToken(at: -1, in: "@ge"))
    }

    @Test func tokenAtCaret() {
        #expect(PendingToken.at(caret: 9, in: "login @ge") == PendingToken(start: 6, end: 9, prefix: "ge"))
        #expect(PendingToken.at(caret: 1, in: "@")?.prefix == "")
        #expect(PendingToken.at(caret: 3, in: "＠ge")?.prefix == "ge")
    }

    @Test func caretInsideRunIsNotPending() {
        #expect(PendingToken.at(caret: 3, in: "@geordi") == nil)
    }

    @Test func caretInEarlierWord() {
        #expect(PendingToken.at(caret: 3, in: "login @ge") == nil)
    }

    @Test func afterSpaceNoToken() {
        #expect(PendingToken.at(caret: 4, in: "@ge ") == nil)
        #expect(PendingToken.at(caret: 4, in: "a@ge") == nil)
    }

    @Test func utf16CaretAfterEmoji() throws {
        let text = "🐛 fix @ge"
        let token = try #require(PendingToken.at(caret: text.utf16.count, in: text))
        #expect(token.start == 7)
        let completion = try #require(
            PersonCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil, people: geordi))
        let result = try #require(completion.accepted(in: text))
        #expect(result.text == "🐛 fix @geordi ")
        #expect(result.caret == result.text.utf16.count)
    }

    @Test func rangeRejectsOffsetsOutsideText() {
        let token = PendingToken(start: 2, end: 9, prefix: "x")
        #expect(token.range(in: "abc") == nil)
        #expect(PendingToken(start: 1, end: 3, prefix: "").range(in: "🐛@a") == nil)
        #expect(PendingToken(start: 2, end: 3, prefix: "").range(in: "🐛@a") != nil)
        #expect(PendingToken(start: 0, end: 1, prefix: "").range(in: "abc") == nil)
    }

    @Test func acceptReusesSpace() throws {
        let completion = try #require(
            PersonCompletion.open(text: "@ge login", caret: 3, dismissedStart: nil, people: geordi))
        let result = try #require(completion.accepted(in: "@ge login"))
        #expect(result.text == "@geordi login")
        #expect(result.caret == 8)
    }

    @Test func acceptReusesTab() throws {
        let completion = try #require(
            PersonCompletion.open(text: "@ge\tlogin", caret: 3, dismissedStart: nil, people: geordi))
        let result = try #require(completion.accepted(in: "@ge\tlogin"))
        #expect(result.text == "@geordi login")
        #expect(result.caret == 8)
    }

    @Test func dismissedStaysClosed() {
        #expect(PersonCompletion.open(text: "login @ge", caret: 9, dismissedStart: 6, people: geordi) == nil)
        #expect(PersonCompletion.open(text: "login @ge", caret: 9, dismissedStart: 0, people: geordi) != nil)
    }

    @Test func movedClamps() throws {
        let three = people(["ga", "gb", "gc"])
        let completion = try #require(PersonCompletion.open(text: "@g", caret: 2, dismissedStart: nil, people: three))
        #expect(completion.moved(by: -1).selection == 0)
        #expect(completion.moved(by: 5).selection == 2)
    }

    @Test func noCandidateAcceptsNothing() throws {
        let completion = try #require(
            PersonCompletion.open(text: "@zzz", caret: 4, dismissedStart: nil, people: geordi))
        #expect(completion.accepted(in: "@zzz") == nil)
    }
}
