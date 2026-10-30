import Foundation

/// What a search on screen covers: everything (the snapshot's matches and GitHub's), or the items one
/// tab lists, matched locally. A scope lives only while the field holds a query.
public enum SearchScope: Hashable, Sendable {
    case everything
    case pullRequests(PRTab)
    case issues(IssueTab)

    public var isNarrowed: Bool { self != .everything }

    /// The mode whose tab this is; nil for everything.
    public var mode: PopoverMode? {
        switch self {
        case .everything: nil
        case .pullRequests: .pullRequests
        case .issues: .issues
        }
    }

    /// A tab clicked during a search: narrows to it, or back to everything when it is the scope already.
    public func picking(_ tab: SearchScope) -> SearchScope {
        tab == self ? .everything : tab
    }

    /// The scope once the field holds `text`: an empty field drops it, so the next query searches everything.
    public func edited(to text: String) -> SearchScope {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .everything : self
    }

    /// Everything when the tab belongs to the other mode or isn't shown (Team without an org).
    public func valid(in mode: PopoverMode, prTabs: [PRTab]) -> SearchScope {
        switch (self, mode) {
        case (.pullRequests(let tab), .pullRequests): prTabs.contains(tab) ? self : .everything
        case (.issues, .issues): self
        default: .everything
        }
    }
}

/// A search narrowed to one tab: the items the tab lists, matched as `SearchEngine.local` matches the
/// snapshot, within the repo focus. Nothing is asked of GitHub.
public enum SearchNarrowing {
    /// Every row of the tab, dimmed ones included, and on Mine the recently closed PRs.
    public static func items(of tab: PRTab, in tabs: BuiltTabs) -> [PullRequest] {
        switch tab {
        case .review: tabs.review.rows.map(\.pr)
        case .mine: tabs.mine.rows.map(\.pr) + tabs.recentlyClosed
        case .team: tabs.team.rows.map(\.pr)
        }
    }

    /// Every group of the tab, the folded Done group included; nothing while Board can't be read.
    public static func items(of tab: IssueTab, in tabs: BuiltIssueTabs) -> [BoardIssue] {
        tabs.contents(tab)?.issues ?? []
    }

    /// The results of `q` within `scope`, in the usual search order; nil for `.everything`. With `snap`, an
    /// issue tab's copies take their board copy's Status first, as search results do, so a `status:` token
    /// matches it and the rows show it.
    public static func results(
        _ q: SearchQuery, scope: SearchScope, tabs: BuiltTabs?, issueTabs: BuiltIssueTabs?, focus: RepoFocus?,
        viewer: String, snap: Snapshot? = nil
    ) -> SearchResults? {
        switch scope {
        case .everything:
            return nil
        case .pullRequests(let tab):
            let prs = matching(q, tabs.map { items(of: tab, in: $0) } ?? [], focus: focus, viewer: viewer)
            return SearchEngine.assemble(prs: prs, issues: [], phase: .done)
        case .issues(let tab):
            let listed = issueTabs.map { items(of: tab, in: $0, snap: snap) } ?? []
            let issues = matching(q, listed, focus: focus, viewer: viewer)
            return SearchEngine.assemble(prs: [], issues: issues, phase: .done)
        }
    }

    /// Each shown tab's matches for `q`, keeping how its count reads: a stale list's matches stay stale,
    /// a list that isn't there stays unavailable. Tabs without lists yet are left out; empty for no query.
    /// `snap` as for `results`.
    public static func counts(
        _ q: SearchQuery, prTabs: [PRTab], tabs: BuiltTabs?, issueTabs: BuiltIssueTabs?, focus: RepoFocus?,
        viewer: String, snap: Snapshot? = nil
    ) -> [SearchScope: IssueTabCount] {
        guard q != .empty else { return [:] }
        var counts: [SearchScope: IssueTabCount] = [:]
        if let tabs {
            for tab in prTabs {
                let matches = matching(q, items(of: tab, in: tabs), focus: focus, viewer: viewer)
                counts[.pullRequests(tab)] = .current(uniqueCount(matches.map(\.key)))
            }
        }
        if let issueTabs {
            for tab in IssueTab.allCases {
                let n = uniqueCount(
                    matching(q, items(of: tab, in: issueTabs, snap: snap), focus: focus, viewer: viewer).map(\.key))
                counts[.issues(tab)] = switch issueTabs.count(tab) {
                case .current: .current(n)
                case .stale(_, let error, let since): .stale(n, error: error, since: since)
                case .unavailable: .unavailable
                }
            }
        }
        return counts
    }

