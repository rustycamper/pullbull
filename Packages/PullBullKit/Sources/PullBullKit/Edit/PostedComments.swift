import Foundation

/// Comments posted from PullBull that GitHub's reads may not show yet. A detail shows each at the end of
/// its Conversation until the detail holds it, and every list and search row counts it and names the viewer
/// as last commenter until a fetch counts it too, or `EditOverrides.lifetime` passes and GitHub's answer wins.
/// Applied to what is shown, never stored into a fetch, so notifications keep comparing raw fetches.
public struct PostedComments: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let id: UUID
        let key: PRKey
        let text: String
        let viewer: String
        /// The comment count the raw list copy would show without this entry; nil when no list holds the item.
        var basis: Int?
        let madeAt: Date
        var comment: Comment?
        /// A fetch has counted this comment on the rows.
        var agreed = false

        var raisesRows: Bool { basis != nil && !agreed }
    }

    /// In the order the comments were posted.
    private var entries: [Entry] = []

    public init() {}

    /// Starts a post: shows `text` by `viewer` as sending. `listCount` is the raw copy's commentCount from
    /// a list, else from search results, else from the opened item; nil only when nothing holds the item.
    @discardableResult
    public mutating func begin(on key: PRKey, text: String, viewer: String, listCount: Int?, at now: Date) -> UUID {
        let id = UUID()
        entries.removeAll { now.timeIntervalSince($0.madeAt) >= EditOverrides.lifetime }
        let pending = entries.filter { $0.key == key && $0.raisesRows }.count
        entries.append(Entry(
            id: id, key: key, text: text, viewer: viewer, basis: listCount.map { $0 + pending }, madeAt: now))
        return id
    }

    /// GitHub took the comment: shows its own copy in place of the sending one.
    public mutating func posted(_ id: UUID, as comment: Comment) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].comment = comment
    }

    /// Takes one post back off, as when GitHub refused it.
    /// Later posts on the same item that still raise rows are re-based one lower.
    public mutating func drop(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let dropped = entries.remove(at: index)
        guard dropped.raisesRows else { return }
        for later in entries.indices where later >= index && entries[later].key == dropped.key && entries[later].raisesRows {
            entries[later].basis = entries[later].basis.map { $0 - 1 }
        }
    }

    /// Whether a post on `key` is still waiting for GitHub's answer.
    public func isSending(_ key: PRKey) -> Bool {
        entries.contains { $0.key == key && $0.comment == nil }
    }

    /// Agrees row entries whose snapshot copy's commentCount exceeds their basis; drops entries past 5 minutes.
    public mutating func reconcile(with fetched: Snapshot, now: Date) {
        entries.removeAll { now.timeIntervalSince($0.madeAt) >= EditOverrides.lifetime }
        guard entries.contains(where: \.raisesRows) else { return }
        var counts: [PRKey: [Int]] = [:]
        for pr in fetched.reviewCandidates + fetched.mine + fetched.team + fetched.recentlyClosed {
            counts[pr.key, default: []].append(pr.commentCount)
        }
        let issues = fetched.boardIssues + (fetched.assignedIssues ?? []) + (fetched.createdIssues ?? [])
            + (fetched.closedIssues ?? [])
        for issue in issues {
            counts[issue.key, default: []].append(issue.commentCount)
        }
        for index in entries.indices where entries[index].raisesRows {
            if let basis = entries[index].basis, counts[entries[index].key]?.contains(where: { $0 > basis }) == true {
                entries[index].agreed = true
            }
        }
    }

    // MARK: Rows

    public func apply(to snapshot: Snapshot) -> Snapshot {
        guard entries.contains(where: \.raisesRows) else { return snapshot }
        var shown = snapshot
        shown.boardIssues = shown.boardIssues.map(apply(to:))
        shown.assignedIssues = shown.assignedIssues?.map(apply(to:))
        shown.createdIssues = shown.createdIssues?.map(apply(to:))
        shown.closedIssues = shown.closedIssues?.map(apply(to:))
        shown.reviewCandidates = shown.reviewCandidates.map(apply(to:))
        shown.mine = shown.mine.map(apply(to:))
        shown.team = shown.team.map(apply(to:))
        shown.recentlyClosed = shown.recentlyClosed.map(apply(to:))
        return shown
    }

    public func apply(to results: SearchResults) -> SearchResults {
        guard entries.contains(where: \.raisesRows) else { return results }
        var shown = results
        shown.openPRs = results.openPRs.map(apply(to:))
        shown.closedPRs = results.closedPRs.map(apply(to:))
        shown.issues = results.issues.map(apply(to:))
        return shown
    }

    public func apply(to pr: PullRequest) -> PullRequest {
        guard let (count, viewer) = raised(pr.key, copyCount: pr.commentCount) else { return pr }
        var pr = pr
        pr.commentCount = count
        pr.lastCommentAuthor = viewer
        pr.lastCommentByBot = false
        return pr
    }

    public func apply(to issue: BoardIssue) -> BoardIssue {
        guard let (count, viewer) = raised(issue.key, copyCount: issue.commentCount) else { return issue }
        var issue = issue
        issue.commentCount = count
        issue.lastCommentAuthor = viewer
        issue.lastCommentByBot = false
        return issue
    }

    /// The count and last commenter a copy shows, or nil when no entry raises it. An entry raises a copy
    /// only while the copy's count is no more than its basis, so a copy that already counts it isn't raised.
    private func raised(_ key: PRKey, copyCount: Int) -> (Int, String)? {
        let raising = entries.filter { entry in
            guard entry.key == key, entry.raisesRows, let basis = entry.basis else { return false }
            return copyCount <= basis
        }
        guard let last = raising.last else { return nil }
        return (copyCount + raising.count, last.viewer)
    }

    // MARK: Conversation

    /// Conversation shown on a detail: `held` (oldest first) plus entries whose ID `held` lacks and that
    /// are under 5 minutes old; `keep` trims to the newest N (2 on issue pages, nil on PR pages). A posted
    /// entry is also left out once `held` has a comment as new as GitHub's copy of it: the detail was
    /// fetched after the post, and has only scrolled it out of its window. `sendingIndex` assumes at most
    /// one post in flight per item (the field is read-only while sending).
    public func conversation(for key: PRKey, held: [Comment], total: Int, keep: Int?, now: Date)
        -> (comments: [Comment], total: Int, earlier: Int, sendingIndex: Int?)
    {
        let heldIDs = Set(held.compactMap(\.id))
        let shown = entries.filter { entry in
            guard entry.key == key, now.timeIntervalSince(entry.madeAt) < EditOverrides.lifetime else { return false }
            if let posted = entry.comment {
                if let id = posted.id, heldIDs.contains(id) { return false }
                if held.contains(where: { $0.createdAt >= posted.createdAt }) { return false }
            }
            return true
        }
        var comments = held + shown.map { $0.comment ?? Comment(author: $0.viewer, body: $0.text, createdAt: $0.madeAt) }
        var sendingIndex = shown.lastIndex { $0.comment == nil }.map { held.count + $0 }
        let total = total + shown.count
        if let keep, comments.count > keep {
            let cut = comments.count - keep
            comments.removeFirst(cut)
            sendingIndex = sendingIndex.flatMap { $0 >= cut ? $0 - cut : nil }
        }
        return (comments, total, max(0, total - comments.count), sendingIndex)
    }
}
