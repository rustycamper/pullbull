import Foundation

/// Sends a label, assignee or reviewer change, or its undo. A Status change sends nothing here.
public struct SetEditor: Sendable {
    private let api: GitHubAPI

    public init(api: GitHubAPI) {
        self.api = api
    }

    /// Sends `change` for the issue `key`, both halves in one request. `contentId` is the issue's node
    /// ID; it is looked up when an old cache lacks it. Throws when GitHub applied neither half; a
    /// result with one half refused is returned for the caller to show.
    public func apply(_ change: EditChange, on key: PRKey, contentId: String?) async throws -> SetChangeResult {
        switch change {
        case .status:
            return SetChangeResult(addApplied: true, removeApplied: true, refusal: nil)
        case .labels(let added, let removed):
            let subject = try await content(contentId, key)
            return try await api.changeLabels(of: subject, adding: added.map(\.id), removing: removed.map(\.id))
        case .assignees(let added, let removed):
            let subject = try await content(contentId, key)
            return try await api.changeAssignees(of: subject, adding: added.map(\.id), removing: removed.map(\.id))
        case .reviewers(let added, let removed):
            return try await api.changeReviewers(of: key, adding: added, removing: removed)
        }
    }

    private func content(_ contentId: String?, _ key: PRKey) async throws -> String {
        if let contentId { return contentId }
        return try await api.nodeId(of: key)
    }
}
