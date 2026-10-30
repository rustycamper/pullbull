import AppKit
import SwiftUI
import PullBullKit

/// What a search result's row adds to the tab's: the query's words, in bold in the title, and the first
/// `@` name's role on the item, as the meta line's suffix.
struct SearchMarks {
    let words: [String]
    let role: String?
}

/// Where a PR row sits: on a tab, whose rules give its review state, or in the search results laid out
/// as that tab lays out its list.
enum RowContext {
    case tab(PRTab)
    case search(PRTab, SearchMarks)
}

/// One PR in a list. Review and Team rows lead with the author's avatar, Mine rows with a state glyph.
/// Review state sits in the meta line (`RowChips`). Compact rows fit on one line. A search result draws
/// as a row of the tab it is laid out for, with its marks.
struct PRRow: View {
    let model: AppModel
    let row: Row
    let context: RowContext
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
            open()
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
            time: marks == nil ? TimeFocusMenu(model: model) : nil, person: .person(model: model, login: pr.author),
            files: model.filesLink(for: pr), failingCheck: { model.openFailingCheck(pr.key) })
    }

    /// A search result moves `searchSelection`, a tab row `listSelection`.
    private func open() {
        switch context {
        case .tab:
            model.listSelection = pr.key
            if PRActions.commandClicked { PRActions.openOnGitHub(pr) } else { model.openRowDetail(pr.key) }
        case .search:
            if PRActions.commandClicked { model.openSearchResultOnGitHub(pr) } else { model.openSearchResult(pr) }
        }
    }

    /// The tab whose rules draw the row: its own, or the one the search results are laid out for.
    var layoutTab: PRTab {
        switch context {
        case .tab(let tab), .search(let tab, _): tab
        }
    }

    /// A search result's words and role; nil on a tab.
    var marks: SearchMarks? {
        if case .search(_, let marks) = context { marks } else { nil }
    }

    /// The tab whose chips the row shows, and whether it names the author (`SearchLayout.chipTab`).
    private var chipTab: PRTab {
        guard marks != nil else { return layoutTab }
        let viewer = model.snapshot?.org.viewer ?? model.settings.account ?? ""
        return SearchLayout.chipTab(for: pr, on: layoutTab, viewer: viewer)
    }

    // MARK: Full

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
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
            trailing
                .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var leading: some View {
        switch layoutTab {
        case .mine:
            Image(symbol: Palette.prGlyph(pr.glyph))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityLabel(pr.isDraft ? "Draft" : "Open")
                .padding(.top, 1)
        case .review, .team:
            AvatarView(login: pr.author, url: pr.authorAvatarURL, size: 20)
                .opacity(row.dimmed ? 0.45 : 1)
                .help(pr.author)
                .padding(.top, 1)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch pr.state {
        case .merged: EndedPill(merged: true)
        case .closed: EndedPill(merged: false)
        case .open: CIGlyph(state: pr.ci)
        }
    }

    /// The title, a search's words in bold.
    private var title: AttributedString {
        guard let marks else { return AttributedString(pr.title) }
        return Highlight.title(pr.title, words: marks.words)
    }

    private var titleStyle: AnyShapeStyle {
        if row.dimmed || pr.isDraft || pr.state != .open { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }

    /// Review state in two tiers: a capsule only when the PR needs acting on, glyph-and-text otherwise.
    private var chips: RowChips { RowChips(row: row, tab: chipTab) }

    /// `repo #num`, or `#num` under a repo header or the focus. A search result outside the focus (a link)
    /// names its repo.
    private var showsRepo: Bool {
        guard marks != nil else { return model.rowsShowRepo(on: layoutTab) }
        return SearchLayout.showsRepo(
            pr.key, underRepoHeader: model.prGrouping(for: layoutTab) == .repository, focus: model.repoFocus)
    }

    /// The relative age, or an ended PR's "merged Oct 12".
    private var age: String {
        EndedAge.text(state: pr.state, closedAt: pr.closedAt, now: now)
            ?? RelativeAge.short(from: pr.updatedAt, to: now)
    }

    /// One line at a fixed height, so a row is as tall with a capsule as without one. Under pressure the
    /// label chips drop off the end into "+N" first, then (on Review and Team) the author goes (its avatar
    /// names it on hover), then the first chip shortens, then the repo name gives way, then the text info;
    /// the age and counts never truncate.
    private var meta: some View {
        let chips = chips
        let labels = LabelChipSet(pr, first: wantedLabels)
        return ChipsThatFit(set: labels, canLean: chipTab != .mine) { fitting in
            metaLine(chips: chips, labels: labels, fitting: fitting)
        }
        .metaLineStyle()
        .frame(height: 16)
    }

    private func metaLine(chips: RowChips, labels: LabelChipSet, fitting: ChipFit) -> some View {
        HStack(spacing: 5) {
            if pr.isDraft { DraftPill().fixedSize() }
            RepoNumber(key: pr.key, showsRepo: showsRepo)
                .layoutPriority(-1)
            MetaDot()
            if chipTab != .mine && !fitting.lean {
                Text(pr.author)
                MetaDot()
            }
            Text(age)
                .fixedSize()
                // The avatar, which names a left-out author on hover, is hidden from VoiceOver.
                .accessibilityLabel(fitting.lean ? "\(pr.author), \(age)" : age)
            if let role = marks?.role {
                MetaDot()
                Text(role)
            }
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
            if layoutTab == .review, let size = DiffSize.text(additions: pr.additions, deletions: pr.deletions) {
                Text(size)
                    .fixedSize()
                    .padding(.leading, 4)
                    .accessibilityLabel(
                        DiffSize.spoken(additions: pr.additions, deletions: pr.deletions) ?? size)
            }
            LabelChips(set: labels, fit: fitting)
        }
    }

    // MARK: Compact

    private var compactBody: some View {
        CompactRowLayout(
            repoNumber: RepoNumber(key: pr.key, showsRepo: showsRepo, compact: true),
            age: age, ageWidth: pr.state == .open ? 24 : nil
        ) {
            switch layoutTab {
            case .mine:
                Image(symbol: Palette.prGlyph(pr.glyph))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityLabel(pr.isDraft ? "Draft" : "Open")
            case .review, .team:
                AvatarView(login: pr.author, url: pr.authorAvatarURL, size: 16)
                    .opacity(row.dimmed ? 0.45 : 1)
                    .help(pr.author)
            }
        } title: {
            Text(pr.isDraft ? AttributedString("Draft: ") + title : title)
                .foregroundStyle(titleStyle)
                .help(pr.title)
        } badges: {
            let chips = chips
            CompactChipGlyphs(
                chips: chips,
                reason: layoutTab == .review && !row.dimmed ? chips.info.first(where: { $0 != .conflicts }) : nil)
        } trailing: {
            if pr.state == .open { CIGlyph(state: pr.ci) }
        }
    }
}

/// A Mine-tab PR that merged or closed in the last 7 days, or a merged or closed search result.
struct ClosedRow: View {
    let model: AppModel
    let pr: PullRequest
    let now: Date
    /// The keyboard highlight (↑/↓).
    var selected = false
    /// A search result's words and role; nil on Mine.
    var search: SearchMarks?
    @State private var hovering = false

    var body: some View {
        let merged = pr.state == .merged
        Button {
            open()
        } label: {
            HStack(spacing: 10) {
                Image(symbol: Palette.prGlyph(pr.glyph))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.prGlyphColor(pr.glyph))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        RepoNumber(key: pr.key)
                        MetaDot()
                        Text(ended(merged: merged)).fixedSize()
                        if let role = search?.role {
                            MetaDot()
                            Text(role)
                        }
                    }
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
            time: search == nil ? TimeFocusMenu(model: model) : nil,
            person: .person(model: model, login: pr.author), files: model.filesLink(for: pr),
            failingCheck: { model.openFailingCheck(pr.key) })
    }

    /// A search result moves `searchSelection`, a Mine row `listSelection`.
    private func open() {
        if search != nil {
            if PRActions.commandClicked { model.openSearchResultOnGitHub(pr) } else { model.openSearchResult(pr) }
        } else {
            model.listSelection = pr.key
            if PRActions.commandClicked { PRActions.openOnGitHub(pr) } else { model.openRowDetail(pr.key) }
        }
    }

    /// The title, a search's words in bold.
    private var title: AttributedString {
        guard let search else { return AttributedString(pr.title) }
        return Highlight.title(pr.title, words: search.words)
    }

    private func ended(merged: Bool) -> String {
        EndedAge.text(state: pr.state, closedAt: pr.closedAt, now: now) ?? (merged ? "merged" : "closed")
    }
}

// MARK: - Pieces

struct CIGlyph: View {
    let state: CIState

    var body: some View {
        let glyph = Palette.ciGlyph(state)
        Image(systemName: glyph.symbol)
            .font(.system(size: 13))
            .foregroundStyle(glyph.color)
            .frame(width: 16, height: 16)
            .help(Palette.ciLabel(state))
            .accessibilityLabel(Palette.ciLabel(state))
    }
}

/// A row's `repo #num` in the meta style, or `#num` where a repo header already names the repo. A long
/// repo name truncates; the number never does, and stands out in medium weight.
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
                .fontWeight(.medium)
                .fixedSize()
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
