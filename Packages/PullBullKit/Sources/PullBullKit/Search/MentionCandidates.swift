import Foundation

/// One row of the `@` list: a person or a team.
public struct MentionCandidate: Equatable, Sendable, Identifiable {
    /// The lowercased login, or "team:<owner>/<slug>".
    public let id: String
    /// What follows the "@": "dana" or "acme/backend".
    public let insertText: String
    /// The login, or the team's name.
    public let title: String
    public let avatarURL: URL?
    public let isTeam: Bool

    public init(id: String, insertText: String, title: String, avatarURL: URL?, isTeam: Bool) {
        self.id = id
        self.insertText = insertText
        self.title = title
        self.avatarURL = avatarURL
        self.isTeam = isTeam
    }
}

public enum MentionCandidates {
    /// Thread people in order: comment authors newest first (skipping `authorIsBot == true`), then
    /// author, assignees, requested reviewers (people only), reviewers.
    public static func thread(
        comments: [Comment], author: String?, assignees: [String], requested: [Reviewer], reviewers: [String]
    ) -> [String] {
        let commenters = comments.filter { $0.authorIsBot != true }
            .sorted { $0.createdAt > $1.createdAt }.map(\.author)
        let people: [String] = requested.compactMap {
            if case .user(let login) = $0 { login } else { nil }
        }
        return commenters + (author.map { [$0] } ?? []) + assignees + people + reviewers
    }

    /// Rows for "@<prefix>": thread people, then mentionable people, known people and teams, the last
    /// three alphabetical. Each person or team appears once, in its first group; the viewer, `ghost` and
    /// bots are left out.
    public static func rank(
        prefix: String, thread: [String], mentionable: [SetCandidate],
        known: [(login: String, avatarURL: URL?)], teams: [SetCandidate]?, owner: String,
        viewer: String, limit: Int = 8
    ) -> [MentionCandidate] {
        let p = prefix.lowercased()
        let viewerKey = viewer.lowercased()
        var avatars: [String: URL] = [:]
        for candidate in mentionable {
            if let url = candidate.avatarURL { avatars[candidate.name.lowercased()] = url }
        }
        for person in known where avatars[person.login.lowercased()] == nil {
            if let url = person.avatarURL { avatars[person.login.lowercased()] = url }
        }

        var seen: Set<String> = []
        func people(_ logins: [String], sorted: Bool) -> [MentionCandidate] {
            var rows: [MentionCandidate] = []
            for login in logins {
                let key = login.lowercased()
                guard !key.isEmpty, key != "ghost", key != viewerKey, !key.hasSuffix("[bot]"),
                      key.hasPrefix(p), seen.insert(key).inserted else { continue }
                rows.append(MentionCandidate(
                    id: key, insertText: login, title: login, avatarURL: avatars[key], isTeam: false))
            }
            return sorted ? rows.sorted { $0.id < $1.id } : rows
        }

        var rows = people(thread, sorted: false)
        rows += people(mentionable.map(\.name), sorted: true)
        rows += people(known.map(\.login), sorted: true)
        let matching = (teams ?? []).compactMap { team -> MentionCandidate? in
            guard let slug = team.team else { return nil }
            let words = team.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            guard p.isEmpty || slug.lowercased().hasPrefix(p) || words.contains(where: { $0.hasPrefix(p) }) else {
                return nil
            }
            let id = "team:\(owner.lowercased())/\(slug.lowercased())"
            guard seen.insert(id).inserted else { return nil }
            return MentionCandidate(id: id, insertText: "\(owner)/\(slug)", title: team.name, avatarURL: nil, isTeam: true)
        }
        rows += matching.sorted { $0.title.lowercased() < $1.title.lowercased() }
        return Array(rows.prefix(limit))
    }
}
