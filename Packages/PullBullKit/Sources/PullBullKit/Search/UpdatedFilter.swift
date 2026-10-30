import Foundation

/// An `updated:` term: a step of the time filter, or a value the kit can't read that GitHub decides.
public enum UpdatedFilter: Equatable, Sendable {
    case step(TimeStep)
    /// The value as typed; GitHub gets it as written and no row matches it locally.
    case raw(String)

    /// `updated:3d`, or `updated:` and the raw value.
    public var token: String {
        switch self {
        case .step(let step): return "updated:" + step.token
        case .raw(let value): return "updated:" + value
        }
    }

    /// `updated:>=2026-10-28T04:00:00Z` for a step (its local start instant in UTC, since GitHub reads a
    /// bare date as 00:00 UTC), else the raw token.
    public func serverQualifier(now: Date, calendar: Calendar) -> String {
        switch self {
        case .step(let step):
            return "updated:>=" + step.start(now: now, calendar: calendar).formatted(.iso8601)
        case .raw:
            return token
        }
    }

    /// Whether `pr` was active since the step's start; a raw value matches nothing.
    public func matches(_ pr: PullRequest, now: Date, calendar: Calendar) -> Bool {
        guard case .step(let step) = self else { return false }
        return ActivityDate.of(pr) >= step.start(now: now, calendar: calendar)
    }

    /// Whether `issue` was active since the step's start; a raw value, or an issue with no date, matches nothing.
    public func matches(_ issue: BoardIssue, now: Date, calendar: Calendar) -> Bool {
        guard case .step(let step) = self, let date = ActivityDate.of(issue) else { return false }
        return date >= step.start(now: now, calendar: calendar)
    }
}
