import Foundation
import PullBullKit
import SwiftUI

// MARK: - Merge mode

extension AppModel {
    /// What the detail offers on `key`, read through the overlay so that Merge and ⌥⌘G don't come back during
    /// GitHub's lag, and a Merge when ready offers Cancel auto-merge at once. `.unavailable` can also mean
    /// the installations haven't loaded, so nothing shows until they have.
    func mergeOffer(for key: PRKey) -> MergeOffer {
        guard editPermissionsKnown else { return .hidden }
        return MergeGate.offer(
            state: edits.overrides.apply(toState: details[key]?.state, on: key),
            info: edits.overrides.apply(toMerge: details[key]?.merge, on: key),
            viewer: runningAccount?.login, permission: setEditPermission(.merge, for: key))
    }

    /// ⌥⌘G or Merge: pins the head on screen, ends review mode keeping its text, takes the keyboard from
    /// the comment field, and reads the PR afresh.
    func enterMergeMode(on key: PRKey) {
        guard mergeMode == nil, case .action = mergeOffer(for: key), reviewMode?.phase != .sending,
              !isPostInFlight(for: key), let head = details[key]?.headOid, let account = runningAccount
        else { return }
        endReviewMode(on: nil)
        let fieldHadFocus = (NSApp.keyWindow?.firstResponder as? CommentEditor)?.key == key
        releaseCommentField(on: key)
        mergeMode = MergeMode(key: key, pinnedHead: head, fieldHadFocus: fieldHadFocus)
        let client = api(for: account)
        mergeTask = Task { [weak self] in
            await self?.readForPanel(key, pinned: head, account: account, client: client)
        }
    }

    /// Esc, Cancel or a click outside. Stops anything not yet sent: a sent merge has no panel.
    /// Esc and Cancel give the comment field its focus back if it had it; a click puts focus where it lands,
    /// so it passes false.
    func leaveMergeMode(returnsFocus: Bool = true) {
        guard let mode = mergeMode else { return }
        stopUnsentMerge()
        mergeMode = nil
        if returnsFocus, mode.fieldHadFocus { requestCommentFieldFocus(on: mode.key) }
    }

    /// The screen, popover or account changed: the panel on `key`, or on anything when nil, closes. Stops
    /// anything not yet sent.
    func endMergeMode(on key: PRKey?) {
        guard let mode = mergeMode, key == nil || mode.key == key else { return }
        stopUnsentMerge()
        mergeMode = nil
    }

    func changeMergeMethod(by offset: Int) {
        mergeMode?.changeMethod(by: offset, at: Date())
    }

    /// The only place a stopped confirm's slot goes, with its own account as `runningAccount` may have
    /// changed: its task then touches nothing, as the slot may by then be a new attempt's.
    private func stopUnsentMerge() {
        mergeTask?.cancel()
        if let merge = confirmingMerge { postsInFlight.remove(account: merge.account.login, key: merge.key) }
        confirmingMerge = nil
    }

    private func closeMergePanel(on key: PRKey) {
        if mergeMode?.key == key { mergeMode = nil }
    }

    /// The panel's first read. Anything but an unmoved head that still offers an action closes it. Each
    /// step stops if the panel closed meanwhile: `mergeTask` is then cancelled.
    private func readForPanel(_ key: PRKey, pinned: String, account: AccountRef, client: GitHubAPI) async {
        var retries = 0
        while true {
            let fresh: PRDetail
            do {
                fresh = try await client.detail(key)
            } catch {
                guard !Task.isCancelled else { return }
                closeMergePanel(on: key)
                showMergeFailure(EditMessage.mergeCheckFailed(on: key, reason: MergeFlow.reason(for: error)), on: key)
                return
            }
            guard !Task.isCancelled else { return }
            storeDetail(fresh, account: account)
            guard fresh.headOid == pinned else {
                closeMergePanel(on: key)
                showMergeFailure(EditMessage.mergeHeadMoved(on: key), on: key)
                return
            }
            if retries < MergeRetry.limit, MergeRetry.shouldRetry(fresh.merge, afterReview: false) {
                retries += 1
                try? await Task.sleep(for: MergeRetry.interval)
                guard !Task.isCancelled else { return }
                continue
            }
            let offer = mergeOffer(for: key)
            if case .action = offer {
                showMergeRead(MergeRead(detail: fresh, offer: offer), on: key)
            } else {
                closeMergePanel(on: key)
            }
            return
        }
    }

