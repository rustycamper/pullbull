import Foundation

/// A PR or issue page's byline: "rado opened 4d ago · updated 1h ago". It names what the row shows beside
/// the opening, so the row's number is on the page too: the last update for an open item, or when a merged
/// or closed one ended ("merged Oct 12", the row's `EndedAge` text). The update is left out when it would
/// read the same as the opening, and a missing date (an issue's can be) leaves its part out.
public enum OpenedLine {
    public static func text(
        author: String, opened: Date?, updated: Date?, ended: String? = nil, now: Date
    ) -> String {
        let openedAgo = opened.map { RelativeAge.ago($0, now: now) }
        let line = "\(author) opened" + (openedAgo.map { " \($0)" } ?? "")
        if let ended { return "\(line) · \(ended)" }
        guard let updatedAgo = updated.map({ RelativeAge.ago($0, now: now) }), updatedAgo != openedAgo else {
            return line
        }
        return "\(line) · updated \(updatedAgo)"
    }
}
