import Foundation

/// One row of the reviewer, assignee or label picker.
public struct SetPickerRow: Equatable, Sendable, Identifiable {
    public let candidate: SetCandidate
    public let isChecked: Bool
    /// False for an unticked person at the 10-assignee limit, and for a ticked label or assignee with no
    /// candidate (a requested reviewer without one can still be unticked).
    public let isEnabled: Bool
    /// A reviewer who was requested when the picker opened, has reviewed, and is now unticked: unticking
    /// takes back the request, never the review.
    public let reviewStays: Bool

    public var id: String { candidate.id }
}

/// The multi-select picker for an issue's labels or assignees, or a pull request's reviewers: ticked values
/// first, filtered by part of a name, with one row highlighted. Closing sends only what changed.
public struct SetPicker: Equatable, Sendable {
    /// GitHub's limit on an issue's assignees.
    public static let assigneeLimit = 10

    public let key: PRKey
    /// `.labels`, `.assignees` or `.reviewers`.
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

    /// What is set now, in order, standing in for any value no candidate matches.
    private let currentPlaceholders: [SetCandidate]
    private let viewer: String
    private var entries: [Entry] = []
    private var hasBuilt = false
    private var hasToggled = false

    /// Names the issue in the picker's header, so an edit never lands on the wrong row: "acme/widgets#412".
    public var title: String { "\(key.repo)#\(key.number)" }

    /// `current`: the label names or logins the issue shows now (overrides applied); `viewer`: the signed-in login.
    public init(field: EditField, key: PRKey, current: [String], viewer: String, permission: EditPermission) {
        self.field = field
        self.key = key
        self.currentPlaceholders = current.map { SetCandidate(id: "missing:\($0)", name: $0) }
        self.viewer = viewer
        self.permission = permission
    }

    /// The reviewers picker: `requested` are the pull request's review requests now (overrides applied).
    public init(reviewersOf key: PRKey, requested: [Reviewer], viewer: String, permission: EditPermission) {
        self.field = .reviewers
        self.key = key
        self.currentPlaceholders = requested.map { reviewer in
            let slug: String? = if case .team(let slug, _) = reviewer { slug } else { nil }
            return SetCandidate(id: "missing:\(reviewer.key)", name: reviewer.displayName, team: slug)
        }
        self.viewer = viewer
        self.permission = permission
    }

    /// The first load fixes the rows' order and ticks; later loads (more people, a filter's answer) only
    /// append candidates not seen yet; a candidate whose id a row already has updates that row in place.
    /// The reviewers picker reorders on every load but a filter's until a row is ticked or unticked, so
    /// past reviewers and suggested people find their place when the pull request's own answer comes.
    /// `fromQuery`: an answer to a filter query, which leaves `isComplete` alone.
    public mutating func load(_ candidates: SetCandidates, fromQuery: Bool = false) {
        if !fromQuery { isComplete = candidates.complete }
        let highlighted = selectedRow?.id
        var replaced: [String: String] = [:]

        var pool: [SetCandidate] = []
        var seen = Set<String>()
        for candidate in candidates.all + candidates.current where seen.insert(candidate.key).inserted {
            pool.append(candidate)
        }

        if !hasBuilt || (field == .reviewers && !hasToggled && !fromQuery) {
            entries = firstEntries(from: pool)
        } else {
            var known = Set(entries.map(\.candidate.key))
            var fresh: [SetCandidate] = []
            for candidate in pool {
                let name = candidate.key
                if let index = entries.firstIndex(where: { $0.isPlaceholder && $0.candidate.key == name }) {
                    replaced[entries[index].candidate.id] = candidate.id
                    entries[index].candidate = candidate
                    entries[index].isPlaceholder = false
                    // A label renamed since it was cached: the stale row for this id folds into the placeholder.
                    entries.removeAll { $0.candidate.id == candidate.id && !$0.isPlaceholder && $0.candidate != candidate }
                    known.insert(name)
                } else if let index = entries.firstIndex(where: { $0.candidate.id == candidate.id }) {
                    known.remove(entries[index].candidate.key)
                    entries[index].candidate = candidate
                    known.insert(name)
                } else if known.insert(name).inserted {
                    fresh.append(candidate)
                }
            }
            entries += ordered(fresh).map { Entry(candidate: $0, isChecked: false, wasChecked: false, isPlaceholder: false) }
        }

        hasBuilt = true
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
        hasToggled = true
        refresh(keeping: row.id)
    }

