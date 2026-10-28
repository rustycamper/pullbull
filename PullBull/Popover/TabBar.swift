import SwiftUI
import PullBullKit

/// The segmented tabs of the current mode, with a count per tab: Review / Mine / Team from `BuiltTabs`
/// (no Team without an org), or Assigned / Created / Board from `BuiltIssueTabs`. An issue list that
/// failed or never loaded shows "–", never "0"; a list kept from before its latest search failed shows
/// its count with a warning triangle. Counts above 99 read "99+". While results are on screen each count
/// is the tab's matches for the query, and a click narrows the search to the tab (`AppModel.pickSearchScope`):
/// only the narrowed tab is drawn as selected, none while the search covers everything.
struct TabBar: View {
    @Bindable var model: AppModel
    /// Results are on screen (`Route.search`).
    var searching = false
    /// Runs before a click picks a tab outside results, so the empty field's hints can close.
    var willSelect: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumbSpace
    @State private var hovered: ShownTab?
    /// Bumped by each click, so only a click slides the thumb; a restore or a mode switch moves it at once.
    @State private var clicks = 0

    var body: some View {
        SegmentRow(spacing: 2, padding: crowded ? 6 : 8) {
            switch model.mode {
            case .pullRequests:
                ForEach(model.prTabs, id: \.self) { tab in
                    segment(
                        .pullRequests(tab), title: tab.title, count: count(of: .pullRequests(tab)),
                        selected: isSelected(.pullRequests(tab))
                    ) {
                        pick(.pullRequests(tab))
                    }
                }
            case .issues:
                ForEach(IssueTab.allCases, id: \.self) { tab in
                    segment(
                        .issues(tab), title: tab.title, count: count(of: .issues(tab)), selected: isSelected(.issues(tab))
                    ) {
                        pick(.issues(tab))
                    }
                }
            }
        }
        // One thumb for the row, following the selected segment, so it slides instead of blinking.
        .background {
            if hasSelection {
                SegmentThumb(radius: 6)
                    .matchedGeometryEffect(id: "thumb", in: thumbSpace, isSource: false)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: clicks)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.mode == .pullRequests ? "Pull request lists" : "Issue lists")
    }

    /// The tab's count: its matches while searching, else its list's count. An empty list shows none;
    /// a search shows its zeros, which say "no matches here".
    private func count(of tab: ShownTab) -> IssueTabCount? {
        if searching { return model.searchMatchCounts[SearchScope(tab)] }
        switch tab {
        case .pullRequests(let tab): return model.contents(of: tab).flatMap { $0.count == 0 ? nil : .current($0.count) }
        case .issues(let tab): return (model.issueTabs?.count(tab)).flatMap { $0 == .current(0) ? nil : $0 }
        }
    }

    private func isSelected(_ tab: ShownTab) -> Bool {
        searching ? model.shownSearchScope == SearchScope(tab) : model.shownTab == tab
    }

    /// None while a search covers everything.
    private var hasSelection: Bool {
        switch model.mode {
        case .pullRequests: model.prTabs.contains { isSelected(.pullRequests($0)) }
        case .issues: IssueTab.allCases.contains { isSelected(.issues($0)) }
        }
    }

    private func pick(_ tab: ShownTab) {
        clicks += 1
        if searching {
            model.pickSearchScope(tab)
            let scope = model.shownSearchScope
            let matches = model.searchResults.map { $0.orderedKeys(mode: model.mode).count }
            AccessibilityNotification.Announcement(
                SearchContext.scopeAnnouncement(tab: scope.isNarrowed ? tab.title : nil, matches: matches)
            ).post()
            return
        }
        willSelect()
        switch tab {
        case .pullRequests(let tab): model.selectedTab = tab
        case .issues(let tab): model.selectedIssueTab = tab
        }
    }

    /// Whether any count on screen reads three or more characters ("99+"), which needs the room.
    private var crowded: Bool {
        let counts: [IssueTabCount?] =
            switch model.mode {
            case .pullRequests: model.prTabs.map { count(of: .pullRequests($0)) }
            case .issues: IssueTab.allCases.map { count(of: .issues($0)) }
            }
        return counts.contains { count in
            switch count {
            case .current(let n), .stale(let n, _, _): TabCountText.header(n).count >= 3
            case .unavailable, nil: false
            }
        }
    }

    /// Nil before the first snapshot: no count at all.
    private func segment(
        _ tab: ShownTab, title: String, count: IssueTabCount?, selected: Bool, action: @escaping () -> Void
    ) -> some View {
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
                if let count {
                    countLabel(count, selected: selected)
                }
            }
            .lineLimit(1)
            .foregroundStyle(.primary)
            // SegmentRow sets the width, and with it the room on each side of the label.
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background {
                if selected {
                    Color.clear.matchedGeometryEffect(id: "thumb", in: thumbSpace, isSource: true)
                } else if hovered == tab {
                    RoundedRectangle(cornerRadius: 6).fill(Palette.fill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = tab
            } else if hovered == tab {
                hovered = nil
            }
        }
        .layoutValue(key: SegmentSelected.self, value: selected)
        .help(Self.help(tab, count: count))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel((count.map { "\(title), \(spoken($0))" } ?? title) + filteredSuffix)
    }

    /// The list counts ignore the repo focus; the label says the list doesn't, so the count isn't misread.
    /// Match counts follow the focus, as the results do.
    private var filteredSuffix: String {
        model.repoFocus.map { ", \(searching ? "in" : "filtered to") \(model.displayName(of: $0.repo))" } ?? ""
    }

