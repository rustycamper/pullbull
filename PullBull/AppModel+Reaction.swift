import Foundation
import PullBullKit
import SwiftUI

/// The subject whose reaction picker is open: a PR, an issue, a comment or a review on `key`.
struct ReactionPickerSubject: Hashable {
    let key: PRKey
    let subjectId: String
}

/// A reaction write on one target whose outcome isn't final. `wanted` is what the latest click asks for;
/// a click made while a call or a confirm is in flight only changes it, and `ReactionFlow` sends the rest.
struct ReactionSend {
    /// This record's, kept by its re-sends: an answer to an earlier record on the same target and account
    /// (from before an org switch, or A→B→A) doesn't match it.
    let id = UUID()
    let key: PRKey
    /// From the route the click was made on: whether `key` is a pull request.
    let isPullRequest: Bool
    let account: AccountRef
    var wanted: Bool
}

// MARK: - Reactions

extension AppModel {
    /// `reactions` as the detail shows them: the clicks GitHub's reads don't show yet laid over them.
    func shownReactions(_ reactions: Reactions?, on key: PRKey, now: Date) -> Reactions? {
        reactionOverrides.apply(
            to: reactions, fetchedAt: details[key]?.fetchedAt ?? issueDetails[key]?.fetchedAt, now: now)
    }

    /// Whether the viewer may react to the subject `reactions` belongs to, on `key`.
    func canReact(_ reactions: Reactions?, on key: PRKey, isPullRequest: Bool) -> Bool {
        reactions?.viewerCanReact == true && commentPermission(for: key, isPullRequest: isPullRequest) == .ready
    }

    /// Opens the picker on `subject`; nil closes it.
    func openReactionPicker(_ subject: ReactionPickerSubject?) {
        reactionPicker = subject
    }

    /// Adds `content` to the subject of `reactions` on `key`, or takes it back when the viewer has it as
    /// shown. Shows at once; GitHub's answer settles it. Leaves the failure line and ⌘Z alone.
    func toggleReaction(_ content: ReactionContent, on reactions: Reactions, key: PRKey, isPullRequest: Bool) {
        // Any pick closes the picker, even one that sends nothing because the viewer can no longer react.
        reactionPicker = nil
        guard canReact(reactions, on: key, isPullRequest: isPullRequest), let account = runningAccount,
              let shown = shownReactions(reactions, on: key, now: Date()) else { return }
        let target = ReactionTarget(subjectId: reactions.subjectId, content: content)
        let wanted = !shown.viewerHasReacted(content)
        reactionOverrides.record(target, add: wanted, on: key, at: Date())
        if reactionSends[target]?.account == account {
            reactionSends[target]?.wanted = wanted
            return
        }
        reactionSends[target] = ReactionSend(key: key, isPullRequest: isPullRequest, account: account, wanted: wanted)
        send(target, add: wanted)
    }

    /// Writes `add` for `target` with the send's account.
    private func send(_ target: ReactionTarget, add: Bool) {
        guard let pending = reactionSends[target] else { return }
        let id = pending.id
        let account = pending.account
        let client = api(for: account)
        Task { [weak self] in
            let answer: ReactionAnswer
            do {
                answer = .applied(
                    add ? try await client.addReaction(target.content, to: target.subjectId)
                        : try await client.removeReaction(target.content, from: target.subjectId))
            } catch {
                switch CommentFailure.classify(error) {
                case .refused(let reason): answer = .refused(reason)
                case .unknown: answer = .unknown
                }
            }
            self?.reactionAnswered(target, sent: add, id: id, account: account, answer: answer)
        }
    }

    /// The send on `target` while it is the record `id` names, `account` owns it and runs. Nil when a
    /// switch cleared it or a newer record owns the target; when another account runs, the send is removed.
    private func liveReactionSend(_ target: ReactionTarget, id: UUID, account: AccountRef) -> ReactionSend? {
        guard let send = reactionSends[target], send.id == id, send.account == account else { return nil }
        guard runningAccount == account else {
            reactionSends[target] = nil
            return nil
        }
        return send
    }

    private func reactionAnswered(
        _ target: ReactionTarget, sent add: Bool, id: UUID, account: AccountRef, answer: ReactionAnswer
    ) {
        guard let pending = liveReactionSend(target, id: id, account: account) else { return }
        // GitHub's answer is written through even when the latest click sends again: should the follow-up
        // be refused, the stored detail already shows what GitHub holds. The latest click's override stays.
        if case .applied(let reactions) = answer {
            storeReactions(reactions, on: pending.key, account: pending.account)
        }
        follow(ReactionFlow.next(sent: add, answer: answer, wanted: pending.wanted), target: target, sent: add, pending)
    }

    /// Acts on what `ReactionFlow` decided for `target`, whose last write sent `add`.
    private func follow(_ step: ReactionStep, target: ReactionTarget, sent add: Bool, _ pending: ReactionSend) {
        switch step {
        case .done:
            // `reactionAnswered` has written GitHub's answer through.
            reactionOverrides.answered(target, at: Date())
            reactionSends[target] = nil
            let emoji = target.content.emoji
            AccessibilityNotification.Announcement(add ? "Reacted with \(emoji)" : "Removed \(emoji)").post()
        case .send(let again):
            send(target, add: again)
        case .refused(let reason):
            endReaction(target)
            let text = EditMessage.reactionRefused(on: pending.key, content: target.content, add: add, reason: reason)
            showReactionFailure(text, pending)
        case .dropQuietly:
            endReaction(target)
        case .confirm:
            confirmReaction(target, sent: add, pending)
        case .unconfirmed:
            endReaction(target)
            showReactionFailure(EditMessage.reactionUnconfirmed(on: pending.key, content: target.content), pending)
        }
    }

    /// The outcome is unknown: the click stops overriding once a detail fetched from now on lands, and one
    /// is fetched. Whether it shows what the latest click asks for decides the rest.
    private func confirmReaction(_ target: ReactionTarget, sent add: Bool, _ pending: ReactionSend) {
        reactionOverrides.answered(target, at: Date())
        Task { [weak self] in
            guard let self else { return }
            let fetched: Reactions?
            do {
                // Judged from the detail this fetch read: an older fetch can land in `details` meanwhile.
                fetched = try await self.fetchDetailReactions(
                    of: target.subjectId, on: pending.key, isPullRequest: pending.isPullRequest,
                    account: pending.account)
            } catch {
                fetched = nil
            }
            guard let current = self.liveReactionSend(target, id: pending.id, account: pending.account) else { return }
            let step = ReactionFlow.afterConfirm(fetched, content: target.content, sent: add, wanted: current.wanted)
            self.follow(step, target: target, sent: add, current)
        }
    }

    /// The click is over: its override and its send go.
    private func endReaction(_ target: ReactionTarget) {
        reactionOverrides.drop(target)
        reactionSends[target] = nil
    }

    private func showReactionFailure(_ text: String, _ pending: ReactionSend) {
        let url = pending.isPullRequest
            ? mergeURL(for: pending.key) : fetchedIssue(for: pending.key)?.url ?? GitHubLinks.issue(pending.key)
        edits.showFailure(EditFailure(text: text, url: url, key: pending.key, staysOnLeaving: true))
    }
}
