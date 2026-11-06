import AppKit
import PullBullKit
import SwiftUI

/// A detail's bottom row: the comment field, the item's own buttons (Review, Merge and Copy branch, or View
/// on board), and Open on GitHub last. Unfocused, the field is one line as tall as the
/// buttons, reading "Comment…" with ⌥⌘M at its end, or a pencil and a waiting draft's first line. ⌥⌘M or
/// a click focuses it: ⌘↩ shows at its end, as the way to post, and it grows upward with the text to 8
/// lines, then scrolls. While a post is in flight, "Sending…" takes the hint's place. Where the account
/// can't comment yet, the note saying what it needs takes the field's place. In review mode the panel
/// sits on top of the row, and the empty field reads what the verdict asks for.
struct CommentField<Secondary: View>: View {
    let model: AppModel
    let key: PRKey
    let isPullRequest: Bool
    /// Where Open on GitHub goes.
    let webURL: URL
    /// Review, Merge and Copy branch on a PR, View on board on an issue on the board.
    @ViewBuilder let secondary: Secondary

    @State private var isFocused = false
    /// The text's laid-out height, reported by the text view.
    @State private var contentHeight = CommentTextView.oneLineHeight
    /// Whether the text view holds nothing but spaces and new lines, as `ReviewGate.canSubmit` reads it,
    /// counting an input method's unfinished text as text. Only the review placeholder reads this.
    @State private var isEmpty = true

    private var account: String? { model.runningAccount?.login }
    private var draftText: String {
        account.flatMap { model.commentDrafts[account: $0, key: key]?.text } ?? ""
    }
    private var isSending: Bool { model.isPostInFlight(for: key) }
    /// The review this field is writing, or nil.
    private var review: ReviewMode? { model.reviewMode.flatMap { $0.key == key ? $0 : nil } }

    var body: some View {
        let permission = model.commentPermission(for: key, isPullRequest: isPullRequest)
        let ready = permission == .ready
        VStack(spacing: 0) {
            if let review { ReviewPanel(model: model, mode: review) }
            HStack(alignment: .bottom, spacing: 8) {
                if ready {
                    field
                } else if let note = permission.note(for: .comment) {
                    permissionSlot(note: note, permission: permission)
                } else {
                    Spacer(minLength: 0)
                }
                secondary
                OutlinedIconButton(name: "Open on GitHub", systemImage: "arrow.up.right.square") {
                    NSWorkspace.shared.open(webURL)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .overlay(alignment: .top) { Hairline() }
        // A field taken away while focused (the permission lost) comes back unfocused, and its @ list ends:
        // the torn-down text view never reports the blur.
        .onChange(of: ready) { _, ready in
            guard !ready else { return }
            isFocused = false
            model.commentFieldBlurred(key: key)
        }
        // The @ list floats over the detail's scroll area, its bottom on the top of the row or the review
        // panel, so it rises as the field grows.
        .overlay(alignment: .top) {
            if ready, let mention, isFocused {
                MentionList(model: model, mention: mention)
                    .padding(.horizontal, 10)
                    .alignmentGuide(.top) { $0[.bottom] }
            }
        }
        .onChange(of: mention?.speech) { old, new in
            if let speech = CompletionSpeech.mentionChange(from: old, to: new) {
                AccessibilityNotification.Announcement(speech).post()
            }
        }
    }

    /// The @ list, when it belongs to this field.
    private var mention: MentionState? {
        model.mention.flatMap { $0.key == key ? $0 : nil }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 6) {
            CommentTextView(
                model: model, key: key, isPullRequest: isPullRequest, account: account, isSending: isSending,
                isReviewing: review != nil, reset: model.commentFieldReset,
                focusRequest: model.commentFieldFocusRequest, release: model.commentFieldRelease,
                insertion: model.mentionInsertion, isFocused: $isFocused, contentHeight: $contentHeight,
                isEmpty: $isEmpty)
                .frame(height: textHeight)
                .overlay(alignment: .leading) {
                    if !isFocused { unfocusedText }
                }
                // On the first line, however many blank lines the field has grown to.
                .overlay(alignment: .topLeading) {
                    if isFocused, let review, isEmpty { reviewPlaceholder(review) }
                }
            // At the end of the last line, beside the text rather than under it.
            if let hint = CommentRow.hint(
                focused: isFocused, sending: isSending && !model.sendingMerges.contains(key),
                hasDraft: CommentRow.preview(of: draftText) != nil, checking: review?.phase == .checking)
            {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(height: CommentTextView.oneLineHeight)
                    .fixedSize()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: CommentTextView.rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.field))
        .overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? Color.accentColor : Palette.separator))
        // Focused, no tooltip covers the text being written.
        .help(isFocused ? "" : CommentTextView.help)
    }

