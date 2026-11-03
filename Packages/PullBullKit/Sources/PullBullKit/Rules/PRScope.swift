import Foundation

/// What the pull request list shows: everything, or one of the fetched lists. The raw values are the
/// `settings.sorts` keys, so the sorts saved per `PRTab` carry over.
public enum PRScope: String, Codable, CaseIterable, Sendable {
    case all, review, mine, team

    public init(_ tab: PRTab) {
        switch tab {
        case .review: self = .review
        case .mine: self = .mine
        case .team: self = .team
        }
    }

    /// The fetched list this scope shows; nil for All, which spans them.
    public var tab: PRTab? {
        switch self {
        case .all: nil
        case .review: .review
        case .mine: .mine
        case .team: .team
        }
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .review: "Needs you"
        case .mine: "Mine"
        case .team: "Team"
        }
    }

    /// The chips shown for `scope`: All, then the PR tabs shown (Team needs an org).
    public static func shown(in scope: FetchScope) -> [PRScope] {
        [.all] + PRTab.shown(in: scope).map(PRScope.init)
    }

    /// The scope after clicking `scope`'s chip: the selected chip goes back to All.
    public func picking(_ scope: PRScope) -> PRScope {
        self == scope ? .all : scope
    }
}
