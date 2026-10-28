import Foundation

/// The placeholder rows a list shows before its first data. They copy the real list's layout, so the
/// data replaces them in place: whether the first rows sit under a group header, as they will once loaded.
public enum ListSkeleton {
    public static let rowCount = 5

    /// PR lists group by repository unless the setting is off or a focus narrows them to one repo.
    public static func prLeadsWithHeader(grouping: Grouping, focused: Bool) -> Bool {
        grouping == .repository && !focused
    }

    /// Issue lists: Created follows the grouping setting; Assigned and Board group by board Status when
    /// it is known, else by repository. A focus merges repository groups into one untitled group but
    /// keeps Status groups. `statusKnown` nil (no data yet) assumes the board's Status columns.
    public static func issueLeadsWithHeader(
        tab: IssueTab, grouping: Grouping, focused: Bool, statusKnown: Bool?
    ) -> Bool {
        switch tab {
        case .created: return grouping == .repository && !focused
        case .assigned, .board: return !focused || (statusKnown ?? true)
        }
    }
}
