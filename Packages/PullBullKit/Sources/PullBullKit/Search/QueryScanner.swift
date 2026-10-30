import Foundation

/// One whitespace-separated term of a search query, or a quoted label that runs past whitespace.
struct QueryTerm {
    enum Kind {
        /// Starts with "@" or "＠".
        case person
        /// Starts with "~" or "～".
        case label
        /// Starts with "label:", any case.
        case labelAlias
        /// Starts with "is:", any case.
        case state
        /// Starts with "status:", any case.
        case status
        /// Starts with "updated:", any case.
        case updated
        /// Starts with "review:", any case.
        case review
        /// Starts with "repo:", any case.
        case repo
        /// Starts with "size:", any case.
        case size
        case word
    }

    let kind: Kind
    /// The whole term, a leading `-`, sigil and quotes included.
    let range: Range<String.Index>
    /// After the sigil, "label:", "is:", "status:", "updated:" or "review:", without quotes; the whole term for a word.
    let value: Substring
    /// The value opened with a quote.
    let quoted: Bool
    /// A quoted value found its closing quote.
    let closed: Bool
    /// A `-` before the sigil excludes what the term names. A word never has one: `-flaky` is a word.
    let negated: Bool
}

enum QueryScanner {
    static let personSigils: Set<Character> = ["@", "＠"]
    static let labelSigils: Set<Character> = ["~", "～"]
    static let labelQualifier = "label:"
    static let stateQualifier = "is:"
    static let statusQualifier = "status:"
    static let updatedQualifier = "updated:"
    static let reviewQualifier = "review:"
    static let repoQualifier = "repo:"
    static let sizeQualifier = "size:"

    /// The terms of `text` in order. A label's or status's value may be quoted (`~"good first issue"`,
    /// `label:"good first issue"`, `status:"In progress"`); a quote left open runs to the end of the text,
    /// or to the whitespace before the next `@`, `~`, `#`, `label:`, `is:`, `status:`, `updated:`, `review:` or `repo:` term, which then
    /// parses as usual. An `is:`, `updated:`, `review:` or `repo:` value is never quoted. A `-` right before any sigil but `#`
    /// negates the term.
    static func terms(in text: String) -> [QueryTerm] {
        var terms: [QueryTerm] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c.isWhitespace {
                i = text.index(after: i)
                continue
            }
            let start = i
            let negated = c == "-" && startsQualifier(text[text.index(after: i)...])
            let sigil = negated ? text.index(after: i) : i
            let valueStart: String.Index?
            let kind: QueryTerm.Kind
            if labelSigils.contains(text[sigil]) {
                kind = .label
                valueStart = text.index(after: sigil)
            } else if startsLabelAlias(text[sigil...]) {
                kind = .labelAlias
                valueStart = text.index(sigil, offsetBy: labelQualifier.count)
            } else if startsState(text[sigil...]) {
                kind = .state
                valueStart = nil
            } else if startsStatus(text[sigil...]) {
                kind = .status
                valueStart = text.index(sigil, offsetBy: statusQualifier.count)
            } else if startsUpdated(text[sigil...]) {
                kind = .updated
                valueStart = nil
            } else if startsReview(text[sigil...]) {
                kind = .review
                valueStart = nil
            } else if startsRepo(text[sigil...]) {
                kind = .repo
                valueStart = nil
            } else if startsSize(text[sigil...]) {
                kind = .size
                valueStart = nil
            } else {
                kind = personSigils.contains(text[sigil]) ? .person : .word
                valueStart = nil
            }
            if let valueStart, valueStart < text.endIndex, text[valueStart] == "\"" {
                let open = text.index(after: valueStart)
                if let close = text[open...].firstIndex(of: "\"") {
                    i = text.index(after: close)
                    terms.append(QueryTerm(
                        kind: kind, range: start..<i, value: text[open..<close], quoted: true, closed: true,
                        negated: negated))
                } else {
                    i = openQuoteEnd(in: text, from: open)
                    terms.append(QueryTerm(
                        kind: kind, range: start..<i, value: text[open..<i], quoted: true, closed: false,
                        negated: negated))
                }
                continue
            }
            var end = i
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            let value: Substring
            switch kind {
            case .word: value = text[start..<end]
            case .person: value = text[text.index(after: sigil)..<end]
            case .label, .labelAlias, .status: value = text[(valueStart ?? end)..<end]
            case .state: value = text[text.index(sigil, offsetBy: stateQualifier.count)..<end]
            case .updated: value = text[text.index(sigil, offsetBy: updatedQualifier.count)..<end]
            case .review: value = text[text.index(sigil, offsetBy: reviewQualifier.count)..<end]
            case .repo: value = text[text.index(sigil, offsetBy: repoQualifier.count)..<end]
            case .size: value = text[text.index(sigil, offsetBy: sizeQualifier.count)..<end]
            }
            terms.append(QueryTerm(
                kind: kind, range: start..<end, value: value, quoted: false, closed: false, negated: negated))
            i = end
        }
        return terms
    }

    /// Where a quote opened before `from` and never closed ends: the first whitespace followed by a
    /// sigil term, else the end of `text`.
    private static func openQuoteEnd(in text: String, from: String.Index) -> String.Index {
        var j = from
        while j < text.endIndex {
            if text[j].isWhitespace {
                let next = text.index(after: j)
                if next < text.endIndex, startsSigilTerm(text[next...]) { return j }
            }
            j = text.index(after: j)
        }
        return text.endIndex
    }

    /// `rest` starts a sigil term, or `-` and one that can be negated.
    private static func startsSigilTerm(_ rest: Substring) -> Bool {
        guard let first = rest.first else { return false }
        return first == "#" || startsQualifier(rest) || (first == "-" && startsQualifier(rest.dropFirst()))
    }

    /// `rest` starts an `@`, `~`, `label:`, `is:`, `status:`, `updated:` `review:` or `repo:` term: one a `-` can negate.
    static func startsQualifier(_ rest: Substring) -> Bool {
        guard let first = rest.first else { return false }
        return personSigils.contains(first) || labelSigils.contains(first) || startsLabelAlias(rest)
            || startsState(rest) || startsStatus(rest) || startsUpdated(rest) || startsReview(rest)
            || startsRepo(rest) || startsSize(rest)
    }

    /// `rest` starts with "is:", any case.
    static func startsState(_ rest: Substring) -> Bool {
        rest.prefix(stateQualifier.count).lowercased() == stateQualifier
    }

    /// `rest` starts with "status:", any case.
    static func startsStatus(_ rest: Substring) -> Bool {
        rest.prefix(statusQualifier.count).lowercased() == statusQualifier
    }

    /// `rest` starts with "updated:", any case.
    static func startsUpdated(_ rest: Substring) -> Bool {
        rest.prefix(updatedQualifier.count).lowercased() == updatedQualifier
    }

    /// `rest` starts with "review:", any case.
    static func startsReview(_ rest: Substring) -> Bool {
        rest.prefix(reviewQualifier.count).lowercased() == reviewQualifier
    }

    /// `rest` starts with "repo:", any case.
    static func startsRepo(_ rest: Substring) -> Bool {
        rest.prefix(repoQualifier.count).lowercased() == repoQualifier
    }

    /// `rest` starts with "size:", any case.
    static func startsSize(_ rest: Substring) -> Bool {
        rest.prefix(sizeQualifier.count).lowercased() == sizeQualifier
    }

    /// `rest` starts with "label:", any case.
    static func startsLabelAlias(_ rest: Substring) -> Bool {
        rest.prefix(labelQualifier.count).lowercased() == labelQualifier
    }
}
