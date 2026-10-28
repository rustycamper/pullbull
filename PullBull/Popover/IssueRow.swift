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
        .help(issue.title)
        .issueContextMenu(
            issue, focus: FocusMenuItem(model: model, repo: issue.key.repo),
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
                IssueMetaLine(issue: issue, now: now, showsRepo: !inRepoGroup)
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
        HStack(spacing: 8) {
            Image(symbol: glyph.symbol)
                .font(.system(size: 11))
                .foregroundStyle(glyph.color)
                .frame(width: 16)
                .accessibilityLabel(glyph.label)
            Text(issue.title)
                .font(.system(size: 12.5))
                .foregroundStyle(past ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                RepoNumber(key: issue.key, showsRepo: !inRepoGroup, compact: true)
                    .fixedSize()
                if let updatedAt = issue.updatedAt {
                    Text(RelativeAge.short(from: updatedAt, to: now))
                        .frame(width: 24, alignment: .trailing)
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            AssigneeStack(assignees: avatars, showUnassigned: tab == .board, size: 16)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }
}

/// repo #num · updated age · comment count · label chips. Chips that don't fit drop off the end into
/// "+N", so the repo, age and comments always show. Under a repo header the repo is left out.
struct IssueMetaLine: View {
    let issue: BoardIssue
    let now: Date
    var showsRepo = true
    var role: String?

    var body: some View {
        let chips = IssueRowRules.chips(issue.labels)
        ViewThatFits(in: .horizontal) {
            ForEach((0...chips.shown.count).reversed(), id: \.self) { fitting in
                line(chips: Array(chips.shown.prefix(fitting)), more: issue.labels.count - fitting)
                    // The last resort truncates instead of overflowing.
                    .fixedSize(horizontal: fitting > 0, vertical: false)
            }
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func line(chips: [String], more: Int) -> some View {
        HStack(spacing: 5) {
            RepoNumber(key: issue.key, showsRepo: showsRepo)
            if let updatedAt = issue.updatedAt {
                Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
                Text(RelativeAge.short(from: updatedAt, to: now))
            }
            if issue.commentCount > 0 {
                Label { Text("\(issue.commentCount)") } icon: { Image(systemName: "bubble.left") }
                    .labelStyle(TightLabelStyle(spacing: 3))
                    .padding(.leading, 2)
                    .accessibilityLabel(issue.commentCount == 1 ? "1 comment" : "\(issue.commentCount) comments")
            }
            if let role {
                Text("·").accessibilityHidden(true)
                Text(role)
            }
            // By position: two labels can share a name, and a cut chip names its label in full.
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                let name = issue.labels[index]
                let color = LabelDotColor.parse(issue.labelColor(at: index))
                if chip == name {
                    LabelChip(text: chip, color: color).accessibilityLabel(name)
                } else {
                    LabelChip(text: chip, color: color).help(name).accessibilityLabel(name)
                }
            }
            if more > 0 {
                LabelChip(text: "+\(more)")
                    .accessibilityLabel(more == 1 ? "1 more label" : "\(more) more labels")
            }
        }
    }
}

/// A muted outline label chip, led by a dot in the label's GitHub colour when it has one. The text stays gray.
private struct LabelChip: View {
    let text: String
    var color: UInt32?

    var body: some View {
        HStack(spacing: 4) {
            if let color { LabelDot(color: color) }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .frame(height: 16)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.separator, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
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
                    } else {
                        avatar
                    }
                }
            }
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(label)
        }
    }

    private var label: String {
        "Assigned to " + assignees.map(\.login).joined(separator: ", ")
    }
}
