import Foundation
import PullBullKit
import SwiftUI

/// Bumped to tell the comment field on `key` to act; the field acts only when `key` is its own.
struct CommentFieldSignal: Equatable {
    let key: PRKey
    let n: Int
}

// MARK: - Commenting

extension AppModel {
    /// Lets each posted comment a stored detail now holds leave that detail for good, so deleting it on
    /// GitHub isn't undone by the overlay. `comments` reads the stored detail's comments for a key.
    func settlePostedComments(_ comments: (PRKey) -> [Comment]?) {
        for key in postedComments.unsettledKeys {
            if let held = comments(key) { postedComments.detailFetched(key, comments: held) }
        }
    }

    /// Whether this account may comment on `key`. `isPullRequest` comes from the route (`.detail` is a PR,
    /// `.issueDetail` an issue), so a PR in no list is gated as a PR.
    func commentPermission(for key: PRKey, isPullRequest: Bool) -> EditPermission {
        guard let account = runningAccount else { return .unavailable }
        let owner = key.repo.split(separator: "/").first.map(String.init) ?? ""
        return EditPermission.of(
            .comment, account: account, boardOwner: nil, installation: installation(named: owner), ghAccounts: accounts,
            onPullRequest: isPullRequest)
    }

    /// Whether the detail shows the comment field, or the note saying what it needs.
    func isCommentShown(for key: PRKey, isPullRequest: Bool) -> Bool {
        runningAccount != nil && commentPermission(for: key, isPullRequest: isPullRequest) != .unavailable
    }

    /// Whether the current account's post on `key` is waiting for its outcome; the field is read-only and
    /// its button reads "Sending…" meanwhile. Lasts across account and org switches, unlike the overlay.
    func isPostInFlight(for key: PRKey) -> Bool {
        guard let account = runningAccount else { return false }
        return postsInFlight.contains(account: account.login, key: key)
    }

    /// Posts the draft on `key`, trimmed. Shows it as sending at once; GitHub's answer makes it the real
    /// comment, takes it back with the reason, or, when the outcome is unknown, a fresh detail decides.
    func postComment(on key: PRKey, isPullRequest: Bool) {
        guard let account = runningAccount,
              commentPermission(for: key, isPullRequest: isPullRequest) == .ready,
              let draft = commentDrafts[account: account.login, key: key] else { return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPostInFlight(for: key), !postedComments.isSending(key) else { return }
        // Another post replaces the failure line, as an edit does; ⌘Z and the last edit stay.
        edits.dismissFailure()
        let start = Date()
        let url = fetchedPullRequest(for: key)?.url ?? GitHubLinks.issue(key)
        let listCount = fetchedPullRequest(for: key)?.commentCount ?? fetchedIssue(for: key)?.commentCount
        postsInFlight.insert(account: account.login, key: key)
        let id = postedComments.begin(on: key, text: text, viewer: account.login, listCount: listCount, at: start)
        refreshShown()
        AccessibilityNotification.Announcement("Sending comment").post()
        let client = api(for: account)
        let post = PendingComment(
            id: id, key: key, isPullRequest: isPullRequest, text: text, account: account, start: start, url: url)
        Task { [weak self] in
            do {
                let comment = try await client.postComment(on: key, body: text)
                self?.commentPosted(post, as: comment, reload: true)
            } catch {
                guard let self else { return }
                switch CommentFailure.classify(error) {
                case .refused(let reason):
                    self.commentFailed(post, text: EditMessage.commentRefused(on: key, reason: reason), focus: true)
                case .unknown:
                    self.confirmComment(post)
                }
            }
        }
    }

    /// One post on its way, with what its answer needs.
    private struct PendingComment {
        let id: UUID
        let key: PRKey
        /// From the route the post was made on: whether `key` is a pull request.
        let isPullRequest: Bool
        /// As sent: the draft, trimmed.
        let text: String
        let account: AccountRef
        let start: Date
        /// The item on GitHub, for the failure line's **Open on GitHub**.
        let url: URL
    }

    /// GitHub has the comment. The posting account's draft goes even when another account now runs;
    /// the rest only while the posting account does. `reload` fetches the item's detail again, whether
    /// it's on screen or held under another layer, so the comment stays once the overlay lets it go.
    private func commentPosted(_ post: PendingComment, as comment: Comment, reload: Bool) {
        postsInFlight.remove(account: post.account.login, key: post.key)
        commentDrafts[account: post.account.login, key: post.key] = nil
        guard runningAccount == post.account else { return }
        postedComments.posted(post.id, as: comment)
        // The unknown-outcome check found it in a detail already stored.
        settlePostedComments { details[$0]?.comments ?? issueDetails[$0]?.lastComments }
        refreshShown()
        resetCommentField(on: post.key)
        if reload {
            if route == .detail(post.key) {
                reloadDetail()
            } else if route == .issueDetail(post.key) {
                reloadIssueDetail()
            } else if post.isPullRequest ? details[post.key] != nil : issueDetails[post.key] != nil {
                Task { [weak self] in
                    _ = try? await self?.fetchDetailComments(
                        post.key, isPullRequest: post.isPullRequest, account: post.account)
                }
            }
        }
        AccessibilityNotification.Announcement("Comment posted").post()
    }

    /// The comment isn't on GitHub, or can't be shown to be: it goes, the draft stays, the failure line
    /// says why. `focus` hands the field back for a refusal, only while the item's detail is on top with
    /// no picker over it: a field under another layer can still take focus, and ⌘↩ would post from it.
    /// Only `postsInFlight` changes once another account runs.
    private func commentFailed(_ post: PendingComment, text: String, focus: Bool) {
        postsInFlight.remove(account: post.account.login, key: post.key)
        guard runningAccount == post.account else { return }
        postedComments.drop(post.id)
        refreshShown()
        edits.showFailure(EditFailure(text: text, url: post.url))
        let shown: Route = post.isPullRequest ? .detail(post.key) : .issueDetail(post.key)
        if focus, route == shown, statusPicker == nil, setPicker == nil { requestCommentFieldFocus(on: post.key) }
    }

    /// The post's outcome is unknown: it stays sending while a fresh detail is read. A comment by the
    /// viewer with the sent text, made since the post started, counts as posted; anything else, or a
    /// failed read, as unconfirmed. Never sends again. Runs with the posting account even after a switch,
    /// so the post's outcome becomes final and it leaves `postsInFlight`.
    private func confirmComment(_ post: PendingComment) {
        Task { [weak self] in
            guard let self else { return }
            let comments = try? await self.fetchDetailComments(
                post.key, isPullRequest: post.isPullRequest, account: post.account)
            if let comments,
               let landed = CommentCheck.landed(post.text, by: post.account.login, since: post.start, in: comments) {
                self.commentPosted(post, as: landed, reload: false)
            } else {
                self.commentFailed(post, text: EditMessage.commentUnconfirmed(on: post.key), focus: false)
            }
        }
    }
}
