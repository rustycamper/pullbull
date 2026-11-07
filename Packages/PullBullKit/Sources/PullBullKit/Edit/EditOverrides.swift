import Foundation

/// Edits made in PullBull that GitHub's answers may not show yet. Search lags, and a refresh can be in
/// flight from before the edit, so each edit is laid over what was fetched until a fetch agrees with it,
/// or `lifetime` passes and GitHub's answer wins. Applied to what is shown, never stored into a fetch,
/// so notifications keep comparing raw fetches.
public struct EditOverrides: Equatable, Sendable {
    public static let lifetime: TimeInterval = 300
    /// How far GitHub's clock may trail the Mac's, for a ready event stamped just before the edit was recorded.
    private static let clockSkew: TimeInterval = 60

    private struct Entry: Equatable, Sendable {
        let id: UUID
        let key: PRKey
        let change: EditChange
        let madeAt: Date
        /// The pull request as it was when a reviewers edit was made, for Review to show it when the
        /// viewer asks themselves before a fetch lists it there.
        let copy: PullRequest?
    }

    /// In the order the edits were made, which is the order they apply in.
    private var entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    /// `copy`: the pull request a reviewers edit is made on, as fetched. A draft flip replaces the PR's earlier
    /// flips, so a stale read agreeing with one can't settle it, and its auto-merge edits, which would replay
    /// an auto-merge GitHub may have turned off since.
    @discardableResult
    public mutating func record(_ change: EditChange, on key: PRKey, at date: Date, carrying copy: PullRequest? = nil) -> UUID {
        if case .draft = change {
            entries.removeAll { entry in
                guard entry.key == key else { return false }
                switch entry.change {
                case .draft, .autoMerge: return true
                default: return false
                }
            }
        }
        let id = UUID()
        entries.append(Entry(id: id, key: key, change: change, madeAt: date, copy: copy))
        return id
    }

    /// Takes one edit back off, as when GitHub refused it.
    public mutating func drop(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Replaces edit `id`'s change in place, keeping its date and its position in the order; drops it
    /// when `change` is empty.
    public mutating func replace(_ id: UUID, with change: EditChange) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if change.isEmpty {
            entries.remove(at: index)
        } else {
            let old = entries[index]
            entries[index] = Entry(id: old.id, key: old.key, change: change, madeAt: old.madeAt, copy: old.copy)
        }
    }

    /// Drops each edit `fetched` agrees with, along with the older edits to the same item it replaced;
    /// each older than `lifetime`; and each Status edit to an option the board no longer has. A review on
    /// a key in `held`, or a merge, auto-merge or draft edit on a key in `heldMerges`, stays although
    /// `fetched` agrees, as its going would uncover an older detail.
    public mutating func reconcile(
        with fetched: Snapshot, now: Date, holdingReviews held: Set<PRKey> = [], holdingMerges heldMerges: Set<PRKey> = []
    ) {
        let options = fetched.boardStatusOptions.flatMap { $0.isEmpty ? nil : Set($0.map(\.id)) }
        var retired = Set<UUID>()
        for (index, entry) in entries.enumerated() {
            if now.timeIntervalSince(entry.madeAt) >= Self.lifetime {
                retired.insert(entry.id)
            } else if case .status(_, let to?, _) = entry.change, let options, !options.contains(to.optionId) {
                retired.insert(entry.id)
            } else if Self.agrees(entry, with: fetched) {
                if case .review = entry.change, held.contains(entry.key) { continue }
                if Self.isMerge(entry.change), heldMerges.contains(entry.key) { continue }
                retired.insert(entry.id)
                for older in entries[..<index] where older.key == entry.key && Self.overlaps(older.change, entry.change) {
                    retired.insert(older.id)
                }
            }
        }
        entries.removeAll { retired.contains($0.id) }
    }

