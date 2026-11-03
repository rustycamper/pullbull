import Foundation

/// Where the pull request list opens each time the popover opens.
public enum OpenOn: String, Codable, CaseIterable, Sendable {
    case all, lastUsed, review, mine, team

    public var title: String {
        switch self {
        case .lastUsed: "Last used"
        case .all: PRScope.all.title
        case .review: PRScope.review.title
        case .mine: PRScope.mine.title
        case .team: PRScope.team.title
        }
    }

    /// The scope this choice opens on; nil for Last used, which follows `AppSettings.lastScope`.
    public var scope: PRScope? {
        switch self {
        case .lastUsed: nil
        case .all: .all
        case .review: .review
        case .mine: .mine
        case .team: .team
        }
    }
}

extension AppSettings {
    /// The chips the list shows: only All with chips off, else those the account's scope shows.
    public var prChips: [PRScope] {
        guard scopeChips else { return [.all] }
        return scope.map(PRScope.shown) ?? PRScope.allCases
    }

    /// The PR tabs a search can narrow to: none with chips off, else those the account's scope shows.
    public var prSearchTabs: [PRTab] {
        guard scopeChips else { return [] }
        return scope.map(PRTab.shown) ?? PRTab.allCases
    }

    /// The scope the list opens on: the chosen one when its chip is shown, else All.
    public var scopeOnOpen: PRScope {
        let wanted = openOn.scope ?? lastScope
        return prChips.contains(wanted) ? wanted : .all
    }

    /// The choices the picker offers: Team only when the account's tabs include it, or it is the current choice.
    public var openOnChoices: [OpenOn] {
        let tabs = scope.map(PRTab.shown) ?? PRTab.allCases
        return OpenOn.allCases.filter { $0 != .team || tabs.contains(.team) || openOn == .team }
    }

    /// The close-time rule: with chips on, remembers the chip shown, whatever `openOn` is. With chips
    /// off it changes nothing, so the last chip survives a chips-off spell.
    public mutating func recordLastScope(_ shown: PRScope) {
        guard scopeChips, lastScope != shown else { return }
        lastScope = shown
    }
}
