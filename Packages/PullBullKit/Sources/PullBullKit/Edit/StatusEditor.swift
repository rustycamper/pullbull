import Foundation

/// Why an edit couldn't be sent at all.
public enum EditError: Error, LocalizedError, Equatable {
    /// The snapshot has no project or Status field IDs yet (one cached before they were stored).
    case boardNotLoaded

    public var errorDescription: String? {
        switch self {
        case .boardNotLoaded: "the board hasn't finished loading. Try again in a moment"
        }
    }
}

/// Sends a Status change, or its undo, to the shown board.
public struct StatusEditor: Sendable {
    private let api: GitHubAPI

    public init(api: GitHubAPI) {
        self.api = api
    }

    /// Sends `change` for the issue `key`. `itemId` is its board item's node ID, `contentId` the issue's;
    /// either may be missing from an old cache and is then found on GitHub. Returns the board item an
    /// `.added` change created, which its undo deletes; nil otherwise. Label and assignee changes send
    /// nothing here.
    public func apply(
        _ change: EditChange, on key: PRKey, itemId: String?, contentId: String?, board: BoardIds?
    ) async throws -> String? {
        guard case .status(_, let to, let placement) = change else { return nil }
        guard let board, let field = board.statusFieldId else { throw EditError.boardNotLoaded }
        let project = board.projectId
        switch placement {
        case .removed:
            guard let itemId else { throw EditError.boardNotLoaded }
            try await api.deleteProjectItem(project: project, item: itemId)
            return nil
        case .already:
            // Adding an issue already on the board returns its existing item.
            let item = if let itemId { itemId } else {
                try await api.addToProject(project: project, content: content(contentId, key))
            }
            try await api.setStatus(project: project, item: item, field: field, option: to?.optionId)
            return nil
        case .added:
            let item = try await api.addToProject(project: project, content: content(contentId, key))
            guard let to else { return item }
            do {
                try await api.setStatus(project: project, item: item, field: field, option: to.optionId)
            } catch {
                // Don't leave a card in No Status behind.
                try? await api.deleteProjectItem(project: project, item: item)
                throw error
            }
            return item
        }
    }

    private func content(_ contentId: String?, _ key: PRKey) async throws -> String {
        if let contentId { return contentId }
        return try await api.nodeId(of: key)
    }
}
