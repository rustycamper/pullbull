import AppKit
import PullBullKit

// MARK: - Loading Stats

extension AppModel {
    /// The report Stats shows: the running account, the scope of the lists on screen, and the chosen
    /// period. Nil until both are known.
    var statsKey: StatsKey? {
        guard let account = runningAccount, let snapshot = shownSnapshot else { return nil }
        return StatsKey(account: account.login, scope: snapshot.org.scope, period: settings.statsPeriod)
    }

    /// A period chip: the choice is kept as a setting, and that period's report shows, fetched when it
    /// isn't fresh.
    func setStatsPeriod(_ period: StatsPeriod) {
        guard period != settings.statsPeriod else { return }
        settings.statsPeriod = period
        loadStats(force: false)
    }

    /// Refresh on Stats: fetches the report again, cached or not.
    func refreshStats() {
        loadStats(force: true)
    }

    /// Shows the cached report for `statsKey` at once, and fetches it when it isn't fresh, or always with
    /// `force`. The answer is cached unless the fetch was stopped meanwhile (Back, another period, a
    /// sign-out), and shown only while Stats for the same key is still up.
    func loadStats(force: Bool) {
        guard let key = statsKey, let account = runningAccount, let snapshot = shownSnapshot else {
            // Nothing to load for: no spinner is left running.
            stopStatsLoad()
            return
        }
        let cached = statsCache.report(for: key)
        if !force, statsCache.isFresh(key, now: Date()) {
            stopStatsLoad()
            showStats(cached, loading: false)
            return
        }
        statsTask?.cancel()
        showStats(cached, loading: true)
        let api = api(for: account)
        let org = key.scope.org
        let me = snapshot.org.viewer
        let myTeams = snapshot.org.myTeams
        statsTask = Task { [weak self] in
            let report = await StatsLoader.load(
                api, period: key.period, scope: key.scope, me: me, myTeams: myTeams,
                orgID: { [weak self] in
                    guard let org else { return nil }
                    guard let self else { throw CancellationError() }
                    return try await self.statsOrgID(org, api: api)
                },
                now: Date(), calendar: .current)
            // A stopped fetch leaves the screen to whatever stopped it, and caches nothing: after a
            // sign-out the account's reports are dropped.
            guard let self, !Task.isCancelled else { return }
            guard let report else {
                // Stopped below the task (StatsLoader answers nil): nothing new, and no longer loading.
                showStats(statsReport, loading: false)
                return
            }
            statsCache.store(report, for: key)
            guard statsOnScreen else { return }
            if statsKey == key {
                showStats(report, loading: false)
            } else {
                // The lists brought another scope while this ran: fetch for that one.
                loadStats(force: false)
            }
        }
    }

    /// The org's node ID, which the reviewed fetch needs. GitHub's answer is kept, so each org is looked
    /// up once.
    private func statsOrgID(_ org: String, api: GitHubAPI) async throws -> String {
        let login = org.lowercased()
        if let id = statsOrgIDs[login] { return id }
        let id = try await api.organizationID(org)
        statsOrgIDs[login] = id
        return id
    }
}

// MARK: - Right now

extension AppModel {
    /// The Right now card's two rows, picked from the lists' Review and Mine rows as loaded.
    var rightNow: RightNow {
        guard let org = shownSnapshot?.org else { return RightNow(waitingOnMe: nil, myLongest: nil) }
        return RightNow.pick(
            review: tabs?.review.rows ?? [], mine: tabs?.mine.rows ?? [], me: org.viewer, myTeams: org.myTeams,
            now: Date())
    }

    /// ←/→ on Stats: the neighbouring period chip, stopping at the ends.
    func moveStatsPeriod(by offset: Int) {
        setStatsPeriod(ListNavigation.tab(settings.statsPeriod, movedBy: offset))
    }

    /// ↑/↓ on Stats: the other Right now row, stopping at the ends.
    func moveStatsSelection(by offset: Int) {
        guard let key = ListNavigation.move(statsSelection, by: offset, in: rightNow.keys) else { return }
        statsSelection = key
    }

    /// The highlighted Right now row, while it is still on the card.
    private var statsSelectionItem: RightNowItem? {
        statsSelection.flatMap(rightNow.item(for:))
    }

    /// Return on Stats: the highlighted row's detail, with Back to Stats; false with none highlighted.
    func openStatsSelection() -> Bool {
        guard let key = statsSelectionItem?.row.id else { return false }
        openDetail(key)
        return true
    }

    /// ⌘↩ on Stats: the highlighted row's PR on GitHub.
    func openStatsSelectionOnGitHub() -> Bool {
        guard let item = statsSelectionItem else { return false }
        NSWorkspace.shared.open(item.row.pr.url)
        return true
    }

    /// ⌘C on Stats: the highlighted row's link.
    func copyStatsSelectionLink() -> Bool {
        guard let item = statsSelectionItem else { return false }
        PRActions.copy(item.row.pr.url.absoluteString)
        return true
    }
}
