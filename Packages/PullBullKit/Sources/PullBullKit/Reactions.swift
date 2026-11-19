import Foundation

/// The eight reactions GitHub offers, in the order it lists them.
public enum ReactionContent: String, Codable, Sendable, CaseIterable, Hashable {
    case thumbsUp = "THUMBS_UP", thumbsDown = "THUMBS_DOWN", laugh = "LAUGH", hooray = "HOORAY"
    case confused = "CONFUSED", heart = "HEART", rocket = "ROCKET", eyes = "EYES"

    public var emoji: String {
        switch self {
        case .thumbsUp: "👍"
        case .thumbsDown: "👎"
        case .laugh: "😄"
        case .hooray: "🎉"
        case .confused: "😕"
        case .heart: "❤️"
        case .rocket: "🚀"
        case .eyes: "👀"
        }
    }

    public var name: String {
        switch self {
        case .thumbsUp: "Thumbs up"
        case .thumbsDown: "Thumbs down"
        case .laugh: "Laugh"
        case .hooray: "Hooray"
        case .confused: "Confused"
        case .heart: "Heart"
        case .rocket: "Rocket"
        case .eyes: "Eyes"
        }
    }
}

/// One reaction on one subject: how many people gave it, whether the viewer did, and the first few of them.
public struct ReactionGroup: Codable, Sendable, Hashable {
    public let content: ReactionContent
    public internal(set) var count: Int
    public internal(set) var viewerHasReacted: Bool
    /// The first logins GitHub returns for this reaction (up to 3), the viewer's included if among them.
    public let reactors: [String]

    public init(content: ReactionContent, count: Int, viewerHasReacted: Bool, reactors: [String]) {
        self.content = content
        self.count = count
        self.viewerHasReacted = viewerHasReacted
        self.reactors = reactors
    }

    /// "alice, bob and frank reacted with 👍". The viewer reads as "You" when they reacted and is dropped
    /// from `reactors` either way, since a removal shown at once can leave their login in the list.
    public func tooltip(viewer: String?) -> String {
        var names = viewerHasReacted ? ["You"] : []
        names += reactors.filter { $0.caseInsensitiveCompare(viewer ?? "") != .orderedSame }
        names = Array(names.prefix(3))
        let others = max(count - names.count, 0)
        let who: String
        if names.isEmpty {
            who = count == 1 ? "1 person" : "\(count) people"
        } else if others > 0 {
            who = "\(names.joined(separator: ", ")) and \(others) \(others == 1 ? "other" : "others")"
        } else if names.count == 1 {
            who = names[0]
        } else {
            who = "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
        return "\(who) reacted with \(content.emoji)"
    }

    /// "👍 3, including you" / "🎉 1".
    public var accessibilityLabel: String {
        "\(content.emoji) \(count)" + (viewerHasReacted ? ", including you" : "")
    }
}

/// What can be reacted to on one subject (a PR, an issue, a comment or a review), and how it stands.
public struct Reactions: Codable, Sendable, Hashable {
    public let subjectId: String
    /// Every group GitHub returned, in `ReactionContent.allCases` order; zero counts included.
    public internal(set) var groups: [ReactionGroup]
    public let viewerCanReact: Bool

    public init(subjectId: String, groups: [ReactionGroup], viewerCanReact: Bool) {
        self.subjectId = subjectId
        self.groups = groups
        self.viewerCanReact = viewerCanReact
    }

    /// The groups with a count above zero, in GitHub's order: the chips.
    public var shown: [ReactionGroup] { groups.filter { $0.count > 0 } }

    public func viewerHasReacted(_ content: ReactionContent) -> Bool {
        groups.first { $0.content == content }?.viewerHasReacted ?? false
    }
}
