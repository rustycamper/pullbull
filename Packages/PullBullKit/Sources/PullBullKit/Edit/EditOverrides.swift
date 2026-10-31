import Foundation

/// Edits made in PullBull that GitHub's answers may not show yet. Search lags, and a refresh can be in
/// flight from before the edit, so each edit is laid over what was fetched until a fetch agrees with it,
/// or `lifetime` passes and GitHub's answer wins. Applied to what is shown, never stored into a fetch,
/// so notifications keep comparing raw fetches.
public struct EditOverrides: Equatable, Sendable {
    public static let lifetime: TimeInterval = 300

    private struct Entry: Equatable, Sendable {
        let id: UUID
        let key: PRKey
        let change: EditChange
        let madeAt: Date
    }

    /// In the order the edits were made, which is the order they apply in.
    private var entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    @discardableResult
    public mutating func record(_ change: EditChange, on key: PRKey, at date: Date) -> UUID {
        let id = UUID()
        entries.append(Entry(id: id, key: key, change: change, madeAt: date))
        return id
    }

    /// Takes one edit back off, as when GitHub refused it.
    public mutating func drop(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Drops each edit `fetched` agrees with, along with the older edits to the same item it replaced;
    /// each older than `lifetime`; and each Status edit to an option the board no longer has.
    public mutating func reconcile(with fetched: Snapshot, now: Date) {
        let options = fetched.boardStatusOptions.flatMap { $0.isEmpty ? nil : Set($0.map(\.id)) }
        var retired = Set<UUID>()
        for (index, entry) in entries.enumerated() {
            if now.timeIntervalSince(entry.madeAt) >= Self.lifetime {
                retired.insert(entry.id)
            } else if case .status(_, let to?, _) = entry.change, let options, !options.contains(to.optionId) {
                retired.insert(entry.id)
            } else if Self.agrees(entry, with: fetched) {
                retired.insert(entry.id)
                for older in entries[..<index] where older.key == entry.key && Self.overlaps(older.change, entry.change) {
                    retired.insert(older.id)
                }
            }
        }
        entries.removeAll { retired.contains($0.id) }
    }

    // MARK: Applying

    public func apply(to snapshot: Snapshot) -> Snapshot {
        guard !entries.isEmpty else { return snapshot }
        var shown = snapshot
        for entry in entries {
            if case .status(_, let to, let placement) = entry.change {
                Self.place(entry.key, status: to, placement: placement, in: &shown)
                continue
            }
            shown.boardIssues = shown.boardIssues.map { Self.change($0, entry) }
            shown.assignedIssues = shown.assignedIssues?.map { Self.change($0, entry) }
            shown.createdIssues = shown.createdIssues?.map { Self.change($0, entry) }
            shown.closedIssues = shown.closedIssues?.map { Self.change($0, entry) }
            shown.reviewCandidates = shown.reviewCandidates.map { Self.change($0, entry) }
            shown.mine = shown.mine.map { Self.change($0, entry) }
            shown.team = shown.team.map { Self.change($0, entry) }
            shown.recentlyClosed = shown.recentlyClosed.map { Self.change($0, entry) }
            if case .assignees(let added, let removed) = entry.change {
                Self.followViewer(entry.key, added: added, removed: removed, in: &shown)
            }
        }
        return shown
    }

    public func apply(to results: SearchResults) -> SearchResults {
        guard !entries.isEmpty else { return results }
        var shown = results
        shown.openPRs = results.openPRs.map(apply(to:))
        shown.closedPRs = results.closedPRs.map(apply(to:))
        shown.issues = results.issues.map(apply(to:))
        return shown
    }

    public func apply(to issue: BoardIssue) -> BoardIssue {
        entries.reduce(issue) { Self.change($0, $1) }
    }

    public func apply(to pr: PullRequest) -> PullRequest {
        entries.reduce(pr) { Self.change($0, $1) }
    }

    // MARK: One item

    private static func change(_ issue: BoardIssue, _ entry: Entry) -> BoardIssue {
        guard issue.key == entry.key else { return issue }
        var issue = issue
        switch entry.change {
        case .status(_, let to, let placement):
            issue.status = placement == .removed ? nil : to
        case .labels(let added, let removed):
            (issue.labels, issue.labelColors) = changeLabels(issue.labels, issue.labelColors, added, removed)
        case .assignees(let added, let removed):
            issue.assignees.removeAll { assignee in removed.contains { same($0.login, assignee.login) } }
            for person in added where !issue.assignees.contains(where: { same($0.login, person.login) }) {
                issue.assignees.append(Assignee(login: person.login, avatarURL: person.avatarURL))
            }
        }
        return issue
    }

    /// Pull requests carry no assignees or Status here; only labels show.
    private static func change(_ pr: PullRequest, _ entry: Entry) -> PullRequest {
        guard pr.key == entry.key, case .labels(let added, let removed) = entry.change else { return pr }
        var pr = pr
        (pr.labels, pr.labelColors) = changeLabels(pr.labels, pr.labelColors, added, removed)
        return pr
    }

    /// Labels and their colours by position; colours missing from an old cache are padded with nil so
    /// an added label's colour lines up.
    private static func changeLabels(
        _ names: [String], _ colors: [String?], _ added: [LabelRef], _ removed: [LabelRef]
    ) -> ([String], [String?]) {
        var pairs = names.enumerated().map { ($1, colors.indices.contains($0) ? colors[$0] : nil) }
        pairs.removeAll { pair in removed.contains { same($0.name, pair.0) } }
        for label in added where !pairs.contains(where: { same($0.0, label.name) }) {
            pairs.append((label.name, label.color))
        }
        return (pairs.map(\.0), pairs.map(\.1))
    }

    // MARK: Lists

    /// Moves the card to `status`; adds it to the board from the first other copy for `.added`, and
    /// takes it off for `.removed`.
    private static func place(_ key: PRKey, status: BoardStatusValue?, placement: BoardPlacement, in shown: inout Snapshot) {
        switch placement {
        case .removed:
            shown.boardIssues.removeAll { $0.key == key }
        case .added where !shown.boardIssues.contains(where: { $0.key == key }):
            let others = (shown.assignedIssues ?? []) + (shown.createdIssues ?? []) + (shown.closedIssues ?? [])
            guard var issue = others.first(where: { $0.key == key }) else { return }
            issue.status = status
            shown.boardIssues.append(issue)
        case .added, .already:
            shown.boardIssues = shown.boardIssues.map { issue in
                guard issue.key == key else { return issue }
                var moved = issue
                moved.status = status
                return moved
            }
        }
    }

    /// Assigning the viewer puts an open issue on Assigned (when that list was fetched); unassigning
    /// takes it off.
    private static func followViewer(_ key: PRKey, added: [PersonRef], removed: [PersonRef], in shown: inout Snapshot) {
        let viewer = shown.org.viewer
        guard var assigned = shown.assignedIssues else { return }
        if removed.contains(where: { same($0.login, viewer) }) {
            assigned.removeAll { $0.key == key }
        }
        if added.contains(where: { same($0.login, viewer) }), !assigned.contains(where: { $0.key == key }),
           let issue = (shown.boardIssues + (shown.createdIssues ?? [])).first(where: { $0.key == key && $0.isOpen }) {
            assigned.append(issue)
        }
        shown.assignedIssues = assigned
    }

    // MARK: Agreement

    private static func agrees(_ entry: Entry, with fetched: Snapshot) -> Bool {
        switch entry.change {
        case .status(_, let to, let placement):
            let card = fetched.boardIssues.first { $0.key == entry.key }
            if placement == .removed { return card == nil }
            guard let card else { return false }
            return card.status?.optionId == to?.optionId
        case .labels(let added, let removed):
            guard let names = labels(of: entry.key, in: fetched) else { return false }
            return holds(names, added: added.map(\.name), removed: removed.map(\.name))
        case .assignees(let added, let removed):
            guard let issue = issues(in: fetched).first(where: { $0.key == entry.key }) else { return false }
            guard holds(issue.assignees.map(\.login), added: added.map(\.login), removed: removed.map(\.login)) else {
                return false
            }
            // Assigned comes from search, which lags the board: wait for it too, or the row flickers.
            let viewer = fetched.org.viewer
            guard issue.isOpen, let assigned = fetched.assignedIssues else { return true }
            let listed = assigned.contains { $0.key == entry.key }
            if added.contains(where: { same($0.login, viewer) }) { return listed }
            if removed.contains(where: { same($0.login, viewer) }) { return !listed }
            return true
        }
    }

    /// Whether `newer` sets something `older` set: the Status, or one of the same labels or people.
    private static func overlaps(_ older: EditChange, _ newer: EditChange) -> Bool {
        func shared(_ a: [String], _ b: [String]) -> Bool {
            a.contains { name in b.contains { same($0, name) } }
        }
        switch (older, newer) {
        case (.status, .status):
            return true
        case (.labels(let a1, let r1), .labels(let a2, let r2)):
            return shared((a1 + r1).map(\.name), (a2 + r2).map(\.name))
        case (.assignees(let a1, let r1), .assignees(let a2, let r2)):
            return shared((a1 + r1).map(\.login), (a2 + r2).map(\.login))
        default:
            return false
        }
    }

    private static func holds(_ have: [String], added: [String], removed: [String]) -> Bool {
        let have = Set(have.map { $0.lowercased() })
        return added.allSatisfy { have.contains($0.lowercased()) } && !removed.contains { have.contains($0.lowercased()) }
    }

    private static func issues(in snapshot: Snapshot) -> [BoardIssue] {
        snapshot.boardIssues + (snapshot.assignedIssues ?? []) + (snapshot.createdIssues ?? []) + (snapshot.closedIssues ?? [])
    }

    private static func labels(of key: PRKey, in snapshot: Snapshot) -> [String]? {
        if let issue = issues(in: snapshot).first(where: { $0.key == key }) { return issue.labels }
        let prs = snapshot.reviewCandidates + snapshot.mine + snapshot.team + snapshot.recentlyClosed
        return prs.first { $0.key == key }?.labels
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}