    /// The pull requests whose detail in `details` lacks the newest review laid over it. GitHub answers a
    /// review before its reads catch up, so the detail fetched straight after one can miss it.
    public func reviewsAhead(of details: [PRKey: PRDetail]) -> Set<PRKey> {
        var newest: [PRKey: Entry] = [:]
        for entry in entries {
            if case .review = entry.change { newest[entry.key] = entry }
        }
        return Set(newest.compactMap { key, entry -> PRKey? in
            guard case .review(let state, let commit, let viewer, _) = entry.change, let detail = details[key] else { return nil }
            let shows = detail.reviews.contains {
                Self.same($0.author, viewer) && $0.state == state && $0.commitOid == commit
            }
            return shows ? nil : key
        })
    }

    /// The pull requests whose detail in `details` lacks the newest merge or auto-merge edit, or the newest
    /// draft flip, laid over it. GitHub answers before its reads catch up, and no list says whether
    /// auto-merge is set. The newest flip is found apart from the merges, so an auto-merge set after a flip
    /// can't end the flip's hold. A detail that is no longer open is never behind on auto-merge, as there's
    /// none left for it to show, nor on a flip, as it has nothing left to merge; nor is one with no merge state.
    public func mergesAhead(of details: [PRKey: PRDetail]) -> Set<PRKey> {
        var newest: [PRKey: Entry] = [:]
        var newestFlip: [PRKey: Entry] = [:]
        for entry in entries where Self.isMerge(entry.change) {
            if case .draft = entry.change { newestFlip[entry.key] = entry } else { newest[entry.key] = entry }
        }
        return Set(newest.keys).union(newestFlip.keys).filter { key in
            guard let detail = details[key] else { return false }
            return [newest[key], newestFlip[key]].compactMap { $0 }.contains { Self.isAhead($0.change, of: detail) }
        }
    }

    /// Whether `detail` doesn't show merge-type edit `change` yet.
    private static func isAhead(_ change: EditChange, of detail: PRDetail) -> Bool {
        switch change {
        case .merged: return detail.state != .merged
        case .autoMerge(let enabled, _):
            if let state = detail.state, state != .open { return false }
            return (detail.merge?.autoMerge != nil) != enabled
        case .draft(let isDraft, _):
            if let state = detail.state, state != .open { return false }
            guard let merge = detail.merge else { return false }
            return merge.isDraft != isDraft
        case .status, .labels, .assignees, .reviewers, .review: return false
        }
    }

