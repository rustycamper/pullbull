import Foundation

/// One row of the assignee or label picker.
public struct SetPickerRow: Equatable, Sendable, Identifiable {
    public let candidate: SetCandidate
    public let isChecked: Bool
    /// False for an unticked person at the 10-assignee limit, and for a ticked value with no candidate.
    public let isEnabled: Bool

    public var id: String { candidate.id }
}

/// The multi-select picker for an issue's labels or assignees: ticked values first, filtered by part of a
/// name, with one row highlighted. Closing sends only what changed.
public struct SetPicker: Equatable, Sendable {
    /// GitHub's limit on an issue's assignees.
    public static let assigneeLimit = 10

    public let key: PRKey
    /// `.labels` or `.assignees`.
    public let field: EditField
    /// Whether this account may edit the field; anything but `.ready` shows its note in place of the rows.
    public let permission: EditPermission
    public private(set) var filter = ""
    public private(set) var rows: [SetPickerRow] = []
    public private(set) var selection = 0
    /// True until the first load or failure.
    public private(set) var isLoading = true
    public private(set) var loadError: String?
    /// False when a filter asks GitHub, because the people list stopped at 100.
    public private(set) var isComplete = true

    private struct Entry: Equatable, Sendable {
        var candidate: SetCandidate
        var isChecked: Bool
        let wasChecked: Bool
        var isPlaceholder: Bool
    }

    private let currentNames: [String]
    private let viewer: String
    private var entries: [Entry] = []

    /// Names the issue in the picker's header, so an edit never lands on the wrong row: "acme/widgets#412".
    public var title: String { "\(key.repo)#\(key.number)" }

    /// `current`: the label names or logins the issue shows now (overrides applied); `viewer`: the signed-in login.
    public init(field: EditField, key: PRKey, current: [String], viewer: String, permission: EditPermission) {
        self.field = field
        self.key = key
        self.currentNames = current
        self.viewer = viewer
        self.permission = permission
    }

    /// The first load fixes the rows' order and ticks; later loads (more people, a filter's answer) only
    /// append candidates not seen yet. `fromQuery`: an answer to a filter query, which leaves `isComplete` alone.
    public mutating func load(_ candidates: SetCandidates, fromQuery: Bool = false) {
        if !fromQuery { isComplete = candidates.complete }
        let highlighted = selectedRow?.id
        var replaced: [String: String] = [:]

        var pool: [SetCandidate] = []
        var seen = Set<String>()
        for candidate in candidates.all + candidates.current where seen.insert(Self.fold(candidate.name)).inserted {
            pool.append(candidate)
        }

        if isLoading {
            entries = firstEntries(from: pool)
        } else {
            var known = Set(entries.map { Self.fold($0.candidate.name) })
            var fresh: [SetCandidate] = []
            for candidate in pool {
                let name = Self.fold(candidate.name)
                if let index = entries.firstIndex(where: { $0.isPlaceholder && Self.fold($0.candidate.name) == name }) {
                    replaced[entries[index].candidate.id] = candidate.id
                    entries[index].candidate = candidate
                    entries[index].isPlaceholder = false
                } else if known.insert(name).inserted {
                    fresh.append(candidate)
                }
            }
            entries += ordered(fresh).map { Entry(candidate: $0, isChecked: false, wasChecked: false, isPlaceholder: false) }
        }

        isLoading = false
        loadError = nil
        refresh(keeping: highlighted.map { replaced[$0] ?? $0 })
    }

    /// Only before the first load; with cached candidates on screen a failed refetch changes nothing.
    public mutating func failedToLoad(_ message: String) {
        guard isLoading else { return }
        isLoading = false
        loadError = message
    }

    /// Keeps the rows whose name contains `text`, case ignored; highlights the first.
    public mutating func setFilter(_ text: String) {
        filter = text
        refresh(keeping: nil)
    }

    /// Steps the selection, stopping at the ends.
    public mutating func move(by offset: Int) {
        selection = min(max(selection + offset, 0), max(rows.count - 1, 0))
    }

    /// Ticks or unticks the highlighted row; a disabled row stays as it is.
    public mutating func toggleSelected() {
        guard let row = selectedRow, row.isEnabled,
              let index = entries.firstIndex(where: { $0.candidate.id == row.id }) else { return }
        entries[index].isChecked.toggle()
        refresh(keeping: row.id)
    }

    /// What closing sends; nil when nothing changed.
    public var change: EditChange? {
        let added = entries.filter { $0.isChecked && !$0.wasChecked }.map(\.candidate)
        let removed = entries.filter { !$0.isChecked && $0.wasChecked }.map(\.candidate)
        guard !added.isEmpty || !removed.isEmpty else { return nil }
        if field == .labels {
            return .labels(added: added.map(labelRef), removed: removed.map(labelRef))
        }
        return .assignees(added: added.map(personRef), removed: removed.map(personRef))
    }

    private var selectedRow: SetPickerRow? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    private var isPeople: Bool { field != .labels }

    private func labelRef(_ candidate: SetCandidate) -> LabelRef {
        LabelRef(id: candidate.id, name: candidate.name, color: candidate.color)
    }

    private func personRef(_ candidate: SetCandidate) -> PersonRef {
        PersonRef(id: candidate.id, login: candidate.name, avatarURL: candidate.avatarURL)
    }

    /// Ticked rows in `current` order, then the viewer when unticked (people only), then the rest.
    private func firstEntries(from pool: [SetCandidate]) -> [Entry] {
        var byName: [String: SetCandidate] = [:]
        for candidate in pool { byName[Self.fold(candidate.name)] = candidate }
        var used = Set<String>()
        var result: [Entry] = []
        for name in currentNames where used.insert(Self.fold(name)).inserted {
            if let candidate = byName[Self.fold(name)] {
                result.append(Entry(candidate: candidate, isChecked: true, wasChecked: true, isPlaceholder: false))
            } else {
                let placeholder = SetCandidate(id: "missing:\(name)", name: name)
                result.append(Entry(candidate: placeholder, isChecked: true, wasChecked: true, isPlaceholder: true))
            }
        }
        if isPeople, used.insert(Self.fold(viewer)).inserted, let candidate = byName[Self.fold(viewer)] {
            result.append(Entry(candidate: candidate, isChecked: false, wasChecked: false, isPlaceholder: false))
        }
        let rest = ordered(pool.filter { !used.contains(Self.fold($0.name)) })
        return result + rest.map { Entry(candidate: $0, isChecked: false, wasChecked: false, isPlaceholder: false) }
    }

    /// Labels keep GitHub's order; people sort by login, case ignored.
    private func ordered(_ candidates: [SetCandidate]) -> [SetCandidate] {
        guard isPeople else { return candidates }
        return candidates.sorted { Self.fold($0.name) < Self.fold($1.name) }
    }

    /// Rebuilds `rows` from the entries and the filter; the highlight follows `id` when its row is shown.
    private mutating func refresh(keeping id: String?) {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let atLimit = isPeople && entries.filter(\.isChecked).count >= Self.assigneeLimit
        rows = entries
            .filter { needle.isEmpty || $0.candidate.name.range(of: needle, options: .caseInsensitive) != nil }
            .map { SetPickerRow(
                candidate: $0.candidate,
                isChecked: $0.isChecked,
                isEnabled: !$0.isPlaceholder && ($0.isChecked || !atLimit)) }
        if let id, let index = rows.firstIndex(where: { $0.id == id }) {
            selection = index
        } else {
            selection = min(selection, max(rows.count - 1, 0))
            if id == nil { selection = 0 }
        }
    }

    private static func fold(_ text: String) -> String { text.lowercased() }
}