    /// Freezes `read` in the panel, which disarms it, and announces the panel's sentence and warnings.
    private func showMergeRead(_ read: MergeRead, on key: PRKey) {
        guard mergeMode?.key == key else { return }
        mergeMode?.show(read, at: Date())
        announceMergePanel()
    }

    private func announceMergePanel() {
        guard let mode = mergeMode, let sentence = mode.sentence else { return }
        let lines = [sentence] + mode.warnings.map(\.text)
        AccessibilityNotification.Announcement(lines.joined(separator: ". ")).post()
    }

    private func showMergeFailure(_ text: String, on key: PRKey) {
        edits.showFailure(EditFailure(text: text, url: mergeURL(for: key), key: key))
    }

    private func mergeURL(for key: PRKey) -> URL {
        fetchedPullRequest(for: key)?.url ?? GitHubLinks.pullRequest(key)
    }

    /// The running account's line from a merge that was answered while another account ran.
    func showHeldMergeLine() {
        guard let login = runningAccount?.login, let line = heldMergeLines.removeValue(forKey: login) else { return }
        edits.showFailure(line)
    }
}

// MARK: - Waiting on GitHub

extension AppModel {
    /// A detail on screen arrived, or a review on it was sent: while GitHub is still working out its merge
    /// state, or shows a `BLOCKED` that may be stale after that review, reads it again up to
    /// `MergeRetry.limit` times, stopping as soon as that no longer holds or the viewer leaves. Neither
    /// case shows a button, so this is the detail's job and not the panel's.
    func rereadMergeState(on key: PRKey, afterReview: Bool = false) {
        guard route == .detail(key), let account = runningAccount else { return }
        let review = afterReview || mergeRereads[key] == true
        guard isMergeStateUnsettled(key, afterReview: review) else { return }
        let isRunning = mergeRereads[key] != nil
        mergeRereads[key] = review
        guard !isRunning else { return }
        let client = api(for: account)
        Task { [weak self] in
            for _ in 0..<MergeRetry.limit {
                try? await Task.sleep(for: MergeRetry.interval)
                guard let self, self.isOnScreen(key, for: account) else { break }
                guard let fresh = try? await client.detail(key) else { continue }
                guard self.isOnScreen(key, for: account) else { break }
                self.storeDetail(fresh, account: account)
                guard self.isMergeStateUnsettled(key, afterReview: self.mergeRereads[key] == true) else { break }
            }
            self?.mergeRereads[key] = nil
        }
    }

    private func isOnScreen(_ key: PRKey, for account: AccountRef) -> Bool {
        route == .detail(key) && runningAccount == account
    }

    private func isMergeStateUnsettled(_ key: PRKey, afterReview: Bool) -> Bool {
        MergeRetry.shouldRetry(details[key]?.merge, afterReview: afterReview) && mergeOffer(for: key) != .hidden
    }
}

// MARK: - Merging

extension AppModel {
    /// One merge or auto-merge change on its way, with what its answer needs. It can outlive the panel, and
    /// the viewer may be on another PR, so every write to `mergeMode` from here on is guarded by its key.
    struct PendingMerge {
        let key: PRKey
        /// What's sent: `.merged`, or `.autoMerge` on or off.
        let change: EditChange
        let account: AccountRef
        /// The item on GitHub, for the failure line's **Open on GitHub**.
        let url: URL
        /// Nil until the send. `clearAccountData` can also leave it stale, and dropping a stale id does nothing.
        var overlay: UUID?

        var isDirect: Bool {
            if case .merged = change { return true }
            return false
        }
    }

