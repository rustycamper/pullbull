import SwiftUI
import PullBullKit

/// The Pull Requests scopes as a row of capsule chips: All, Needs you, Mine and Team (no Team without an
/// org), each with its count. Counts above 99 read "99+". While results are on screen All reads
/// Everywhere and counts the results, each other count is the scope's matches for the query, and a click
/// narrows the search to the scope (`AppModel.pickSearchScope`): only the narrowed chip is drawn as
/// selected. Outside search the counts ignore the repo and time focus.
struct ScopeChips: View {
    let model: AppModel
    /// Results are on screen (`Route.search`).
    let searching: Bool
    /// Runs before a click picks a scope outside results, so the empty field's hints can close.
    let willSelect: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.prScopes, id: \.self) { scope in
                ScopeChip(
                    title: title(of: scope), count: count(of: scope), selected: isSelected(scope),
                    hot: !searching && scope == .review, crowded: crowded,
                    help: help(of: scope), spoken: spoken(of: scope)
                ) {
                    pick(scope)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pull request scopes")
    }

    private func title(of scope: PRScope) -> String {
        searching && scope == .all ? "Everywhere" : scope.title
    }

    /// The scope's count: its matches while searching (Everywhere's is the results'), else its list's count.
    /// An empty list shows none, and so does All; a search shows its zeros, which say "no matches here".
    private func count(of scope: PRScope) -> IssueTabCount? {
        if searching {
            guard let tab = scope.tab else { return model.everywhereCount }
            return model.searchMatchCounts[.pullRequests(tab)]
        }
        guard scope != .all else { return nil }
        return (model.tabs?.count(of: scope)).flatMap { $0 == 0 ? nil : .current($0) }
    }

    private func isSelected(_ scope: PRScope) -> Bool {
        searching ? model.shownSearchScope == SearchScope(.pullRequests(scope)) : model.prScope == scope
    }

    /// Whether any count on screen reads three or more characters ("99+"), which needs the room.
    private var crowded: Bool {
        model.prScopes.contains { scope in
            switch count(of: scope) {
            case .current(let n), .stale(let n, _, _): TabCountText.header(n).count >= 3
            case .unavailable, nil: false
            }
        }
    }

    private func pick(_ scope: PRScope) {
        let tab = ShownTab.pullRequests(scope)
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
        model.pickScope(scope)
    }

    /// What the scope covers: while searching, Everywhere searches the lists and GitHub.
    private func help(of scope: PRScope) -> String {
        searching && scope == .all ? "Your lists and GitHub" : ShownTab.pullRequests(scope).summary
    }

    /// Title, then count; the label says when the count ignores the focus, so it isn't misread.
    private func spoken(of scope: PRScope) -> String {
        let title = title(of: scope)
        let base = count(of: scope).map { "\(title), \(spoken($0))" } ?? title
        return base + filteredSuffix
    }

    /// The counts ignore the repo focus and the time focus; match counts follow the repo focus, as the
    /// results do, and ignore the time focus.
    private var filteredSuffix: String {
        if searching {
            return model.repoFocus.map { ", in \(model.displayName(of: $0.repo))" } ?? ""
        }
        var parts: [String] = []
        if let repo = model.repoFocus { parts.append(model.displayName(of: repo.repo)) }
        if let time = model.timeFocus { parts.append("updated \(time.step.title)") }
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

private struct ScopeChip: View {
    let title: String
    let count: IssueTabCount?
    let selected: Bool
    /// Needs you with something waiting: its count takes the accent colour.
    let hot: Bool
    let crowded: Bool
    let help: String
    let spoken: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // The semibold width is always reserved, so selecting changes the weight, never the position.
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .hidden()
                    .overlay {
                        Text(title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Palette.secondaryText)
                    }
                if let count { countLabel(count) }
            }
            .lineLimit(1)
            .padding(.horizontal, crowded ? 6 : 9)
            .frame(height: 22)
            .background(Capsule().fill(fill))
            .overlay {
                // Increase Contrast edges the chosen chip too.
                if selected, contrast == .increased { Capsule().strokeBorder(Color.primary, lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel(spoken)
    }

    private var fill: Color {
        if selected { return Palette.strongFill }
        return hovering ? Palette.fill : .clear
    }

    @ViewBuilder private func countLabel(_ count: IssueTabCount) -> some View {
        let color: Color = hot && count != .current(0) ? .accentColor : selected ? .primary : Palette.secondaryText
        switch count {
        case .current(let n), .stale(let n, _, _):
            Text(TabCountText.header(n))
                .font(.system(size: 11, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(color)
        case .unavailable:
            Text("–")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(color)
        }
    }
}
