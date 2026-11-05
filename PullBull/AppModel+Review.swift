import Foundation
import PullBullKit
import SwiftUI

// MARK: - Review mode

extension AppModel {
    /// Whether the detail offers a review of `key`: the Review button, and ⌥⌘V doing anything.
    func isReviewOffered(for key: PRKey) -> Bool {
        ReviewGate.canReview(
            detail: details[key], viewer: runningAccount?.login, permission: setEditPermission(.review, for: key))
    }

    /// ⌥⌘V or Review: pins the head on screen, which nothing moves from here on, and focuses the field.
    func enterReviewMode(on key: PRKey) {
        guard isReviewOffered(for: key), !isPostInFlight(for: key), reviewMode?.key != key,
              let detail = details[key], let head = detail.headOid, let viewer = runningAccount?.login
        else { return }
        let last = detail.reviews
            .filter { $0.author.caseInsensitiveCompare(viewer) == .orderedSame }
            .max { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }
        let mode = ReviewMode(key: key, head: head, lastReview: last?.state)
        reviewMode = mode
        requestCommentFieldFocus(on: key)
        let summary = ReviewSummary(head: mode.head, detail: detail)
        AccessibilityNotification.Announcement("Reviewing. \(mode.verdict.title) selected. \(summary.text)").post()
    }

    /// Esc or Cancel: review mode ends and the text stays. During the check this is what stops it, and the
    /// only place a cancelled attempt's slot goes: its task then touches nothing, as the slot may by then
    /// be a new attempt's. A write under way can't be called back.
    func leaveReviewMode() {
        guard let mode = reviewMode, mode.canCancel else { return }
        if mode.phase == .checking {
            reviewCheckTask?.cancel()
            if let account = runningAccount { postsInFlight.remove(account: account.login, key: mode.key) }
        }
        reviewMode = nil
    }

    /// The field blurred, the screen or account changed, the popover closed or a review finished: review
    /// mode on `key`, or on anything when nil, ends. A submit under way carries on, since ⌘↩ meant send.
    func endReviewMode(on key: PRKey?) {
        guard key == nil || reviewMode?.key == key else { return }
        reviewMode = nil
    }

    func changeReviewVerdict() {
        reviewMode?.toggleVerdict()
    }
}

// MARK: - Submitting

extension AppModel {
    /// One submitted review on its way, with what its answer needs. It can outlive review mode, and the
    /// viewer may be on another PR, so every write to `reviewMode` from here on is guarded by its key.
    private struct PendingReview {
        let key: PRKey
        /// As at ⌘↩; the verdict can't change under the check.
        let verdict: ReviewVerdict
        let head: String
        let account: AccountRef
        /// The item on GitHub, for the failure line's **Open on GitHub**.
        let url: URL
        /// When the write started, for the unknown-outcome check.
        var since: Date
        /// Nil when another account ran at the send. `clearAccountData` can also leave it stale, and
        /// dropping a stale id does nothing.
        var overlay: UUID?
    }

