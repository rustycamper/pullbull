import Foundation

/// A label, a person or a team the picker offers: `name` is the label name, the login or the team's name.
public struct SetCandidate: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let detail: String?
    public let color: String?
    public let avatarURL: URL?
    /// A team's slug; nil for a label or a person.
    public let team: String?
    /// A past reviewer's latest verdict on the pull request.
    public let verdict: ReviewState?
    /// GitHub suggests this person as a reviewer.
    public let isSuggested: Bool

    /// `id` is the node ID, which the mutations take (a team's is its `key`); `detail` is a label's
    /// description, `color` its 6-hex colour, `avatarURL` a person's avatar.
    public init(
        id: String, name: String, detail: String? = nil, color: String? = nil, avatarURL: URL? = nil,
        team: String? = nil, verdict: ReviewState? = nil, isSuggested: Bool = false
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.color = color
        self.avatarURL = avatarURL
        self.team = team
        self.verdict = verdict
        self.isSuggested = isSuggested
    }

    /// Who or what this is, case ignored: the name, or "team:<slug>" for a team, as `Reviewer.key`.
    public var key: String { team.map { "team:" + $0.lowercased() } ?? name.lowercased() }

    /// The review request this candidate stands for.
    public var reviewer: Reviewer { team.map { .team(slug: $0, name: name) } ?? .user(name) }
}

/// What the reviewers picker offers for one pull request, with the parts that may be cached apart.
public struct ReviewerCandidates: Sendable {
    /// The repo's assignable people as GitHub lists them, with node IDs: the assignees picker's people.
    public let people: [SetCandidate]
    /// The owner organisation's teams; nil when they couldn't be read or the owner is a user.
    public let teams: [SetCandidate]?
    /// Past reviewers, suggested people, assignable people and teams (`all`), and the requested
    /// reviewers (`current`); one candidate per reviewer, never the author or a bot.
    public let picker: SetCandidates
}

/// What the picker offers for one issue: the repo's candidates and the issue's own.
public struct SetCandidates: Equatable, Sendable {
    /// The repo's labels, or its assignable people.
    public let all: [SetCandidate]
    /// The issue's own, with IDs, as GitHub has them now.
    public let current: [SetCandidate]
    /// False when GitHub had more than were read.
    public let complete: Bool

    public init(all: [SetCandidate], current: [SetCandidate], complete: Bool) {
        self.all = all
        self.current = current
        self.complete = complete
    }
}
