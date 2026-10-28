import Foundation

/// The Ask behind the search field: the question in flight, the last outcome, the no-key notice, and
/// which reply may still land (`AskGeneration`).
public struct AskState: Equatable, Sendable {
    /// Where a reply that landed shows.
    public enum Arrival: Equatable, Sendable {
        /// An answer: the Ask screen.
        case screen
        /// A failure: one line over the normal results, which stay.
        case errorLine
        /// A later Ask or an edit came first: nothing changes.
        case ignored
    }

    public static let needsKeyNotice = "Add an Anthropic API key in Settings → Ask"

    /// The question in flight; nil when none runs.
    public private(set) var asking: String?
    /// The last reply that landed; nil while asking and after an edit.
    public private(set) var outcome: AskOutcome?
    /// Shown in place of an Ask that sent nothing.
    public private(set) var notice: String?
    private var generation = AskGeneration()

    public init() {}

    /// Starts asking `question`; only the returned token's reply can land.
    public mutating func begin(_ question: String) -> Int {
        asking = question
        outcome = nil
        notice = nil
        return generation.begin()
    }

    /// The reply for `token`; dropped when a later Ask or an edit came after it.
    public mutating func land(_ outcome: AskOutcome, token: Int) -> Arrival {
        guard generation.accepts(token) else { return .ignored }
        asking = nil
        self.outcome = outcome
        if case .failed = outcome { return .errorLine }
        return .screen
    }

    /// The Ask for `token` was cancelled: no line, and "Asking…" goes if it was the running one.
    public mutating func cancelled(token: Int) {
        if generation.accepts(token) { asking = nil }
    }

    /// Esc while asking, or a detail opening: the reply in flight is dropped; what showed stays.
    public mutating func cancel() {
        generation.cancel()
        asking = nil
    }

    /// The field was edited or emptied: back to normal search, with no Ask, line or notice.
    public mutating func clear() {
        cancel()
        outcome = nil
        notice = nil
    }

    /// ⌥⌘↩ without a key: nothing is sent, and the notice says why.
    public mutating func needsKey() {
        clear()
        notice = Self.needsKeyNotice
    }

    /// The failure line for the search on screen; nil unless the last Ask of `question` failed.
    public func errorLine(for question: String) -> String? {
        guard case .failed(let asked, let error) = outcome, asked == question else { return nil }
        return error.message
    }
}
