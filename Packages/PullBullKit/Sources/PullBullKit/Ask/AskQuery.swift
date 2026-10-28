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

    /// The question's words (`[a-z0-9]`, two or more characters, no stopwords), each quoted so an FTS5
    /// operator or column filter in the question is plain text, joined with OR. Nil when none are left.
    public static func match(_ question: String) -> String? {
        var words: [String] = []
        var current = ""
        func flush() {
            if current.count >= 2, !stopwords.contains(current) { words.append(current) }
            current = ""
        }
        for scalar in question.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }
}
