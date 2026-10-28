import Foundation

public struct PendingToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `@login`
        case person
        /// `~label` or `~"label with spaces"`
        case label
        /// `is:open`
        case state
    }

    /// UTF-16 offset of the sigil ("@", "＠", "~", "～" or "is:", any case).
    public let start: Int
    /// UTF-16 offset of the caret.
    public let end: Int
    /// After the sigil (and a label's opening quote), as typed.
    public let prefix: String
    public let kind: Kind

    public init(start: Int, end: Int, prefix: String, kind: Kind = .person) {
        self.start = start
        self.end = end
        self.prefix = prefix
        self.kind = kind
    }

    /// The `@`, `~` or `is:` token that ends at the caret, if any. A label may be quoted; a closed quote
    /// ends it. An `is:` value is letters only.
    public static func at(caret: Int, in text: String) -> PendingToken? {
        let scalars = text.unicodeScalars
        guard caret >= 0, caret <= text.utf16.count else { return nil }
        let caretIndex = String.Index(utf16Offset: caret, in: text)
        guard caretIndex.samePosition(in: scalars) != nil else { return nil }
        if caretIndex < scalars.endIndex, !scalars[caretIndex].properties.isWhitespace { return nil }
        let head = String(text[..<caretIndex])
        guard let term = QueryScanner.terms(in: head).last, term.range.upperBound == head.endIndex else { return nil }
        let start = term.range.lowerBound.utf16Offset(in: head)
        let prefix = String(term.value)
        switch term.kind {
        case .person:
            guard prefix.isEmpty || SearchQuery.isLogin(term.value) else { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .person)
        case .label:
            if term.quoted && term.closed { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .label)
        case .state:
            guard prefix.allSatisfy(\.isLetter) else { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .state)
        case .labelAlias, .word:
            return nil
        }
    }

    /// Whether a sigil at UTF-16 `offset` begins a word: at the start of `text` or after whitespace. With
    /// a `kind`, only that kind's sigils count.
    public static func startsToken(at offset: Int, in text: String, kind: Kind? = nil) -> Bool {
        guard offset >= 0, offset < text.utf16.count else { return false }
        let scalars = text.unicodeScalars
        let index = String.Index(utf16Offset: offset, in: text)
        guard index.samePosition(in: scalars) != nil, sigilEnd(in: text, at: index, of: kind) != nil else {
            return false
        }
        return index == scalars.startIndex || scalars[scalars.index(before: index)].properties.isWhitespace
    }

    public func range(in text: String) -> Range<String.Index>? {
        guard start >= 0, start <= end, end <= text.utf16.count else { return nil }
        let scalars = text.unicodeScalars
        let lower = String.Index(utf16Offset: start, in: text)
        let upper = String.Index(utf16Offset: end, in: text)
        guard lower.samePosition(in: scalars) != nil, upper.samePosition(in: scalars) != nil,
            lower < scalars.endIndex, Self.sigilEnd(in: text, at: lower, of: kind) != nil
        else { return nil }
        return lower..<upper
    }

    /// Where the sigil of `kind` (of any kind when nil) at `index` ends; nil when none starts there.
    /// `index` is a scalar boundary before the end of `text`.
    static func sigilEnd(in text: String, at index: String.Index, of kind: Kind?) -> String.Index? {
        let scalars = text.unicodeScalars
        let character = Character(scalars[index])
        let kinds: [Kind] = kind.map { [$0] } ?? [.person, .label, .state]
        for kind in kinds {
            switch kind {
            case .person where QueryScanner.personSigils.contains(character),
                 .label where QueryScanner.labelSigils.contains(character):
                return scalars.index(after: index)
            case .state where QueryScanner.startsState(text[index...]):
                return text.index(index, offsetBy: QueryScanner.stateQualifier.count)
            default:
                continue
            }
        }
        return nil
    }
}

/// A row of a completion list.
public protocol CompletionCandidate: Equatable, Sendable, Identifiable where ID == String {
    /// What completing with this row writes in place of the token.
    var insertText: String { get }
}

/// The candidates for the token at the caret, and the selected one.
public struct TokenCompletion<Candidate: CompletionCandidate>: Equatable, Sendable {
    public let token: PendingToken
    public let candidates: [Candidate]
    /// Meaningless when `candidates` is empty.
    public private(set) var selection: Int

    init(token: PendingToken, candidates: [Candidate], selection: Int) {
        self.token = token
        self.candidates = candidates
        self.selection = selection
    }

    /// The candidate at `selection`; nil when there is none.
    public var selectedCandidate: Candidate? {
        candidates.indices.contains(selection) ? candidates[selection] : nil
    }

    public func moved(by offset: Int) -> TokenCompletion {
        let last = max(candidates.count - 1, 0)
        return TokenCompletion(token: token, candidates: candidates, selection: min(max(selection + offset, 0), last))
    }