    /// The pull requests with a direct merge laid over them, whose rows `TabBuilder` keeps in place until
    /// the edit settles. An auto-merge edit isn't one: its PR stays open.
    public var directMerges: Set<PRKey> {
        Set(entries.compactMap { entry -> PRKey? in
            guard case .merged = entry.change else { return nil }
            return entry.key
        })
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
            if case .reviewers(let added, _) = entry.change, let copy = entry.copy, copy.state == .open,
               !Self.viewerKeys(shown.org).isDisjoint(with: added.map(\.key)),
               !shown.reviewCandidates.contains(where: { $0.key == entry.key }) {
                // Review lists what asks for the viewer's review; the tab's rules decide from here.
                shown.reviewCandidates.append(apply(to: copy))
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

    /// `requests` on pull request `key` with its reviewer edits laid over: the detail's own requests.
    public func apply(toRequests requests: [Reviewer], on key: PRKey) -> [Reviewer] {
        entries.reduce(requests) { requests, entry in
            guard entry.key == key else { return requests }
            switch entry.change {
            case .reviewers(let added, let removed): return Self.changeRequests(requests, added, removed)
            case .review(_, _, let viewer, _): return Self.changeRequests(requests, [], [.user(viewer)])
            default: return requests
            }
        }
    }

    /// `reviews` on pull request `key` with the viewer's submitted review laid over: the detail's own reviews.
    public func apply(toReviews reviews: [Review], on key: PRKey) -> [Review] {
        entries.reduce(reviews) { reviews, entry in
            guard entry.key == key, case .review(let state, let commit, let viewer, let body) = entry.change else { return reviews }
            return Self.changeReviews(reviews, state, commit, viewer, body, at: entry.madeAt)
        }
    }

    /// `info` on pull request `key` with the viewer's auto-merge edits and draft flips laid over: the
    /// detail's own merge state.
    public func apply(toMerge info: MergeInfo?, on key: PRKey) -> MergeInfo? {
        entries.reduce(info) { info, entry in
            guard entry.key == key, var info else { return info }
            switch entry.change {
            case .autoMerge(let enabled, let viewer):
                info.autoMerge = enabled ? AutoMerge(enabledBy: viewer) : nil
                info.canDisableAutoMerge = enabled
            case .draft(let isDraft, _):
                info.isDraft = isDraft
            default:
                break
            }
            return info
        }
    }

    /// `pr`, a pull request linked from an issue's detail, with a draft flip laid over.
    public func apply(toLinked pr: LinkedPR) -> LinkedPR {
        entries.reduce(pr) { pr, entry in
            guard entry.key == pr.key, case .draft(let isDraft, _) = entry.change else { return pr }
            var pr = pr
            pr.isDraft = isDraft
            return pr
        }
    }

    /// `state` on pull request `key` with a merge laid over: the detail's own state.
    public func apply(toState state: PRState?, on key: PRKey) -> PRState? {
        entries.reduce(state) { state, entry in
            guard entry.key == key, case .merged = entry.change else { return state }
            return .merged
        }
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
            issue.assignees = changeAssignees(issue.assignees, added, removed)
        case .reviewers, .review, .merged, .autoMerge, .draft:
            break
        }
        return issue
    }

    /// Pull requests carry no Status or auto-merge here.
    private static func change(_ pr: PullRequest, _ entry: Entry) -> PullRequest {
        guard pr.key == entry.key else { return pr }
        var pr = pr
        switch entry.change {
        case .status, .autoMerge:
            break
        case .labels(let added, let removed):
            (pr.labels, pr.labelColors) = changeLabels(pr.labels, pr.labelColors, added, removed)
        case .assignees(let added, let removed):
            pr.assignees = changeAssignees(pr.assignees, added, removed)
        case .reviewers(let added, let removed):
            let before = Set(pr.reviewRequests.map(\.key))
            pr.reviewRequests = changeRequests(pr.reviewRequests, added, removed)
            // A new request starts its wait now; one already pending keeps GitHub's time.
            for key in added.map(\.key) where !before.contains(key) {
                pr.reviewRequestTimes[key] = entry.madeAt
            }
        case .review(let state, let commit, let viewer, let body):
            pr.latestReviews = changeReviews(pr.latestReviews, state, commit, viewer, body, at: entry.madeAt)
            // The review answers a direct request; a team's request stays until GitHub drops it.
            pr.reviewRequests = changeRequests(pr.reviewRequests, [], [.user(viewer)])
        case .merged(let viewer):
            pr.state = .merged
            pr.mergedBy = viewer
        case .draft(let isDraft, _):
            pr.isDraft = isDraft
            // Marking ready starts the review wait now, until GitHub's ready event arrives.
            if !isDraft { pr.readyForReviewAt = entry.madeAt }
        }
        return pr
    }

    /// Removes and adds people by login, case ignored; someone already assigned isn't added twice.
    private static func changeAssignees(
        _ assignees: [Assignee], _ added: [PersonRef], _ removed: [PersonRef]
    ) -> [Assignee] {
        var assignees = assignees
        assignees.removeAll { assignee in removed.contains { same($0.login, assignee.login) } }
        for person in added where !assignees.contains(where: { same($0.login, person.login) }) {
            assignees.append(Assignee(login: person.login, avatarURL: person.avatarURL))
        }
        return assignees
    }

    /// Review requests with `removed` taken out and `added` appended, matched on login or team slug.
    private static func changeRequests(_ requests: [Reviewer], _ added: [Reviewer], _ removed: [Reviewer]) -> [Reviewer] {
        var requests = requests
        requests.removeAll { request in removed.contains(request.key, by: \.key) }
        for reviewer in added where !requests.contains(reviewer.key, by: \.key) {
            requests.append(reviewer)
        }
        return requests
    }

    /// `reviews` with the viewer's earlier reviews replaced by the one just submitted, logins compared
    /// case-insensitively.
    private static func changeReviews(
        _ reviews: [Review], _ state: ReviewState, _ commit: String, _ viewer: String, _ body: String, at date: Date
    ) -> [Review] {
        var reviews = reviews
        reviews.removeAll { same($0.author, viewer) }
        reviews.append(Review(author: viewer, state: state, submittedAt: date, commitOid: commit, body: body))
        return reviews
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
            guard let issue = issues(in: fetched).first(where: { $0.key == entry.key }) else {
                guard let pr = prs(in: fetched).first(where: { $0.key == entry.key }) else { return false }
                return holds(pr.assignees.map(\.login), added: added.map(\.login), removed: removed.map(\.login))
            }
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
        case .reviewers(let added, let removed):
            guard let pr = prs(in: fetched).first(where: { $0.key == entry.key }) else { return false }
            let have = Set(pr.reviewRequests.map(\.key))
            guard added.allSatisfy({ have.contains($0.key) }), !removed.contains(where: { have.contains($0.key) })
            else { return false }
            guard pr.state == .open else { return true }
            // Review comes from search, which lags the PR's own fields: wait for it too, or the row flickers.
            // The viewer's own teams count as the viewer.
            let mine = Self.viewerKeys(fetched.org)
            let listed = Set(fetched.reviewCandidates.first { $0.key == entry.key }?.reviewRequests.map(\.key) ?? [])
            return added.allSatisfy { !mine.contains($0.key) || listed.contains($0.key) }
                && !removed.contains { mine.contains($0.key) && listed.contains($0.key) }
        case .review(let state, let commit, let viewer, _):
            let copies = prs(in: fetched).filter { $0.key == entry.key }
            return !copies.isEmpty && copies.allSatisfy { copy in
                copy.latestReviews.contains { same($0.author, viewer) && $0.state == state && $0.commitOid == commit }
            }
        case .merged:
            // A merged PR leaves the open lists, and may not reach Recently closed: gone counts as agreeing.
            return !prs(in: fetched).contains { $0.key == entry.key && $0.state == .open }
        case .autoMerge:
            // No list says; `mergesAhead` holds it until the detail does.
            return true
        case .draft(let isDraft, _):
            // As for a merge, a PR in no list agrees, and `mergesAhead` holds it until the detail does. Marking
            // ready waits for the ready event too, or the review wait would jump back to the PR's full age.
            return prs(in: fetched).allSatisfy { copy in
                guard copy.key == entry.key else { return true }
                guard copy.isDraft == isDraft else { return false }
                if isDraft { return true }
                guard let ready = copy.readyForReviewAt else { return false }
                return ready >= entry.madeAt - clockSkew
            }
        }
    }

