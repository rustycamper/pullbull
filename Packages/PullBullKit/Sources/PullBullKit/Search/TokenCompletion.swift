import Foundation

public struct PendingToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `@login`
        case person
        /// `~label`, `~"label with spaces"` or `label:label`
        case label
        /// `is:open`
        case state
        /// `status:prog` or `status:"In progress"`
        case status
        /// `updated:3d`
        case updated
        /// `review:changes`
        case review
        /// `repo:widgets` or `repo:acme/widgets`
        case repo
    }

    /// UTF-16 offset of the sigil ("@", "＠", "~", "～", "label:", "is:", "status:", "updated:", "review:" or "repo:", any case).
    public let start: Int
    /// UTF-16 offset of the caret.
    public let end: Int
    /// After the sigil (and a label's or status's opening quote), as typed.
    public let prefix: String
    public let kind: Kind

    public init(start: Int, end: Int, prefix: String, kind: Kind = .person) {
        self.start = start
        self.end = end
        self.prefix = prefix
        self.kind = kind
    }

    /// The `@`, `~`, `label:`, `is:`, `status:` or `updated:` token that ends at the caret, if any. A label or
    /// status may be quoted; a closed quote ends it. An `is:` value is letters only. After a `-`, the token
    /// starts at its sigil, so the `-` stays when a candidate is picked.
    public static func at(caret: Int, in text: String) -> PendingToken? {
        let scalars = text.unicodeScalars
        guard caret >= 0, caret <= text.utf16.count else { return nil }
        let caretIndex = String.Index(utf16Offset: caret, in: text)
        guard caretIndex.samePosition(in: scalars) != nil else { return nil }
        if caretIndex < scalars.endIndex, !scalars[caretIndex].properties.isWhitespace { return nil }
        let head = String(text[..<caretIndex])
        guard let term = QueryScanner.terms(in: head).last, term.range.upperBound == head.endIndex else { return nil }
        let sigil = term.negated ? head.index(after: term.range.lowerBound) : term.range.lowerBound
        let start = sigil.utf16Offset(in: head)
        let prefix = String(term.value)
        switch term.kind {
        case .person:
            guard prefix.isEmpty || SearchQuery.isLogin(term.value) else { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .person)
        case .label, .labelAlias, .status:
            if term.quoted && term.closed { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: term.kind == .status ? .status : .label)
        case .state:
            guard prefix.allSatisfy(\.isLetter) else { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .state)
        case .updated:
            guard prefix.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .updated)
        case .review:
            guard prefix.allSatisfy(\.isLetter) else { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .review)
        case .repo:
            guard prefix.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }) else { return nil }
            return PendingToken(start: start, end: caret, prefix: prefix, kind: .repo)
        case .size, .word:
            return nil
        }
    }

    /// Whether a sigil at UTF-16 `offset` begins a word: at the start of `text` or after whitespace, or after
    /// a `-` that is. With a `kind`, only that kind's sigils count.
    public static func startsToken(at offset: Int, in text: String, kind: Kind? = nil) -> Bool {
        guard offset >= 0, offset < text.utf16.count else { return false }
        let scalars = text.unicodeScalars
        let index = String.Index(utf16Offset: offset, in: text)
        guard index.samePosition(in: scalars) != nil, sigilEnd(in: text, at: index, of: kind) != nil else {
            return false
        }
        func startsWord(_ i: String.Index) -> Bool {
            i == scalars.startIndex || scalars[scalars.index(before: i)].properties.isWhitespace
        }
        if startsWord(index) { return true }
        let before = scalars.index(before: index)
        return scalars[before] == "-" && startsWord(before)
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
        let kinds: [Kind] = kind.map { [$0] } ?? [.person, .label, .state, .status, .updated, .review, .repo]
        for kind in kinds {
            switch kind {
            case .person where QueryScanner.personSigils.contains(character),
                 .label where QueryScanner.labelSigils.contains(character):
                return scalars.index(after: index)
            case .label where QueryScanner.startsLabelAlias(text[index...]):
                return text.index(index, offsetBy: QueryScanner.labelQualifier.count)
            case .state where QueryScanner.startsState(text[index...]):
                return text.index(index, offsetBy: QueryScanner.stateQualifier.count)
            case .status where QueryScanner.startsStatus(text[index...]):
                return text.index(index, offsetBy: QueryScanner.statusQualifier.count)
            case .updated where QueryScanner.startsUpdated(text[index...]):
                return text.index(index, offsetBy: QueryScanner.updatedQualifier.count)
            case .review where QueryScanner.startsReview(text[index...]):
                return text.index(index, offsetBy: QueryScanner.reviewQualifier.count)
            case .repo where QueryScanner.startsRepo(text[index...]):
                return text.index(index, offsetBy: QueryScanner.repoQualifier.count)
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
public typealias StatusCompletion = TokenCompletion<StatusCandidate>
public typealias UpdatedCompletion = TokenCompletion<TimeStepCandidate>
public typealias ReviewCompletion = TokenCompletion<ReviewCandidate>
public typealias RepoCompletion = TokenCompletion<RepoCandidate>

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

extension TokenCompletion where Candidate == StatusCandidate {
    /// Nil when no `status:` token ends at the caret or the token at `dismissedStart` is the one there.
    public static func open(
        text: String, caret: Int, dismissedStart: Int?, statuses: StatusIndex
    ) -> StatusCompletion? {
        token(.status, text: text, caret: caret, dismissedStart: dismissedStart).map {
            StatusCompletion(token: $0, candidates: statuses.candidates(prefix: $0.prefix), selection: 0)
        }
    }
}

extension TokenCompletion where Candidate == TimeStepCandidate {
    /// Nil when no `updated:` token ends at the caret or the token at `dismissedStart` is the one there.
    public static func open(text: String, caret: Int, dismissedStart: Int?) -> UpdatedCompletion? {
        token(.updated, text: text, caret: caret, dismissedStart: dismissedStart).map {
            UpdatedCompletion(token: $0, candidates: TimeStepCandidate.candidates(prefix: $0.prefix), selection: 0)
        }
    }
}

extension TokenCompletion where Candidate == ReviewCandidate {
    /// Nil when no `review:` token ends at the caret or the token at `dismissedStart` is the one there.
    public static func open(text: String, caret: Int, dismissedStart: Int?) -> ReviewCompletion? {
        token(.review, text: text, caret: caret, dismissedStart: dismissedStart).map {
            ReviewCompletion(token: $0, candidates: ReviewCandidate.candidates(prefix: $0.prefix), selection: 0)
        }
    }
}

extension TokenCompletion where Candidate == RepoCandidate {
    /// Nil when no `repo:` token ends at the caret or the token at `dismissedStart` is the one there.
    public static func open(
        text: String, caret: Int, dismissedStart: Int?, repos: RepoIndex
    ) -> RepoCompletion? {
        token(.repo, text: text, caret: caret, dismissedStart: dismissedStart).map {
            RepoCompletion(token: $0, candidates: repos.candidates(prefix: $0.prefix), selection: 0)
        }
    }
}

/// The one completion list the search field can show: people for an `@` token, labels for a `~` token,
/// states and conditions for an `is:` token, board Status columns for a `status:` token, time steps for an
/// `updated:` token, review filters for a `review:` token, repositories for a `repo:` token.
public enum SearchCompletion: Equatable, Sendable {
    case people(PersonCompletion)
    case labels(LabelCompletion)
    case states(StateCompletion)
    case statuses(StatusCompletion)
    case updated(UpdatedCompletion)
    case reviews(ReviewCompletion)
    case repos(RepoCompletion)

    /// The list for the token at the caret, of whichever kind it is.
    public static func open(
        text: String, caret: Int, dismissedStart: Int?, people: PeopleIndex, labels: LabelIndex,
        statuses: StatusIndex = .empty, repos: RepoIndex = .empty
    ) -> SearchCompletion? {
        if let completion = PersonCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart, people: people) {
            return .people(completion)
        }
        if let completion = LabelCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart, labels: labels) {
            return .labels(completion)
        }
        if let completion = StateCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart) {
            return .states(completion)
        }
        if let completion = StatusCompletion.open(
            text: text, caret: caret, dismissedStart: dismissedStart, statuses: statuses) {
            return .statuses(completion)
        }
        if let completion = ReviewCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart) {
            return .reviews(completion)
        }
        if let completion = RepoCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart, repos: repos) {
            return .repos(completion)
        }
        return UpdatedCompletion.open(text: text, caret: caret, dismissedStart: dismissedStart)
            .map(SearchCompletion.updated)
    }

    public var token: PendingToken {
        switch self {
        case .people(let c): c.token
        case .labels(let c): c.token
        case .states(let c): c.token
        case .statuses(let c): c.token
        case .updated(let c): c.token
        case .reviews(let c): c.token
        case .repos(let c): c.token
        }
    }

    public var selection: Int {
        switch self {
        case .people(let c): c.selection
        case .labels(let c): c.selection
        case .states(let c): c.selection
        case .statuses(let c): c.selection
        case .updated(let c): c.selection
        case .reviews(let c): c.selection
        case .repos(let c): c.selection
        }
    }

    public var hasCandidates: Bool {
        switch self {
        case .people(let c): !c.candidates.isEmpty
        case .labels(let c): !c.candidates.isEmpty
        case .states(let c): !c.candidates.isEmpty
        case .statuses(let c): !c.candidates.isEmpty
        case .updated(let c): !c.candidates.isEmpty
        case .reviews(let c): !c.candidates.isEmpty
        case .repos(let c): !c.candidates.isEmpty
        }
    }

    public func moved(by offset: Int) -> SearchCompletion {
        switch self {
        case .people(let c): .people(c.moved(by: offset))
        case .labels(let c): .labels(c.moved(by: offset))
        case .states(let c): .states(c.moved(by: offset))
        case .statuses(let c): .statuses(c.moved(by: offset))
        case .updated(let c): .updated(c.moved(by: offset))
        case .reviews(let c): .reviews(c.moved(by: offset))
        case .repos(let c): .repos(c.moved(by: offset))
        }
    }

    public func accepted(in text: String) -> (text: String, caret: Int)? {
        switch self {
        case .people(let c): c.accepted(in: text)
        case .labels(let c): c.accepted(in: text)
        case .states(let c): c.accepted(in: text)
        case .statuses(let c): c.accepted(in: text)
        case .updated(let c): c.accepted(in: text)
        case .reviews(let c): c.accepted(in: text)
        case .repos(let c): c.accepted(in: text)
        }
    }

    /// Same kind with the same rows (selection aside).
    func hasSameCandidates(as other: SearchCompletion) -> Bool {
        switch (self, other) {
        case (.people(let a), .people(let b)): a.candidates == b.candidates
        case (.labels(let a), .labels(let b)): a.candidates == b.candidates
        case (.states(let a), .states(let b)): a.candidates == b.candidates
        case (.statuses(let a), .statuses(let b)): a.candidates == b.candidates
        case (.updated(let a), .updated(let b)): a.candidates == b.candidates
        case (.reviews(let a), .reviews(let b)): a.candidates == b.candidates
        case (.repos(let a), .repos(let b)): a.candidates == b.candidates
        default: false
        }
    }

    var selectedID: String? {
        switch self {
        case .people(let c): c.selectedCandidate?.id
        case .labels(let c): c.selectedCandidate?.id
        case .states(let c): c.selectedCandidate?.id
        case .statuses(let c): c.selectedCandidate?.id
        case .updated(let c): c.selectedCandidate?.id
        case .reviews(let c): c.selectedCandidate?.id
        case .repos(let c): c.selectedCandidate?.id
        }
    }

    /// This list with the row `id` selected, or the first row when it is not listed.
    func selecting(_ id: String?) -> SearchCompletion {
        let index: Int?
        switch self {
        case .people(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .labels(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .states(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .statuses(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .updated(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .reviews(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        case .repos(let c): index = id.flatMap { id in c.candidates.firstIndex { $0.id == id } }
        }
        return moved(by: (index ?? 0) - selection)
    }
}
