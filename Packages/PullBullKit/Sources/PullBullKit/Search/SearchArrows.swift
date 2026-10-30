import Foundation

/// When ← and → in the search field switch the scope instead of editing the text.
public enum SearchArrows {
    /// True with the field unfocused. Otherwise only with the caret (not a selection, so `caret` is non-nil)
    /// at the end of the text for → or at the start for ←, no completion list open and no key repeat.
    public static func movesScope(
        offset: Int, fieldFocused: Bool, caret: Int?, length: Int, completionOpen: Bool, isRepeat: Bool
    ) -> Bool {
        guard !isRepeat, !completionOpen else { return false }
        guard fieldFocused else { return true }
        guard let caret else { return false }
        return caret == (offset > 0 ? length : 0)
    }
}
