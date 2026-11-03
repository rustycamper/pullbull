import SwiftUI
import PullBullKit

/// The Issues scopes as a row of capsule chips: All, Assigned, Created and Board, each with its list's
/// count; Board is shown with or without a board. A list that failed or never loaded shows "–"; one kept
/// from before its latest search failed shows its count with a warning triangle, and All, which has no
/// count, shows the triangle while Assigned or Created is so kept. Counts above 99 read "99+". While
/// results are on screen All reads Everywhere and counts the results, each other count is the list's
/// matches for the query, and a click narrows the search to the scope (`AppModel.pickSearchScope`): only
/// the narrowed chip is drawn as selected. No chip takes the accent colour: none is a request waiting.
struct IssueScopeChips: View {
    let model: AppModel
    /// Results are on screen (`Route.search`).
    let searching: Bool
    /// Runs before a click picks a scope outside results, so the empty field's hints can close.
    let willSelect: () -> Void

    /// Created keeps the issues also assigned to me, which All's You opened leaves out.
    private static let createdNote = "Includes issues also assigned to you"

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IssueScope.allCases, id: \.self) { scope in
                ScopeChip(
                    title: title(of: scope), count: count(of: scope), selected: isSelected(scope),
                    hot: false, crowded: crowded, help: help(of: scope), spoken: spoken(of: scope),
                    warning: !staleLists(of: scope).isEmpty
                ) {
                    pick(scope)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Issue scopes")
    }

    private func title(of scope: IssueScope) -> String {
        searching && scope == .all ? "Everywhere" : scope.title
    }

    /// The scope's count: its matches while searching (Everywhere's is the results'), else its list's count.
    /// An empty list shows none, and All has none; a stale or unreadable list still shows, and a search
    /// shows its zeros, which say "no matches here".
    private func count(of scope: IssueScope) -> IssueTabCount? {
        if searching {
            guard let tab = scope.tab else { return model.everywhereCount }
            return model.searchMatchCounts[.issues(tab)]
        }
        return model.issueTabs?.chipCount(of: scope)
    }

    /// The lists All reads that didn't update, outside search; empty for the other chips, whose own count
    /// carries the warning.
    private func staleLists(of scope: IssueScope) -> [IssueTab] {
        guard !searching, scope == .all else { return [] }
        return model.issueTabs?.staleTabs ?? []
    }

    private func isSelected(_ scope: IssueScope) -> Bool {
        searching ? model.shownSearchScope == SearchScope(.issues(scope)) : model.issueScope == scope
    }

    /// Whether any count on screen reads three or more characters ("99+"), which needs the room.
    private var crowded: Bool {
        IssueScope.allCases.contains { scope in
            switch count(of: scope) {
            case .current(let n), .stale(let n, _, _): TabCountText.header(n).count >= 3
            case .unavailable, nil: false
            }
        }
    }

    private func pick(_ scope: IssueScope) {
        let tab = ShownTab.issues(scope)
        if searching {
            model.pickSearchScope(tab)
            let shown = model.shownSearchScope
            let matches = model.searchResults.map { $0.orderedKeys(mode: model.mode).count }
            AccessibilityNotification.Announcement(
                SearchContext.scopeAnnouncement(tab: shown.isNarrowed ? tab.title : nil, matches: matches)
            ).post()
            return
        }
        willSelect()
        model.pickIssueScope(scope)
    }

    /// What the scope covers, then why a list didn't update: while searching, Everywhere searches the
    /// lists and GitHub.
    private func help(of scope: IssueScope) -> String {
        if searching && scope == .all { return "Your lists and GitHub" }
        let stale = staleLists(of: scope).map { IssueScope($0).title }
        let lines = [
            ShownTab.issues(scope).summary,
            scope == .created ? Self.createdNote : nil,
            count(of: scope).flatMap(ScopeChip.staleHelp),
            stale.isEmpty ? nil : "Didn't update · " + stale.joined(separator: ", "),
        ]
        return lines.compactMap(\.self).joined(separator: "\n")
    }

    /// Title, then count; the label says when the count ignores the focus, so it isn't misread.
    private func spoken(of scope: IssueScope) -> String {
        let title = title(of: scope)
        var base = count(of: scope).map { "\(title), \(spoken($0))" } ?? title
        let stale = staleLists(of: scope).map { IssueScope($0).title }
        if !stale.isEmpty { base += ", " + ListFormatter.localizedString(byJoining: stale) + " didn't update" }
        if scope == .created { base += ", " + Self.createdNote }
        return base + filteredSuffix(for: scope)
    }

    /// The counts ignore the repo focus and the time focus; the time focus is named on the chip on screen,
    /// the one it applies to. Match counts follow the repo focus, as the results do, and ignore the time
    /// focus.
    private func filteredSuffix(for scope: IssueScope) -> String {
        if searching {
            return model.repoFocus.map { ", in \(model.displayName(of: $0.repo))" } ?? ""
        }
        var parts: [String] = []
        if let repo = model.repoFocus { parts.append(model.displayName(of: repo.repo)) }
        if let time = model.timeFocus, model.issueScope == scope { parts.append("updated \(time.step.title)") }
        return parts.isEmpty ? "" : ", filtered to " + parts.joined(separator: ", ")
    }

    /// The exact number, which "99+" hides.
    private func spoken(_ count: IssueTabCount) -> String {
        if searching { return SearchContext.spokenMatches(count) }
        switch count {
        case .current(let n): return "\(n)"
        case .stale(let n, _, _): return "\(n), didn't update"
        case .unavailable: return "unavailable"
        }
    }
}
