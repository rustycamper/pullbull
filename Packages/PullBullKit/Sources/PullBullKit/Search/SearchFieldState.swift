import Foundation

/// The search field's text, its "@user", "~label", "is:state" or "status:column" completion and the query searched for.
/// Each change returns the query to search for, or nil when the results stay as they are.
///
/// - Typing at the end of an `@`, `~`, `is:` or `status:` token opens its list; the token is left out of the query
///   while it is picked, so typing inside it never changes the results.
/// - A caret move can close the list (the token then counts as typed) but never opens it.
/// - Esc closes the list and searches with the token; it stays closed on that token until text
///   replaces it with a fresh `@`.
/// - `close()` (popover hidden, a detail opened) closes the list without searching; `isStale` then says
///   the next rerun has a different query.
public struct SearchFieldState: Equatable, Sendable {
    public private(set) var text = ""
    /// The open list, people, labels, states or Status columns.
    public private(set) var searchCompletion: SearchCompletion?
    /// The query last searched for.
    public private(set) var query: SearchQuery = .empty
    /// The field editor's caret (UTF-16) as last reported; nil when unknown.
    public private(set) var caret: Int?
    /// UTF-16 start of the token the list was closed on, so it doesn't reopen there.
    private var dismissedStart: Int?
    /// The kind of that token: a dismissal holds only while the same sigil starts there.
    private var dismissedKind: PendingToken.Kind?

    public init() {}

    /// The open "@user" list; nil when none is open or the list is of another kind.
    public var completion: PersonCompletion? {
        if case .people(let completion) = searchCompletion { return completion }
        return nil
    }

    /// The open "~label" list; nil when none is open or the list is of another kind.
    public var labelCompletion: LabelCompletion? {
        if case .labels(let completion) = searchCompletion { return completion }
        return nil
    }

    /// The open "is:" list; nil when none is open or the list is of another kind.
    public var stateCompletion: StateCompletion? {
        if case .states(let completion) = searchCompletion { return completion }
        return nil
    }

    /// The open "status:" list; nil when none is open or the list is of another kind.
    public var statusCompletion: StatusCompletion? {
        if case .statuses(let completion) = searchCompletion { return completion }
        return nil
    }

    /// The open "updated:" list; nil when none is open or the list is of another kind.
    public var updatedCompletion: UpdatedCompletion? {
        if case .updated(let completion) = searchCompletion { return completion }
        return nil
    }

    /// The open "review:" list; nil when none is open or the list is of another kind.
    public var reviewCompletion: ReviewCompletion? {
        if case .reviews(let completion) = searchCompletion { return completion }
        return nil
    }

    /// The open "repo:" list; nil when none is open or the list is of another kind.
    public var repoCompletion: RepoCompletion? {
        if case .repos(let completion) = searchCompletion { return completion }
        return nil
    }

    /// The open "size:" list; nil when none is open or the list is of another kind.
    public var sizeCompletion: SizeCompletion? {
        if case .sizes(let completion) = searchCompletion { return completion }
        return nil
    }

    /// Whether the text, read without an open completion, asks for a different query than the last one.
    public var isStale: Bool { pendingQuery != query }

    /// Text from the field or an entry point, with the field editor's caret (UTF-16) when known. Without
    /// a caret, a text change closes the list and the same text searches again.
    @discardableResult
    public mutating func edit(
        _ text: String, caret: Int?, people: PeopleIndex, labels: LabelIndex = .empty,
        statuses: StatusIndex = .empty, repos: RepoIndex = .empty
    ) -> SearchQuery? {
        let changed = text != self.text
        // A rerun of the same text without a caret leaves the last one standing.
        if changed || caret != nil { self.caret = caret }
        if changed, let start = dismissedStart, !Self.dismissalHolds(at: start, kind: dismissedKind, in: text) {
            dismissedStart = nil
            dismissedKind = nil
        }
        self.text = text
        if let caret {
            searchCompletion = Self.merge(
                SearchCompletion.open(
                    text: text, caret: caret, dismissedStart: dismissedStart, people: people, labels: labels,
                    statuses: statuses, repos: repos),
                into: searchCompletion)
        } else if changed {
            searchCompletion = nil
        }
        return search(rerun: !changed && caret == nil)
    }

