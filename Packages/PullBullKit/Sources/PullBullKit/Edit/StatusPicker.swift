import Foundation

/// One row of the Status picker: a board option, or Clear Status.
public struct StatusPickerRow: Equatable, Sendable, Identifiable {
    /// Nil for Clear Status.
    public let option: StatusOption?
    /// Open issues in the column, as `status:` counts them; nil for Clear Status.
    public let openCount: Int?
    public let isCurrent: Bool

    public var id: String { option?.id ?? "clear" }
    public var name: String { option?.name ?? "Clear Status" }
}

/// The Status picker for one issue: the board's options in board order, then Clear Status when the
/// issue has a Status, filtered by part of a name and with one row selected.
public struct StatusPicker: Equatable, Sendable {
    public let key: PRKey
    /// Whether this account may set Status; anything but `.ready` shows its note in place of the rows.
    public let permission: EditPermission
    public private(set) var filter = ""
    public private(set) var rows: [StatusPickerRow]
    public private(set) var selection = 0

    private let allRows: [StatusPickerRow]

    /// Names the issue in the picker's header, so an edit never lands on the wrong row: "acme/widgets#412".
    public var title: String { "\(key.repo)#\(key.number)" }

    /// Nil when Status isn't offered on the issue.
    public static func make(for key: PRKey, in snapshot: Snapshot, permission: EditPermission) -> StatusPicker? {
        guard StatusEdit.isOffered(key, in: snapshot), let options = snapshot.boardStatusOptions else { return nil }
        let current = snapshot.boardIssues.first { $0.key == key }?.status
        var counts: [String: Int] = [:]
        for issue in SearchEngine.cachedIssues(snapshot) where issue.isOpen {
            if let id = issue.status?.optionId { counts[id, default: 0] += 1 }
        }
        var seen = Set<String>()
        var rows = options.filter { seen.insert($0.id).inserted }.map {
            StatusPickerRow(option: $0, openCount: counts[$0.id] ?? 0, isCurrent: $0.id == current?.optionId)
        }
        if current != nil { rows.append(StatusPickerRow(option: nil, openCount: nil, isCurrent: false)) }
        return StatusPicker(key: key, permission: permission, rows: rows)
    }

    private init(key: PRKey, permission: EditPermission, rows: [StatusPickerRow]) {
        self.key = key
        self.permission = permission
        self.allRows = rows
        self.rows = rows
        self.selection = Self.start(in: rows)
    }

    public var selectedRow: StatusPickerRow? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// The Status the selected row sets: `.some(nil)` clears it; nil when no row is shown.
    public var pick: BoardStatusValue?? {
        guard let row = selectedRow else { return nil }
        return .some(row.option.map { BoardStatusValue(optionId: $0.id, name: $0.name) })
    }

    /// Keeps the rows whose name contains `text`, case ignored; selects the current row when shown.
    public mutating func setFilter(_ text: String) {
        filter = text
        let needle = text.trimmingCharacters(in: .whitespaces)
        rows = needle.isEmpty ? allRows : allRows.filter { $0.name.range(of: needle, options: .caseInsensitive) != nil }
        selection = Self.start(in: rows)
    }

    /// Steps the selection, stopping at the ends.
    public mutating func move(by offset: Int) {
        selection = min(max(selection + offset, 0), max(rows.count - 1, 0))
    }

    private static func start(in rows: [StatusPickerRow]) -> Int {
        rows.firstIndex(where: \.isCurrent) ?? 0
    }
}
