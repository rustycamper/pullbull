import Testing
@testable import PullBullKit

struct AppMenuEntryTests {
    @Test func settingsAndShortcutsLeadThenAboutThenQuit() {
        #expect(AppMenuEntry.entries(updatesAvailable: true)
            == [.settings, .shortcuts, .stats, .separator, .about, .checkForUpdates, .separator, .quit])
    }

    @Test func checkForUpdatesOnlyWhereSparkleRuns() {
        #expect(AppMenuEntry.entries(updatesAvailable: false)
            == [.settings, .shortcuts, .stats, .separator, .about, .separator, .quit])
    }

    @Test func titlesAndKeysMatchTheShortcutsTheyName() {
        #expect(AppMenuEntry.settings.title == "Settings…")
        #expect(AppMenuEntry.settings.keyEquivalent == ",")
        #expect(AppMenuEntry.shortcuts.title == "Keyboard Shortcuts")
        #expect(AppMenuEntry.shortcuts.keyEquivalent == "/")
        #expect(AppMenuEntry.stats.title == "Stats")
        #expect(AppMenuEntry.stats.keyEquivalent == "3")
        #expect(AppMenuEntry.about.title == "About PullBull")
        #expect(AppMenuEntry.about.keyEquivalent == "")
        #expect(AppMenuEntry.checkForUpdates.title == "Check for Updates…")
        #expect(AppMenuEntry.quit.title == "Quit PullBull")
        #expect(AppMenuEntry.quit.keyEquivalent == "q")
        #expect(AppMenuEntry.separator.title == nil)
    }
}
