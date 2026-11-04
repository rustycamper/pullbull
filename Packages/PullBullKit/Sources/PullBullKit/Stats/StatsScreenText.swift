import Foundation

/// One run of a value as a card draws it: figures large, a unit ("h", "m") small after them.
public struct StatTextPart: Equatable, Sendable {
    public let text: String
    public let isUnit: Bool

    public init(text: String, isUnit: Bool) {
        self.text = text
        self.isUnit = isUnit
    }
}

extension StatValue {
    /// "3 h 10 m" as 3, h, 10, m, so the units can draw smaller. "137+" and "–" are one figure; the "<"
    /// of "< 1 m" draws small, as a unit does.
    public var parts: [StatTextPart] {
        text.split(separator: " ").map { word in
            StatTextPart(text: String(word), isUnit: word != "–" && !word.contains(where: \.isNumber))
        }
    }
}

extension StatsPeriod {
    /// The reviews card's trailing note, "Last 7 days": the chips stand for trailing days, not calendar weeks.
    public var span: String { "Last \(days) days" }

    /// The chip's tooltip, "Today and the 6 days before".
    public var summary: String { "Today and the \(days - 1) days before" }
}

extension StatsCard {
    public var title: String {
        switch self {
        case .reviews: "Your reviews"
        case .pullRequests: "Your pull requests"
        case .issues: "Issues"
        }
    }

    /// What VoiceOver reads for a card with no report behind it yet.
    public func placeholderSpeech(loading: Bool) -> String {
        loading ? "\(title), loading" : "\(title), not available"
    }
}

/// The Stats footer's provenance line and its tooltip.
public enum StatsFooter {
    /// "From GitHub, for dana in acme", or "in your repositories" for the personal scope, then the cap
    /// note when a cap cut in.
    public static func text(login: String, org: String?, capNote: String?) -> String {
        let place = org.map { "in \($0)" } ?? "in your repositories"
        let line = "From GitHub, for \(login) \(place)"
        return capNote.map { "\(line) \($0)" } ?? line
    }

    /// "Updated 4 minutes ago. Only repositories PullBull can see."; without a report, the second sentence.
    public static func help(fetchedAt: Date?, now: Date) -> String {
        let scope = "Only repositories PullBull can see."
        guard let fetchedAt else { return scope }
        return "Updated \(RelativeAge.spoken(from: fetchedAt, to: now)) ago. \(scope)"
    }
}
