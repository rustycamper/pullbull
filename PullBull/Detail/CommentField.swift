import AppKit
import PullBullKit
import SwiftUI

/// A detail's bottom row: the comment field, then the item's own buttons (Copy branch or View on board,
/// and Open on GitHub). Unfocused, the field is one line as tall as the buttons, reading "Comment…" with
/// ⌥⌘M at its end, or a pencil and a waiting draft's first line. ⌥⌘M or a click focuses it: the Comment
/// button takes the buttons' place and the field grows upward with the text to 8 lines, then scrolls.
/// Where the account can't comment yet, the note saying what it needs takes the field's place.
struct CommentField<Buttons: View>: View {
    let model: AppModel
    let key: PRKey
    let isPullRequest: Bool
    @ViewBuilder let buttons: Buttons

    @State private var isFocused = false
    /// The text's laid-out height, reported by the text view.
    @State private var contentHeight = CommentTextView.oneLineHeight

    private var account: String? { model.runningAccount?.login }
    private var draftText: String {
        account.flatMap { model.commentDrafts[account: $0, key: key]?.text } ?? ""
    }
    private var isSending: Bool { model.isPostInFlight(for: key) }

    var body: some View {
        let permission = model.commentPermission(for: key, isPullRequest: isPullRequest)
        let ready = permission == .ready
        let row = CommentRow(focused: ready && isFocused, sending: ready && isSending)
        HStack(alignment: .bottom, spacing: 8) {
            if ready {
                field
            } else if let note = permission.note(for: .comment) {
                permissionSlot(note: note, permission: permission)
            } else {
                Spacer(minLength: 0)
            }
            if row.showsCommentButton { commentButton }
            if row.showsItemButtons { buttons }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Hairline() }
    }