    private func spoken(_ count: IssueTabCount) -> String {
        searching ? SearchContext.spokenMatches(count) : Self.spoken(count)
    }

    /// On the selected thumb the secondary color drops to about 3.3:1 in dark mode, so the count there is primary.
    @ViewBuilder private func countLabel(_ count: IssueTabCount, selected: Bool) -> some View {
        let color = selected ? Color.primary : Palette.secondaryText
        switch count {
        case .current(let n):
            Text(TabCountText.header(n))
                .font(.system(size: 11, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(color)
        case .stale(let n, _, _):
            // The shape says "didn't update", not just the color.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.amberGlyph)
                Text(TabCountText.header(n))
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        case .unavailable:
            Text("–")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(color)
        }
    }

    /// What the tab lists, then on a stale count why it didn't update.
    private static func help(_ tab: ShownTab, count: IssueTabCount?) -> String {
        [tab.summary, count.flatMap(staleHelp)].compactMap(\.self).joined(separator: "\n")
    }

    private static func staleHelp(_ count: IssueTabCount) -> String? {
        guard case .stale(_, let error, let since) = count else { return nil }
        guard let since else { return "Didn't update · \(error)" }
        return "Didn't update · last good \(RelativeAge.ago(since, now: Date()))"
    }

    /// The exact number, which "99+" hides.
    private static func spoken(_ count: IssueTabCount) -> String {
        switch count {
        case .current(let n): "\(n)"
        case .stale(let n, _, _): "\(n), didn't update"
        case .unavailable: "unavailable"
        }
    }
}

/// Whether a segment is the selected one, which draws a thumb around its label.
private struct SegmentSelected: LayoutValueKey {
    static let defaultValue = false
}

/// Lays segments out at equal widths when every label fits with `padding` on each side; otherwise each
/// gets its ideal width plus an equal share of what is left (or minus an equal share of the shortfall),
/// so a long label like "Assigned 55" takes room from the shorter ones instead of truncating. When even
/// that is too tight, only the selected segment keeps `padding` inside its thumb and the others make do
/// with `tightPadding`; tighter still, the padding is shared out before any label is cut.
private struct SegmentRow: Layout {
    var spacing: CGFloat
    /// Room between a label and the edge of the thumb.
    var padding: CGFloat = 8
    /// Room on each side of an unselected label when the row is tight; neighbors stay apart by twice
    /// this plus `spacing`.
    static let tightPadding: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = ideals.map(\.height).max() ?? 0
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let width = proposal.width ?? (ideals.map { $0.width + 2 * padding }.reduce(0, +) + gaps)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let available = bounds.width - spacing * CGFloat(subviews.count - 1)
        let labels = subviews.map { $0.sizeThatFits(.unspecified).width }
        let roomy = labels.map { $0 + 2 * padding }
        let tight = zip(labels, subviews).map { label, subview in
            label + 2 * (subview[SegmentSelected.self] ? padding : Self.tightPadding)
        }
        let ideals = [roomy, tight].first { $0.reduce(0, +) <= available } ?? labels
        let widths = Self.widths(ideals: ideals, available: available)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    /// Never adds up to more than `available` (unless it is negative): a segment the shortfall would
    /// take below zero gets zero, and the rest of the shortfall is shared by the segments still wider.
    static func widths(ideals: [CGFloat], available: CGFloat) -> [CGFloat] {
        let equal = available / CGFloat(ideals.count)
        if ideals.allSatisfy({ $0 <= equal }) { return ideals.map { _ in equal } }
        var sharing = Set(ideals.indices)
        while !sharing.isEmpty {
            let share = (available - sharing.map { ideals[$0] }.reduce(0, +)) / CGFloat(sharing.count)
            let squeezedOut = sharing.filter { ideals[$0] + share < 0 }
            if squeezedOut.isEmpty {
                return ideals.indices.map { sharing.contains($0) ? ideals[$0] + share : 0 }
            }
            sharing.subtract(squeezedOut)
        }
        return ideals.map { _ in 0 }
    }
}

extension PRTab {
    var title: String {
        switch self {
        case .review: "Review"
        case .mine: "Mine"
        case .team: "Team"
        }
    }
}

extension IssueTab {
    var title: String {
        switch self {
        case .assigned: "Assigned"
        case .created: "Created"
        case .board: "Board"
        }
    }
}

extension ShownTab {
    /// What the tab lists, for its tooltip; kept in step with the searches in `LiveSnapshotFetcher.fetch`
    /// and the rules in `TabBuilder` and `IssueTabBuilder`.
    var summary: String {
        switch self {
        case .pullRequests(.review): "PRs waiting for your review"
        case .pullRequests(.mine): "Your open PRs · closed last 7 days below"
        case .pullRequests(.team): "Open PRs by your teammates"
        case .issues(.assigned): "Issues assigned to you"
        case .issues(.created): "Issues you opened"
        case .issues(.board): "Everyone's issues on the board"
        }
    }
}

extension AppModel {
    /// The name of the tab the search is narrowed to; nil while it covers everything.
    var searchScopeTitle: String? {
        switch shownSearchScope {
        case .everything: nil
        case .pullRequests(let tab): tab.title
        case .issues(let tab): tab.title
        }
    }

    /// The name of the tab on screen in the current mode, for Back buttons.
    var selectedTabTitle: String {
        switch mode {
        case .pullRequests: selectedTab.title
        case .issues: selectedIssueTab.title
        }
    }
}
