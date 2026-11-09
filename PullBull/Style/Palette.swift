import AppKit
import SwiftUI
import PullBullKit

/// Color and glyph rules: gray for healthy or informational states, color only where action is needed.
enum Palette {
    static func ciGlyph(_ s: CIState) -> (symbol: String, color: Color) {
        switch s {
        case .success: ("checkmark.circle", .secondary)
        case .failure: ("xmark.circle.fill", .red)
        case .pending: ("clock", .secondary)
        case .skipped: ("minus.circle", .secondary)
        case .cancelled: ("stop.circle", .secondary)
        case .none: ("minus", tertiary)
        }
    }

    static func ciLabel(_ s: CIState) -> String {
        switch s {
        case .success: "Checks passed"
        case .failure: "Checks failed"
        case .pending: "Checks running"
        case .skipped: "Checks skipped"
        case .cancelled: "Checks cancelled"
        case .none: "No checks"
        }
    }

    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    /// Informational small text: `.secondary` is about 3.8:1 in light mode, this is about 5.5:1. Dark mode keeps the system color.
    static let secondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .secondaryLabelColor : NSColor.black.withAlphaComponent(0.6)
    })
    /// A neutral pill's text (Open, Ready to merge) on its fill: about 7.5:1 in both appearances, where
    /// `secondaryText` on a fill drops near 4:1 in dark mode at the pills' 10pt.
    static let pillText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.8) : NSColor.black.withAlphaComponent(0.7)
    })
    /// Text and glyphs on an accent-filled button: white, or black where the user's accent is too light or
    /// too gray for white (`OnAccentText`). Resolved per appearance, since the system accent differs between them.
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        var black = false
        appearance.performAsCurrentDrawingAppearance {
            if let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                black = OnAccentText.prefersBlack(
                    red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
            }
        }
        return black ? .black : .white
    })
    static let separator = Color(nsColor: .separatorColor)
    static let fill = Color.primary.opacity(0.06)
    /// The skeleton's sweeping highlight: a lighter fill in light mode, a brighter one in dark mode.
    static let shimmer = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: (0.4, 0.07))
    static let strongFill = Color.primary.opacity(0.1)
    static let rowHover = Color.primary.opacity(0.05)
    static let selection = Color.accentColor.opacity(0.15)
    /// Behind a search match in a title: a soft highlighter yellow, the colour macOS finds text in, kept
    /// apart from the accent so it reads on the selected row.
    static let match = dynamic(light: 0xFFCC00, dark: 0xFFD60A, alpha: (0.4, 0.3))
    /// A row chosen to open, for a moment: the system's emphasized selection, with its text colour.
    static let rowFlash = Color(nsColor: .selectedContentBackgroundColor)
    static let rowFlashText = Color(nsColor: .alternateSelectedControlTextColor)
    static let field = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: (1, 0.07))

    static let changesRequested = dynamic(light: 0xA13007, dark: 0xFF9468)
    /// Go and done: the Ready to merge glyph on rows and in the detail, the Approved check, the diffstat's
    /// addition blocks, and a finished step in Settings and setup.
    static let approved = dynamic(light: 0x1F7A3A, dark: 0x56C26F)
    static let amberFill = dynamic(light: 0xB07000, dark: 0xF5B041, alpha: (0.13, 0.15))
    static let amberGlyph = dynamic(light: 0x8A5700, dark: 0xF5B041)
    /// Text on an `amberGlyph` fill: white on the dark light-mode amber, black on the bright dark-mode one.
    static let onAmber = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let mergedText = dynamic(light: 0x7339AE, dark: 0xC69EF0)
    static let mergedFill = dynamic(light: 0x7339AE, dark: 0xC69EF0, alpha: (0.09, 0.11))
    /// Red for something wrong in the popover and Settings: a closed PR, a rejected key, an invalid field.
    /// A failing check keeps the system red in `ciGlyph`, a filled disc rather than text.
    static let closedText = dynamic(light: 0xB1271F, dark: 0xFF7B73)
    static let closedFill = dynamic(light: 0xB1271F, dark: 0xFF7B73, alpha: (0.08, 0.1))

    private static func dynamic(light: UInt32, dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light, alpha: isDark ? alpha.1 : alpha.0)
        })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }
}

extension Palette {
    /// Pull request glyphs differ by shape; every view picks a PR's state glyph here.
    static func prGlyph(_ g: PRGlyph) -> String {
        switch g {
        case .open: "pullbull.pullrequest"
        case .draft: "pullbull.pullrequest.draft"
        case .merged: "pullbull.pullrequest.merged"
        case .closed: "pullbull.pullrequest.closed"
        }
    }

    /// Colour only where a PR has ended: open and draft stay gray.
    static func prGlyphColor(_ g: PRGlyph) -> Color {
        switch g {
        case .open, .draft: .secondary
        case .merged: mergedText
        case .closed: closedText
        }
    }

    /// Issue glyphs differ by shape: open and not planned are gray, completed is merged purple.
    static func issueGlyph(_ g: IssueGlyph) -> (symbol: String, color: Color, label: String) {
        switch g {
        case .open: ("pullbull.issue", Color.secondary, "Open issue")
        case .completed: ("pullbull.issue.closed", mergedText, "Closed as completed")
        case .notPlanned: ("pullbull.issue.notplanned", Color.secondary, "Closed as not planned")
        }
    }
}

extension Palette {
    /// A board lane's header glyph in the colour the owner gave its Status option; gray stays `.secondary`.
    /// Tuned for a small glyph on popover material: at least 4.5:1 on light, without neon on dark.
    static func statusOptionColor(_ c: StatusOptionColor) -> Color {
        switch c {
        case .gray: .secondary
        case .blue: dynamic(light: 0x0B5FC5, dark: 0x6CB0FF)
        case .green: dynamic(light: 0x1A7F37, dark: 0x5FC27A)
        case .yellow: dynamic(light: 0x8A5700, dark: 0xD8B04A)
        case .orange: dynamic(light: 0xA64B00, dark: 0xF59E5A)
        case .red: closedText
        case .pink: dynamic(light: 0xAD2471, dark: 0xF38DC4)
        case .purple: mergedText
        }
    }
}