    /// ⌃⌘↩ or the panel's Merge button: moves to the second step, or re-reads the PR and sends only if it
    /// still looks as the panel shows it.
    func confirmMerge(on key: PRKey) {
        guard let mode = mergeMode, mode.key == key, let account = runningAccount,
              setEditPermission(.merge, for: key) == .ready, !isPostInFlight(for: key),
              let read = mode.read, let action = read.facts.action, let method = mode.method,
              let nodeID = read.info?.nodeID
        else { return }
        guard mergeMode?.confirm(at: Date()) == true else {
            if let armed = mergeMode, armed.isSecondStep, !mode.isSecondStep {
                AccessibilityNotification.Announcement(armed.confirmTitle).post()
            }
            return
        }
        edits.dismissFailure()
        postsInFlight.insert(account: account.login, key: key)
        let viewer = account.login
        let head = mode.pinnedHead
        let client = api(for: account)
        let change: EditChange = action == .merge ? .merged(viewer: viewer) : .autoMerge(enabled: true, viewer: viewer)
        var merge = PendingMerge(key: key, change: change, account: account, url: mergeURL(for: key))
        confirmingMerge = merge
        mergeTask = Task { [weak self] in
            let outcome = await MergeFlow.run(
                shown: read.facts,
                // Only closing the panel cancels this task, and only before `willSend`.
                isCancelled: { Task.isCancelled },
                read: {
                    let fresh = try await client.detail(key)
                    // No overlay: this is GitHub's word, and `confirmMerge` checked the permission.
                    let offer = MergeGate.offer(state: fresh.state, info: fresh.merge, viewer: viewer, permission: .ready)
                    return MergeRead(detail: fresh, offer: offer)
                },
                willSend: { self?.mergeWillSend(&merge) },
                send: {
                    switch action {
                    case .merge:
                        return try await client.requestMerge(key, head: head, method: method)
                    case .mergeWhenReady:
                        try await client.enableAutoMerge(key, nodeID: nodeID, head: head, method: method)
                        return .autoMergeSet
                    }
                },
                poll: { uuid in try await client.mergeResult(key, uuid: uuid) },
                sleep: { duration in try await Task.sleep(for: duration) })
            self?.mergeAnswered(merge, outcome, client: client)
        }
    }

    /// The read checked out and the write is about to start: it can't be called back from here, so the panel
    /// closes and the PR shows as merged at once, dimmed, for the sending account only. Any bad answer comes
    /// back as the failure line.
    private func mergeWillSend(_ merge: inout PendingMerge) {
        confirmingMerge = nil
        guard runningAccount == merge.account else { return }
        closeMergePanel(on: merge.key)
        recordMerge(&merge)
        AccessibilityNotification.Announcement("Merging").post()
    }

    /// Lays `merge` over what's shown. Only a direct merge joins `mergedHere`: a Merge when ready notifies.
    private func recordMerge(_ merge: inout PendingMerge) {
        let before = shownListKeys()
        merge.overlay = edits.recordMerge(merge.change, on: merge.key, at: Date())
        sendingMerges.insert(merge.key)
        if merge.isDirect { mergedHere.insert(merge.key) }
        refreshShown()
        followEditedRow(merge.key, from: before)
    }

    private func mergeAnswered(_ merge: PendingMerge, _ outcome: MergeOutcome, client: GitHubAPI) {
        let key = merge.key
        switch outcome {
        case .cancelled:
            // Closing the panel did the work, and the slot may now belong to a new attempt.
            break
        case .merged, .autoMergeSet:
            mergeSent(merge)
        case .changed(let read):
            guard runningAccount == merge.account, mergeMode?.key == key else {
                // Only a send can outlive the panel, so that send was turned down and nobody saw why.
                mergeFailed(merge, EditMessage.mergeChanged(on: key), dropsOverlay: true, reloads: true)
                return
            }
            _ = settleMerge(merge)
            dropMergeOverlay(merge)
            if read.facts.action != nil {
                showMergeRead(read, on: key)
            } else {
                closeMergePanel(on: key)
                reloadReviewedDetail(key, account: merge.account)
            }
        case .headMoved:
            mergeFailed(merge, EditMessage.mergeHeadMoved(on: key), dropsOverlay: true, reloads: true)
        case .notOpen(let merged):
            // Closed, the overlay would claim a merge that never happened until its lifetime ran out. Merged, it
            // stays true, but the merge wasn't ours, so it should notify.
            if merged, runningAccount == merge.account { mergedHere.remove(key) }
            mergeFailed(merge, EditMessage.reviewNotOpen(on: key, merged: merged), dropsOverlay: !merged, reloads: true)
        case .checkFailed(let reason):
            mergeFailed(merge, EditMessage.mergeCheckFailed(on: key, reason: reason), dropsOverlay: false, reloads: false)
        case .refused(let reason):
            mergeFailed(merge, EditMessage.mergeRefused(on: key, reason: reason), dropsOverlay: true, reloads: false)
        case .unknown:
            confirmUnknownMerge(merge, client: client)
        }
    }

