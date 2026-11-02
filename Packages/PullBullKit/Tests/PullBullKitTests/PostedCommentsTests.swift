import Foundation
import Testing
@testable import PullBullKit

private typealias Comment = PullBullKit.Comment
private let t0 = Date(timeIntervalSince1970: 1_800_000_100)
private let key = editKey(7)
private let life = EditOverrides.lifetime

private func prWith(count: Int, last: String? = "alice", author: String = "pb") -> PullRequest {
    var pr = editPR(7, author: author)
    pr.commentCount = count
    pr.lastCommentAuthor = last
    pr.lastCommentByBot = false
    return pr
}

private func issueWith(count: Int, last: String? = "alice") -> BoardIssue {
    var issue = editIssue(7)
    issue.commentCount = count
    issue.lastCommentAuthor = last
    issue.lastCommentByBot = false
    return issue
}

private func held(_ n: Int) -> [Comment] {
    (0..<n).map { Comment(id: "C\($0)", author: "alice", body: "b\($0)", createdAt: t0.addingTimeInterval(Double($0) - 100)) }
}

private let github = Comment(id: "C_new", author: "pb", body: "hello", createdAt: t0)

@Suite struct PostedCommentsTests {
    private func began(listCount: Int? = 3) -> (PostedComments, UUID) {
        var p = PostedComments()
        let id = p.begin(on: key, text: "hello", viewer: "pb", listCount: listCount, at: t0)
        return (p, id)
    }

