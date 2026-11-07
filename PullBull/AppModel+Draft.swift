import Foundation
import PullBullKit
import SwiftUI

// MARK: - Draft ↔ ready for review

extension AppModel {
    /// What the detail offers for the draft flip on `key`, read through the overlay as `mergeOffer` is.
    /// Nothing shows until the installations have loaded.
    func draftOffer(for key: PRKey) -> DraftOffer {
        guard editPermissionsKnown else { return .hidden }
        return DraftGate.offer(
            state: edits.overrides.apply(toState: details[key]?.state, on: key),
            info: edits.overrides.apply(toMerge: details[key]?.merge, on: key),
            author: details[key]?.author, viewer: runningAccount?.login,
            permission: setEditPermission(.draft, for: key))
    }

    /// The controls stay on screen but disabled while the merge panel is open on `key`, or anything is on
    /// its way for it.
    func canFlipDraft(on key: PRKey) -> Bool {
        !isPostInFlight(for: key) && mergeMode?.key != key
    }

    /// Ready for review or Convert to draft: one click, sent at once with the held node ID. Only the
    /// control's label changes until GitHub answers yes.
    func flipDraft(on key: PRKey) {
        guard canFlipDraft(on: key) else { return }
        let toDraft: Bool
        switch draftOffer(for: key) {
        case .markReady: toDraft = false
        case .convert: toDraft = true
        case .permission, .hidden: return
        }
        guard let account = runningAccount, let nodeID = details[key]?.merge?.nodeID else { return }
        edits.dismissFailure(startingOn: key)
        postsInFlight.insert(account: account.login, key: key)
        draftFlips.insert(key)
        // Set before sending, so a poll landing between GitHub's answer and `draftAnswered` can't notify.
        readiedHere[key] = toDraft ? nil : Date()
        let flip = PendingMerge(
            key: key, change: .draft(isDraft: toDraft, viewer: account.login), account: account,
            url: mergeURL(for: key), sent: true)
        // As shown before anything is sent, a flip made just before included: marking ready a PR already
        // ready keeps its ready time.
        let copy = pullRequest(for: key)
        let client = api(for: account)
        Task { [weak self] in
            let result = await DraftFlow.run(
                toDraft: toDraft,
                send: {
                    toDraft
                        ? try await client.convertToDraft(key, nodeID: nodeID)
                        : try await client.markReadyForReview(key, nodeID: nodeID)
                },
                read: { try await client.detail(key) },
                sleep: { duration in try await Task.sleep(for: duration) })
            self?.draftAnswered(flip, result.outcome, read: result.read, copy: copy)
        }
    }

    /// With another account running, nothing is stored or shown for the sending one: `settleMerge` and
    /// `mergeFailed` release its slot and hold its line, and its next refresh and detail load show the flip.
    private func draftAnswered(_ flip: PendingMerge, _ outcome: DraftOutcome, read: PRDetail?, copy: PullRequest?) {
        let key = flip.key
        let runs = runningAccount == flip.account
        // `clearAccountData` emptied these on a switch, so with another account running they're its own.
        if runs { draftFlips.remove(key) }
        if let read, runs { storeDetail(read, account: flip.account) }
        guard case .draft(let toDraft, _) = flip.change else { return }
        switch outcome {
        case .done:
            guard settleMerge(flip) else { return }
            let before = shownListKeys()
            _ = edits.recordMerge(flip.change, on: key, at: Date(), carrying: copy)
            refreshShown()
            followEditedRow(key, from: before)
            // The window counts from GitHub's answer.
            if !toDraft { readiedHere[key] = Date() }
            if read == nil { reloadReviewedDetail(key, account: flip.account) }
            let line = toDraft ? "#\(key.number) is a draft" : "#\(key.number) is ready for review"
            AccessibilityNotification.Announcement(line).post()
        case .refused(let reason):
            if runs { readiedHere[key] = nil }
            let line = EditMessage.draftRefused(on: key, toDraft: toDraft, reason: reason)
            mergeFailed(flip, line, dropsOverlay: false, reloads: false)
        case .unknown:
            // `readiedHere` keeps the key: the flip may have landed.
            let line = EditMessage.draftUnconfirmed(on: key, toDraft: toDraft)
            mergeFailed(flip, line, dropsOverlay: false, reloads: false)
        }
    }
}
