import Foundation

/// A section of the pull request list, declared in display order.
public enum PRSection: String, CaseIterable, Sendable {
    case needsReview, yourPRs, waiting, recentlyClosed, team, otherResults

    public var title: String {
        switch self {
        case .needsReview: "Needs your review"
        case .yourPRs: "Your PRs"
        case .waiting: "Waiting on others"
        case .recentlyClosed: "Recently closed"
        case .team: "Team"
        case .otherResults: "Other results"
        }
    }

    /// The fetched list whose row rules apply to this section's rows; nil for Recently closed.
    public var rowTab: PRTab? {
        switch self {
        case .needsReview: .review
        case .yourPRs, .waiting: .mine
        case .team, .otherResults: .team
        case .recentlyClosed: nil
        }
    }

    /// Where an open PR of mine goes: Your PRs when it is waiting on me, else Waiting on others. A
    /// cancelled-only run reads as a failure in GitHub's rollup, so it lands in Your PRs.
    public static func mine(_ pr: PullRequest) -> PRSection {
        let needsMe = ReviewRules.isReadyToMerge(pr)
            || pr.latestReviews.contains { $0.state == .changesRequested }
            || pr.ci == .failure
            || pr.hasConflicts
            || pr.isDraft
        return needsMe ? .yourPRs : .waiting
    }
}

extension PRScope {
    /// The sections this scope shows, in display order.
    public var sections: [PRSection] {
        switch self {
        case .all: [.needsReview, .yourPRs, .waiting, .recentlyClosed, .team]
        case .review: [.needsReview]
        case .mine: [.yourPRs, .waiting, .recentlyClosed]
        case .team: [.team]
        }
    }

    public var showsSectionHeaders: Bool { self == .all || self == .mine }
}

public struct ListSection: Sendable, Identifiable {
    public let section: PRSection
    public let contents: TabContents
    public var id: PRSection { section }

    /// The counted rows, but every row for Recently closed.
    public var count: Int { section == .recentlyClosed ? contents.rows.count : contents.count }

    init(section: PRSection, contents: TabContents) {
        self.section = section
        self.contents = contents
    }
}

/// The sections a scope shows, each pull request once.
public struct PRList: Sendable {
    public let scope: PRScope
    /// Non-empty sections only, in display order.
    public let sections: [ListSection]

    init(scope: PRScope, sections: [ListSection]) {
        self.scope = scope
        self.sections = sections
    }

    public var isEmpty: Bool { sections.isEmpty }

    /// Counted rows outside Recently closed.
    public var count: Int { sections.filter { $0.section != .recentlyClosed }.reduce(0) { $0 + $1.count } }

    /// Every row.
    public var rowCount: Int { sections.reduce(0) { $0 + $1.contents.rows.count } }

    /// All, with something listed, and nothing to review and none of my PRs waiting on me.
    public var nothingNeedsYou: Bool {
        scope == .all && !isEmpty
            && !sections.contains { $0.section == .needsReview && $0.count > 0 }
            && !sections.contains { $0.section == .yourPRs }
    }

    public static func build(
        _ tabs: BuiltTabs, scope: PRScope, teamShown: Bool, settings: AppSettings, org: OrgContext, now: Date
    ) -> PRList {
        var built: [ListSection] = []
        for section in scope.sections where section != .team || teamShown {
            var contents = rows(of: section, in: tabs)
            if scope == .all, let tab = section.rowTab {
                contents = TabBuilder.contents(
                    contents.rows, sort: settings.sort(for: PRScope.all), on: tab, me: org.viewer,
                    myTeams: org.myTeams, now: now)
            }
            if !contents.rows.isEmpty { built.append(ListSection(section: section, contents: contents)) }
        }
        return PRList(scope: scope, sections: built)
    }

    private static func rows(of section: PRSection, in tabs: BuiltTabs) -> TabContents {
        switch section {
        case .needsReview: tabs.review
        case .yourPRs: tabs.yourPRs
        case .waiting: tabs.waitingOnOthers
        case .team: tabs.teamSection
        case .recentlyClosed:
            TabContents(rows: tabs.recentlyClosed.map { Row(pr: $0, dimmed: false, counted: false) })
        case .otherResults: TabContents(rows: [])
        }
    }
}

extension BuiltTabs {
    /// My PRs that need me, in Mine's order.
    public var yourPRs: TabContents {
        TabContents(rows: mine.rows.filter { PRSection.mine($0.pr) == .yourPRs })
    }

    /// My PRs waiting on others, in Mine's order.
    public var waitingOnOthers: TabContents {
        TabContents(rows: mine.rows.filter { PRSection.mine($0.pr) == .waiting })
    }

    /// Team without any PR in Needs your review, dimmed rows included.
    public var teamSection: TabContents {
        let reviewKeys = Set(review.rows.map(\.id))
        return TabContents(rows: team.rows.filter { !reviewKeys.contains($0.id) })
    }

    /// The chip's count; nil for All.
    public func count(of scope: PRScope) -> Int? {
        switch scope {
        case .all: nil
        case .review: review.count
        case .mine: yourPRs.count + waitingOnOthers.count
        case .team: teamSection.count
        }
    }
}

public struct ScopedPRList: Sendable {
    public let list: PRList
    /// Every row the focus hides, counted or dimmed.
    public let hiddenCount: Int

    public init(unscoped list: PRList) {
        self.list = list
        hiddenCount = 0
    }

    init(list: PRList, hiddenCount: Int) {
        self.list = list
        self.hiddenCount = hiddenCount
    }
}
