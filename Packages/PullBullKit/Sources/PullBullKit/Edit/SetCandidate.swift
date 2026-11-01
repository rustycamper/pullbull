import Foundation

/// A label or a person the picker offers: `name` is the label name or the login.
public struct SetCandidate: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let detail: String?
    public let color: String?
    public let avatarURL: URL?

    /// `id` is the node ID, which the mutations take; `detail` is a label's description, `color` its
    /// 6-hex colour, `avatarURL` a person's avatar.
    public init(id: String, name: String, detail: String? = nil, color: String? = nil, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.color = color
        self.avatarURL = avatarURL
    }
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