    /// One line unfocused; focused, the text's height between one line and eight.
    private var textHeight: CGFloat {
        guard isFocused else { return CommentTextView.oneLineHeight }
        return min(max(contentHeight, CommentTextView.oneLineHeight), CommentTextView.eightLineHeight)
    }

    /// Unfocused, the field reads "Comment…", or a pencil and the draft's first line, dimmed; the hint
    /// beside it carries the shortcut. The text view under it keeps the draft for VoiceOver and takes the click.
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
            }
        }
        .font(.system(size: CommentTextView.fontSize))
        .lineLimit(1)
        .truncationMode(.tail)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Focused and blank in review mode, what the verdict asks for; a Request changes sent blank warns.
    private func reviewPlaceholder(_ review: ReviewMode) -> some View {
        Text(CommentRow.reviewPlaceholder(review.verdict))
            .font(.system(size: CommentTextView.fontSize))
            .foregroundStyle(review.missingText ? Palette.amberGlyph : Palette.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: CommentTextView.oneLineHeight)
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
    /// In review mode, VoiceOver's action submits the review.
    let isReviewing: Bool
    /// `AppModel.commentFieldReset`, `commentFieldFocusRequest` and `commentFieldRelease`, acted on when
    /// their key is `key`.
    let reset: CommentFieldSignal?
    let focusRequest: CommentFieldSignal?
    let release: CommentFieldSignal?
    /// `AppModel.mentionInsertion`, made when its key is `key`.
    let insertion: MentionInsertion?
    @Binding var isFocused: Bool
    @Binding var contentHeight: CGFloat
    @Binding var isEmpty: Bool

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
        coordinator.seenRelease = release
        coordinator.seenInsertion = insertion
        textView.onFocusChange = { [weak coordinator] focused in coordinator?.focusChanged(focused) }
        textView.onPost = { [model, key, isPullRequest] in model.postComment(on: key, isPullRequest: isPullRequest) }
        textView.onSubmitReview = { [model, key] in model.submitReview(on: key) }
        coordinator.observeFrame()
        coordinator.load(account: account)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        textView.isEditable = !isSending
        textView.isReviewing = isReviewing
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
        if release != coordinator.seenRelease {
            coordinator.seenRelease = release
            if release?.key == key {
                DispatchQueue.main.async { [weak textView] in
                    // Only its own focus: a covered field never takes it from a picker or another field.
                    guard let textView, let window = textView.window, window.firstResponder === textView else { return }
                    window.makeFirstResponder(nil)
                }
            }
        }
        if insertion != coordinator.seenInsertion {
            coordinator.seenInsertion = insertion
            if let insertion, insertion.key == key {
                DispatchQueue.main.async { [weak coordinator] in coordinator?.apply(insertion) }
            }
        }
        // Unfocused, the SwiftUI line above shows the draft; the view stays for VoiceOver and clicks.
        scrollView.alphaValue = isFocused ? 1 : 0
        textView.toolTip = isFocused ? nil : Self.help
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
        var seenRelease: CommentFieldSignal?
        var seenInsertion: MentionInsertion?
        /// The focus the last update laid out for.
        var shownFocused = false
        /// The view's own, so loading a draft or a post can clear it without touching the window's.
        private let undo = UndoManager()
        /// Set while a draft is put in the view, whose own changes then write nothing back.
        private var loading = false
        /// Set while an @ row's text goes in, whose in-between states don't move the @ list.
        private var inserting = false

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
            reportEmpty()
            // A focused field's @ list reads the new text, after the current update.
            if textView.window?.firstResponder === textView {
                DispatchQueue.main.async { [weak self, weak textView] in
                    if let textView { self?.reportMention(textView, typed: false) }
                }
            }
        }

        /// Puts the taken @ row in place of its token, with the view's own undo, and the caret after it.
        func apply(_ insertion: MentionInsertion) {
            guard let textView, textView.isEditable, !textView.hasMarkedText(),
                  insertion.range.upperBound <= (textView.string as NSString).length else { return }
            inserting = true
            // Its own undo step: ⌘Z takes back the row, not the "@" typed before it.
            textView.breakUndoCoalescing()
            textView.insertText(
                insertion.replacement,
                replacementRange: NSRange(location: insertion.range.lowerBound, length: insertion.range.count))
            textView.breakUndoCoalescing()
            inserting = false
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(insertion.caret, length), length: 0))
            writeDraft(textView)
            reportMention(textView, typed: false)
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
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.isFocused = focused
                if focused, let textView = self.textView {
                    self.parent.model.commentFieldFocused(
                        key: self.parent.key, isPullRequest: self.parent.isPullRequest, text: textView.string,
                        caret: Self.caret(of: textView))
                } else if !focused {
                    self.parent.model.commentFieldBlurred(key: self.parent.key)
                }
            }
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard !loading, let textView else { return }
            // An input method's unfinished text isn't the draft yet; it is once committed.
            if !textView.hasMarkedText() {
                writeDraft(textView)
                if !inserting { reportMention(textView, typed: true) }
            }
            reportHeight()
            reportEmpty()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !loading, let textView, !textView.hasMarkedText() else { return }
            writeDraft(textView)
            if !inserting { reportMention(textView, typed: false) }
        }

        /// The @ list follows the focused field's token at the caret; the token is read from the text,
        /// never from keys, so "@" typed with ⌥, a dead key or an input method opens it.
        private func reportMention(_ textView: NSTextView, typed: Bool) {
            guard textView.window?.firstResponder === textView else { return }
            parent.model.commentTextChanged(
                key: parent.key, isPullRequest: parent.isPullRequest, text: textView.string,
                caret: Self.caret(of: textView), typed: typed)
        }

        /// The caret, or nil while text is selected.
        private static func caret(of textView: NSTextView) -> Int? {
            let range = textView.selectedRange()
            return range.length == 0 ? range.location : nil
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

        /// Whether the view holds only spaces and new lines, for the review placeholder; passed on after
        /// the current update.
        private func reportEmpty() {
            guard let textView else { return }
            let empty = textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard empty != parent.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in self?.parent.isEmpty = empty }
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
    /// Posts the text, as ⌘↩ does; VoiceOver's "Post comment" action, since there is no button.
    var onPost: (() -> Void)?
    /// Submits the review, as ⌘↩ does in review mode; VoiceOver's "Submit review" action.
    var onSubmitReview: (() -> Void)?
    /// In review mode the field's action is "Submit review", and "Post comment" goes while it's there.
    var isReviewing = false
    private var focusAllowed = false

    override var acceptsFirstResponder: Bool { focusAllowed && super.acceptsFirstResponder }

    /// Plain text only, whatever the pasteboard holds.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    /// Unfocused, VoiceOver reads a waiting draft as "Draft: " and its first line, as the field shows it.
    override func accessibilityValue() -> String? {
        if window?.firstResponder !== self, let value = CommentRow.unfocusedValue(of: string) { return value }
        return super.accessibilityValue()
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let reviewing = isReviewing
        let send = NSAccessibilityCustomAction(name: reviewing ? "Submit review" : "Post comment") { [weak self] in
            guard let perform = reviewing ? self?.onSubmitReview : self?.onPost else { return false }
            perform()
            return true
        }
        return [send] + (super.accessibilityCustomActions() ?? [])
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