    /// The caret moved without a text change: keeps the list on the same token or closes it.
    @discardableResult
    public mutating func caretMoved(
        to caret: Int, people: PeopleIndex, labels: LabelIndex = .empty, statuses: StatusIndex = .empty,
        repos: RepoIndex = .empty
    ) -> SearchQuery? {
        self.caret = caret
        guard let current = searchCompletion else { return nil }
        let fresh = SearchCompletion.open(
            text: text, caret: caret, dismissedStart: dismissedStart, people: people, labels: labels,
            statuses: statuses, repos: repos)
        searchCompletion = fresh?.token.start == current.token.start ? Self.merge(fresh, into: current) : nil
        return search(rerun: false)
    }

    public mutating func move(by offset: Int) {
        searchCompletion = searchCompletion?.moved(by: offset)
    }

    /// Esc, or Return with no candidate: the token counts as typed and the list stays closed on it.
    @discardableResult
    public mutating func dismiss() -> SearchQuery? {
        guard let open = searchCompletion else { return nil }
        dismissedStart = open.token.start
        dismissedKind = open.token.kind
        searchCompletion = nil
        return search(rerun: false)
    }

    /// Closes the list as `dismiss()` does but searches nothing; `isStale` tells whether a rerun is due.
    public mutating func close() {
        guard let open = searchCompletion else { return }
        dismissedStart = open.token.start
        dismissedKind = open.token.kind
        searchCompletion = nil
    }

    /// Drops the list and any dismissal (search cancelled, or replaced by an entry point).
    public mutating func forgetCompletion() {
        searchCompletion = nil
        dismissedStart = nil
        dismissedKind = nil
    }

    /// New people, labels, Status columns and repositories (a refresh): the open list takes their candidates and keeps
    /// the selected row.
    public mutating func refresh(
        people: PeopleIndex, labels: LabelIndex = .empty, statuses: StatusIndex = .empty, repos: RepoIndex = .empty
    ) {
        guard let open = searchCompletion,
              let fresh = SearchCompletion.open(
                text: text, caret: open.token.end, dismissedStart: nil, people: people, labels: labels,
                statuses: statuses, repos: repos),
              !fresh.hasSameCandidates(as: open) else { return }
        searchCompletion = fresh.selecting(open.selectedID)
    }

    /// Text is selected: there is no caret until the next move reports one.
    public mutating func forgetCaret() {
        caret = nil
    }

    /// The qualifier the word at the caret starts, while no list is open; `status:` only with Status
    /// columns to pick from.
    public func ghost(statuses: StatusIndex) -> QualifierGhost? {
        guard searchCompletion == nil, let caret else { return nil }
        return QualifierGhost.at(caret: caret, in: text, statuses: !statuses.isEmpty)
    }

    private var pendingQuery: SearchQuery {
        SearchQuery.parse(text, excluding: searchCompletion?.token.range(in: text))
    }

    private mutating func search(rerun: Bool) -> SearchQuery? {
        let next = pendingQuery
        guard rerun || next != query else { return nil }
        query = next
        return next
    }

    /// The open list on the same token keeps its selection while the candidates are the same.
    private static func merge(_ fresh: SearchCompletion?, into current: SearchCompletion?) -> SearchCompletion? {
        guard let fresh, let current, fresh.token.start == current.token.start,
              fresh.hasSameCandidates(as: current) else { return fresh }
        return fresh.token == current.token ? current : fresh.moved(by: current.selection)
    }

    /// A dismissal holds while a token of the same kind, with at least one character after the sigil,
    /// still starts there.
    private static func dismissalHolds(at start: Int, kind: PendingToken.Kind?, in text: String) -> Bool {
        guard PendingToken.startsToken(at: start, in: text, kind: kind),
              let next = PendingToken.sigilEnd(in: text, at: String.Index(utf16Offset: start, in: text), of: kind)
        else { return false }
        let scalars = text.unicodeScalars
        return next < scalars.endIndex && !scalars[next].properties.isWhitespace
    }
}
