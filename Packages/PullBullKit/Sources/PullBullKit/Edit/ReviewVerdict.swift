import Foundation

/// The two verdicts a review can be submitted with; the raw value is GitHub's `event`.
public enum ReviewVerdict: String, CaseIterable, Sendable {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"

    /// The review state GitHub records for this verdict.
    public var state: ReviewState {
        switch self {
        case .approve: .approved
        case .requestChanges: .changesRequested
        }
    }

    public var title: String {
        switch self {
        case .approve: "Approve"
        case .requestChanges: "Request changes"
        }
    }
}

/// A pull request's head commit and state at one moment.
public struct PRHead: Equatable, Sendable {
    public let oid: String
    public let state: PRState

    public init(oid: String, state: PRState) {
        self.oid = oid
        self.state = state
    }
}
