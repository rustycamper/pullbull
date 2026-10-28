import AppKit

/// The caret of the window's active field editor, in UTF-16 offsets (`NSString` indices).
@MainActor
enum FieldCaret {
    /// The caret when the editor has no selected range, else nil. With `text`, also nil unless the
    /// editor holds exactly that text, so a caret is never paired with other text. Nil while an input
    /// method composes, so completion stays off composing input.
    static func read(in window: NSWindow?, text: String? = nil) -> Int? {
        guard let editor = window?.firstResponder as? NSTextView, !editor.hasMarkedText() else { return nil }
        if let text, editor.string != text { return nil }
        let range = editor.selectedRange()
        return range.length == 0 ? range.location : nil
    }

    /// Moves the caret, clamped to the text. With `text`, only when the editor already holds that text.
    static func set(_ caret: Int, in window: NSWindow?, text: String? = nil) {
        guard let editor = window?.firstResponder as? NSTextView else { return }
        if let text, editor.string != text { return }
        let length = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: min(max(caret, 0), length), length: 0))
    }
}

/// Calls `handler` with the caret and the editor's text whenever the selection of a field editor in
/// `window` changes, nothing is selected and no input method is composing. Installed while the popover
/// is visible.
@MainActor
final class FieldCaretObserver {
    private var observer: (any NSObjectProtocol)?
    private weak var window: NSWindow?

    func install(on window: NSWindow, handler: @escaping @MainActor (_ caret: Int, _ text: String) -> Void) {
        remove()
        self.window = window
        observer = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Posted by the text view on the main thread; the notification never leaves it.
            nonisolated(unsafe) let notification = notification
            MainActor.assumeIsolated {
                guard let self, let window = self.window,
                      let editor = notification.object as? NSTextView,
                      editor.isFieldEditor, editor.window === window, window.firstResponder === editor,
                      !editor.hasMarkedText()
                else { return }
                let range = editor.selectedRange()
                guard range.length == 0 else { return }
                handler(range.location, editor.string)
            }
        }
    }

    func remove() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        window = nil
    }
}
