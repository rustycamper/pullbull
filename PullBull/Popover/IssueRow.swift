import SwiftUI
import PullBullKit

/// One issue in an Issues list: the state glyph, the title and a meta line (repo #num · age · comments ·
/// label chips), with assignee avatars on the right. Compact rows fit on one line. A search result draws
/// as a row of the tab it is laid out for, with its marks.
struct IssueRow: View {
    let model: AppModel
    let issue: BoardIssue
    let tab: IssueTab
    let now: Date
    /// The keyboard highlight (↑/↓).
    var selected = false
    /// Under a repo header, which already names the repo.
    var inRepoGroup = false
    /// The labels a `~label` search asks for, passed in so a row doesn't follow every keystroke.
    var wantedLabels: [String] = []
    /// A search result's words and role; nil on a tab.
    var search: SearchMarks?
    @State private var hovering = false

    private var compact: Bool { model.settings.compact }
    private var glyph: (symbol: String, color: Color, label: String) { Palette.issueGlyph(issue.glyph) }
    /// A Board item in the folded Done group, or a closed search result.
    private var past: Bool { tab == .board && IssueTabBuilder.isDone(issue) || search != nil && !issue.isOpen }
    private var me: String { model.snapshot?.org.viewer ?? model.settings.account ?? "" }
    private var avatars: [Assignee] { IssueRowRules.avatars(issue, tab: tab, me: me) }

