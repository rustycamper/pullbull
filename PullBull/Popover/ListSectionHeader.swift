import SwiftUI
import PullBullKit

/// A list section's header, the same in every list: repo groups, lanes, Done, "Recently closed" and the
/// search groups. The glyph sits in the rows' icon column, so header and row glyphs share one axis and the
/// title starts on the row titles' edge; an author group shows an avatar there instead. A header that
/// folds toggles as a whole, its chevron hanging in the leading inset, left of the icon column, so every
/// fold's chevron sits on one line and every title on another.
struct ListSectionHeader: View {
    let glyph: String?
    var glyphColor: Color = .secondary
    let title: String
    /// Nil for headers that show no count.
    var count: Int? = nil
    /// Quiet text after the count, as in "Done 4 · last 14 days".
    var note: String? = nil
    /// Quiet text at the trailing edge, as in "Recently closed"'s "Last 7 days"; not read out.
    var trailing: String? = nil
    /// Why the rows are a kept list that didn't update: a warning glyph after the count, this text as the
    /// header's tooltip.
    var warning: String? = nil
    /// Nil for headers that don't fold.
    var fold: Fold? = nil
    /// A person's avatar in the glyph's place, as an author group's header shows.
    var avatar: Avatar? = nil
    /// The rows' icon column: compact rows have a narrower one.
    var compact = false

    struct Avatar {
        let login: String
        let url: URL?
    }

    struct Fold {
        let isOpen: Bool
        let toggle: () -> Void
    }

    /// Every header's height, so a list's headers line up whatever they show; `PinnedHeader.clearance`
    /// covers it.
    nonisolated static let height: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let warning {
            content.help(warning)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if let fold {
            Button(action: fold.toggle) {
                label
                    .overlay(alignment: .leading) {
                        chevron(fold).frame(width: 8)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(fold.isOpen ? "expanded" : "collapsed")
            .accessibilityAddTraits(.isHeader)
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityTitle)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var accessibilityTitle: String {
        ([title] + [count.map(String.init), note, warning.map { _ in "didn't update" }].compactMap { $0 })
            .joined(separator: ", ")
    }

    private func chevron(_ fold: Fold) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(fold.isOpen ? 90 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: fold.isOpen)
    }

    /// At 11pt the SF circle matches the 13pt row glyph's diameter.
    private var label: some View {
        HStack(spacing: compact ? 8 : 10) {
            if let avatar {
                AvatarView(login: avatar.login, url: avatar.url, size: compact ? 14 : 16)
                    .frame(width: compact ? 16 : 20)
            } else if let glyph {
                Image(symbol: glyph)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(glyphColor)
                    .frame(width: compact ? 16 : 20)
            }
            HStack(spacing: 6) {
                // The title in the label colour stands apart from the rows' grey meta lines; the count, note
                // and trailing text stay quiet.
                Text(title)
                    .foregroundStyle(Color.primary)
                if let count {
                    Text("\(count)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                if let note {
                    Text("· \(note)")
                        .fontWeight(.regular)
                }
                if warning != nil {
                    // The shape says "didn't update", not just the color.
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.amberGlyph)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .fontWeight(.regular)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PRSection {
    /// The glyph in the section header's icon column.
    var glyph: String {
        switch self {
        case .needsReview: "bell"
        case .yourPRs: "pullbull.pullrequest"
        case .waiting: "clock"
        case .recentlyClosed: "archivebox"
        case .team: "person.2"
        case .otherResults: "magnifyingglass"
        }
    }

    var glyphColor: Color { self == .needsReview ? .accentColor : .secondary }
}

extension IssueSection {
    /// The glyph in the section header's icon column.
    var glyph: String {
        switch self {
        case .assignedToYou: "person.crop.circle"
        case .youOpened: "square.and.pencil"
        case .doneStillOpen: "checkmark.circle"
        case .restOfBoard: "rectangle.split.3x1"
        case .otherResults: "magnifyingglass"
        }
    }
}