    @Test func sendingShowsAtEndOfConversation() {
        let (p, _) = began()
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0)
        #expect(r.comments.count == 3)
        #expect(r.comments.last?.author == "pb")
        #expect(r.comments.last?.body == "hello")
        #expect(r.total == 3)
        #expect(r.sendingIndex == 2)
        #expect(p.isSending(key))
    }

    @Test func postedSwapsInGitHubsComment() {
        var (p, id) = began()
        p.posted(id, as: github)
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0)
        #expect(r.comments.last == github)
        #expect(r.sendingIndex == nil)
        #expect(!p.isSending(key))
    }

    @Test func droppedWhenDetailHoldsId() {
        var (p, id) = began()
        p.posted(id, as: github)
        let h = held(2) + [github]
        let r = p.conversation(for: key, held: h, total: 3, keep: nil, now: t0)
        #expect(r.comments == h)
        #expect(r.total == 3)
    }

    /// Once a detail has held it, a fetch without it means it was deleted on GitHub: not shown again.
    @Test func deletedAfterTheDetailHeldItStaysGone() {
        var (p, id) = began()
        p.posted(id, as: github)
        p.detailFetched(key, comments: held(2) + [github])
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0.addingTimeInterval(10))
        #expect(r.comments == held(2))
        #expect(r.total == 2)
    }

    /// Held only as "a newer comment is there" (an issue page's two-comment window): deleting it stays gone too.
    @Test func deletedAfterANewerCommentWasHeldStaysGone() {
        var (p, id) = began()
        p.posted(id, as: github)
        let newer = Comment(id: "IC_newer", author: "bob", body: "later", createdAt: github.createdAt.addingTimeInterval(5))
        p.detailFetched(key, comments: [newer])
        let r = p.conversation(for: key, held: held(1), total: 1, keep: 2, now: t0.addingTimeInterval(10))
        #expect(!r.comments.contains(github))
    }

    /// Another item's fetch settles nothing.
    @Test func otherItemsFetchKeepsIt() {
        var (p, id) = began()
        p.posted(id, as: github)
        p.detailFetched(editKey(8), comments: [github])
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0.addingTimeInterval(10))
        #expect(r.comments.last == github)
    }

    @Test func preFetchDetailKeepsIt() {
        var (p, id) = began()
        p.posted(id, as: github)
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0.addingTimeInterval(10))
        #expect(r.comments.last == github)
    }

    @Test func expiresAfterLifetime() {
        var (p, id) = began()
        p.posted(id, as: github)
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0.addingTimeInterval(life + 1))
        #expect(r.comments == held(2))
        #expect(r.total == 2)
    }

    @Test func issuePageKeepsNewestTwo() {
        var (p, id) = began()
        p.posted(id, as: github)
        let h = held(2)
        let r = p.conversation(for: key, held: h, total: 5, keep: 2, now: t0)
        #expect(r.comments == [h[1], github])
        #expect(r.total == 6)
        #expect(r.earlier == 4)
    }

    @Test func rowsCountAndNameViewer() {
        let (p, _) = began()
        let pr = p.apply(to: prWith(count: 3))
        #expect(pr.commentCount == 4)
        #expect(pr.lastCommentAuthor == "pb")
        #expect(pr.lastCommentByBot == false)
        let issue = p.apply(to: issueWith(count: 3))
        #expect(issue.commentCount == 4)
        #expect(issue.lastCommentAuthor == "pb")
        #expect(issue.lastCommentByBot == false)
        let results = p.apply(to: SearchResults(
            openPRs: [prWith(count: 3)], closedPRs: [], issues: [issueWith(count: 3)], phase: .done))
        #expect(results.openPRs[0].commentCount == 4)
        #expect(results.issues[0].lastCommentAuthor == "pb")
        let snap = p.apply(to: editSnapshot(board: [issueWith(count: 3)], mine: [prWith(count: 3)]))
        #expect(snap.mine[0].commentCount == 4)
        #expect(snap.boardIssues[0].commentCount == 4)
    }

    @Test func unansweredClearsOnPost() {
        let (p, _) = began()
        let pr = prWith(count: 3)
        #expect(ItemCondition.unanswered.matches(pr, viewer: "pb"))
        #expect(!ItemCondition.unanswered.matches(p.apply(to: pr), viewer: "pb"))
    }

    @Test func agreesOnHigherCount() {
        var (p, _) = began()
        p.reconcile(with: editSnapshot(mine: [prWith(count: 4, last: "bob")]), now: t0)
        let pr = p.apply(to: prWith(count: 4, last: "bob"))
        #expect(pr.commentCount == 4)
        #expect(pr.lastCommentAuthor == "bob")
        let stale = p.apply(to: SearchResults(openPRs: [prWith(count: 3)], closedPRs: [], issues: [], phase: .done))
        #expect(stale.openPRs[0].commentCount == 3)
        #expect(stale.openPRs[0].lastCommentAuthor == "alice")
    }

    @Test func twoPostsBasesStack() {
        var (p, _) = began()
        p.begin(on: key, text: "two", viewer: "pb", listCount: 3, at: t0)
        #expect(p.apply(to: prWith(count: 3)).commentCount == 5)
        p.reconcile(with: editSnapshot(mine: [prWith(count: 4)]), now: t0)
        #expect(p.apply(to: prWith(count: 4)).commentCount == 5)
        #expect(p.apply(to: prWith(count: 3)).commentCount == 4)
        p.reconcile(with: editSnapshot(mine: [prWith(count: 5, last: "bob")]), now: t0)
        let pr = p.apply(to: prWith(count: 5, last: "bob"))
        #expect(pr.commentCount == 5)
        #expect(pr.lastCommentAuthor == "bob")
    }

    @Test func searchCopyAlreadyCountingIsNotRaised() {
        let (p, _) = began()
        let results = p.apply(to: SearchResults(openPRs: [prWith(count: 4)], closedPRs: [], issues: [], phase: .done))
        #expect(results.openPRs[0].commentCount == 4)
    }

    @Test func rowsExpireOnReconcile() {
        var (p, _) = began()
        let snap = editSnapshot(mine: [prWith(count: 3)])
        p.reconcile(with: snap, now: t0.addingTimeInterval(life + 1))
        #expect(p.apply(to: prWith(count: 3)).commentCount == 3)
    }

    @Test func noListCopyNeverTouchesRows() {
        let (p, _) = began(listCount: nil)
        let pr = prWith(count: 3)
        #expect(p.apply(to: pr) == pr)
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0)
        #expect(r.comments.count == 3)
    }

    @Test func dropRemovesSending() {
        var (p, id) = began()
        p.drop(id)
        #expect(!p.isSending(key))
        let r = p.conversation(for: key, held: held(2), total: 2, keep: nil, now: t0)
        #expect(r.comments == held(2))
        #expect(r.sendingIndex == nil)
        let pr = prWith(count: 3)
        #expect(p.apply(to: pr) == pr)
    }

    @Test func notResurrectedAfterWindowMoves() {
        var (p, id) = began()
        p.posted(id, as: github)
        let first = [github, Comment(id: "C_x", author: "alice", body: "x", createdAt: t0.addingTimeInterval(5))]
        #expect(p.conversation(for: key, held: first, total: 5, keep: 2, now: t0.addingTimeInterval(6)).total == 5)
        let moved = [
            Comment(id: "C_x", author: "alice", body: "x", createdAt: t0.addingTimeInterval(5)),
            Comment(id: "C_y", author: "bob", body: "y", createdAt: t0.addingTimeInterval(8)),
        ]
        let r = p.conversation(for: key, held: moved, total: 6, keep: 2, now: t0.addingTimeInterval(10))
        #expect(r.comments == moved)
        #expect(r.total == 6)
    }

    @Test func dropRebasesLaterPosts() {
        var p = PostedComments()
        p.begin(on: key, text: "A", viewer: "pb", listCount: 3, at: t0)
        let b = p.begin(on: key, text: "B", viewer: "pb", listCount: 3, at: t0)
        p.begin(on: key, text: "C", viewer: "pb", listCount: 3, at: t0)
        p.drop(b)
        #expect(p.apply(to: prWith(count: 3)).commentCount == 5)
        p.reconcile(with: editSnapshot(mine: [prWith(count: 5, last: "bob")]), now: t0)
        #expect(p.apply(to: prWith(count: 4)).commentCount == 4)
    }

    @Test func beginPrunesExpiredBeforeBasing() {
        var p = PostedComments()
        p.begin(on: key, text: "one", viewer: "pb", listCount: 3, at: t0)
        p.begin(on: key, text: "two", viewer: "pb", listCount: 3, at: t0.addingTimeInterval(life + 1))
        #expect(p.apply(to: prWith(count: 3)).commentCount == 4)
        #expect(p.apply(to: prWith(count: 4)).commentCount == 4)
    }
}