    var body: some View {
        Button {
            open()
        } label: {
            Group {
                if compact { compactBody } else { fullBody }
            }
            .contentShape(Rectangle())
            .modifier(RowFill(
                cornerRadius: compact ? 6 : 7, selected: selected, hovering: hovering,
                flashing: model.rowFlash.key == issue.key))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .editPickerAnchor(for: issue.key, field: nil, model: model)
        .issueContextMenu(
            issue, focus: FocusMenuItem(model: model, repo: issue.key.repo),
            time: search == nil ? TimeFocusMenu(model: model) : nil,
            person: .person(model: model, login: issue.author),
            status: StatusMenu.make(model: model, key: issue.key),
            sets: SetEditMenu.make(model: model, key: issue.key))
    }

    /// A search result moves `searchSelection`, a tab row `listSelection`.
    private func open() {
        if search != nil {
            if PRActions.commandClicked { model.openSearchResultOnGitHub(issue) } else { model.openSearchResult(issue) }
        } else {
            model.listSelection = issue.key
            if PRActions.commandClicked { PRActions.openOnGitHub(issue) } else { model.openRowIssueDetail(issue.key) }
        }
    }

    /// The title, a search's words in bold.
    private var title: AttributedString {
        guard let search else { return AttributedString(issue.title) }
        return Highlight.title(issue.title, words: search.words)
    }

    // MARK: Full

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(symbol: glyph.symbol)
                .font(.system(size: 13))
                .foregroundStyle(glyph.color)
                .frame(width: 20, height: 20)
                .accessibilityLabel(glyph.label)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13))
                    .lineSpacing(1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(past ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    // On the title alone: a row-wide tip would cover the chips' and glyphs' own.
                    .help(issue.title)
                IssueMetaLine(
                    issue: issue, now: now, showsRepo: !inRepoGroup, role: search?.role, wantedLabels: wantedLabels)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AssigneeStack(assignees: avatars, showUnassigned: tab == .board, size: 18)
                .padding(.top, 1)
            if !issue.isOpen {
                // Ended items carry their pill, as a closed PR row does.
                IssueEndedPill(glyph: issue.glyph)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    // MARK: Compact

    private var compactBody: some View {
        CompactRowLayout(
            repoNumber: RepoNumber(key: issue.key, showsRepo: !inRepoGroup, compact: true),
            age: IssueMetaLine.age(of: issue, now: now), ageWidth: issue.isOpen ? 24 : nil,
            ageHelp: IssueMetaLine.ageHelp(of: issue, now: now)
        ) {
            Image(symbol: glyph.symbol)
                .font(.system(size: 11))
                .foregroundStyle(glyph.color)
                .frame(width: 16)
                .accessibilityLabel(glyph.label)
        } title: {
            Text(title)
                .foregroundStyle(past ? .secondary : .primary)
                // On the title alone: a row-wide tip would cover the chips' and glyphs' own.
                .help(issue.title)
        } badges: {
            EmptyView()
        } trailing: {
            AssigneeStack(assignees: avatars, showUnassigned: tab == .board, size: 16)
            if !issue.isOpen { IssueEndedPill(glyph: issue.glyph) }
        }
    }
}

/// repo #num · updated age · comment count · label chips. Chips that don't fit drop off the end into
/// "+N", so the repo, age and comments always show. Under a repo header the repo is left out.
struct IssueMetaLine: View {
    let issue: BoardIssue
    let now: Date
    var showsRepo = true
    var role: String?
    /// The labels a `~label` search asks for, whose chips lead.
    var wantedLabels: [String] = []

    var body: some View {
        let chips = LabelChipSet(issue, first: wantedLabels)
        ChipsThatFit(set: chips) { fitting in
            line(chips: chips, fitting: fitting)
        }
        .metaLineStyle()
    }

    private var age: String? { Self.age(of: issue, now: now) }

    /// "closed 3d ago" for a closed issue, or just "closed" without a date, as a closed PR row says;
    /// otherwise the time since its last update.
    static func age(of issue: BoardIssue, now: Date) -> String? {
        if !issue.isOpen { return EndedAge.text(state: .closed, closedAt: issue.closedAt, now: now) ?? "closed" }
        return issue.updatedAt.map { RelativeAge.short(from: $0, to: now) }
    }

    /// What an open issue's age measures, as on a PR row; a closed issue's age already says "closed".
    static func ageHelp(of issue: BoardIssue, now: Date) -> String? {
        guard issue.isOpen, let updated = issue.updatedAt else { return nil }
        return "Updated \(RelativeAge.ago(updated, now: now))"
    }

    private func line(chips: LabelChipSet, fitting: ChipFit) -> some View {
        HStack(spacing: 5) {
            RepoNumber(key: issue.key, showsRepo: showsRepo)
            if let age {
                MetaDot()
                Text(age)
                    .ageHelp(Self.ageHelp(of: issue, now: now))
            }
            if issue.commentCount > 0 {
                CommentCount(count: issue.commentCount)
                    .padding(.leading, 2)
            }
            if let role {
                MetaDot()
                Text(role)
            }
            LabelChips(set: chips, fit: fitting)
        }
    }
}

/// Overlapping assignee avatars, at most three. With `showUnassigned`, an issue with no assignees
/// shows a dashed circle. A change of assignees fades and scales the avatars in and out.
private struct AssigneeStack: View {
    let assignees: [Assignee]
    let showUnassigned: Bool
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxShown = 3
    private static let overlap: CGFloat = 5
    private static let change: AnyTransition = .scale(scale: 0.6).combined(with: .opacity)

    var body: some View {
        ZStack(alignment: .trailing) {
            if assignees.isEmpty {
                if showUnassigned {
                    Circle()
                        .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: size, height: size)
                        .help("Unassigned")
                        .accessibilityElement()
                        .accessibilityLabel("Unassigned")
                        .transition(Self.change)
                }
            } else {
                let shown = Array(assignees.prefix(Self.maxShown))
                HStack(spacing: -Self.overlap) {
                    ForEach(Array(shown.enumerated()), id: \.element.login) { index, assignee in
                        let avatar = AvatarView(login: assignee.login, url: assignee.avatarURL, size: size)
                        Group {
                            if index < shown.count - 1 {
                                // A gap the avatar on top of this one is cut out of, so the stack needs no ring color.
                                avatar.mask {
                                    Circle()
                                        .overlay {
                                            Circle()
                                                .padding(-1.5)
                                                .offset(x: size - Self.overlap)
                                                .blendMode(.destinationOut)
                                        }
                                        .compositingGroup()
                                }
                            } else {
                                avatar
                            }
                        }
                        .help(assignee.login)
                        .transition(Self.change)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(label)
                .transition(Self.change)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: assignees.prefix(Self.maxShown).map(\.login))
    }

    private var label: String {
        "Assigned to " + assignees.map(\.login).joined(separator: ", ")
    }
}
