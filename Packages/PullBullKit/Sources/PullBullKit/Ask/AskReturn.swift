import Foundation

/// Where Back, Esc and a popover reopen land for the Ask screen and the details opened from it. Route
/// agnostic: the app maps its own `Route` to `Place` and back.
public struct AskReturn: Equatable, Sendable {
    public enum Place: Equatable, Sendable {
        case search, list, ask, issueDetail, pullRequestDetail
    }

    /// Where the popover is, and the search field's text.
    public struct Landing: Equatable, Sendable {
        public let place: Place
        public let searchText: String
    }

    /// Where each open detail returns to, innermost last.
    private var openers: [Place] = []

    public init() {}

    /// A detail opens from `place`. An issue opened from Ask pushes `.ask`; a PR linked from that issue
    /// pushes `.issueDetail`.
    public mutating func open(from place: Place) { openers.append(place) }

    /// The innermost detail closes: back to its opener, `.list` when nothing is open.
    public mutating func close() -> Place { openers.popLast() ?? .list }

    /// The back button's title for the innermost detail: "Ask results" only when Ask opened it.
    public var backTitle: String? { openers.last == .ask ? "Ask results" : nil }

    /// Leaving Ask or the popover closing drops every open detail.
    public mutating func reset() { openers.removeAll() }

    /// Esc on the Ask screen: the search field, with the question kept.
    public static func leavingAsk(question: String) -> Landing {
        Landing(place: .search, searchText: question)
    }

    /// The popover opening again. Within `PopoverReopen.keepDetailFor` it stays where it was; after that
    /// it opens on search with the question kept.
    public static func reopening(at place: Place, question: String, closedAt: Date, now: Date) -> Landing {
        if PopoverReopen.showsList(closedAt: closedAt, now: now) { return leavingAsk(question: question) }
        return Landing(place: place, searchText: question)
    }
}

/// Which Ask may still land its reply. A new Ask or an edit to the field moves the token on, so an
/// earlier reply is dropped.
public struct AskGeneration: Equatable, Sendable {
    private var current = 0

    public init() {}

    /// Starts an Ask; its token is the only one accepted until the next `begin` or `cancel`.
    public mutating func begin() -> Int {
        current += 1
        return current
    }

    /// Typing in the field or leaving Ask: no reply lands until the next `begin`.
    public mutating func cancel() { current += 1 }

    public func accepts(_ token: Int) -> Bool { token == current }

    /// A cancelled Ask reports `CancellationError`, or `URLError.cancelled` from the request; both are ignored.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}
