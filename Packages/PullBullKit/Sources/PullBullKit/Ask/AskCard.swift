import Foundation

/// The text block the model reads for one item: a header line, the title, then the body.
public enum AskCard {
    public static let bodyLimit = 1500

    /// `### owner/repo#7 | PR | merged | @ann | created … | updated …[ | merged … into main][ | [bug,api]]`,
    /// the title, and the body with whitespace collapsed and cut at `bodyLimit` characters. Dates are UTC.
    public static func render(_ item: AskItem) -> String {
        var header = [
            "### \(item.key.askKey)", item.kind == .pr ? "PR" : "issue", item.state,
            "@\(item.author ?? "?")", "created \(day(item.created))", "updated \(day(item.updated))",
        ]
        if let merged = item.mergedAt {
            header.append("merged \(day(merged))" + (item.baseRef.map { " into \($0)" } ?? ""))
        }
        if !item.labels.isEmpty { header.append("[\(item.labels.joined(separator: ","))]") }
        let body = item.body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return header.joined(separator: " | ") + "\n" + item.title + "\n" + String(body.prefix(bodyLimit))
    }

    private static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    }
}
