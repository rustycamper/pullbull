import SwiftUI

/// A list section's header, the same in every list: repo groups, lanes, Done, "Recently closed" and the
/// search groups. The glyph sits in the rows' icon column, so header and row glyphs share one axis and the
/// title starts on the row titles' edge; without a glyph the title starts where the row glyphs do. A
/// header that folds toggles as a whole, its chevron hanging in the leading inset, left of the icon column.
struct ListSectionHeader: View {
    let glyph: String?
    var glyphColor: Color = .secondary
    let title: String
    /// Nil for headers that show no count.
    var count: Int? = nil
    /// Quiet text after the count, as in "Done 4 · last 14 days".
    var note: String? = nil
    /// Nil for headers that don't fold.
    var fold: Fold? = nil
    /// The rows' icon column: compact rows have a narrower one.
    var compact = false

    struct Fold {
        let isOpen: Bool
        let toggle: () -> Void
    }

    /// Every header's height, so a list's headers line up whatever they show; `PinnedHeader.clearance`
    /// covers it.
    static let height: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let fold {
            Button(action: fold.toggle) {
                label
                    .overlay(alignment: .leading) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(fold.isOpen ? 90 : 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: fold.isOpen)
                            .frame(width: 8)
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
        ([title] + [count.map(String.init), note].compactMap { $0 }).joined(separator: ", ")
    }

    /// At 11pt the SF circle matches the 13pt row glyph's diameter.
    private var label: some View {
        HStack(spacing: compact ? 8 : 10) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(glyphColor)
                    .frame(width: compact ? 16 : 20)
            }
            HStack(spacing: 6) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                if let note {
                    Text("· \(note)")
                        .fontWeight(.regular)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
