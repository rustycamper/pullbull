import Foundation
import Testing
@testable import PullBullKit

private func ghost(_ text: String, statuses: Bool = true) -> QualifierGhost? {
    QualifierGhost.at(caret: text.utf16.count, in: text, statuses: statuses)
}

@Suite struct QualifierGhostTests {
    @Test func theRestOfTheQualifier() {
        #expect(ghost("st")?.remainder == "atus:")
        #expect(ghost("fix STA")?.remainder == "tus:")
        #expect(ghost("status")?.remainder == ":")
        #expect(ghost("la")?.remainder == "bel:")
        #expect(ghost("Label")?.remainder == ":")
    }

    @Test func updatedGhost() {
        #expect(ghost("up")?.remainder == "dated:")
        #expect(ghost("UPD")?.remainder == "ated:")
        #expect(ghost("upda")?.remainder == "ted:")
        #expect(ghost("updat") == nil)
        #expect(ghost("update") == nil)
        #expect(ghost("updated") == nil)
        #expect(ghost("stat")?.remainder == "us:")
        #expect(ghost("u") == nil)
        #expect(ghost("upx") == nil)
        #expect(ghost("st")?.remainder == "atus:")
        #expect(ghost("up", statuses: false)?.remainder == "dated:")
    }

    @Test func ghostAfterDash() throws {
        #expect(ghost("-st")?.remainder == "atus:")
        #expect(ghost("fix -la")?.remainder == "bel:")
        #expect(ghost("-s") == nil)
        #expect(ghost("--st") == nil)
        let accepted = try #require(ghost("-st")?.accepted(in: "-st"))
        #expect(accepted.text == "-status:")
        #expect(accepted.caret == 8)
    }

    @Test func noGhost() {
        #expect(ghost("s") == nil)
        #expect(ghost("l") == nil)
        #expect(ghost("is") == nil)
        #expect(ghost("stag") == nil)
        #expect(ghost("statuses") == nil)
        #expect(ghost("st ") == nil)
        #expect(ghost("status:") == nil)
        #expect(ghost("~st") == nil)
        #expect(ghost("@st") == nil)
        #expect(ghost(#"~"good st"#) == nil)
        #expect(ghost("") == nil)
    }

    @Test func statusOnlyWithABoard() {
        #expect(ghost("st", statuses: false) == nil)
        #expect(ghost("la", statuses: false)?.remainder == "bel:")
    }

    @Test func onlyWithTheCaretAtTheEnd() {
        #expect(QualifierGhost.at(caret: 2, in: "st fix", statuses: true) == nil)
        #expect(QualifierGhost.at(caret: 7, in: "fix sta", statuses: true)?.remainder == "tus:")
    }

    @Test func acceptWritesTheQualifierInLowercase() throws {
        let accepted = try #require(ghost("fix Sta")?.accepted(in: "fix Sta"))
        #expect(accepted.text == "fix status:")
        #expect(accepted.caret == accepted.text.utf16.count)
    }

    @Test func acceptedStatusOpensTheColumnList() throws {
        let statuses = StatusIndex.build(Snapshot(
            fetchedAt: Date(timeIntervalSince1970: 0),
            org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
            boardProject: 1, boardTitle: nil, boardError: nil, assignedIssues: nil, createdIssues: nil,
            boardStatusOptions: [StatusOption(id: "t", name: "Todo")]))
        var field = SearchFieldState()
        field.edit("st", caret: 2, people: .empty, statuses: statuses)
        #expect(field.ghost(statuses: statuses)?.remainder == "atus:")
        let accepted = try #require(field.ghost(statuses: statuses)?.accepted(in: field.text))
        field.edit(accepted.text, caret: accepted.caret, people: .empty, statuses: statuses)
        #expect(field.statusCompletion?.candidates.map(\.name) == ["Todo"])
        #expect(field.ghost(statuses: statuses) == nil)
    }

    @Test func theFieldFollowsTheCaret() {
        var field = SearchFieldState()
        field.edit("la fix", caret: 6, people: .empty)
        #expect(field.ghost(statuses: .empty) == nil)
        field.edit("fix la", caret: 6, people: .empty)
        #expect(field.ghost(statuses: .empty)?.remainder == "bel:")
        field.caretMoved(to: 2, people: .empty)
        #expect(field.ghost(statuses: .empty) == nil)
        field.edit("fix la", caret: 6, people: .empty)
        // A rerun of the same text keeps the caret; new text without one drops it.
        field.edit("fix la", caret: nil, people: .empty)
        #expect(field.ghost(statuses: .empty)?.remainder == "bel:")
        field.forgetCaret()
        #expect(field.ghost(statuses: .empty) == nil)
        field.edit("fix la", caret: 6, people: .empty)
        field.edit("fix lab", caret: nil, people: .empty)
        #expect(field.ghost(statuses: .empty) == nil)
    }
}

@Suite struct LabelAliasCompletionTests {
    @Test func labelAliasOpensTheLabelList() throws {
        let token = try #require(PendingToken.at(caret: 8, in: "label:bu"))
        #expect(token == PendingToken(start: 0, end: 8, prefix: "bu", kind: .label))
        #expect(PendingToken.startsToken(at: 4, in: "fix LABEL:bug", kind: .label))
    }
}
