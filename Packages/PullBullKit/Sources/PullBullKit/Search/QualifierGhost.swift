import Foundation

/// The rest of a qualifier that the word before the caret starts (`sta` → `tus:`), drawn after the caret in
/// the search field; Tab writes it. Only `status:`, `label:` and `updated:`: `is` is too common a title word.
public struct QualifierGhost: Equatable, Sendable {
    /// `status:`, `label:` or `updated:`.
    public let qualifier: String
    /// What the field draws after the caret.
    public let remainder: String
    /// UTF-16 offset of the word the qualifier replaces.
    let start: Int

    /// Shortest word that shows a ghost, so a lone letter never does.
    static let minimumWord = 2

    /// Longest word that shows the `updated:` ghost: "update" is a title word, so past "upda" it stays quiet.
    static let maximumUpdatedWord = 4

    /// The ghost for the word ending at `caret`, which must be the end of `text`: a plain word of at least
    /// two letters, after an optional `-`, that starts a qualifier's name, ignoring case; `updated:` only for
    /// two to four letters. A `-` stays before the qualifier.
    /// `statuses` is false when the board has no Status columns, so `status:` would have nothing to list.
    public static func at(caret: Int, in text: String, statuses: Bool) -> QualifierGhost? {
        guard caret == text.utf16.count, let term = QueryScanner.terms(in: text).last,
              term.kind == .word, term.range.upperBound == text.endIndex
        else { return nil }
        let negated = term.value.first == "-"
        let word = (negated ? term.value.dropFirst() : term.value).lowercased()
        guard word.count >= minimumWord else { return nil }
        let qualifiers = (statuses ? [QueryScanner.statusQualifier] : []) + [QueryScanner.labelQualifier]
            + (word.count <= maximumUpdatedWord ? [QueryScanner.updatedQualifier] : [])
        guard let qualifier = qualifiers.first(where: { $0.dropLast().hasPrefix(word) }) else { return nil }
        return QualifierGhost(
            qualifier: qualifier, remainder: String(qualifier.dropFirst(word.count)),
            start: term.range.lowerBound.utf16Offset(in: text) + (negated ? 1 : 0))
    }

    /// `text` with the word replaced by the qualifier, and the caret after it so its list opens.
    public func accepted(in text: String) -> (text: String, caret: Int)? {
        guard start >= 0, start <= text.utf16.count else { return nil }
        let lower = String.Index(utf16Offset: start, in: text)
        let head = String(text[..<lower]) + qualifier
        return (head, head.utf16.count)
    }
}
