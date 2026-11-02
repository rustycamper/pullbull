import Foundation
import Testing
@testable import PullBullKit

private func person(_ login: String) -> MentionCandidate {
    MentionCandidate(id: login, insertText: login, title: login, avatarURL: nil, isTeam: false)
}

private let team = MentionCandidate(
    id: "team:acme/backend", insertText: "acme/backend", title: "Back End", avatarURL: nil, isTeam: true)

@Suite struct MentionSpeechTests {
    @Test func rowLabels() {
        #expect(CompletionSpeech.label(person("dana")) == "dana")
        #expect(CompletionSpeech.label(team) == "Back End, team acme/backend")
    }

    @Test func opened() {
        #expect(CompletionSpeech.mentionsOpened(rows: [], loading: true) == "Loading people")
        #expect(CompletionSpeech.mentionsOpened(rows: [person("dana")], loading: false)
            == "1 suggestion. Up and down arrows to choose, Return to insert.")
        #expect(CompletionSpeech.mentionsOpened(rows: [person("dana"), team], loading: true)
            == "2 suggestions. Up and down arrows to choose, Return to insert.")
    }

    @Test func change() {
        let rows = [person("amy"), person("bob")]
        let a = MentionSpeechState(start: 3, rows: rows, selection: 0, loading: false)
        #expect(CompletionSpeech.mentionChange(from: nil, to: a) == CompletionSpeech.mentionsOpened(rows: rows, loading: false))
        #expect(CompletionSpeech.mentionChange(from: a, to: nil) == nil)
        // The same list on the same token says nothing.
        #expect(CompletionSpeech.mentionChange(from: a, to: a) == nil)
        // ↓ reads the selected row and its place.
        let down = MentionSpeechState(start: 3, rows: rows, selection: 1, loading: false)
        #expect(CompletionSpeech.mentionChange(from: a, to: down) == "bob, 2 of 2")
        // A new token opens afresh.
        let other = MentionSpeechState(start: 9, rows: rows, selection: 0, loading: false)
        #expect(CompletionSpeech.mentionChange(from: a, to: other) == CompletionSpeech.mentionsOpened(rows: rows, loading: false))
        // Loading, then rows: opens again.
        let loading = MentionSpeechState(start: 3, rows: [], selection: 0, loading: true)
        #expect(CompletionSpeech.mentionChange(from: loading, to: a) == CompletionSpeech.mentionsOpened(rows: rows, loading: false))
        // Narrowing on the same token says nothing.
        let narrowed = MentionSpeechState(start: 3, rows: [person("amy")], selection: 0, loading: false)
        #expect(CompletionSpeech.mentionChange(from: a, to: narrowed) == nil)
    }
}
