import SwiftUI
import PullBullKit

/// A compact row on one 26pt line: leading glyph or avatar, title, badge glyphs, `repo #num`, age and a
/// trailing glyph or pill. The title truncates first; everything after it keeps its size. Tab rows and
/// search results share it, so compact mode looks the same everywhere.
struct CompactRowLayout<Leading: View, Title: View, Badges: View, Trailing: View>: View {
    let repoNumber: RepoNumber
    let age: String?
    /// The age's column, so short ages line up down a list; nil sizes it to fit (an ended item's "merged Oct 12").
    let ageWidth: CGFloat?
    let leading: Leading
    let title: Title
    let badges: Badges
    let trailing: Trailing

    init(
        repoNumber: RepoNumber, age: String?, ageWidth: CGFloat? = 24,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder title: () -> Title,
        @ViewBuilder badges: () -> Badges,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.repoNumber = repoNumber
        self.age = age
        self.ageWidth = ageWidth
        self.leading = leading()
        self.title = title()
        self.badges = badges()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            title
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            badges
            Group {
                repoNumber
                    .fixedSize()
                if let age {
                    if let ageWidth {
                        Text(age)
                            .frame(width: ageWidth, alignment: .trailing)
                    } else {
                        Text(age)
                            .fixedSize()
                    }
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }
}

/// A compact row's review glyphs, standing in for the meta line's capsule and info: changes requested,
/// ready to merge, a Review reason, then conflicts.
struct CompactChipGlyphs: View {
    let chips: RowChips
    /// Review rows only: why the review is asked for.
    var reason: RowChips.Info?

    var body: some View {
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
        if let reason {
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
    }
}
