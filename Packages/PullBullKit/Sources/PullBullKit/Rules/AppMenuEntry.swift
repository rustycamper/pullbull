/// The app menu, shown by the footer gear and by a right-click on the menu bar item: Settings and Keyboard
/// Shortcuts first, what the gear is for, then About and Check for Updates, then Quit.
public enum AppMenuEntry: Equatable, Sendable {
    case settings
    case shortcuts
    case about
    case checkForUpdates
    case quit
    case separator

    /// Check for Updates… only where Sparkle runs (release builds).
    public static func entries(updatesAvailable: Bool) -> [AppMenuEntry] {
        [.settings, .shortcuts, .separator, .about] + (updatesAvailable ? [.checkForUpdates] : []) + [.separator, .quit]
    }

    /// The item's title; nil for a separator.
    public var title: String? {
        switch self {
        case .settings: "Settings…"
        case .shortcuts: "Keyboard Shortcuts"
        case .about: "About PullBull"
        case .checkForUpdates: "Check for Updates…"
        case .quit: "Quit PullBull"
        case .separator: nil
        }
    }

    /// The ⌘ key the item shows, the one that does the same in the popover (⌘, ⌘/ ⌘Q); "" for none.
    public var keyEquivalent: String {
        switch self {
        case .settings: ","
        case .shortcuts: "/"
        case .quit: "q"
        case .about, .checkForUpdates, .separator: ""
        }
    }
}
