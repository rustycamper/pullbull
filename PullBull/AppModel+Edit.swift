import Foundation
import PullBullKit

// MARK: - Editing Status

extension AppModel {
    /// Whether the issue `key` can have its board Status set from here.
    func isStatusOffered(for key: PRKey) -> Bool {
        shownSnapshot.map { StatusEdit.isOffered(key, in: $0) } ?? false
    }

    /// Whether this account may set Status on the shown board. `.unavailable` (installations not loaded
    /// yet) lets the edit go: GitHub's answer then says whether it may.
    func statusEditPermission() -> EditPermission {
        guard let account = runningAccount else { return .unavailable }
        let owner = shownSnapshot?.board?.owner
        return EditPermission.of(
            .status, account: account, boardOwner: owner, installation: owner.flatMap(installation(owning:)),
            ghAccounts: accounts)
    }

    /// The issue ⌥⌘S acts on: the selected result while searching, else the highlighted row in Issues
    /// mode; nil when neither is an issue.
    func selectedIssueKey(in listKeys: [PRKey]?) -> PRKey? {
        if route == .search {
            guard let key = searchSelection, searchResults?.issues.contains(where: { $0.key == key }) == true
            else { return nil }
            return key
        }
        guard mode == .issues, let listKeys else { return nil }
        return ListNavigation.shown(listSelection, in: listKeys)
    }

    // MARK: Picker

    func openStatusPicker(for key: PRKey) {
        guard let snapshot = shownSnapshot else { return }
        statusPicker = StatusPicker.make(for: key, in: snapshot, permission: statusEditPermission())
    }

    func moveStatusPicker(by offset: Int) {
        statusPicker?.move(by: offset)
    }

    func filterStatusPicker(_ text: String) {
        statusPicker?.setFilter(text)
    }

    /// Sets the selected row's Status and closes the picker; with no row shown, or no permission, it stays.
    func applyStatusPicker() {
        guard let picker = statusPicker, Self.allows(picker.permission), let pick = picker.pick else { return }
        statusPicker = nil
        setStatus(pick, for: picker.key)
    }

    func closeStatusPicker() {
        statusPicker = nil
    }

    // MARK: Edits

    /// Moves the issue to `status` (nil clears it), adding it to the board when it isn't on it. Without
    /// permission, the picker opens on it to say what's missing.
    func setStatus(_ status: BoardStatusValue?, for key: PRKey) {
        guard let shown = shownSnapshot, let change = StatusEdit.change(for: key, to: status, in: shown) else { return }
        guard Self.allows(statusEditPermission()) else {
            openStatusPicker(for: key)
            return
        }
        run(change, on: key, addedItemId: nil, isUndo: false)
    }

    /// Whether ⌘Z has an edit to take back now.
    var canUndoEdit: Bool { edits.canUndo(now: Date()) }

    /// Sends the inverse of the last edit, within 10 seconds of it; false when there is none.
    @discardableResult
    func undoLastEdit() -> Bool {
        guard let record = edits.takeUndo(now: Date()) else { return false }
        run(record.change.inverse, on: record.key, addedItemId: record.addedItemId, isUndo: true)
        return true
    }

    func dismissEditFailure() {
        edits.dismissFailure()
    }

    /// Shows `change` at once, then sends it; a failure takes it back off and says why. `addedItemId` is
    /// the board item an undone add created, which the undo deletes.
    private func run(_ change: EditChange, on key: PRKey, addedItemId: String?, isUndo: Bool) {
        guard let account = runningAccount else { return }
        let card = snapshot?.boardIssues.first { $0.key == key }
        let url = (card ?? issue(for: key))?.url ?? GitHubLinks.issue(key)
        let contentId = (card ?? issue(for: key))?.nodeId
        let itemId = addedItemId ?? card?.boardItemNodeId
        let board = snapshot?.boardIds
        let before = shownListKeys()
        let id = edits.begin(change, on: key, at: Date())
        refreshShown()
        followEditedRow(key, from: before)
        let editor = StatusEditor(api: api(for: account))
        Task { [weak self] in
            do {
                let added = try await editor.apply(change, on: key, itemId: itemId, contentId: contentId, board: board)
                guard let self, !isUndo else { return }
                self.edits.applied(EditRecord(key: key, change: change, madeAt: Date(), addedItemId: added))
            } catch {
                guard let self else { return }
                let before = self.shownListKeys()
                self.edits.failed(id, change: change, on: key, url: url, error: error)
                self.refreshShown()
                self.followEditedRow(key, from: before)
            }
        }
    }

    /// Keeps the edited row selected in its new lane and scrolls to it; when it left the list, selects
    /// the row after it.
    private func followEditedRow(_ key: PRKey, from before: [PRKey]) {
        guard listSelection == key else { return }
        let after = shownListKeys()
        if after.contains(key) {
            editScrollRequest += 1
        } else {
            listSelection = ListNavigation.selection(key, from: before, to: after)
        }
    }

    private func shownListKeys() -> [PRKey] {
        listKeys(closedExpanded: listExpansion.closed, doneExpanded: listExpansion.done)
    }

    private static func allows(_ permission: EditPermission) -> Bool {
        switch permission {
        case .ready, .unavailable: true
        case .needsAppApproval, .needsGhScope: false
        }
    }
}
