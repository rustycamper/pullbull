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

private func completion(_ text: String, _ index: PeopleIndex) -> PersonCompletion? {
    PersonCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil, people: index)
}

@Suite struct CompletionSpeechTests {
    @Test func opened() throws {
        let index = people(["geordi", "geordie", "gina"])
        let three = try #require(completion("@g", index))
        #expect(CompletionSpeech.opened(three, loaded: true)
            == "3 people. Up and down arrows to choose, Return to complete.")
        let one = try #require(completion("@gin", index))
        #expect(CompletionSpeech.opened(one, loaded: true)
            == "1 person. Up and down arrows to choose, Return to complete.")
        let none = try #require(completion("@zz", index))
        #expect(CompletionSpeech.opened(none, loaded: true) == "No matching people. Return to search anyway.")
        let empty = try #require(completion("@g", .empty))
        #expect(CompletionSpeech.opened(empty, loaded: false) == "People appear once PullBull has loaded")
    }

    @Test func label() {
        let candidate = { (member: Bool, count: Int) in
            PersonCandidate(login: "alice", avatarURL: nil, isMember: member, isViewer: false, openCount: count)
        }
        #expect(CompletionSpeech.label(candidate(true, 6)) == "alice, member, on 6 items")
        #expect(CompletionSpeech.label(candidate(true, 1)) == "alice, member, on 1 item")
        #expect(CompletionSpeech.label(candidate(true, 0)) == "alice, member")
        #expect(CompletionSpeech.label(candidate(false, 2)) == "alice, on 2 items")
        #expect(CompletionSpeech.label(candidate(false, 0)) == "alice")
    }

    @Test func selected() throws {
        let index = people(["geordi", "geordie", "gina"])
        let open = try #require(completion("@g", index))
        let first = try #require(open.candidates.first)
        #expect(CompletionSpeech.selected(open) == "\(first.login), member, 1 of 3")
        let moved = open.moved(by: 2)
        #expect(CompletionSpeech.selected(moved) == "\(moved.candidates[2].login), member, 3 of 3")
        let none = try #require(completion("@zz", index))
        #expect(CompletionSpeech.selected(none) == nil)
    }

    @Test func selectedCandidate() throws {
        let index = people(["geordi", "geordie", "gina"])
        let open = try #require(completion("@g", index))
        #expect(open.selectedCandidate == open.candidates.first)
        let moved = open.moved(by: 1)
        #expect(moved.selectedCandidate == open.candidates[1])
        #expect(open.moved(by: 10).selectedCandidate == open.candidates.last)
        let none = try #require(completion("@zz", index))
        #expect(none.selectedCandidate == nil)
    }

    @Test func completed() {
        let viewer = PersonCandidate(login: "devon", avatarURL: nil, isMember: true, isViewer: true, openCount: 3)
        #expect(CompletionSpeech.completed(viewer) == "Showing items devon is on")
    }
}
