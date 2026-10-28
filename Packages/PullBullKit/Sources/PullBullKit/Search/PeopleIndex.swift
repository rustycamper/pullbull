import Foundation

public struct PersonCandidate: CompletionCandidate {
    /// Display casing; the viewer's own login for the viewer.
    public let login: String
    public let avatarURL: URL?
    public let isMember: Bool
    public let isViewer: Bool
    public let openCount: Int

    public var id: String { login.lowercased() }
    public var insertText: String { isViewer ? "@me" : "@\(login)" }

    public init(login: String, avatarURL: URL?, isMember: Bool, isViewer: Bool, openCount: Int) {
        self.login = login
        self.avatarURL = avatarURL
        self.isMember = isMember
        self.isViewer = isViewer
        self.openCount = openCount
    }
}

public struct PeopleIndex: Equatable, Sendable {
    public static let empty = PeopleIndex(people: [], positions: [:], viewer: nil)

    private let people: [PersonCandidate]
    private let positions: [String: Int]
    private let viewer: String?

    private init(people: [PersonCandidate], positions: [String: Int], viewer: String?) {
        self.people = people
        self.positions = positions
        self.viewer = viewer
    }

    public static func build(_ snap: Snapshot) -> PeopleIndex {
        var display: [String: String] = [:]
        var order: [String] = []
        var avatars: [String: URL] = [:]
        var counts: [String: Int] = [:]

        func note(_ login: String, avatar: URL? = nil) {
            let key = login.lowercased()
            guard key != "ghost", !login.isEmpty else { return }
            if display[key] == nil {
                display[key] = login
                order.append(key)
            }
            if avatars[key] == nil, let avatar { avatars[key] = avatar }
        }

        let viewerKey = snap.org.viewer.lowercased()
        for member in snap.org.members { note(member) }

        let prs = snap.reviewCandidates + snap.mine + snap.team + snap.recentlyClosed
        for pr in prs { note(pr.author, avatar: pr.authorAvatarURL) }
        for pr in prs {
            for request in pr.reviewRequests {
                if case .user(let login) = request { note(login) }
            }
            for review in pr.latestReviews { note(review.author) }
        }
        let allIssues = snap.boardIssues + (snap.assignedIssues ?? []) + (snap.createdIssues ?? [])
        for issue in allIssues {
            if let author = issue.author { note(author) }
            for assignee in issue.assignees { note(assignee.login, avatar: assignee.avatarURL) }
        }
        note(snap.org.viewer)

        var prRoles: [PRKey: Set<String>] = [:]
        for pr in prs where pr.state == .open {
            prRoles[pr.key, default: []].insert(pr.author.lowercased())
            for request in pr.reviewRequests {
                if case .user(let login) = request { prRoles[pr.key, default: []].insert(login.lowercased()) }
            }
            for review in pr.latestReviews { prRoles[pr.key, default: []].insert(review.author.lowercased()) }
        }
        var issueRoles: [PRKey: Set<String>] = [:]
        // The one copy per issue that search reads, so a count never names an item search can't show.
        for issue in SearchEngine.cachedIssues(snap) where issue.isOpen {
            if let author = issue.author { issueRoles[issue.key, default: []].insert(author.lowercased()) }
            for assignee in issue.assignees { issueRoles[issue.key, default: []].insert(assignee.login.lowercased()) }
        }
        for involved in Array(prRoles.values) + Array(issueRoles.values) {
            for key in involved { counts[key, default: 0] += 1 }
        }

        let members = Set(snap.org.members.map { $0.lowercased() })
        let people = order.map { key in
            PersonCandidate(
                login: display[key] ?? key, avatarURL: avatars[key], isMember: members.contains(key),
                isViewer: key == viewerKey, openCount: counts[key] ?? 0)
        }
        let positions = Dictionary(people.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return PeopleIndex(people: people, positions: positions, viewer: viewerKey.isEmpty ? nil : viewerKey)
    }

    public func candidates(prefix: String, limit: Int = 6) -> [PersonCandidate] {
        let p = prefix.lowercased()
        var ranked: [(tier: Int, person: PersonCandidate)] = []
        for person in people {
            var tier = Self.tier(of: person.login.lowercased(), for: p)
            if person.isViewer, let viaMe = Self.tier(of: "me", for: p), viaMe <= 2 {
                tier = min(tier ?? viaMe, viaMe)
            }
            if let tier { ranked.append((tier, person)) }
        }
        ranked.sort { a, b in
            if p.isEmpty, a.person.isViewer != b.person.isViewer { return a.person.isViewer }
            if a.tier != b.tier { return a.tier < b.tier }
            if a.person.openCount != b.person.openCount { return a.person.openCount > b.person.openCount }
            if a.person.isMember != b.person.isMember { return a.person.isMember }
            return a.person.login.lowercased() < b.person.login.lowercased()
        }
        return ranked.prefix(limit).map(\.person)
    }

    public func contains(_ login: String) -> Bool {
        let key = login.lowercased()
        if key == "me" { return viewer != nil }
        return positions[key] != nil
    }

    /// The avatar PullBull has seen for `login` (`me` is the viewer), nil when unknown or none was loaded.
    public func avatarURL(_ login: String) -> URL? {
        let key = login.lowercased() == "me" ? (viewer ?? "") : login.lowercased()
        return positions[key].flatMap { people[$0].avatarURL }
    }

    public func display(_ login: String) -> String {
        let key = login.lowercased() == "me" ? (viewer ?? login.lowercased()) : login.lowercased()
        return positions[key].map { people[$0].login } ?? login
    }

    private static func tier(of login: String, for p: String) -> Int? {
        if login == p { return 1 }
        if login.hasPrefix(p) { return 2 }
        if login.split(separator: "-").contains(where: { $0.hasPrefix(p) }) { return 3 }
        if login.contains(p) { return 4 }
        return nil
    }
}
