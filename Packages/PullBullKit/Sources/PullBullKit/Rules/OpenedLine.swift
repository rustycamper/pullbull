import Foundation

/// A PR page's byline: "rado opened 4d ago · updated 1h ago". The update is the age a PR row shows, so
/// the number on the row is on the page too; it's left out when it would read the same as the opening.
public enum OpenedLine {
    public static func text(author: String, opened: Date, updated: Date, now: Date) -> String {
        let openedAgo = RelativeAge.ago(opened, now: now)
        let updatedAgo = RelativeAge.ago(updated, now: now)
        let line = "\(author) opened \(openedAgo)"
        return updatedAgo == openedAgo ? line : "\(line) · updated \(updatedAgo)"
    }
}
