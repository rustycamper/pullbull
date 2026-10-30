import Foundation

/// How far back the time filter reaches, counted in calendar days that include today.
public enum TimeStep: String, CaseIterable, Sendable {
    case today, threeDays, week, month

    /// Whole days before today that the window starts.
    public var daysBack: Int {
        switch self {
        case .today: return 0
        case .threeDays: return 2
        case .week: return 6
        case .month: return 29
        }
    }

    /// The search token's value, without the `updated:` prefix.
    public var token: String {
        switch self {
        case .today: return "today"
        case .threeDays: return "3d"
        case .week: return "1w"
        case .month: return "1m"
        }
    }

    /// The step a token names, ignoring case.
    public init?(token: String) {
        guard let step = Self.allCases.first(where: { $0.token == token.lowercased() }) else { return nil }
        self = step
    }

    /// The phrase after "Updated" and "Nothing".
    public var title: String {
        switch self {
        case .today: return "today"
        case .threeDays: return "in the last 3 days"
        case .week: return "in the last week"
        case .month: return "in the last month"
        }
    }

    public var menuTitle: String {
        switch self {
        case .today: return "Today"
        case .threeDays: return "In the Last 3 Days"
        case .week: return "In the Last Week"
        case .month: return "In the Last Month"
        }
    }

    /// Local midnight `daysBack` days before the day containing `now`.
    public func start(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: now))!
    }
}

/// The date the time filter judges an item by.
public enum ActivityDate {
    /// `updatedAt` while open, otherwise when it ended (a merged PR's `closedAt` is its merge time).
    public static func of(_ pr: PullRequest) -> Date {
        pr.state == .open ? pr.updatedAt : pr.closedAt ?? pr.updatedAt
    }

    /// nil when the issue carries no date to judge by.
    public static func of(_ issue: BoardIssue) -> Date? {
        issue.isOpen ? issue.updatedAt : issue.closedAt ?? issue.updatedAt
    }
}

/// A transient time window that narrows what a list shows to items active since `start`.
public struct TimeFocus: Equatable, Sendable {
    public let step: TimeStep
    public let start: Date

    public init(step: TimeStep, now: Date, calendar: Calendar = .current) {
        self.step = step
        self.start = step.start(now: now, calendar: calendar)
    }

    public func matches(_ pr: PullRequest) -> Bool { ActivityDate.of(pr) >= start }

    public func matches(_ issue: BoardIssue) -> Bool {
        guard let date = ActivityDate.of(issue) else { return false }
        return date >= start
    }

    /// The strip's line: "Updated in the last week · since Oct 24".
    public func stripText(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let since: String
        switch step {
        case .today:
            return "Updated \(step.title)"
        case .threeDays:
            since = start.formatted(base.weekday(.abbreviated))
        case .week, .month:
            let sameYear = calendar.isDate(start, equalTo: now, toGranularity: .year)
            since = start.formatted(sameYear ? base.month(.abbreviated).day() : base.month(.abbreviated).day().year())
        }
        return "Updated \(step.title) · since \(since)"
    }
}

public struct TimeStepCandidate: CompletionCandidate {
    public let step: TimeStep

    public var id: String { step.rawValue }
    public var insertText: String { QueryScanner.updatedQualifier + step.token }

    public init(step: TimeStep) {
        self.step = step
    }

    /// The steps whose token starts with `prefix`, ignoring case, in `TimeStep` order.
    static func candidates(prefix: String) -> [TimeStepCandidate] {
        let p = prefix.lowercased()
        return TimeStep.allCases.filter { $0.token.hasPrefix(p) }.map(TimeStepCandidate.init)
    }
}
