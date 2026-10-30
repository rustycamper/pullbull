import Foundation

/// A name and a query, applied from the empty search field as if the query were typed.
public struct SavedSearch: Codable, Equatable, Identifiable, Sendable {
    public static let nameLimit = 40

    public var id: UUID
    public var name: String
    public var query: String

    public init(id: UUID = UUID(), name: String, query: String) {
        self.id = id
        self.name = name
        self.query = query
    }

    /// `name` trimmed, or nil when that is empty or longer than `nameLimit` characters.
    public static func validName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > nameLimit ? nil : trimmed
    }

    /// `query` trimmed, or nil when that is empty.
    public static func validQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The search with its name and query trimmed; nil when either is invalid.
    public static func validated(id: UUID = UUID(), name: String, query: String) -> SavedSearch? {
        guard let name = validName(name), let query = validQuery(query) else { return nil }
        return SavedSearch(id: id, name: name, query: query)
    }

    /// What a name field takes: at most `nameLimit` characters.
    public static func capped(_ name: String) -> String {
        String(name.prefix(nameLimit))
    }

    /// The name the save row starts with: the query, trimmed and capped.
    public static func defaultName(for query: String) -> String {
        capped(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The field's text after applying it: the query and a space, so typing goes on with a new term.
    public var fieldText: String { query + " " }

    /// The name is the query, as it starts out: its chip shows it as code.
    public var nameIsQuery: Bool { name == query }

    /// What VoiceOver reads for its chip in the hint panel; a name left as its query is read once.
    public var accessibilityLabel: String { nameIsQuery ? "\(name), saved search" : "\(name), saved search, \(query)" }
}

/// The saved searches in the owner's order. Every entry is valid (`SavedSearch.validated`); it encodes
/// as a plain JSON array.
public struct SavedSearches: Codable, Equatable, Sendable {
    public private(set) var items: [SavedSearch] = []

    public init() {}

    public init(from decoder: any Decoder) throws {
        // Entry by entry: a hand-edited or older entry that doesn't decode, or isn't valid, is dropped,
        // not kept half-working, and the others still load.
        var entries = try decoder.unkeyedContainer()
        while !entries.isAtEnd {
            if let entry = try? entries.decode(SavedSearch.self) {
                if let search = SavedSearch.validated(id: entry.id, name: entry.name, query: entry.query) {
                    items.append(search)
                }
            } else if (try? entries.decode(Skipped.self)) == nil {
                break
            }
        }
    }

    /// Steps over an entry that doesn't decode as a `SavedSearch`.
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(items)
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Appends the search; nil (and nothing saved) when the name or query is invalid.
    @discardableResult
    public mutating func add(id: UUID = UUID(), name: String, query: String) -> SavedSearch? {
        guard let search = SavedSearch.validated(id: id, name: name, query: query) else { return nil }
        items.append(search)
        return search
    }

    /// Replaces the name and query of `id`. Returns false, keeping the last valid value, when either is
    /// invalid or `id` isn't saved.
    @discardableResult
    public mutating func update(_ id: UUID, name: String, query: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let search = SavedSearch.validated(id: id, name: name, query: query) else { return false }
        items[index] = search
        return true
    }

    public mutating func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Moves the rows at `offsets` to before `destination`, as a list's drag reorder reports it.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moved = IndexSet(offsets.filter { items.indices.contains($0) })
        guard !moved.isEmpty else { return }
        let target = min(max(destination, 0), items.count)
        var rest = items.enumerated().filter { !moved.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moved.map { items[$0] }, at: target - moved.count(in: 0..<target))
        items = rest
    }

    /// Whether `query`, trimmed, is exactly (case included) a saved query.
    public func contains(query: String) -> Bool {
        guard let query = SavedSearch.validQuery(query) else { return false }
        return items.contains { $0.query == query }
    }
}

/// Settings' saved search table: the store's rows with the text typed into them, and a new row that
/// isn't saved until its name and query are valid.
///
/// A valid edit goes to the store at once (trimmed); an invalid one stays in the row, outlined, while
/// the store keeps the last valid value. `close()` (the window or tab closing) drops the typed text and
/// a new row that never became valid.
public struct SavedSearchEditor: Equatable, Sendable {
    public static let newRowName = "New search"

    public struct Row: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let query: String

        public init(id: UUID, name: String, query: String) {
            self.id = id
            self.name = name
            self.query = query
        }

        public var nameIsValid: Bool { SavedSearch.validName(name) != nil }
        public var queryIsValid: Bool { SavedSearch.validQuery(query) != nil }
        public var isValid: Bool { nameIsValid && queryIsValid }
    }

    /// The text in rows edited since the editor opened, by ID.
    private var typed: [UUID: Row] = [:]
    /// The "+" row, until it is first valid.
    private var unsaved: UUID?
    /// Between `close()` and `open()`: a field unfocused after the tab closed can still push its text
    /// back, and that edit must not bring a draft back.
    private var closed = false

    public init() {}

    /// The store's rows as typed, then the unsaved row.
    public func rows(in saved: SavedSearches) -> [Row] {
        let stored = saved.items.map { typed[$0.id] ?? Row(id: $0.id, name: $0.name, query: $0.query) }
        guard let unsaved else { return stored }
        return stored + [typed[unsaved] ?? Row(id: unsaved, name: Self.newRowName, query: "")]
    }

    /// "+": a row named "New search" with an empty query, or the unsaved one already there.
    public mutating func addRow() -> UUID {
        if let unsaved { return unsaved }
        let id = UUID()
        unsaved = id
        typed[id] = Row(id: id, name: Self.newRowName, query: "")
        return id
    }

    /// The row's fields changed: valid text is saved, the unsaved row joining the store. Ignored while closed.
    public mutating func edit(_ id: UUID, name: String, query: String, in saved: inout SavedSearches) {
        guard !closed, id == unsaved || saved.items.contains(where: { $0.id == id }) else { return }
        typed[id] = Row(id: id, name: name, query: query)
        if id == unsaved {
            if saved.add(id: id, name: name, query: query) != nil { unsaved = nil }
        } else {
            saved.update(id, name: name, query: query)
        }
    }

    /// "−": the row goes, saved or not, without confirmation.
    public mutating func delete(_ id: UUID, in saved: inout SavedSearches) {
        typed[id] = nil
        if id == unsaved { unsaved = nil } else { saved.remove(id) }
    }

    /// A drag reorder over `rows(in:)`. The unsaved row stays last: dragging it does nothing, and a
    /// drop below it lands above it.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int, in saved: inout SavedSearches) {
        let count = saved.items.count
        guard offsets.allSatisfy({ $0 < count }) else { return }
        saved.move(fromOffsets: offsets, toOffset: min(destination, count))
    }

    /// The window or tab closed: rows show the store again, and edits are ignored until `open()`.
    public mutating func close() {
        typed = [:]
        unsaved = nil
        closed = true
    }

    /// The tab is on screen again: edits count.
    public mutating func open() {
        closed = false
    }
}

extension SearchFieldState {
    /// Fills the field with a saved search's query and a trailing space, the caret at the end, as if it
    /// were typed, and returns the query to search for.
    @discardableResult
    public mutating func apply(
        _ saved: SavedSearch, people: PeopleIndex, labels: LabelIndex, statuses: StatusIndex = .empty,
        repos: RepoIndex = .empty
    ) -> SearchQuery? {
        forgetCompletion()
        let text = saved.fieldText
        let query = edit(
            text, caret: text.utf16.count, people: people, labels: labels, statuses: statuses, repos: repos)
        forgetCompletion()
        return query
    }
}
