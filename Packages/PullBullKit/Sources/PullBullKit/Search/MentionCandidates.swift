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
    /// bots are left out. A person with no avatar from `mentionable` or `known` shows their GitHub picture.
    /// "@<owner>/<rest>" lists only the teams of `owner` (case ignored) that match `rest`.
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
                let avatar = avatars[key] ?? URL(string: "https://github.com/\(login).png")
                rows.append(MentionCandidate(id: key, insertText: login, title: login, avatarURL: avatar, isTeam: false))
            }
            return sorted ? rows.sorted { $0.id < $1.id } : rows
        }

        var rows = people(thread, sorted: false)
        rows += people(mentionable.map(\.name), sorted: true)
        rows += people(known.map(\.login), sorted: true)
        // "acme/back": the owner's teams matching "back"; another owner's, none.
        var teamPrefix = p
        if let slash = p.firstIndex(of: "/") {
            teamPrefix = String(p[p.index(after: slash)...])
            if p[..<slash] != owner.lowercased() { return Array(rows.prefix(limit)) }
        }
        let matching = (teams ?? []).compactMap { team -> MentionCandidate? in
            guard let slug = team.team else { return nil }
            let words = team.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            guard teamPrefix.isEmpty || slug.lowercased().hasPrefix(teamPrefix)
                || words.contains(where: { $0.hasPrefix(teamPrefix) }) else {
                return nil
            }
            let id = "team:\(owner.lowercased())/\(slug.lowercased())"
            guard seen.insert(id).inserted else { return nil }
            return MentionCandidate(id: id, insertText: "\(owner)/\(slug)", title: team.name, avatarURL: nil, isTeam: true)
        }
        rows += matching.sorted { $0.title.lowercased() < $1.title.lowercased() }
        return Array(rows.prefix(limit))
    }

    /// Whether GitHub is asked for people matching `prefix` once typing pauses: a person's prefix (no
    /// "/"), fewer than 8 rows, and the repo's mentionable people not all read already (nil: not read).
    public static func wantsRemote(prefix: String, rowCount: Int, mentionableComplete: Bool?) -> Bool {
        !prefix.isEmpty && !prefix.contains("/") && rowCount < 8 && mentionableComplete != true
    }

    /// The selection in `new` rows: the row selected in `old` where it still is, else the first.
    public static func selection(keeping selection: Int, of old: [MentionCandidate], in new: [MentionCandidate]) -> Int {
        guard old.indices.contains(selection) else { return 0 }
        return new.firstIndex { $0.id == old[selection].id } ?? 0
    }
}
