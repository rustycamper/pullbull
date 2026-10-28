import AppKit
import PullBullKit

/// What the status item shows: the template glyph plus the badge count. Zero shows the glyph only. When
/// the last refresh failed offline the glyph is slashed and dimmed; a failure the user can act on adds an
/// exclamation badge to the normal glyph (`MenuBarGlyph`), never dimmed; before an account is set up the
/// normal glyph is dimmed. Either way the last known count stays. Otherwise data older than two poll
/// intervals (a refresh that never finishes) is dimmed, as is a count that adds Assigned issues whose
/// latest search failed or never ran. Counts above 99 read "99+", as the tabs do; the accessibility text
/// and tooltip keep the exact number.
struct StatusItemLabel: Equatable {
    let count: Int
    let glyph: MenuBarGlyph
    let dimmed: Bool
    let accessibilityText: String

    @MainActor init(model: AppModel, now: Date) {
        count = model.badgeCount()
        let error = model.status.error
        let firstRun = model.showsFirstRun
        // No account yet is setup, not a failure; a signed-out app account is one.
        glyph = MenuBarGlyph.glyph(
            for: error, noAccount: model.settings.account == nil, signedOut: model.isSignedOut)
        let stale = model.status.isStale(now: now, interval: .seconds(max(1, model.settings.refreshMinutes) * 60))
        let issuesIncomplete = model.badgeIssuesIncomplete
        dimmed = glyph.dimmed(stale: stale, issuesIncomplete: issuesIncomplete)
        accessibilityText = Self.accessibilityText(count: count, error: error.map(model.message(for:)),
                                                 firstRun: firstRun, stale: stale,
                                                 issuesIncomplete: issuesIncomplete,
                                                 countsIssues: model.settings.countAssignedIssues)
    }

    /// One template image for glyph and count, so the menu bar tints both for light, dark and highlighted
    /// states. When dimmed, glyph and count are both drawn at half alpha, which a template image keeps, so a
    /// stale count never reads as current. The three glyphs share one size, so the item's width never
    /// changes with its state.
    @MainActor func image() -> NSImage {
        let glyphName = switch glyph {
        case .normal, .notSetUp: "MenuBarGlyph"
        case .offline: "MenuBarGlyphOffline"
        case .error: "MenuBarGlyphError"
        }
        let glyphSize = NSImage(named: glyphName)?.size ?? NSSize(width: 18, height: 18)
        let text = count > 0 ? TabCountText.header(count) : ""
        let fontSize = NSFont.menuBarFont(ofSize: 0).pointSize
        let textSize = (text as NSString).size(withAttributes: [.font: Self.font(size: fontSize)])
        let spacing: CGFloat = text.isEmpty ? 0 : 3
        let size = NSSize(width: ceil(glyphSize.width + spacing + textSize.width), height: glyphSize.height)
        let alpha: CGFloat = dimmed ? 0.5 : 1
        let image = NSImage(size: size, flipped: false) { rect in
            let glyphRect = NSRect(x: 0, y: (rect.height - glyphSize.height) / 2, width: glyphSize.width,
                                   height: glyphSize.height)
            NSImage(named: glyphName)?.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: alpha)
            guard !text.isEmpty else { return true }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font(size: fontSize), .foregroundColor: NSColor.black.withAlphaComponent(alpha),
            ]
            let origin = NSPoint(x: glyphSize.width + spacing, y: (rect.height - textSize.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityText
        return image
    }

    private static func font(size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private static func accessibilityText(count: Int, error: String?, firstRun: Bool, stale: Bool,
                                          issuesIncomplete: Bool, countsIssues: Bool) -> String {
        if let error { return "PullBull, \(error), last known count \(count)" }
        if firstRun { return "PullBull, not signed in" }
        if stale { return "PullBull, not updated recently, last known count \(count)" }
        if issuesIncomplete { return "PullBull, assigned issues didn't update, last known count \(count)" }
        if count == 0 { return "PullBull, nothing needs your attention" }
        if countsIssues { return "PullBull, \(count) item\(count == 1 ? "" : "s") needing attention" }
        return "PullBull, \(count) pull request\(count == 1 ? "" : "s")"
    }
}