    /// ⌘↩ in review mode: checks the head is still the pinned one, then sends the review on that commit.
    /// Empty text is a valid Approve, so there's no draft to require here, unlike `postComment`.
    func submitReview(on key: PRKey) {
        guard let mode = reviewMode, mode.key == key, mode.phase == .composing, let account = runningAccount,
              setEditPermission(.review, for: key) == .ready, !isPostInFlight(for: key) else { return }
        let text = (commentDrafts[account: account.login, key: key]?.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReviewGate.canSubmit(mode.verdict, text: text) else {
            reviewMode?.missingText = true
            AccessibilityNotification.Announcement(CommentRow.reviewPlaceholder(mode.verdict)).post()
            return
        }
        edits.dismissFailure()
        endMentions()
        postsInFlight.insert(account: account.login, key: key)
        reviewMode?.phase = .checking
        let verdict = mode.verdict
        let url = fetchedPullRequest(for: key)?.url ?? GitHubLinks.pullRequest(key)
        let client = api(for: account)
        var review = PendingReview(
            key: key, verdict: verdict, head: mode.head, account: account, url: url, since: Date())
        reviewCheckTask = Task { [weak self] in
            let outcome = await ReviewFlow.run(
                pinned: review.head,
                // Only `leaveReviewMode` cancels this task, so this reads as "Cancel or Esc was pressed".
                // Blur, closing the popover and an account change end the mode and leave it running.
                isCancelled: { Task.isCancelled },
                readHead: { try await client.prHead(key) },
                willSend: { self?.reviewWillSend(&review) },
                send: { commit in
                    try await client.submitReview(on: key, verdict: verdict, body: text, commit: commit)
                })
            self?.reviewAnswered(review, outcome, client: client)
        }
    }

    /// The head checked out and the write is about to start: it can't be called back from here. Shown at
    /// once, for the posting account only: another account may be reviewing the same PR by now, and that
    /// mode isn't this review's.
    private func reviewWillSend(_ review: inout PendingReview) {
        review.since = Date()
        guard runningAccount == review.account else { return }
        if reviewMode?.key == review.key { reviewMode?.phase = .sending }
        let before = shownListKeys()
        let change = EditChange.review(state: review.verdict.state, commit: review.head, viewer: review.account.login)
        review.overlay = edits.recordReview(change, on: review.key, at: Date())
        sendingReviews.insert(review.key)
        refreshShown()
        followEditedRow(review.key, from: before)
        AccessibilityNotification.Announcement("Sending review").post()
    }

    private func reviewAnswered(_ review: PendingReview, _ outcome: ReviewOutcome, client: GitHubAPI) {
        let key = review.key
        switch outcome {
        case .cancelled:
            // `leaveReviewMode` did the work, and the slot may now belong to a new attempt.
            break
        case .sent:
            reviewSent(review)
        case .headMoved:
            guard settleReview(review) else { return }
            endReviewMode(on: key)
            // Out of the field, so a following ⌘↩ opens GitHub rather than posting the text as a comment.
            releaseCommentField(on: key)
            showReviewFailure(EditMessage.reviewHeadMoved(on: key), review)
            reloadReviewedDetail(review)
        case .notOpen(let merged):
            guard settleReview(review) else { return }
            backToComposing(on: key)
            showReviewFailure(EditMessage.reviewNotOpen(on: key, merged: merged), review)
            reloadReviewedDetail(review)
        case .checkFailed(let reason):
            guard settleReview(review) else { return }
            backToComposing(on: key)
            showReviewFailure(EditMessage.reviewRefused(on: key, reason: reason), review)
        case .refused(let reason):
            guard settleReview(review) else { return }
            dropReviewOverlay(review)
            backToComposing(on: key)
            showReviewFailure(EditMessage.reviewRefused(on: key, reason: reason), review)
        case .unknown:
            confirmReview(review, client: client)
        }
    }

    /// The write had no clear answer: the field stays read-only while a fresh detail decides. A failed read
    /// counts as unconfirmed, and nothing is ever sent again. Runs with the posting account even after a
    /// switch, so the slot goes. Its own task, which nothing cancels. The read is kept either way, so the
    /// Reviewers section the unconfirmed line points at shows what GitHub has.
    private func confirmReview(_ review: PendingReview, client: GitHubAPI) {
        Task { [weak self] in
            let fresh = try? await client.detail(review.key)
            guard let self else { return }
            if let fresh, ReviewCheck.landed(
                review.verdict, by: review.account.login, since: review.since, in: fresh.reviews) != nil {
                self.reviewSent(review, read: fresh)
                return
            }
            guard self.settleReview(review) else { return }
            if let fresh { self.keepDetail(fresh) }
            self.dropReviewOverlay(review)
            self.endReviewMode(on: review.key)
            self.releaseCommentField(on: review.key)
            self.showReviewFailure(EditMessage.reviewUnconfirmed(on: review.key), review)
        }
    }

    /// GitHub has the review. The posting account's draft goes even when another account now runs. `read`
    /// is the detail that showed it landed, which stands in for fetching it again.
    private func reviewSent(_ review: PendingReview, read: PRDetail? = nil) {
        let isCurrent = settleReview(review)
        commentDrafts[account: review.account.login, key: review.key] = nil
        guard isCurrent else { return }
        endReviewMode(on: review.key)
        resetCommentField(on: review.key)
        releaseCommentField(on: review.key)
        if let read {
            keepDetail(read)
        } else {
            reloadReviewedDetail(review)
        }
        let done = switch review.verdict {
        case .approve: "Approved #\(review.key.number)"
        case .requestChanges: "Requested changes on #\(review.key.number)"
        }
        AccessibilityNotification.Announcement(done).post()
    }

    /// The outcome is final: the review leaves the in-flight tracking. True while its account still runs;
    /// nothing else may change otherwise.
    private func settleReview(_ review: PendingReview) -> Bool {
        postsInFlight.remove(account: review.account.login, key: review.key)
        sendingReviews.remove(review.key)
        return runningAccount == review.account
    }

    private func dropReviewOverlay(_ review: PendingReview) {
        let before = shownListKeys()
        if let id = review.overlay { edits.dropReview(id) }
        refreshShown()
        followEditedRow(review.key, from: before)
    }

    private func backToComposing(on key: PRKey) {
        if reviewMode?.key == key { reviewMode?.phase = .composing }
    }

    private func showReviewFailure(_ text: String, _ review: PendingReview) {
        edits.showFailure(EditFailure(text: text, url: review.url))
    }

    /// Fetches the detail again, whether it's on screen or held under another layer.
    private func reloadReviewedDetail(_ review: PendingReview) {
        if route == .detail(review.key) {
            reloadDetail()
        } else if details[review.key] != nil {
            Task { [weak self] in
                _ = try? await self?.fetchDetailComments(review.key, isPullRequest: true, account: review.account)
            }
        }
    }
}
