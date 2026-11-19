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

extension Reactions {
    /// One viewer's reaction laid over these groups: a missing group is added (count 0, no reactors) at its
    /// `ReactionContent.allCases` place. A group already in the asked state is left as it is.
    func laying(_ content: ReactionContent, add: Bool) -> Reactions {
        var result = self
        let order = ReactionContent.allCases
        var index = result.groups.firstIndex { $0.content == content }
        if index == nil {
            let rank = order.firstIndex(of: content) ?? order.count
            let at = result.groups.firstIndex { (order.firstIndex(of: $0.content) ?? order.count) > rank }
                ?? result.groups.count
            result.groups.insert(ReactionGroup(content: content, count: 0, viewerHasReacted: false, reactors: []), at: at)
            index = at
        }
        guard let index, result.groups[index].viewerHasReacted != add else { return result }
        result.groups[index].count = max(result.groups[index].count + (add ? 1 : -1), 0)
        result.groups[index].viewerHasReacted = add
        return result
    }
}

extension PRDetail {
    /// GitHub's answer for one subject written into the stored detail: the description, a comment or a
    /// review whose `reactions.subjectId` matches. `fetchedAt` is kept. Unchanged when nothing matches.
    public func replacingReactions(_ reactions: Reactions) -> PRDetail {
        var copy = self
        if self.reactions?.subjectId == reactions.subjectId { copy.reactions = reactions }
        for index in copy.comments.indices where copy.comments[index].reactions?.subjectId == reactions.subjectId {
            copy.comments[index].reactions = reactions
        }
        for index in copy.reviews.indices where copy.reviews[index].reactions?.subjectId == reactions.subjectId {
            copy.reviews[index].reactions = reactions
        }
        return copy
    }
}

extension IssueDetail {
    /// GitHub's answer for one subject written into the stored detail: the description or a comment whose
    /// `reactions.subjectId` matches. `fetchedAt` is kept. Unchanged when nothing matches.
    public func replacingReactions(_ reactions: Reactions) -> IssueDetail {
        var copy = self
        if self.reactions?.subjectId == reactions.subjectId { copy.reactions = reactions }
        for index in copy.lastComments.indices where copy.lastComments[index].reactions?.subjectId == reactions.subjectId {
            copy.lastComments[index].reactions = reactions
        }
        return copy
    }
}
