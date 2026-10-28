import Foundation

/// ⌥⌘C and Copy as Markdown Link: `[Fix token refresh (initech/widgets#250)](https://…)`.
public enum MarkdownLink {
    /// The title, then the reference in parentheses, linking to `url`; the reference alone when there is
    /// no title. Brackets and backslashes in the title are escaped so the link text can't end early; any
    /// other Markdown in it is left as typed.
    public static func item(title: String?, key: PRKey, url: URL) -> String {
        let reference = ListNavigation.reference(key)
        let words = (title ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let text = words.isEmpty ? reference : "\(escaped(words)) (\(reference))"
        return "[\(text)](\(destination(url)))"
    }

    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if character == "\\" || character == "[" || character == "]" { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Parentheses and spaces would end or break the destination.
    private static func destination(_ url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: " ", with: "%20")
    }
}