    /// Text with the token replaced by `insertText` plus one space (an existing space is reused) and
    /// the caret after it; nil when there is no candidate.
    public func accepted(in text: String) -> (text: String, caret: Int)? {
        guard let candidate = selectedCandidate, let range = token.range(in: text) else { return nil }
        let head = String(text[..<range.lowerBound]) + candidate.insertText + " "
        let tail = text[range.upperBound...]
        let rest = tail.first?.isWhitespace == true ? tail.dropFirst() : tail
        return (head + rest, head.utf16.count)
    }

    /// The token at the caret when it is of `kind` and not the one at `dismissedStart`.
    fileprivate static func token(
        _ kind: PendingToken.Kind, text: String, caret: Int, dismissedStart: Int?
    ) -> PendingToken? {
        guard let token = PendingToken.at(caret: caret, in: text), token.kind == kind,
              token.start != dismissedStart else { return nil }
        return token
    }
}

public typealias PersonCompletion = TokenCompletion<PersonCandidate>
public typealias LabelCompletion = TokenCompletion<LabelCandidate>
public typealias StateCompletion = TokenCompletion<StateCandidate>

extension TokenCompletion where Candidate == PersonCandidate {
    /// Nil when no `@` token ends at the caret or the token at `dismissedStart` is the one there.
    public static func open(
        text: String, caret: Int, dismissedStart: Int?, people: PeopleIndex
    ) -> PersonCompletion? {
        token(.person, text: text, caret: caret, dismissedStart: dismissedStart).map {
            PersonCompletion(token: $0, candidates: people.candidates(prefix: $0.prefix), selection: 0)
        }
    }
}

extension TokenCompletion where Candidate == LabelCandidate {
    /// Nil when no `~` token ends at the caret or the token at `dismissedStart` is the one there.
    public static func open(
        text: String, caret: Int, dismissedStart: Int?, labels: LabelIndex
    ) -> LabelCompletion? {
        token(.label, text: text, caret: caret, dismissedStart: dismissedStart).map {
            LabelCompletion(token: $0, candidates: labels.candidates(prefix: $0.prefix), selection: 0)
        }
    }
}

extension TokenCompletion where Candidate == StateCandidate {
    /// Nil when no `is:` token ends at the caret or the token at `dismissedStart` is the one there.
    public static func open(text: String, caret: Int, dismissedStart: Int?) -> StateCompletion? {
        token(.state, text: text, caret: caret, dismissedStart: dismissedStart).map {
            StateCompletion(token: $0, candidates: StateCandidate.candidates(prefix: $0.prefix), selection: 0)
        }
    }
}

/// The one completion list the search field can show: people for an `@` token, labels for a `~` token,
/// states for an `is:` token.
public enum SearchCompletion: Equatable, Sendable {
    case people(PersonCompletion)
    case labels(LabelCompletion)
    case states(StateCompletion)

    /// The list for the token at the caret, of whichever kind it is.
    public static func open(
        text: String, caret: Int, dismissedStart: Int?, people: PeopleIndex, labels: LabelIndex
    ) -> SearchCompletion? {
        if let completion = PersonCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart, people: people) {
            return .people(completion)
        }
        if let completion = LabelCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart, labels: labels) {
            return .labels(completion)
        }
        return StateCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart)
            .map(SearchCompletion.states)
    }

    public var token: PendingToken {
        switch self {
        case .people(let c): c.token
        case .labels(let c): c.token
        case .states(let c): c.token
        }
    }

    public var selection: Int {
        switch self {
        case .people(let c): c.selection
        case .labels(let c): c.selection
        case .states(let c): c.selection
        }
    }

    public var hasCandidates: Bool {
        switch self {
        case .people(let c): !c.candidates.isEmpty
        case .labels(let c): !c.candidates.isEmpty
        case .states(let c): !c.candidates.isEmpty
        }
    }

    public func moved(by offset: Int) -> SearchCompletion {
        switch self {
        case .people(let c): .people(c.moved(by: offset))
        case .labels(let c): .labels(c.moved(by: offset))
        case .states(let c): .states(c.moved(by: offset))
        }
    }

    public func accepted(in text: String) -> (text: String, caret: Int)? {
        switch self {
        case .people(let c): c.accepted(in: text)
        case .labels(let c): c.accepted(in: text)
        case .states(let c): c.accepted(in: text)
        }
    }

    /// Same kind with the same rows (selection aside).
    func hasSameCandidates(as other: SearchCompletion) -> Bool {
        switch (self, other) {
        case (.people(let a), .people(let b)): a.candidates == b.candidates
        case (.labels(let a), .labels(let b)): a.candidates == b.candidates
        case (.states(let a), .states(let b)): a.candidates == b.candidates
        default: false
        }
    }

    var selectedID: String? {
        switch self {
        case .people(let c): c.selectedCandidate?.id
        case .labels(let c): c.selectedCandidate?.id
        case .states(let c): c.selectedCandidate?.id
        }
    }

    /// This list with the row `id` selected, or the first row when it is not listed.
    func selecting(_ id: String?) -> SearchCompletion {
        let index: Int?
        switch self {
        case .people(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .labels(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .states(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        }
        return moved(by: (index ?? 0) - selection)
    }
}
