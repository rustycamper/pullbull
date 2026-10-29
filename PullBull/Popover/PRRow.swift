import AppKit
import SwiftUI
import PullBullKit

/// One PR in a list. Review and Team rows lead with the author's avatar; Mine rows lead with a state
/// glyph. Review state sits in the meta line (`RowChips`). Compact rows fit on one line.
struct PRRow: View {
    let model: AppModel
    let row: Row
    let tab: PRTab
    let compact: Bool
    let now: Date
    /// The keyboard highlight (↑/↓).
    var selected = false
    /// The labels a `~label` search asks for, passed in so a row doesn't follow every keystroke.
    var wantedLabels: [String] = []
    @State private var hovering = false

    private var pr: PullRequest { row.pr }

    var body: some View {
        Button {
            model.listSelection = pr.key
            if PRActions.commandClicked { PRActions.openOnGitHub(pr) } else { model.openRowDetail(pr.key) }
        } label: {
            Group {
                if compact { compactBody } else { fullBody }
            }
            .contentShape(Rectangle())
            .modifier(RowFill(
                cornerRadius: compact ? 6 : 7, selected: selected, hovering: hovering,
                flashing: model.rowFlash.key == pr.key))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .prContextMenu(
            pr, focus: FocusMenuItem(model: model, repo: pr.key.repo),
            person: .person(model: model, login: pr.author))
    }

    // MARK: Full

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 10) {
            leading
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(pr.title)
                    .font(.system(size: 13))
                    .lineSpacing(1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(titleStyle)
                    .fixedSize(horizontal: false, vertical: true)
                    // On the title alone: a row-wide tip would cover the avatar's, chips' and glyphs' own.
                    .help(pr.title)
                meta
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CIGlyph(state: pr.ci, muted: tab == .team)
                .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var leading: some View {
        if tab == .mine {
            Image(symbol: Palette.prGlyph(pr.glyph))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityLabel(pr.isDraft ? "Draft" : "Open")
        } else {
            AvatarView(login: pr.author, url: pr.authorAvatarURL, size: 20)
                .opacity(row.dimmed ? 0.45 : 1)
                .help(pr.author)
        }
    }

    private var titleStyle: AnyShapeStyle {
        if row.dimmed { return AnyShapeStyle(.secondary) }
        if pr.isDraft { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    /// Review state in two tiers: a capsule only when the PR needs acting on, glyph-and-text otherwise.
    private var chips: RowChips { RowChips(row: row, tab: tab) }

    /// One line at a fixed height, so a row is as tall with a capsule as without one. Under pressure the
    /// label chips drop off the end into "+N" first, then the author goes (its avatar names it on hover),
    /// then the first chip shortens, then the repo name gives way, then the text info; the age and counts
    /// never truncate.
    private var meta: some View {
        let chips = chips
        let labels = LabelChipSet(pr, first: wantedLabels)
        return ChipsThatFit(set: labels, canLean: tab != .mine) { fitting in
            metaLine(chips: chips, labels: labels, fitting: fitting)
        }
        .metaLineStyle()
        .frame(height: 16)
    }

    private func metaLine(chips: RowChips, labels: LabelChipSet, fitting: ChipFit) -> some View {
        HStack(spacing: 5) {
            if pr.isDraft { DraftPill().fixedSize() }
            identifier
                .layoutPriority(-1)
            MetaDot()
            if tab != .mine && !fitting.lean {
                Text(pr.author)
                MetaDot()
            }
            let age = RelativeAge.short(from: pr.updatedAt, to: now)
            Text(age)
                .fixedSize()
                // The avatar, which names a left-out author on hover, is hidden from VoiceOver.
                .accessibilityLabel(fitting.lean ? "\(pr.author), \(age)" : age)
            ForEach(chips.info.filter { !$0.isCount }, id: \.text) { info in
                MetaDot()
                MetaInfo(info: info)
            }
            ForEach(chips.info.filter(\.isCount), id: \.text) { info in
                Label { Text(info.text) } icon: { Image(systemName: info.symbol) }
                    .labelStyle(TightLabelStyle(spacing: 2))
                    .fixedSize()
                    .padding(.leading, 4)
                    .help(info.label)
                    .accessibilityLabel(info.label)
            }
            if pr.commentCount > 0 {
                CommentCount(count: pr.commentCount)
                    .padding(.leading, 4)
            }
            if let action = chips.action {
                ActionCapsule(action: action)
                    .padding(.leading, 4)
            }
            LabelChips(set: labels, fit: fitting)
        }
    }

    /// `repo #num`, or `#num` under a repo header.
    private var identifier: some View {
        RepoNumber(key: pr.key, showsRepo: model.rowsShowRepo)
    }

    // MARK: Compact

    private var compactBody: some View {
        HStack(spacing: 8) {
            if tab == .mine {
                Image(symbol: Palette.prGlyph(pr.glyph))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            } else {
                AvatarView(login: pr.author, url: pr.authorAvatarURL, size: 16)
                    .opacity(row.dimmed ? 0.45 : 1)
                    .help(pr.author)
            }
            Text((pr.isDraft ? "Draft: " : "") + pr.title)
                .font(.system(size: 12.5))
                .foregroundStyle(titleStyle)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(pr.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if case .changesRequested = chips.action {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.changesRequested)
                    .accessibilityLabel("Changes requested")
            }
            if chips.action == .readyToMerge {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .help("Ready to merge")
                    .accessibilityLabel("Ready to merge")
            }
            if tab == .review && !row.dimmed, let reason = chips.info.first {
                Image(systemName: reason.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(reason.label)
                    .accessibilityLabel(reason.label)
            }
            if chips.info.contains(.conflicts) {
                Image(systemName: RowChips.Info.conflicts.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.amberGlyph)
                    .help(RowChips.Info.conflicts.label)
                    .accessibilityLabel(RowChips.Info.conflicts.label)
            }
            Group {
                RepoNumber(key: pr.key, showsRepo: model.rowsShowRepo, compact: true)
                    .fixedSize()
                Text(RelativeAge.short(from: pr.updatedAt, to: now))
                    .frame(width: 24, alignment: .trailing)
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            CIGlyph(state: pr.ci, muted: tab == .team)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }
}

/// A Mine-tab PR that merged or closed in the last 7 days.
struct ClosedRow: View {
    let model: AppModel
    let pr: PullRequest
    let now: Date
    /// The keyboard highlight (↑/↓).
    var selected = false
    @State private var hovering = false

    var body: some View {
        let merged = pr.state == .merged
        Button {
            model.listSelection = pr.key
            if PRActions.commandClicked { PRActions.openOnGitHub(pr) } else { model.openRowDetail(pr.key) }
        } label: {
            HStack(spacing: 10) {
                Image(symbol: Palette.prGlyph(pr.glyph))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.prGlyphColor(pr.glyph))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(meta(merged: merged))
                        .metaLineStyle()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                EndedPill(merged: merged)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .modifier(RowFill(
                cornerRadius: 7, selected: selected, hovering: hovering, flashing: model.rowFlash.key == pr.key))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(pr.title)
        .prContextMenu(
            pr, focus: FocusMenuItem(model: model, repo: pr.key.repo),
            person: .person(model: model, login: pr.author))
    }

    private func meta(merged: Bool) -> String {
        let repo = pr.key.repo.split(separator: "/").last.map(String.init) ?? pr.key.repo
        let ended = EndedAge.text(state: pr.state, closedAt: pr.closedAt, now: now) ?? (merged ? "merged" : "closed")
        return "\(repo) #\(pr.key.number) · \(ended)"
    }
}

// MARK: - Pieces

struct CIGlyph: View {
    let state: CIState
    /// Someone else's PR: a failure is shown in gray, as it isn't the viewer's to act on.
    var muted = false

    var body: some View {
        let glyph = Palette.ciGlyph(state, muted: muted)
        Image(systemName: glyph.symbol)
            .font(.system(size: 13))
            .foregroundStyle(glyph.color)
            .frame(width: 16, height: 16)
            .help(Palette.ciLabel(state))
            .accessibilityLabel(Palette.ciLabel(state))
    }
}

/// A row's `repo #num` in the meta style, or `#num` where a repo header already names the repo. A long
/// repo name truncates before the number does.
struct RepoNumber: View {
    let key: PRKey
    var showsRepo = true
    /// Compact rows size this to fit (`fixedSize`); the cap keeps a long repo from crowding out the title.
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if showsRepo {
                Text(key.repo.split(separator: "/").last.map(String.init) ?? key.repo)
                    .lineLimit(1)
                    .frame(maxWidth: compact ? 110 : nil)
                    .layoutPriority(-1)
            }
            Text("#\(String(key.number))")
        }
    }
}

/// The tertiary "·" between meta-line items, which VoiceOver skips.
struct MetaDot: View {
    var body: some View {
        Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
    }
}

/// A meta line's comment count: a speech bubble and the number, which never truncates.
struct CommentCount: View {
    let count: Int

    var body: some View {
        Label { Text("\(count)") } icon: { Image(systemName: "bubble.left") }
            .labelStyle(TightLabelStyle(spacing: 3))
            .fixedSize()
            .accessibilityLabel(count == 1 ? "1 comment" : "\(count) comments")
    }
}

/// A `RowChips.Info` that follows the age after a `·`: glyph and text, the glyph amber for a warning.
struct MetaInfo: View {
    let info: RowChips.Info

    var body: some View {
        Label { Text(info.text) } icon: {
            Image(systemName: info.symbol)
                .foregroundStyle(info.isWarning ? AnyShapeStyle(Palette.amberGlyph) : AnyShapeStyle(.secondary))
        }
            .labelStyle(TightLabelStyle(spacing: 3))
            .help(info.label)
            .accessibilityLabel(info.label)
    }
}

/// A full PR row's tier-1 capsule (`RowChips.Action`): the one thing on the row that asks for action.
struct ActionCapsule: View {
    let action: RowChips.Action

    var body: some View {
        switch action {
        case .readyToMerge:
            ReadyToMergePill()
                .fixedSize()
        case .changesRequested(let by):
            Pill(
                symbol: "arrow.uturn.backward",
                text: "Changes requested · \(by.joined(separator: ", "))",
                foreground: Palette.changesRequested, fill: Palette.changesRequested.opacity(0.12))
        }
    }
}

extension View {
    /// The type of a row's meta line: 11pt, monospaced digits, secondary, one line.
    func metaLineStyle() -> some View {
        font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct Pill: View {
    let symbol: String?
    let text: String
    let foreground: Color
    let fill: Color
    /// Tints the glyph alone; the text keeps `foreground`.
    var symbolColor: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(symbol: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(symbolColor ?? foreground)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(Capsule().fill(fill))
    }
}

/// Mine's single pill once a PR is approved, green and has no change requests: gray, like the review
/// pills it replaces.
struct ReadyToMergePill: View {
    var fill = Palette.fill

    var body: some View {
        Pill(symbol: "arrow.triangle.merge", text: "Ready to merge", foreground: Palette.secondaryText, fill: fill)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ready to merge")
    }
}

/// The "Merged" or "Closed" pill of an item that has ended.
struct EndedPill: View {
    let merged: Bool

    var body: some View {
        if merged {
            Pill(symbol: nil, text: "Merged", foreground: Palette.mergedText, fill: Palette.mergedFill)
        } else {
            Pill(symbol: nil, text: "Closed", foreground: Palette.closedText, fill: Palette.closedFill)
        }
    }
}

struct DraftPill: View {
    var body: some View {
        Text("Draft")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 0.5))
    }
}

struct TightLabelStyle: LabelStyle {
    let spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon.font(.system(size: 9.5))
            configuration.title
        }
    }
}

struct AvatarView: View {
    let login: String
    let url: URL?
    let size: CGFloat
    @State private var image: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(login: String, url: URL?, size: CGFloat) {
        self.login = login
        self.url = url
        self.size = size
        // An image already in memory draws on the first frame, with no placeholder before it.
        _image = State(initialValue: url.flatMap(AvatarCache.shared.cachedImage(for:)))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Palette.strongFill
                Text(login.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return }
            if let cached = AvatarCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            // Read from disk or fetched: fades in, or swaps at once under Reduce Motion.
            let loaded = await AvatarCache.shared.image(for: url)
            withAnimation(loaded == nil || reduceMotion ? nil : .easeOut(duration: 0.15)) { image = loaded }
        }
    }
}
