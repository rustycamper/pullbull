import Foundation

/// Turns a chat-style question into an FTS5 MATCH expression.
public enum AskQuery {
    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "did", "do", "does", "for", "from", "had",
        "has", "have", "how", "i", "if", "in", "into", "is", "it", "its", "of", "on", "or", "our", "so",
        "that", "the", "their", "them", "then", "there", "these", "they", "this", "to", "was", "we", "were",
        "what", "when", "where", "which", "who", "why", "will", "with", "yet", "you", "your", "up", "now",
        "some", "just", "thing", "stuff", "one", "ones",
    ]

    /// The question's words (letters and numbers, two or more characters, no stopwords), each quoted so an FTS5
    /// operator or column filter in the question is plain text, joined with OR. Nil when none are left.
    public static func match(_ question: String) -> String? {
        var words: [String] = []
        var current = ""
        func flush() {
            if current.count >= 2, !stopwords.contains(current) { words.append(current) }
            current = ""
        }
        // Per scalar, not per Character: a grapheme cluster can start with a letter and still carry a `"`.
        for scalar in question.lowercased().unicodeScalars {
            if isWordScalar(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    /// Letters, numbers and combining marks; never FTS5 syntax.
    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        if properties.isAlphabetic || properties.numericType != nil { return true }
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }
}
