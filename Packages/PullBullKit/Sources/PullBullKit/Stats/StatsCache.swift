import Foundation

/// Which report: one account's scope and period.
public struct StatsKey: Hashable, Sendable {
    public let account: String
    public let scope: FetchScope
    public let period: StatsPeriod

    public init(account: String, scope: FetchScope, period: StatsPeriod) {
        self.account = account
        self.scope = scope
        self.period = period
    }
}

/// The last report per account, scope and period, so reopening Stats shows it at once.
public struct StatsCache: Sendable {
    /// How long a complete report is shown without fetching again.
    public static let freshFor: TimeInterval = 900

    private var reports: [StatsKey: StatsReport] = [:]

    public init() {}

    public mutating func store(_ report: StatsReport, for key: StatsKey) {
        reports[key] = report
    }

    public func report(for key: StatsKey) -> StatsReport? {
        reports[key]
    }

    /// Whether `key` has a complete report under 15 minutes old. A report with a failure is never fresh.
    public func isFresh(_ key: StatsKey, now: Date) -> Bool {
        guard let report = reports[key], report.isComplete else { return false }
        return now.timeIntervalSince(report.fetchedAt) < Self.freshFor
    }

    /// Forgets everything for `account`, e.g. when it is removed.
    public mutating func drop(account: String) {
        reports = reports.filter { $0.key.account != account }
    }
}
