import Foundation

/// An `updated:` term: a step of the time filter, one of GitHub's date forms, or a value the kit can't read
/// that GitHub decides.
public enum UpdatedFilter: Equatable, Sendable {
    case step(TimeStep)
    /// A GitHub date form (`>D`, `>=D`, `<D`, `<=D`, `D`, `D..D`, `D..*`, `*..D`), read as the instants it
    /// spans; `text` is the value as typed, which GitHub gets as written.
    case range(lower: Date?, lowerInclusive: Bool, upper: Date?, upperInclusive: Bool, text: String)
    /// The value as typed; GitHub gets it as written and no row matches it locally.
    case raw(String)

    /// The filter a typed `updated:` value stands for: a step, a date form, else `.raw`.
    public static func parse(_ value: String) -> UpdatedFilter {
        if let step = TimeStep(token: value) { return .step(step) }
        return Self.range(of: value) ?? .raw(value)
    }

    /// `updated:3d`, or `updated:` and the value as typed.
    public var token: String {
        switch self {
        case .step(let step): return "updated:" + step.token
        case .range(_, _, _, _, let text), .raw(let text): return "updated:" + text
        }
    }

    /// `updated:>=2026-10-28T04:00:00Z` for a step (its local start instant in UTC, since GitHub reads a
    /// bare date as 00:00 UTC), else the token as typed.
    public func serverQualifier(now: Date, calendar: Calendar) -> String {
        switch self {
        case .step(let step):
            return "updated:>=" + step.start(now: now, calendar: calendar).formatted(.iso8601)
        case .range, .raw:
            return token
        }
    }

    /// The instants the filter spans, worked out once for a query's rows.
    public struct Window: Sendable {
        let lower: Date?
        let lowerInclusive: Bool
        let upper: Date?
        let upperInclusive: Bool
        let matchesNothing: Bool

        func contains(_ date: Date) -> Bool {
            if matchesNothing { return false }
            if let lower, lowerInclusive ? date < lower : date <= lower { return false }
            if let upper, upperInclusive ? date > upper : date >= upper { return false }
            return true
        }
    }

    /// The filter's window as of `now`; a raw value's window holds nothing.
    public func resolved(now: Date, calendar: Calendar) -> Window {
        switch self {
        case .step(let step):
            return Window(
                lower: step.start(now: now, calendar: calendar), lowerInclusive: true, upper: nil,
                upperInclusive: true, matchesNothing: false)
        case .range(let lower, let lowerInclusive, let upper, let upperInclusive, _):
            return Window(
                lower: lower, lowerInclusive: lowerInclusive, upper: upper, upperInclusive: upperInclusive,
                matchesNothing: false)
        case .raw:
            return Window(lower: nil, lowerInclusive: true, upper: nil, upperInclusive: true, matchesNothing: true)
        }
    }

    /// Whether `pr` was active within the window.
    public func matches(_ pr: PullRequest, now: Date, calendar: Calendar) -> Bool {
        resolved(now: now, calendar: calendar).contains(ActivityDate.of(pr))
    }

    /// Whether `issue` was active within the window; an issue with no date matches nothing.
    public func matches(_ issue: BoardIssue, now: Date, calendar: Calendar) -> Bool {
        guard let date = ActivityDate.of(issue) else { return false }
        return resolved(now: now, calendar: calendar).contains(date)
    }
}

extension UpdatedFilter.Window {
    func matches(_ pr: PullRequest) -> Bool { contains(ActivityDate.of(pr)) }

    func matches(_ issue: BoardIssue) -> Bool { ActivityDate.of(issue).map(contains) ?? false }
}

private extension UpdatedFilter {
    /// One end of a date form: a day (read as that UTC day) or an exact instant.
    enum Endpoint {
        case day(Date)
        case instant(Date)

        var start: Date {
            switch self {
            case .day(let date), .instant(let date): date
            }
        }

        /// The first instant after the endpoint's day, or the instant itself.
        var end: Date {
            switch self {
            case .day(let date): date.addingTimeInterval(86_400)
            case .instant(let date): date
            }
        }

        var isDay: Bool {
            if case .day = self { return true }
            return false
        }
    }

    static func range(of text: String) -> UpdatedFilter? {
        func make(_ lower: Date?, _ lowerInclusive: Bool, _ upper: Date?, _ upperInclusive: Bool) -> UpdatedFilter {
            .range(
                lower: lower, lowerInclusive: lowerInclusive, upper: upper, upperInclusive: upperInclusive,
                text: text)
        }
        if let dots = text.range(of: "..") {
            let from = String(text[..<dots.lowerBound]), to = String(text[dots.upperBound...])
            let lower = from == "*" ? nil : endpoint(from), upper = to == "*" ? nil : endpoint(to)
            guard (from == "*" || lower != nil), (to == "*" || upper != nil), lower != nil || upper != nil else {
                return nil
            }
            return make(lower?.start, true, upper?.end, !(upper?.isDay ?? false))
        }
        for (prefix, op) in [(">=", 0), ("<=", 1), (">", 2), ("<", 3)] where text.hasPrefix(prefix) {
            guard let point = endpoint(String(text.dropFirst(prefix.count))) else { return nil }
            switch op {
            case 0: return make(point.start, true, nil, true)
            case 1: return make(nil, true, point.end, !point.isDay)
            case 2: return make(point.end, point.isDay, nil, true)
            default: return make(nil, true, point.start, false)
            }
        }
        guard let point = endpoint(text) else { return nil }
        return make(point.start, true, point.end, !point.isDay)
    }

    /// `yyyy-MM-dd` as that UTC day, or an ISO-8601 datetime with `Z` or an offset as that instant.
    static func endpoint(_ text: String) -> Endpoint? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let components = DateComponents(year: year, month: month, day: day)
            guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
            return .day(date)
        }
        guard text.contains("T") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text).map(Endpoint.instant)
    }
}
