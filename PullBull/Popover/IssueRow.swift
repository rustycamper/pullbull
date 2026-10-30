import SwiftUI
import PullBullKit

/// One issue in an Issues list: the state glyph, the title and a meta line (repo #num · age · comments ·
/// label chips), with assignee avatars on the right. Compact rows fit on one line.
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
    @State private var hovering = false

    private var compact: Bool { model.settings.compact }
    private var glyph: (symbol: String, color: Color, label: String) { Palette.issueGlyph(issue.glyph) }
    /// A Board item in the folded Done group.
    private var past: Bool { tab == .board && IssueTabBuilder.isDone(issue) }
    private var me: String { model.snapshot?.org.viewer ?? model.settings.account ?? "" }
    private var avatars: [Assignee] { IssueRowRules.avatars(issue, tab: tab, me: me) }

    var body: some View {
        Button {
            model.listSelection = issue.key
            if PRActions.commandClicked { PRActions.openOnGitHub(issue) } else { model.openRowIssueDetail(issue.key) }
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
        .issueContextMenu(
            issue, focus: FocusMenuItem(model: model, repo: issue.key.repo), time: TimeFocusMenu(model: model),
            person: .person(model: model, login: issue.author))
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
                Text(issue.title)
                    .font(.system(size: 13))
                    .lineSpacing(1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(past ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    // On the title alone: a row-wide tip would cover the chips' and glyphs' own.
                    .help(issue.title)
                IssueMetaLine(issue: issue, now: now, showsRepo: !inRepoGroup, wantedLabels: wantedLabels)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AssigneeStack(assignees: avatars, showUnassigned: tab == .board, size: 18)
                .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    // MARK: Compact

    private var compactBody: some View {
        CompactRowLayout(
            repoNumber: RepoNumber(key: issue.key, showsRepo: !inRepoGroup, compact: true),
            age: IssueMetaLine.age(of: issue, now: now), ageWidth: issue.isOpen ? 24 : nil
        ) {
            Image(symbol: glyph.symbol)
                .font(.system(size: 11))
                .foregroundStyle(glyph.color)
                .frame(width: 16)
                .accessibilityLabel(glyph.label)
        } title: {
            Text(issue.title)
                .foregroundStyle(past ? .secondary : .primary)
                // On the title alone: a row-wide tip would cover the chips' and glyphs' own.
                .help(issue.title)
        } badges: {
            EmptyView()
        } trailing: {
            AssigneeStack(assignees: avatars, showUnassigned: tab == .board, size: 16)
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

    /// "closed 3d ago" for a closed issue; otherwise the time since its last update.
    static func age(of issue: BoardIssue, now: Date) -> String? {
        if !issue.isOpen, let ended = EndedAge.text(state: .closed, closedAt: issue.closedAt, now: now) {
            return ended
        }
        return issue.updatedAt.map { RelativeAge.short(from: $0, to: now) }
    }

    private func line(chips: LabelChipSet, fitting: ChipFit) -> some View {
        HStack(spacing: 5) {
            RepoNumber(key: issue.key, showsRepo: showsRepo)
            if let age {
                MetaDot()
                Text(age)
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
/// shows a dashed circle.
private struct AssigneeStack: View {
    let assignees: [Assignee]
    let showUnassigned: Bool
    let size: CGFloat

    private static let maxShown = 3
    private static let overlap: CGFloat = 5

    var body: some View {
        if assignees.isEmpty {
            if showUnassigned {
                Circle()
                    .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: size, height: size)
                    .help("Unassigned")
                    .accessibilityElement()
                    .accessibilityLabel("Unassigned")
            }
        } else {
            let shown = Array(assignees.prefix(Self.maxShown))
            HStack(spacing: -Self.overlap) {
                ForEach(Array(shown.enumerated()), id: \.element.login) { index, assignee in
                    let avatar = AvatarView(login: assignee.login, url: assignee.avatarURL, size: size)
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
                        .help(assignee.login)
                    } else {
                        avatar.help(assignee.login)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
        }
    }

    private var label: String {
        "Assigned to " + assignees.map(\.login).joined(separator: ", ")
    }
}
