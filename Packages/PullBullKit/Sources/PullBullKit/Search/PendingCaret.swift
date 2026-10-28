import Foundation

/// A caret waiting for the search field to show the text it belongs to, such as the one after
/// completing a name: SwiftUI pushes the new text into the field editor some time after the model
/// changes, and a caret set on the old text would land in the wrong place.
///
/// Single use: it lives for one async hop after completing, plus at most one field editor selection
/// change after that hop when the editor still lagged. Anything else drops it, so it can never move a
/// caret the user placed later.
public struct PendingCaret: Equatable, Sendable {
    /// The text the caret belongs to.
    public let text: String
    /// UTF-16 offset in `text`.
    public let caret: Int
    /// The async hop after completing has run.
    public private(set) var hopped = false

    public enum Outcome: Equatable, Sendable {
        /// The editor shows `text`: set this caret now, then forget it.
        case apply(Int)
        /// The editor still shows the old text; keep it for one more chance.
        case wait
        /// Forget it.
        case drop
    }

    public init(text: String, caret: Int) {
        self.text = text
        self.caret = caret
    }

    /// The one async hop after completing. `editorText` is nil when the field editor doesn't have focus
    /// (a click moved it), which drops the caret. A second hop never waits.
    public mutating func afterHop(editorText: String?, searchText: String) -> Outcome {
        defer { hopped = true }
        guard let editorText, searchText == text else { return .drop }
        if editorText == text { return .apply(caret) }
        return hopped ? .drop : .wait
    }

    /// A selection change in the field editor. Before the hop, one on the old text is the field's own
    /// and is waited out; after it, the first one either finds the text and applies or drops the caret.
    public func selectionChanged(editorText: String, searchText: String) -> Outcome {
        guard searchText == text else { return .drop }
        if editorText == text { return .apply(caret) }
        return hopped ? .drop : .wait
    }
}