    private static func matching(
        _ q: SearchQuery, _ prs: [PullRequest], focus: RepoFocus?, viewer: String
    ) -> [PullRequest] {
        let window = q.updated?.resolved(now: Date(), calendar: .current)
        return prs.filter { q.matches($0, viewer: viewer, window: window) && SearchEngine.inFocus($0.key, q.keeping(focus)) }
    }

    /// The tab's items, with their board copy's Status when `snap` is given.
    private static func items(of tab: IssueTab, in tabs: BuiltIssueTabs, snap: Snapshot?) -> [BoardIssue] {
        let listed = items(of: tab, in: tabs)
        return snap.map { SearchEngine.onBoard(listed, in: $0) } ?? listed
    }

    private static func matching(
        _ q: SearchQuery, _ issues: [BoardIssue], focus: RepoFocus?, viewer: String
    ) -> [BoardIssue] {
        let window = q.updated?.resolved(now: Date(), calendar: .current)
        return issues.filter { q.matches($0, viewer: viewer, window: window) && SearchEngine.inFocus($0.key, q.keeping(focus)) }
    }

    /// As many as the results list: an item listed twice shows once.
    private static func uniqueCount(_ keys: [PRKey]) -> Int { Set(keys).count }
}

extension SearchContext {
    /// `<query> in <tab> · N matches`: `#12`, `owner/name #12`, `“words”`, or the tokens then `· “words”` as
    /// `text` lists them.
    public static func narrowedText(_ q: SearchQuery, tab: String, matches: Int) -> String {
        let what: String
        switch q {
        case .number(let n): what = "#\(n)"
        case .item(let repo, let n): what = "\(repo) #\(n)"
        case .text(let words): what = "“\(words.joined(separator: " "))”"
        case .filtered(let logins, let labels, let words, let states, let statuses, let updated):
            var tokens = SearchQuery.tokenList(
                logins: logins, labels: labels, states: states, statuses: statuses, updated: updated)
            if !words.isEmpty { tokens += " · “\(words.joined(separator: " "))”" }
            what = tokens
        case .empty: what = ""
        }
        let place = what.isEmpty ? "In \(tab)" : "\(what) in \(tab)"
        return "\(place) · \(matchCount(matches))"
    }

    /// `#12 in <tab>`, `Titles matching <words> in <tab>`, or `Filtered by …, in <tab>`, then `, in <repo>`
    /// with a focus and the matches.
    public static func narrowedAccessibilityLabel(
        _ q: SearchQuery, tab: String, matches: Int, repo: String?
    ) -> String {
        var label: String
        switch q {
        case .number(let n): label = "#\(n) in \(tab)"
        case .item(let repo, let n): label = "\(repo) #\(n) in \(tab)"
        case .text(let words): label = "Titles matching \(words.joined(separator: " ")) in \(tab)"
        case .filtered(let logins, let labels, let words, let states, let statuses, let updated):
            label = filterDescription(
                logins: logins, labels: labels, states: states, statuses: statuses, updated: updated, words: words) + ", in \(tab)"
        case .empty: label = "In \(tab)"
        }
        // An item names its own repository.
        if let repo, q.keeping(RepoFocus(repo: repo)) != nil { label += ", in \(repo)" }
        return label + ", " + matchCount(matches)
    }

    /// `1 match`, `3 matches`.
    public static func matchCount(_ n: Int) -> String {
        n == 1 ? "1 match" : "\(n) matches"
    }

    /// The empty state of a narrowed search.
    public static func noMatches(inTab tab: String) -> String {
        "No matches in \(tab)"
    }

    /// What VoiceOver says when a tab click changes the scope: `Searching <tab>, N matches`, or
    /// `Searching everything` without a tab.
    public static func scopeAnnouncement(tab: String?, matches: Int?) -> String {
        guard let tab else { return "Searching everything" }
        return matches.map { "Searching \(tab), \(matchCount($0))" } ?? "Searching \(tab)"
    }

    /// A tab's count during a search, as VoiceOver says it after the tab's name.
    public static func spokenMatches(_ count: IssueTabCount) -> String {
        switch count {
        case .current(let n): matchCount(n)
        case .stale(let n, _, _): "\(matchCount(n)), didn't update"
        case .unavailable: "unavailable"
        }
    }
}
