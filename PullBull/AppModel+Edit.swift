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
        closeSetPicker(apply: true)
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

    // MARK: Reviewer, assignee and label pickers

    /// The key of the open picker, Status or set; the popover's focus and key routing read it.
    var editPickerKey: PRKey? { statusPicker?.key ?? setPicker?.key }

    /// Whether the issue or pull request `key` can have its labels or assignees edited: one PullBull holds,
    /// with a running account.
    func isSetEditOffered(for key: PRKey) -> Bool {
        (issue(for: key) != nil || pullRequest(for: key) != nil) && runningAccount != nil
    }

    /// Whether the pull request `key` can have its reviewers edited: one PullBull holds, with a running account.
    func isReviewersOffered(for key: PRKey) -> Bool {
        pullRequest(for: key) != nil && runningAccount != nil
    }

    /// The issue or PR ⌥⌘A and ⌥⌘L act on: the selected result while searching, else the highlighted row.
    func selectedSetEditKey(in listKeys: [PRKey]?) -> PRKey? {
        selectedIssueKey(in: listKeys) ?? selectedPRKey(in: listKeys)
    }

    func setEditPermission(_ field: EditField, for key: PRKey) -> EditPermission {
        guard let account = runningAccount else { return .unavailable }
        let owner = key.repo.split(separator: "/").first.map(String.init) ?? ""
        let installation = installation(named: owner)
        return EditPermission.of(
            field, account: account, boardOwner: nil, installation: installation, ghAccounts: accounts,
            onPullRequest: pullRequest(for: key) != nil)
    }

    /// Opens the picker for `field` (`.labels`, `.assignees` or `.reviewers`) on `key`, applying an open one
    /// first. The cached candidates show at once; a fetch follows.
    func openSetPicker(_ field: EditField, for key: PRKey) {
        closeSetPicker(apply: true)
        guard let account = runningAccount else { return }
        let viewer = shownSnapshot?.org.viewer ?? settings.account ?? ""
        let permission = setEditPermission(field, for: key)
        var picker: SetPicker
        if field == .reviewers {
            guard let pr = pullRequest(for: key) else { return }
            picker = SetPicker(reviewersOf: key, requested: pr.reviewRequests, viewer: viewer, permission: permission)
        } else if let issue = issue(for: key) {
            let current = field == .labels ? issue.labels : issue.assignees.map(\.login)
            picker = SetPicker(field: field, key: key, current: current, viewer: viewer, permission: permission)
        } else if let pr = pullRequest(for: key) {
            let current = field == .labels ? pr.labels : pr.assignees.map(\.login)
            picker = SetPicker(field: field, key: key, current: current, viewer: viewer, permission: permission)
        } else {
            return
        }
        statusPicker = nil
        let cacheKey = Self.setCandidatesKey(field, key)
        guard Self.allows(permission) else {
            setPicker = picker
            return
        }
        let cached = field == .reviewers ? cachedReviewerCandidates(for: key) : setCandidates[cacheKey]
        if let cached { picker.load(cached) }
        setPicker = picker
        let client = api(for: account)
        setPickerTask?.cancel()
        setPickerTask = Task { [weak self] in
            do {
                if field == .reviewers {
                    let answer = try await client.reviewerCandidates(for: key, query: nil)
                    guard let self, !Task.isCancelled, self.isSetPickerCurrent(key, field, account) else { return }
                    self.setCandidates[cacheKey] = SetCandidates(
                        all: answer.people, current: [], complete: answer.picker.complete)
                    if let teams = answer.teams {
                        self.setCandidates[Self.teamCandidatesKey(key)] = SetCandidates(all: teams, current: [], complete: true)
                    }
                    self.setPicker?.load(answer.picker)
                    return
                }
                let answer = field == .labels
                    ? try await client.labelCandidates(for: key)
                    : try await client.assigneeCandidates(for: key, query: nil)
                guard let self, !Task.isCancelled, self.isSetPickerCurrent(key, field, account) else { return }
                self.setCandidates[cacheKey] = SetCandidates(all: answer.all, current: [], complete: answer.complete)
                self.setPicker?.load(answer)
            } catch {
                guard let self, !Task.isCancelled, self.isSetPickerCurrent(key, field, account) else { return }
                self.setPicker?.failedToLoad(RefreshError(error).message)
            }
        }
    }

    /// Filters the rows; for people (and teams) past the first 100, GitHub is asked after a 0.3 s pause.
    func filterSetPicker(_ text: String) {
        guard var picker = setPicker else { return }
        picker.setFilter(text)
        setPicker = picker
        guard picker.field != .labels, !picker.isComplete, Self.allows(picker.permission),
              let account = runningAccount else { return }
        setFilterTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        let key = picker.key, field = picker.field
        let client = api(for: account)
        setFilterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let answer = field == .reviewers
                ? try? await client.reviewerCandidates(for: key, query: query).picker
                : try? await client.assigneeCandidates(for: key, query: query)
            guard let answer, let self, !Task.isCancelled, self.isSetPickerCurrent(key, field, account) else { return }
            self.setPicker?.load(answer, fromQuery: true)
        }
    }

    func moveSetPicker(by offset: Int) {
        setPicker?.move(by: offset)
    }

    func toggleSetPicker() {
        setPicker?.toggleSelected()
    }

    /// Closes the picker; `apply` sends its change (Esc, ⌘↩, its key, a click outside, the popover hiding).
    func closeSetPicker(apply: Bool) {
        guard let picker = setPicker else { return }
        setPicker = nil
        setPickerTask?.cancel()
        setPickerTask = nil
        setFilterTask?.cancel()
        setFilterTask = nil
        guard apply, let change = picker.change, Self.allows(picker.permission) else { return }
        run(change, on: picker.key, addedItemId: nil, isUndo: false)
    }

    private func isSetPickerCurrent(_ key: PRKey, _ field: EditField, _ account: AccountRef) -> Bool {
        setPicker?.key == key && setPicker?.field == field && runningAccount == account
    }

    /// Reviewers share the assignees' people: both are the repo's assignable people.
    private static func setCandidatesKey(_ field: EditField, _ key: PRKey) -> String {
        "\(field == .labels ? "labels" : "assignees")|\(key.repo)"
    }

    /// The teams of `key`'s owner, which the reviewers picker and the @ list share.
    static func teamCandidatesKey(_ key: PRKey) -> String {
        "teams|\(key.repo.split(separator: "/").first.map(String.init) ?? "")"
    }

    /// The cached people (but the PR's author) and teams for the reviewers picker on `key`; nil when
    /// neither is cached. The PR's own requests, reviews and suggestions come with the fetch. No teams
    /// (as the @ list caches for a user's repo or without read:org) counts as nothing cached, so the
    /// picker shows it's loading rather than an empty list.
    private func cachedReviewerCandidates(for key: PRKey) -> SetCandidates? {
        let people = setCandidates[Self.setCandidatesKey(.reviewers, key)]
        let teams = setCandidates[Self.teamCandidatesKey(key)].flatMap { $0.all.isEmpty ? nil : $0 }
        guard people != nil || teams != nil else { return nil }
        let author = pullRequest(for: key)?.author.lowercased()
        return SetCandidates(
            all: (people?.all ?? []).filter { $0.key != author } + (teams?.all ?? []),
            current: [], complete: people?.complete ?? false)
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
        let held = card ?? issue(for: key)
        let pr = held == nil ? pullRequest(for: key) : nil
        let url = held?.url ?? pr?.url ?? GitHubLinks.issue(key)
        let contentId = held?.nodeId ?? pr?.nodeId
        let itemId = addedItemId ?? card?.boardItemNodeId
        let board = snapshot?.boardIds
        let before = shownListKeys()
        let copy: PullRequest? = if case .reviewers = change { fetchedPullRequest(for: key) } else { nil }
        let id = edits.begin(change, on: key, at: Date(), carrying: copy)
        refreshShown()
        followEditedRow(key, from: before)
        let client = api(for: account)
        Task { [weak self] in
            do {
                var added: String?
                switch change {
                case .status:
                    added = try await StatusEditor(api: client).apply(
                        change, on: key, itemId: itemId, contentId: contentId, board: board)
                case .labels, .assignees, .reviewers:
                    let result = try await SetEditor(api: client).apply(change, on: key, contentId: contentId)
                    if result.addApplied, case .reviewers(let added, _) = change, self?.asksViewer(added) == true {
                        NotificationService.shared.ownReviewRequest(on: key)
                    }
                    if !(result.addApplied && result.removeApplied) {
                        guard let self else { return }
                        let before = self.shownListKeys()
                        self.edits.partlyApplied(
                            id, change: change, result: result, on: key, url: url, isUndo: isUndo, at: Date())
                        self.refreshShown()
                        self.followEditedRow(key, from: before)
                        return
                    }
                }
                guard let self, !isUndo else { return }
                self.edits.applied(id, EditRecord(key: key, change: change, madeAt: Date(), addedItemId: added))
            } catch {
                guard let self else { return }
                let before = self.shownListKeys()
                self.edits.failed(id, change: change, on: key, url: url, error: error)
                self.refreshShown()
                self.followEditedRow(key, from: before)
            }
        }
    }

    /// Whether `reviewers` include the viewer, or one of the viewer's teams.
    private func asksViewer(_ reviewers: [Reviewer]) -> Bool {
        guard let org = shownSnapshot?.org else { return false }
        return reviewers.contains { reviewer in
            switch reviewer {
            case .user(let login): login.caseInsensitiveCompare(org.viewer) == .orderedSame
            case .team(let slug, _): org.myTeams.contains(slug.lowercased())
            }
        }
    }

    /// Keeps the edited row selected in its new lane and scrolls to it; when it left the list, selects
    /// the row after it, and the row again when an undo or failure brings it back.
    private func followEditedRow(_ key: PRKey, from before: [PRKey]) {
        switch editSelection.follow(key, selection: listSelection, from: before, to: shownListKeys()) {
        case .none: break
        case .scroll: editScrollRequest += 1
        case .select(let next): listSelection = next
        }
    }

    private func shownListKeys() -> [PRKey] {
        listKeys(doneExpanded: listExpansion.done)
    }

    static func allows(_ permission: EditPermission) -> Bool {
        switch permission {
        case .ready, .unavailable: true
        case .needsAppApproval, .needsGhScope: false
        }
    }
}
