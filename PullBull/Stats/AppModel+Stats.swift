import Foundation
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
    /// `force`. The answer is cached whatever happens meanwhile, and shown only while Stats for the same
    /// key is still up.
    func loadStats(force: Bool) {
        guard let key = statsKey, let account = runningAccount, let snapshot = shownSnapshot else { return }
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
            guard let self, let report else { return }
            statsCache.store(report, for: key)
            guard !Task.isCancelled, statsOnScreen else { return }
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