    /// The write had no clear answer: the overlay stays while one fresh detail decides, matched to what
    /// was sent. A failed read counts as unconfirmed, and nothing is ever sent again. Runs with the sending
    /// account even after a switch, so the slot goes. Its own task, which nothing cancels.
    private func confirmUnknownMerge(_ merge: PendingMerge, client: GitHubAPI) {
        Task { [weak self] in
            let fresh = try? await client.detail(merge.key)
            guard let self else { return }
            if let fresh, MergeFlow.landed(merge.change, in: fresh) {
                self.mergeSent(merge, read: fresh)
                return
            }
            if let fresh, self.runningAccount == merge.account { self.storeDetail(fresh, account: merge.account) }
            self.mergeFailed(merge, EditMessage.mergeUnconfirmed(on: merge.key), dropsOverlay: true, reloads: false)
        }
    }

    /// GitHub has it. The overlay stays until the held detail shows it. `read` is the detail that showed it
    /// landed, which stands in for fetching it again. With another account running a success needs no
    /// line, as the lists show it.
    private func mergeSent(_ merge: PendingMerge, read: PRDetail? = nil) {
        guard settleMerge(merge) else { return }
        closeMergePanel(on: merge.key)
        if let read {
            storeDetail(read, account: merge.account)
        } else {
            reloadReviewedDetail(merge.key, account: merge.account)
        }
        let number = merge.key.number
        AccessibilityNotification.Announcement(merge.isDirect ? "Merged #\(number)" : "Auto-merge set on #\(number)").post()
    }

    /// The answer's final and bad: the panel closes and `text` shows, or waits for the sending account when
    /// another runs, in which case nothing else on screen changes.
    private func mergeFailed(_ merge: PendingMerge, _ text: String, dropsOverlay: Bool, reloads: Bool) {
        let failure = EditFailure(text: text, url: merge.url, key: merge.key)
        guard settleMerge(merge) else {
            heldMergeLines[merge.account.login] = failure
            return
        }
        if dropsOverlay { dropMergeOverlay(merge) }
        closeMergePanel(on: merge.key)
        edits.showFailure(failure)
        if reloads { reloadReviewedDetail(merge.key, account: merge.account) }
    }

    /// The outcome is final: the merge leaves the in-flight tracking. True while its account still runs;
    /// nothing else may change otherwise.
    private func settleMerge(_ merge: PendingMerge) -> Bool {
        postsInFlight.remove(account: merge.account.login, key: merge.key)
        if confirmingMerge?.key == merge.key, confirmingMerge?.account == merge.account { confirmingMerge = nil }
        guard runningAccount == merge.account else { return false }
        sendingMerges.remove(merge.key)
        return true
    }

    /// Also takes the key off `mergedHere`, so a later real merge notifies.
    private func dropMergeOverlay(_ merge: PendingMerge) {
        let before = shownListKeys()
        if let id = merge.overlay { edits.dropMerge(id) }
        if merge.isDirect { mergedHere.remove(merge.key) }
        refreshShown()
        followEditedRow(merge.key, from: before)
    }
}

// MARK: - Cancelling auto-merge

extension AppModel {
    /// One click, as on the web. A failure says so loudly: a cancel that goes unnoticed is an unwanted merge.
    func cancelAutoMerge(on key: PRKey) {
        guard mergeMode == nil, mergeOffer(for: key) == .cancelAutoMerge, !isPostInFlight(for: key),
              let account = runningAccount, let nodeID = details[key]?.merge?.nodeID
        else { return }
        edits.dismissFailure()
        postsInFlight.insert(account: account.login, key: key)
        let change = EditChange.autoMerge(enabled: false, viewer: account.login)
        var merge = PendingMerge(key: key, change: change, account: account, url: mergeURL(for: key))
        recordMerge(&merge)
        let sent = merge
        let client = api(for: account)
        Task { [weak self] in
            let outcome = await MergeFlow.cancelAutoMerge(
                send: { try await client.disableAutoMerge(key, nodeID: nodeID) },
                stillSet: { try await client.detail(key).merge?.autoMerge != nil })
            self?.autoMergeCancelAnswered(sent, outcome)
        }
    }

    private func autoMergeCancelAnswered(_ merge: PendingMerge, _ outcome: AutoMergeCancelOutcome) {
        let key = merge.key
        switch outcome {
        case .cancelled:
            guard settleMerge(merge) else { return }
            reloadReviewedDetail(key, account: merge.account)
            AccessibilityNotification.Announcement("Auto-merge cancelled on #\(key.number)").post()
        case .refused(let reason):
            let line = EditMessage.autoMergeCancelRefused(on: key, reason: reason)
            mergeFailed(merge, line, dropsOverlay: true, reloads: false)
        case .unknown:
            mergeFailed(merge, EditMessage.autoMergeCancelUnconfirmed(on: key), dropsOverlay: true, reloads: false)
        }
    }
}
