import CoreGraphics

/// The saved searches under the empty search field as wrapping chips: two lines, the last slot "+N"
/// when more are saved; expanded, every search and then "Show less", scrolling past five lines. The
/// view measures each chip's text; this decides what shows and where each line breaks.
public struct SavedChipCloud: Equatable, Sendable {
    public static let collapsedLines = 2
    public static let expandedLines = 5
    public static let spacing: CGFloat = 6
    public static let chipHeight: CGFloat = 24
    public static let chipPadding: CGFloat = 9
    public static let maxChipWidth: CGFloat = 168
    /// The expanded cloud's height once it scrolls: five lines and their gaps.
    public static let expandedHeight = CGFloat(expandedLines) * chipHeight + CGFloat(expandedLines - 1) * spacing

    /// The chip after the shown searches.
    public enum More: Equatable, Sendable {
        /// "+N": `N` searches are hidden.
        case hidden(Int)
        /// The expanded cloud's last chip.
        case showLess

        public var title: String {
            switch self {
            case .hidden(let count): "+\(count)"
            case .showLess: "Show less"
            }
        }

        /// What VoiceOver reads, and the caption; `total` is every saved search.
        public func accessibilityLabel(total: Int) -> String {
            switch self {
            case .hidden: "Show all \(total) saved searches"
            case .showLess: "Show fewer saved searches"
            }
        }
    }

    public enum Chip: Equatable, Sendable {
        case saved(SavedSearch)
        case more(More)

        /// The cursor's item for the chip.
        public var item: HintPanelItem {
            switch self {
            case .saved(let search): .saved(search.id)
            case .more: .more
            }
        }
    }

    /// The chips in reading order.
    public let chips: [Chip]
    /// `chips` broken into lines.
    public let lines: [[Chip]]
    /// The first search "+N" hides, which takes the cursor when it expands from the keyboard.
    public let firstHidden: SavedSearch?

    /// `measure` is a chip's width (`chipWidth(textWidth:)` of its text); `width` is the line's.
    public init(saved: SavedSearches, expanded: Bool, width: CGFloat, measure: (Chip) -> CGFloat) {
        let all = saved.items.map(Chip.saved)
        let widths = all.map(measure)
        var chips = all
        var firstHidden: SavedSearch?
        if Self.lines(widths, in: width).count > Self.collapsedLines {
            if expanded {
                chips.append(.more(.showLess))
            } else {
                // The most searches that still fit two lines with "+N" after them; at least one.
                let count = (1..<all.count).reversed().first { count in
                    let more = Chip.more(.hidden(all.count - count))
                    return Self.lines(Array(widths.prefix(count)) + [measure(more)], in: width).count
                        <= Self.collapsedLines
                } ?? 1
                chips = Array(all.prefix(count)) + [.more(.hidden(all.count - count))]
                firstHidden = saved.items[count]
            }
        }
        self.chips = chips
        self.firstHidden = firstHidden
        self.lines = Self.lines(chips.map(measure), in: width).map { $0.map { chips[$0] } }
    }


    /// Expanded past five lines: the cloud scrolls at `expandedHeight`.
    public var scrolls: Bool { lines.count > Self.expandedLines }

    /// A chip's width for text `textWidth` wide: rounded up with a point of slack, so the chip never
    /// truncates text it was measured to fit, plus padding, capped at `maxChipWidth`.
    public static func chipWidth(textWidth: CGFloat) -> CGFloat {
        min(textWidth.rounded(.up) + 1 + 2 * chipPadding, maxChipWidth)
    }

    /// The indices of `widths` by line, greedily, `spacing` apart; a chip wider than the line has a
    /// line of its own.
    public static func lines(_ widths: [CGFloat], in width: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var used: CGFloat = 0
        for (index, chip) in widths.enumerated() {
            if let last = lines.indices.last, used + spacing + chip <= width {
                lines[last].append(index)
                used += spacing + chip
            } else {
                lines.append([index])
                used = chip
            }
        }
        return lines
    }
}