    /// What closing sends; nil when nothing changed.
    public var change: EditChange? {
        let added = entries.filter { $0.isChecked && !$0.wasChecked }.map(\.candidate)
        let removed = entries.filter { !$0.isChecked && $0.wasChecked }.map(\.candidate)
        guard !added.isEmpty || !removed.isEmpty else { return nil }
        switch field {
        case .labels: return .labels(added: added.map(labelRef), removed: removed.map(labelRef))
        case .reviewers: return .reviewers(added: added.map(\.reviewer), removed: removed.map(\.reviewer))
        case .assignees, .status, .comment, .review, .merge, .rerun, .draft:
            return .assignees(added: added.map(personRef), removed: removed.map(personRef))
        }
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

    /// Ticked rows in `current` order, then past reviewers (reviewers only), then the viewer when unticked
    /// (people only), then the rest.
    private func firstEntries(from pool: [SetCandidate]) -> [Entry] {
        var byKey: [String: SetCandidate] = [:]
        for candidate in pool { byKey[candidate.key] = candidate }
        var used = Set<String>()
        var result: [Entry] = []
        for placeholder in currentPlaceholders where used.insert(placeholder.key).inserted {
            if let candidate = byKey[placeholder.key] {
                result.append(Entry(candidate: candidate, isChecked: true, wasChecked: true, isPlaceholder: false))
            } else {
                result.append(Entry(candidate: placeholder, isChecked: true, wasChecked: true, isPlaceholder: true))
            }
        }
        if field == .reviewers {
            for candidate in pool where candidate.verdict != nil && used.insert(candidate.key).inserted {
                result.append(Entry(candidate: candidate, isChecked: false, wasChecked: false, isPlaceholder: false))
            }
        }
        let viewerKey = viewer.lowercased()
        if isPeople, used.insert(viewerKey).inserted, let candidate = byKey[viewerKey] {
            result.append(Entry(candidate: candidate, isChecked: false, wasChecked: false, isPlaceholder: false))
        }
        let rest = ordered(pool.filter { !used.contains($0.key) })
        return result + rest.map { Entry(candidate: $0, isChecked: false, wasChecked: false, isPlaceholder: false) }
    }

    /// Labels keep GitHub's order; people sort by login, case ignored. Reviewers: suggested people first,
    /// then the others by login, then teams in GitHub's order.
    private func ordered(_ candidates: [SetCandidate]) -> [SetCandidate] {
        guard isPeople else { return candidates }
        let byLogin = { (list: [SetCandidate]) in list.sorted { $0.key < $1.key } }
        guard field == .reviewers else { return byLogin(candidates) }
        let people = candidates.filter { $0.team == nil }
        return people.filter(\.isSuggested) + byLogin(people.filter { !$0.isSuggested })
            + candidates.filter { $0.team != nil }
    }

    /// Rebuilds `rows` from the entries and the filter; the highlight follows `id` when its row is shown.
    private mutating func refresh(keeping id: String?) {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let atLimit = field == .assignees && entries.filter(\.isChecked).count >= Self.assigneeLimit
        rows = entries
            .filter { needle.isEmpty || $0.candidate.name.range(of: needle, options: .caseInsensitive) != nil }
            .map { SetPickerRow(
                candidate: $0.candidate,
                isChecked: $0.isChecked,
                isEnabled: (!$0.isPlaceholder || field == .reviewers) && ($0.isChecked || !atLimit),
                reviewStays: $0.wasChecked && !$0.isChecked && $0.candidate.verdict != nil) }
        if let id, let index = rows.firstIndex(where: { $0.id == id }) {
            selection = index
        } else {
            selection = min(selection, max(rows.count - 1, 0))
            if id == nil { selection = 0 }
        }
    }

}
