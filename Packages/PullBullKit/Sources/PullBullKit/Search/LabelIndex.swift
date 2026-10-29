import Foundation

public struct LabelCandidate: CompletionCandidate {
    /// Display casing: as first seen.
    public let name: String
    /// Open items in the sets search reads locally that carry the label.
    public let openCount: Int

    public var id: String { name.lowercased() }
    public var insertText: String { SearchQuery.labelToken(name) }

    public init(name: String, openCount: Int) {
        self.name = name
        self.openCount = openCount
    }
}

/// Every label the current snapshot holds, for the `~label` completion. Derived, never stored.
public struct LabelIndex: Equatable, Sendable {
    public static let empty = LabelIndex(labels: [], positions: [:])

    private let labels: [LabelCandidate]
    private let positions: [String: Int]

    private init(labels: [LabelCandidate], positions: [String: Int]) {
        self.labels = labels
        self.positions = positions
    }

    /// Labels of the PRs and issues search reads locally, deduplicated case-insensitively.
    public static func build(_ snap: Snapshot) -> LabelIndex {
        var display: [String: String] = [:]
        var order: [String] = []
        func note(_ label: String) {
            let key = label.lowercased()
            guard !key.isEmpty, display[key] == nil else { return }
            display[key] = label
            order.append(key)
        }

        let prs = snap.reviewCandidates + snap.mine + snap.team + snap.recentlyClosed
        for pr in prs { pr.labels.forEach(note) }
        for issue in snap.boardIssues + (snap.assignedIssues ?? []) + (snap.createdIssues ?? []) {
            issue.labels.forEach(note)
        }

        // One set per item, so a PR in two lists counts once.
        var prLabels: [PRKey: Set<String>] = [:]
        for pr in prs where pr.state == .open {
            prLabels[pr.key, default: []].formUnion(pr.labels.map { $0.lowercased() })
        }
        var issueLabels: [PRKey: Set<String>] = [:]
        // The one copy per issue that search reads, so a count never names an item search can't show.
        for issue in SearchEngine.cachedIssues(snap) where issue.isOpen {
            issueLabels[issue.key, default: []].formUnion(issue.labels.map { $0.lowercased() })
        }
        var counts: [String: Int] = [:]
        for set in Array(prLabels.values) + Array(issueLabels.values) {
            for key in set { counts[key, default: 0] += 1 }
        }

        let labels = order.map { LabelCandidate(name: display[$0] ?? $0, openCount: counts[$0] ?? 0) }
        let positions = Dictionary(labels.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return LabelIndex(labels: labels, positions: positions)
    }

    /// Ranked for prefix `p`, ignoring case: (1) the name, (2) a name starting with `p`, (3) a word of
    /// the name starting with `p`, (4) a name containing `p`. Within a tier, more open items first, then
    /// by name.
    public func candidates(prefix: String, limit: Int = 6) -> [LabelCandidate] {
        let p = prefix.lowercased()
        var ranked: [(tier: Int, label: LabelCandidate)] = []
        for label in labels {
            if let tier = Self.tier(of: label.id, for: p) { ranked.append((tier, label)) }
        }
        ranked.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.label.openCount != b.label.openCount { return a.label.openCount > b.label.openCount }
            return a.label.id < b.label.id
        }
        return ranked.prefix(limit).map(\.label)
    }

    public func contains(_ name: String) -> Bool {
        positions[name.lowercased()] != nil
    }

    /// The casing PullBull has seen for `name`; `name` itself when unknown.
    public func display(_ name: String) -> String {
        positions[name.lowercased()].map { labels[$0].name } ?? name
    }

    static func tier(of name: String, for p: String) -> Int? {
        if name == p { return 1 }
        if name.hasPrefix(p) { return 2 }
        let parts = name.split { $0.isWhitespace || $0 == "-" || $0 == "_" || $0 == "/" || $0 == ":" }
        if parts.contains(where: { $0.hasPrefix(p) }) { return 3 }
        if name.contains(p) { return 4 }
        return nil
    }
}
