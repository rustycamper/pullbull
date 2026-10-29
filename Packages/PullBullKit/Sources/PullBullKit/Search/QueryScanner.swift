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
        case word
    }

    let kind: Kind
    /// The whole term, sigil and quotes included.
    let range: Range<String.Index>
    /// After the sigil, "label:", "is:" or "status:", without quotes; the whole term for a word.
    let value: Substring
    /// The value opened with a quote.
    let quoted: Bool
    /// A quoted value found its closing quote.
    let closed: Bool
}

enum QueryScanner {
    static let personSigils: Set<Character> = ["@", "＠"]
    static let labelSigils: Set<Character> = ["~", "～"]
    static let labelQualifier = "label:"
    static let stateQualifier = "is:"
    static let statusQualifier = "status:"

    /// The terms of `text` in order. A label's or status's value may be quoted (`~"good first issue"`,
    /// `label:"good first issue"`, `status:"In progress"`); a quote left open runs to the end of the text,
    /// or to the whitespace before the next `@`, `~`, `#`, `label:`, `is:` or `status:` term, which then
    /// parses as usual. An `is:` value is never quoted.
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
            let valueStart: String.Index?
            let kind: QueryTerm.Kind
            if labelSigils.contains(c) {
                kind = .label
                valueStart = text.index(after: i)
            } else if text[i...].prefix(labelQualifier.count).lowercased() == labelQualifier {
                kind = .labelAlias
                valueStart = text.index(i, offsetBy: labelQualifier.count)
            } else if startsState(text[i...]) {
                kind = .state
                valueStart = nil
            } else if startsStatus(text[i...]) {
                kind = .status
                valueStart = text.index(i, offsetBy: statusQualifier.count)
            } else {
                kind = personSigils.contains(c) ? .person : .word
                valueStart = nil
            }
            if let valueStart, valueStart < text.endIndex, text[valueStart] == "\"" {
                let open = text.index(after: valueStart)
                if let close = text[open...].firstIndex(of: "\"") {
                    i = text.index(after: close)
                    terms.append(QueryTerm(
                        kind: kind, range: start..<i, value: text[open..<close], quoted: true, closed: true))
                } else {
                    i = openQuoteEnd(in: text, from: open)
                    terms.append(QueryTerm(
                        kind: kind, range: start..<i, value: text[open..<i], quoted: true, closed: false))
                }
                continue
            }
            var end = i
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            let value: Substring
            switch kind {
            case .word: value = text[start..<end]
            case .person: value = text[text.index(after: start)..<end]
            case .label, .labelAlias, .status: value = text[(valueStart ?? end)..<end]
            case .state: value = text[text.index(start, offsetBy: stateQualifier.count)..<end]
            }
            terms.append(QueryTerm(kind: kind, range: start..<end, value: value, quoted: false, closed: false))
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

    private static func startsSigilTerm(_ rest: Substring) -> Bool {
        guard let first = rest.first else { return false }
        return personSigils.contains(first) || labelSigils.contains(first) || first == "#"
            || rest.prefix(labelQualifier.count).lowercased() == labelQualifier || startsState(rest) || startsStatus(rest)
    }

    /// `rest` starts with "is:", any case.
    static func startsState(_ rest: Substring) -> Bool {
        rest.prefix(stateQualifier.count).lowercased() == stateQualifier
    }

    /// `rest` starts with "status:", any case.
    static func startsStatus(_ rest: Substring) -> Bool {
        rest.prefix(statusQualifier.count).lowercased() == statusQualifier
    }

    /// `rest` starts with "label:", any case.
    static func startsLabelAlias(_ rest: Substring) -> Bool {
        rest.prefix(labelQualifier.count).lowercased() == labelQualifier
    }
}
