import Foundation

/// A PR or issue page's byline: "rado opened 4d ago · updated 1h ago". The update is the age the row
/// shows, so the number on the row is on the page too; it's left out when it would read the same as the
/// opening. A missing date (an issue's can be) leaves its part out.
public enum OpenedLine {
    public static func text(author: String, opened: Date?, updated: Date?, now: Date) -> String {
        let openedAgo = opened.map { RelativeAge.ago($0, now: now) }
        let updatedAgo = updated.map { RelativeAge.ago($0, now: now) }
        let line = "\(author) opened" + (openedAgo.map { " \($0)" } ?? "")
        guard let updatedAgo, updatedAgo != openedAgo else { return line }
        return "\(line) · updated \(updatedAgo)"
    }
}
