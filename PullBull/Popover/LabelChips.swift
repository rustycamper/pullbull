import SwiftUI
import PullBullKit

/// The label chips a meta line ends with: at most `IssueRowRules.maxChips`, the labels a `~label`
/// search asks for first, each cut by `IssueRowRules.chips`, and how many labels there are in all.
struct LabelChipSet {
    struct Chip {
        let name: String
        let text: String
        let color: UInt32?
    }

    let chips: [Chip]
    let total: Int

    /// `color(i)` is the GitHub colour of `labels[i]`.
    init(labels: [String], color: (Int) -> String?, first wanted: [String]) {
        let order = IssueRowRules.chipOrder(labels, first: wanted)
        let shown = IssueRowRules.chips(order.map { labels[$0] }).shown
        chips = zip(order, shown).map { index, text in
            Chip(name: labels[index], text: text, color: LabelDotColor.parse(color(index)))
        }
        total = labels.count
    }

    init(_ pr: PullRequest, first wanted: [String]) {
        self.init(labels: pr.labels, color: pr.labelColor(at:), first: wanted)
    }

    init(_ issue: BoardIssue, first wanted: [String]) {
        self.init(labels: issue.labels, color: issue.labelColor(at:), first: wanted)
    }
}

/// How many of a set's chips a meta line shows, whether the first may shorten to fit, and whether the line
/// leaves out what it can spare (a PR's author, which its avatar names on hover).
struct ChipFit: Hashable {
    let count: Int
    let squeezed: Bool
    var lean = false
}

/// `line(fit)` with as many chips of `set` as fit at full width: chips drop off the end into "+N", so the
/// rest of the line always shows. With `canLean`, the line next tries leaving out what it can spare, with
/// or without labels, before anything shortens. The last resort, the only one that may truncate, keeps one
/// chip, shortened, so a row with labels always shows a colour; it gives way before the rest of the line.
struct ChipsThatFit<Line: View>: View {
    let set: LabelChipSet
    var canLean = false
    @ViewBuilder let line: (ChipFit) -> Line

    private var fits: [ChipFit] {
        guard !set.chips.isEmpty else {
            let full = ChipFit(count: 0, squeezed: false)
            return canLean ? [full, ChipFit(count: 0, squeezed: false, lean: true)] : [full]
        }
        let counts = (1...set.chips.count).reversed()
        let full = counts.map { ChipFit(count: $0, squeezed: false) }
        let lean = canLean ? counts.map { ChipFit(count: $0, squeezed: false, lean: true) } : []
        return full + lean + [ChipFit(count: 1, squeezed: true, lean: canLean)]
    }

    var body: some View {
        let fits = fits
        ViewThatFits(in: .horizontal) {
            ForEach(fits, id: \.self) { fit in
                line(fit)
                    .fixedSize(horizontal: fit != fits.last, vertical: false)
            }
        }
    }
}

/// The first `fit.count` chips of `set`, then "+N" for the labels left out.
struct LabelChips: View {
    let set: LabelChipSet
    let fit: ChipFit

    var body: some View {
        ForEach(Array(set.chips.prefix(fit.count).enumerated()), id: \.offset) { _, chip in
            if fit.squeezed {
                RowLabelChip(text: chip.text, color: chip.color, squeezable: true)
                    .layoutPriority(-2)
                    .help(chip.name)
                    .accessibilityLabel(chip.name)
            } else if chip.text == chip.name {
                RowLabelChip(text: chip.text, color: chip.color).accessibilityLabel(chip.name)
            } else {
                RowLabelChip(text: chip.text, color: chip.color).help(chip.name).accessibilityLabel(chip.name)
            }
        }
        let more = set.total - fit.count
        if more > 0 {
            RowLabelChip(text: "+\(more)")
                .accessibilityLabel(more == 1 ? "1 more label" : "\(more) more labels")
        }
    }
}

/// A muted outline label chip, led by a dot in the label's GitHub colour when it has one. The text stays gray.
/// A `squeezable` chip shortens its text with "…" when the line runs out of room, down to the dot.
struct RowLabelChip: View {
    let text: String
    var color: UInt32?
    var squeezable = false

    /// A squeezed chip keeps its dot and a letter or so.
    private static let minimumWidth: CGFloat = 22

    var body: some View {
        let content = HStack(spacing: 4) {
            if let color { LabelDot(color: color) }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        Group {
            if squeezable {
                content.frame(minWidth: Self.minimumWidth, alignment: .leading)
            } else {
                content.fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 16)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.separator, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}