    private static func isMerge(_ change: EditChange) -> Bool {
        switch change {
        case .merged, .autoMerge, .draft: true
        case .status, .labels, .assignees, .reviewers, .review: false
        }
    }

    /// The reviewer keys that ask for the viewer's own review: the viewer and the viewer's teams.
    private static func viewerKeys(_ org: OrgContext) -> Set<String> {
        Set([Reviewer.user(org.viewer).key] + org.myTeams.map { Reviewer.team(slug: $0, name: $0).key })
    }

    /// Whether `newer` sets something `older` set: the Status, one of the same labels or people, or the
    /// review, merge, auto-merge or draft flip; a review also replaces an older request for the reviewer.
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
        case (.reviewers(let a1, let r1), .reviewers(let a2, let r2)):
            return !Set((a1 + r1).map(\.key)).isDisjoint(with: (a2 + r2).map(\.key))
        case (.review, .review), (.merged, .merged), (.autoMerge, .autoMerge), (.draft, .draft):
            return true
        case (.reviewers(let added, let removed), .review(_, _, let viewer, _)):
            // GitHub drops the viewer's own request on a review, so an older self-add never agrees. An edit
            // that does more stays, as going would take its other changes off the screen.
            return removed.isEmpty && added.map(\.key) == [Reviewer.user(viewer).key]
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
        return prs(in: snapshot).first { $0.key == key }?.labels
    }

    private static func prs(in snapshot: Snapshot) -> [PullRequest] {
        snapshot.reviewCandidates + snapshot.mine + snapshot.team + snapshot.recentlyClosed
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}

private extension Array where Element == Reviewer {
    func contains(_ key: String, by path: KeyPath<Reviewer, String>) -> Bool {
        contains { $0[keyPath: path] == key }
    }
}
