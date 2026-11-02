import Foundation
import Testing
@testable import PullBullKit

private typealias PBComment = PullBullKit.Comment

private func comment(_ author: String, _ minute: Int, bot: Bool? = nil) -> PBComment {
    PBComment(author: author, authorIsBot: bot, body: "x", createdAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(minute) * 60))
}

private func person(_ login: String) -> SetCandidate { SetCandidate(id: "U_" + login, name: login) }

private func rank(
    _ prefix: String = "", thread: [String] = [], mentionable: [String] = [], known: [String] = [],
    teams: [SetCandidate]? = nil, viewer: String = "viewer", limit: Int = 8
) -> [MentionCandidate] {
    MentionCandidates.rank(
        prefix: prefix, thread: thread, mentionable: mentionable.map(person),
        known: known.map { (login: $0, avatarURL: nil) }, teams: teams, owner: "acme", viewer: viewer, limit: limit)
}

@Suite struct MentionCandidatesTests {
    @Test func threadOrderIsCommentersNewestFirstThenRoles() {
        let people = MentionCandidates.thread(
            comments: [comment("old", 1), comment("new", 5), comment("mid", 3), comment("bot", 9, bot: true)],
            author: "author", assignees: ["asg"], requested: [.team(slug: "t", name: "T"), .user("req")],
            reviewers: ["rev"])
        #expect(people == ["new", "mid", "old", "author", "asg", "req", "rev"])
    }

    @Test func eachPersonAppearsOnceInTheirFirstGroup() {
        let result = rank(thread: ["dana"], mentionable: ["Dana", "dave"], known: ["DAVE", "dina"])
        #expect(result.map(\.title) == ["dana", "dave", "dina"])
    }

    @Test func viewerGhostAndBotsAreLeftOut() {
        let result = rank(thread: ["viewer", "ghost", "ci[bot]", "dana"], mentionable: ["Viewer", "dependabot[bot]"])
        #expect(result.map(\.title) == ["dana"])
    }

    @Test func prefixMatchesTheLoginStart() {
        let result = rank("da", thread: ["adam", "dana"])
        #expect(result.map(\.title) == ["dana"])
    }

    @Test func laterGroupsAreAlphabetical() {
        let result = rank(thread: ["zed"], mentionable: ["carl", "bob"], known: ["yan", "abe"])
        #expect(result.map(\.title) == ["zed", "bob", "carl", "abe", "yan"])
    }

    @Test func teamsMatchSlugOrNameWordAndInsertTheOwnerSlug() {
        let teams = [SetCandidate(id: "team:backend", name: "Back End", team: "backend")]
        let result = rank("back", teams: teams)
        #expect(result.count == 1)
        #expect(result[0].isTeam)
        #expect(result[0].insertText == "acme/backend")
        #expect(result[0].id == "team:acme/backend")
        #expect(result[0].title == "Back End")
        #expect(rank("end", teams: teams).count == 1)
        #expect(rank("ack", teams: teams).isEmpty)
    }

    @Test func nilTeamsGiveNoTeams() {
        #expect(rank("back", teams: nil).isEmpty)
    }

    @Test func atMostEight() {
        let names = (1...12).map { "u\(String(format: "%02d", $0))" }
        #expect(rank(mentionable: names).count == 8)
        #expect(rank(mentionable: names, limit: 3).count == 3)
    }

    @Test func emptyPrefixGivesThreadPeopleFirst() {
        let result = rank(thread: ["zed"], mentionable: ["amy"])
        #expect(result.map(\.title) == ["zed", "amy"])
        #expect(result.allSatisfy { !$0.isTeam })
        #expect(result[0].insertText == "zed")
    }
    @Test func ownerSlashListsTheOwnersTeamsOnly() {
        let teams = [
            SetCandidate(id: "team:backend", name: "Back End", team: "backend"),
            SetCandidate(id: "team:design", name: "Design", team: "design"),
        ]
        let all = rank("acme/", thread: ["acme"], mentionable: ["acmebot"], teams: teams)
        #expect(all.map(\.insertText) == ["acme/backend", "acme/design"])
        #expect(rank("ACME/back", teams: teams).map(\.insertText) == ["acme/backend"])
        #expect(rank("acme/end", teams: teams).map(\.insertText) == ["acme/backend"])
        #expect(rank("other/back", teams: teams).isEmpty)
        #expect(rank("acme/back", teams: nil).isEmpty)
    }

    @Test func aPersonWithNoKnownAvatarGetsTheirGitHubPicture() {
        let withAvatar = SetCandidate(id: "U_dana", name: "dana", avatarURL: URL(string: "https://avatars.example/dana"))
        let result = MentionCandidates.rank(
            prefix: "", thread: ["zed", "dana"], mentionable: [withAvatar], known: [], teams: nil, owner: "acme",
            viewer: "viewer")
        #expect(result.map(\.avatarURL) == [
            URL(string: "https://github.com/zed.png"), URL(string: "https://avatars.example/dana"),
        ])
    }

    @Test func remoteQueryWantsAPrefixFewRowsAndAnIncompleteList() {
        #expect(MentionCandidates.wantsRemote(prefix: "da", rowCount: 3, mentionableComplete: false))
        #expect(MentionCandidates.wantsRemote(prefix: "da", rowCount: 3, mentionableComplete: nil))
        #expect(!MentionCandidates.wantsRemote(prefix: "", rowCount: 3, mentionableComplete: false))
        #expect(!MentionCandidates.wantsRemote(prefix: "da", rowCount: 8, mentionableComplete: false))
        #expect(!MentionCandidates.wantsRemote(prefix: "da", rowCount: 3, mentionableComplete: true))
        #expect(!MentionCandidates.wantsRemote(prefix: "acme/", rowCount: 0, mentionableComplete: false))
    }

    @Test func selectionFollowsTheSameRow() {
        let old = rank(thread: ["amy", "bob", "cat"])
        let new = rank(thread: ["zed", "bob", "cat"])
        #expect(MentionCandidates.selection(keeping: 1, of: old, in: new) == 1)
        #expect(MentionCandidates.selection(keeping: 2, of: old, in: rank(thread: ["cat"])) == 0)
        #expect(MentionCandidates.selection(keeping: 0, of: old, in: new) == 0)
        #expect(MentionCandidates.selection(keeping: 5, of: old, in: new) == 0)
    }
}
