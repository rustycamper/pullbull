import Foundation

/// The GitHub reads Stats makes, so tests can stand in for `GitHubAPI`.
public protocol StatsSource: Sendable {
    func reviewedPRs(window: StatsWindow, login: String, scope: FetchScope) async throws -> Capped<ReviewedPR>
    func openedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<OpenedPR>
    func mergedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<MergedPR>
    func issueCount(_ query: String) async throws -> Int
    func myComments(window: StatsWindow, scope: FetchScope) async throws -> Capped<Date>
}

extension GitHubAPI: StatsSource {}

/// Fetches everything one period's Stats needs and builds the report.
public enum StatsLoader {
    /// Runs every fetch at once. A failed fetch hides only its own values, with the lists' wording for why.
    /// Returns nil when cancelled, so the caller discards it.
    public static func load(
        _ source: any StatsSource, period: StatsPeriod, scope: FetchScope, me: String, myTeams: Set<String>,
        now: Date, calendar: Calendar
    ) async -> StatsReport? {
        let window = period.window(now: now, calendar: calendar)
        let before = period.comparisonWindow(now: now, calendar: calendar)

        async let reviewed = capture { try await source.reviewedPRs(window: window, login: me, scope: scope) }
        async let reviewedBefore = capture { try await source.reviewedPRs(window: before, login: me, scope: scope) }
        async let opened = capture { try await source.openedPRs(window: window, scope: scope) }
        async let openedBefore = capture { try await source.openedPRs(window: before, scope: scope) }
        async let merged = capture { try await source.mergedPRs(window: window, scope: scope) }
        async let mergedBefore = capture { try await source.mergedPRs(window: before, scope: scope) }
        async let closed = capture {
            try await source.issueCount(StatsQueries.closedIssues(window: window, scope: scope))
        }
        async let closedBefore = capture {
            try await source.issueCount(StatsQueries.closedIssues(window: before, scope: scope))
        }
        async let issuesOpened = capture {
            try await source.issueCount(StatsQueries.openedIssues(window: window, scope: scope))
        }
        async let issuesOpenedBefore = capture {
            try await source.issueCount(StatsQueries.openedIssues(window: before, scope: scope))
        }
        async let comments = capture { try await source.myComments(window: window, scope: scope) }

        let results = (
            await reviewed, await reviewedBefore, await opened, await openedBefore, await merged,
            await mergedBefore, await closed, await closedBefore, await issuesOpened, await issuesOpenedBefore,
            await comments)
        if Task.isCancelled { return nil }
        guard let reviewed = results.0, let reviewedBefore = results.1, let opened = results.2,
              let openedBefore = results.3, let merged = results.4, let mergedBefore = results.5,
              let closed = results.6, let closedBefore = results.7, let issuesOpened = results.8,
              let issuesOpenedBefore = results.9, let comments = results.10
        else { return nil }

        let facts = StatsFacts(
            reviewed: reviewed, reviewedBefore: reviewedBefore, opened: opened, openedBefore: openedBefore,
            merged: merged, mergedBefore: mergedBefore, closed: closed, closedBefore: closedBefore,
            issuesOpened: issuesOpened, issuesOpenedBefore: issuesOpenedBefore, comments: comments)
        return StatsReport.build(facts, period: period, me: me, myTeams: myTeams, now: now, calendar: calendar)
    }

    /// The fetch's value or its failure in the lists' wording; nil when it was cancelled.
    private static func capture<T: Sendable>(_ fetch: () async throws -> T) async -> Result<T, StatsFailure>? {
        do {
            return .success(try await fetch())
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            return .failure(StatsFailure(message: RefreshError(error).message))
        }
    }
}