    private var field: some View {
        CommentTextView(
            model: model, key: key, isPullRequest: isPullRequest, account: account, isSending: isSending,
            reset: model.commentFieldReset, focusRequest: model.commentFieldFocusRequest,
            isFocused: $isFocused, contentHeight: $contentHeight)
            .frame(height: textHeight)
            .overlay(alignment: .leading) {
                if !isFocused { unfocusedText }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: CommentTextView.rowHeight)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.field))
            .overlay(
                RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? Color.accentColor : Palette.separator))
            .help(CommentTextView.help)
    }

    private var commentButton: some View {
        Button(isSending ? "Sending…" : "Comment") {
            model.postComment(on: key, isPullRequest: isPullRequest)
        }
        .controlSize(.small)
        .disabled(isSending || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Comment")
        .frame(height: CommentTextView.rowHeight)
    }

    /// One line unfocused; focused, the text's height between one line and eight.
    private var textHeight: CGFloat {
        guard isFocused else { return CommentTextView.oneLineHeight }
        return min(max(contentHeight, CommentTextView.oneLineHeight), CommentTextView.eightLineHeight)
    }

    /// Unfocused, the field reads "Comment…" with its shortcut, or a pencil and the draft's first line,
    /// dimmed. The text view under it keeps the draft for VoiceOver and takes the click.
    private var unfocusedText: some View {
        HStack(spacing: 4) {
            if let preview = CommentRow.preview(of: draftText) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(preview)
                    .foregroundStyle(.secondary)
            } else {
                Text("Comment…")
                    .foregroundStyle(Palette.tertiary)
                Spacer(minLength: 8)
                Text("⌥⌘M")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .font(.system(size: CommentTextView.fontSize))
        .lineLimit(1)
        .truncationMode(.tail)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// In the field's place, a field-shaped box reading what the account needs. With the page where the
    /// permissions are accepted, the box is the link to it; without one, it only reads.
    @ViewBuilder
    private func permissionSlot(note: String, permission: EditPermission) -> some View {
        if case .needsAppApproval(_, _, let url?) = permission {
            Button { NSWorkspace.shared.open(url) } label: {
                permissionBox(note: note, linked: true)
            }
            .buttonStyle(.plain)
            .help(note)
            .accessibilityLabel(note)
            .accessibilityHint("Opens GitHub to accept the permissions")
        } else {
            permissionBox(note: note, linked: false)
                .help(note)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(note)
        }
    }

    private func permissionBox(note: String, linked: Bool) -> some View {
        HStack(spacing: 4) {
            Text(note)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .font(.system(size: CommentTextView.fontSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: CommentTextView.rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.separator))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The comment field's `NSTextView`: plain text, its own undo, and focus only when asked. Text and
/// caret write through to the running account's draft on each change.
struct CommentTextView: NSViewRepresentable {
    let model: AppModel
    let key: PRKey
    let isPullRequest: Bool
    /// The running account's login: its draft fills the view.
    let account: String?
    /// Read-only while the post is in flight.
    let isSending: Bool
    /// `AppModel.commentFieldReset` and `commentFieldFocusRequest`, acted on when their key is `key`.
    let reset: CommentFieldSignal?
    let focusRequest: CommentFieldSignal?
    @Binding var isFocused: Bool
    @Binding var contentHeight: CGFloat

    static let fontSize: CGFloat = 12
    /// The unfocused field's height, an outlined icon button's, so the bottom row is 40 pt.
    static let rowHeight: CGFloat = 24
    static let help = "Comment (⌥⌘M) · ⌘↩ to post"
    private static let font = NSFont.systemFont(ofSize: fontSize)
    private static let verticalInset: CGFloat = 4
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
    static let oneLineHeight = (lineHeight + verticalInset * 2).rounded(.up)
    static let eightLineHeight = (lineHeight * 8 + verticalInset * 2).rounded(.up)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CommentEditor(usingTextLayoutManager: false)
        textView.key = key
        textView.isPullRequest = isPullRequest
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        // Spelling is checked but never corrected or completed, so code and names arrive as typed.
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: Self.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Comment on \(key.repo)#\(key.number)")
        textView.toolTip = Self.help
        textView.postsFrameChangedNotifications = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        let coordinator = context.coordinator
        coordinator.textView = textView
        coordinator.seenReset = reset
        coordinator.seenFocusRequest = focusRequest
        textView.onFocusChange = { [weak coordinator] focused in coordinator?.focusChanged(focused) }
        coordinator.observeFrame()
        coordinator.load(account: account)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        textView.isEditable = !isSending
        if account != coordinator.loadedAccount { coordinator.load(account: account) }
        if reset != coordinator.seenReset {
            coordinator.seenReset = reset
            if reset?.key == key { coordinator.load(account: account) }
        }
        if focusRequest != coordinator.seenFocusRequest {
            coordinator.seenFocusRequest = focusRequest
            // A covered layer is disabled; its field leaves the request to the detail on top.
            if focusRequest?.key == key, context.environment.isEnabled {
                DispatchQueue.main.async { [weak textView] in textView?.requestFocus() }
            }
        }
        // Unfocused, the SwiftUI line above shows the draft; the view stays for VoiceOver and clicks.
        scrollView.alphaValue = isFocused ? 1 : 0
        // Focused, the field grows from one line; once it has, the caret is brought into view.
        if isFocused, !coordinator.shownFocused {
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
        coordinator.shownFocused = isFocused
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommentTextView
        weak var textView: CommentEditor?
        var loadedAccount: String?
        var seenReset: CommentFieldSignal?
        var seenFocusRequest: CommentFieldSignal?
        /// The focus the last update laid out for.
        var shownFocused = false
        /// The view's own, so loading a draft or a post can clear it without touching the window's.
        private let undo = UndoManager()
        /// Set while a draft is put in the view, whose own changes then write nothing back.
        private var loading = false

        init(_ parent: CommentTextView) {
            self.parent = parent
        }

        /// Puts `account`'s draft for the item in the view, caret where it was, with a fresh undo stack.
        func load(account: String?) {
            guard let textView else { return }
            loadedAccount = account
            let draft = account.flatMap { parent.model.commentDrafts[account: $0, key: parent.key] }
            loading = true
            textView.string = draft?.text ?? ""
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(draft?.caret ?? length, length), length: 0))
            loading = false
            textView.breakUndoCoalescing()
            undo.removeAllActions()
            reportHeight()
        }

        /// A new width rewraps the text, so its height is reported again.
        func observeFrame() {
            NotificationCenter.default.addObserver(
                self, selector: #selector(frameChanged), name: NSView.frameDidChangeNotification, object: textView)
        }

        @objc private func frameChanged(_ notification: Notification) {
            reportHeight()
        }

        /// Passed on after the current update: focus can change while SwiftUI is updating, as when the
        /// detail closes under it.
        func focusChanged(_ focused: Bool) {
            DispatchQueue.main.async { [weak self] in self?.parent.isFocused = focused }
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard !loading, let textView else { return }
            // An input method's unfinished text isn't the draft yet; it is once committed.
            if !textView.hasMarkedText() { writeDraft(textView) }
            reportHeight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !loading, let textView, !textView.hasMarkedText() else { return }
            writeDraft(textView)
        }

        private func writeDraft(_ textView: NSTextView) {
            guard let account = loadedAccount else { return }
            let draft = CommentDraft(text: textView.string, caret: textView.selectedRange().location)
            let held = parent.model.commentDrafts[account: account, key: parent.key]
            // An empty draft isn't kept, so a caret move in an empty field changes nothing.
            guard held != draft, !(draft.text.isEmpty && held == nil) else { return }
            parent.model.commentDrafts[account: account, key: parent.key] = draft
        }

        /// The text's laid-out height, for the field to grow to; passed on after the current update.
        private func reportHeight() {
            guard let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let height = (layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2)
                .rounded(.up)
            guard height != parent.contentHeight else { return }
            DispatchQueue.main.async { [weak self] in self?.parent.contentHeight = height }
        }
    }
}

/// The comment field's text view. It refuses first responder until asked (⌥⌘M, a click, or the model's
/// focus request), so the popover never puts the caret in it on its own, and it handles the editing
/// chords itself: PullBull has no Edit menu.
final class CommentEditor: NSTextView {
    var key: PRKey?
    var isPullRequest = false
    var onFocusChange: ((Bool) -> Void)?
    private var focusAllowed = false

    override var acceptsFirstResponder: Bool { focusAllowed && super.acceptsFirstResponder }

    /// Plain text only, whatever the pasteboard holds.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    /// Unfocused, VoiceOver reads a waiting draft as "Draft: " and its first line, as the field shows it.
    override func accessibilityValue() -> String? {
        if window?.firstResponder !== self, let value = CommentRow.unfocusedValue(of: string) { return value }
        return super.accessibilityValue()
    }

    func requestFocus() {
        guard let window else { return }
        focusAllowed = true
        if !window.makeFirstResponder(self) { focusAllowed = false }
    }

    /// `makeFirstResponder` doesn't ask `acceptsFirstResponder`, so the refusal is here too.
    override func becomeFirstResponder() -> Bool {
        guard focusAllowed, super.becomeFirstResponder() else { return false }
        onFocusChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        focusAllowed = false
        // Unfocused, the field is one line from the top, as its preview is.
        scroll(.zero)
        onFocusChange?(false)
        return true
    }

    /// A click on the unfocused field focuses it with the caret where it was: the click isn't passed on,
    /// so the selection the view kept (the draft's caret, from `load` or from before it was left) stays.
    /// Once focused, clicks place the caret as usual.
    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder === self {
            super.mouseDown(with: event)
        } else {
            requestFocus()
        }
    }

    /// VoiceOver focusing the field asks for it as a click does.
    override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        if accessibilityFocused, window?.firstResponder !== self {
            requestFocus()
            return
        }
        super.setAccessibilityFocused(accessibilityFocused)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, performEditingChord(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if performEditingChord(event) { return }
        super.keyDown(with: event)
    }

    /// The detail's shortcuts reach the field as keys it has no binding for (⌘R, ⌘[, ⌥⌘A…): they do
    /// nothing, without the system beep.
    override func doCommand(by selector: Selector) {
        if selector == Selector(("noop:")) { return }
        super.doCommand(by: selector)
    }

    /// ⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V and ⌘A; by key position on layouts that type no Latin letter there.
    private func performEditingChord(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags == .command || flags == [.command, .shift] else { return false }
        let shifted = flags.contains(.shift)
        switch (Self.letter(event), shifted) {
        case ("z", false):
            if isEditable, undoManager?.canUndo == true { undoManager?.undo() }
        case ("z", true):
            if isEditable, undoManager?.canRedo == true { undoManager?.redo() }
        case ("x", false): cut(nil)
        case ("c", false): copy(nil)
        case ("v", false): paste(nil)
        case ("a", false): selectAll(nil)
        default: return false
        }
        return true
    }

    private static func letter(_ event: NSEvent) -> String? {
        guard let typed = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        guard !typed.isEmpty, !typed.allSatisfy(\.isASCII) else { return typed }
        switch event.keyCode {
        case SearchKeyMonitor.letterZ: return "z"
        case SearchKeyMonitor.letterX: return "x"
        case SearchKeyMonitor.letterC: return "c"
        case SearchKeyMonitor.letterV: return "v"
        case SearchKeyMonitor.letterA: return "a"
        default: return typed
        }
    }
}
