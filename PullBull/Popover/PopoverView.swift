import AppKit
import SwiftUI
import PullBullKit

struct PopoverView: View {
    @Bindable var model: AppModel
    let presence: PopoverPresence
    /// Folded on every launch; not persisted.
    @State private var closedExpanded: Bool
    /// The Issues tabs whose Done group is unfolded (Board's and Assigned's fold separately); folded on
    /// every launch, not persisted.
    @State private var doneExpandedTabs: Set<IssueTab> = []
    /// The search field was picked (a click, ⌘F, `/`) and has no text yet, so its hints show; with text,
    /// `model.route` is `.search`.
    @State private var fieldOpen = false
    /// Type-anywhere put text in the field; the caret goes to the end instead of selecting it all.
    @State private var caretToEnd = false
    @State private var keyMonitor = SearchKeyMonitor()
    @State private var caretObserver = FieldCaretObserver()
    /// The qualifier ghost is on screen; Tab writes only one the user can see.
    @State private var qualifierGhostDrawn = false
    /// The caret after a completed name, set once the field editor shows the completed text.
    @State private var pendingCaret: PendingCaret?
    /// The saved chip or token the arrows highlighted under the empty field; Return picks it.
    @State private var hintSelection: HintPanelItem?
    /// "+N" expanded the saved chips; folded again when the field closes or a search is applied.
    @State private var savedExpanded = false
    /// The save row's name while it is open under the field; nil when closed.
    @State private var saveName: String?
    @FocusState private var saveNameFocused: Bool
    /// Set when ← leaves a detail: the held key's repeats do nothing, in the list too, until another key.
    @State private var swallowArrowRepeats = false
    /// On screen: the panel is created once and only ordered out, so the views stay mounted while closed.
    @State private var shown = false
    /// When the popover last closed on a detail.
    @State private var closedOnDetail: Date?
    @FocusState private var fieldFocused: Bool
    /// The detail layers on screen, bottom to top. They follow the route, one update behind, so each
    /// change can pick its own animation.
    @State private var layers: [DetailLayer]
    /// Spans the filter row's place, so its bottom is the row's bottom, or the header's without a row.
    @State private var repoMenuAnchor = MenuAnchor()
    /// The filter row's board name, for ⌘⇧B.
    @State private var boardMenuAnchor = MenuAnchor()
    @State private var accountMenuAnchor = MenuAnchor()
    /// The pane the last pass showed; rows arriving for it fade in, a newly switched-to one cuts.
    @State private var fadePane: ListPane?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, presence: PopoverPresence = PopoverPresence(), closedExpanded: Bool = false) {
        self.model = model
        self.presence = presence
        _closedExpanded = State(initialValue: closedExpanded)
        _layers = State(initialValue: DetailLayer.stack(for: model))
    }

    private var searching: Bool { model.route == .search }
    /// The search results stay drawn under the Ask AI screen, so its fade never shows the list swapping in.
    private var searchShown: Bool { searching || model.route == .ask || layers.first == .ask }
    private var searchOpen: Bool { searchShown || fieldOpen }
    /// The "@user", "~label" or "is:" list is on screen (only with the search field open).
    private var completionShown: Bool { model.completion != nil && searchOpen }
    /// The panel under the empty field takes the arrows, Return and Esc.
    private var hintsActive: Bool { fieldOpen && !searching && model.searchText.isEmpty && !completionShown }
    /// The saved chips under the empty field.
    private var hintCloud: SavedChipCloud {
        SearchHints.cloud(saved: model.settings.savedSearches, expanded: savedExpanded)
    }
    /// The items the arrows reach under the empty field: saved chips, then tokens.
    private var hintItems: [HintPanelItem] { HintPanelItem.items(cloud: hintCloud) }
    /// The PR detail on top, if any.
    private var detailKey: PRKey? { if case .pr(let key) = layers.last { key } else { nil } }
    /// The issue detail on screen, or the one under a linked PR's detail that Back returns to.
    private var issueLayerKey: PRKey? {
        layers.lazy.compactMap { if case .issue(let key) = $0 { key } else { nil } }.first
    }
    /// The Ask screen is on screen, or under the details opened from it.
    private var askLayerShown: Bool { layers.first == .ask }
    /// The Ask screen is the top layer, with no detail over it.
    private var askShownAlone: Bool { layers == [.ask] }
    private var slides: Bool { !reduceMotion }
    /// The Board tab is on screen and its filter row names the board.
    private var boardPartShown: Bool {
        model.mode == .issues && model.selectedIssueTab == .board && model.issueTabs != nil && model.offersBoardMenu
    }
    /// The row at the top of the list or search results; nil with nothing to filter.
    private var filterRow: FilterRow? {
        let listsBuilt = switch (searchShown, model.mode) {
        case (true, _): model.tabs != nil
        case (false, .pullRequests): model.contents(of: model.selectedTab) != nil
        case (false, .issues): model.issueTabs != nil
        }
        return FilterRow.make(
            searching: searchShown, listsBuilt: listsBuilt,
            focusName: model.repoFocus.map { model.displayName(of: $0.repo) },
            timeTitle: model.timeFocus?.stripText(now: Date()),
            boardTitle: boardPartShown ? model.boardMenuTitle : nil)
    }
    /// The Done group of the Issues tab on screen is unfolded.
    private var doneExpanded: Bool { doneExpandedTabs.contains(model.selectedIssueTab) }

    private func doneExpanded(_ tab: IssueTab) -> Binding<Bool> {
        Binding {
            doneExpandedTabs.contains(tab)
        } set: { expanded in
            if expanded { doneExpandedTabs.insert(tab) } else { doneExpandedTabs.remove(tab) }
        }
    }

    var body: some View {
        // The list (and an issue detail under a linked PR's detail) stays underneath, so Back finds it
        // at the same scroll position. A detail slides in from the trailing edge over it.
        ZStack {
            listAndSearch
                // The Ask screen replaces the search in place: a fade-through, never both half visible.
                .modifier(CoveredLayer(covered: !layers.isEmpty, slides: slides && layers.first != .ask))
                .animation(askShownAlone ? Self.fadeThroughOut : Self.fadeThroughIn, value: askShownAlone)
                .zIndex(0)
            if askLayerShown {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    AskView(
                        question: model.askQuestion, outcome: model.askOutcome, asking: model.asking != nil,
                        selection: model.askSelection, now: context.date, onOpen: model.openAskResult,
                        onBack: model.closeAsk)
                }
                .modifier(CoveredLayer(covered: layers.count > 1, slides: slides))
                .transition(.asymmetric(
                    insertion: .opacity.animation(Self.fadeThroughIn),
                    removal: .opacity.animation(Self.fadeThroughOut).combined(with: .modifier(
                        active: LeavingLayer(leaving: true), identity: LeavingLayer(leaving: false)))))
                .zIndex(0.5)
            }
            if let issueLayerKey {
                // A replaced issue detail starts fresh too.
                IssueDetailView(model: model, key: issueLayerKey)
                    .id(issueLayerKey)
                    .modifier(PushedLayer(slides: slides))
                    .modifier(CoveredLayer(covered: detailKey != nil, slides: slides))
                    .transition(layerTransition)
                    .zIndex(1)
            }
            if let detailKey {
                // A replaced detail starts fresh: top of the page, description folded.
                PRDetailView(model: model, key: detailKey)
                    .id(detailKey)
                    .modifier(PushedLayer(slides: slides))
                    .transition(layerTransition)
                    .zIndex(2)
            }
        }
        // Skeletons shimmer only while the panel is open.
        .environment(\.skeletonAnimates, shown)
        .frame(width: Self.size.width, height: Self.size.height)
        // Sliding layers stay inside the rounded panel.
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .onAppear {
            presence.onShow = popoverDidShow
            presence.onHide = popoverDidHide
            if presence.isShown, let window = presence.window { popoverDidShow(window) }
        }
        .onChange(of: DetailLayer.stack(for: model)) { _, _ in
            syncLayers(animated: true)
        }
        .onChange(of: model.repoFocus) { _, new in
            // VoiceOver hears the change only while the popover is on screen, including a drop on refresh.
            guard presence.isShown else { return }
            AccessibilityNotification.Announcement(
                new.map { "Showing only \(model.displayName(of: $0.repo))" } ?? "Showing all repositories"
            ).post()
        }
        .onChange(of: model.timeFocus?.step) { _, new in
            guard presence.isShown else { return }
            AccessibilityNotification.Announcement(
                new.map { "Showing items updated \($0.title)" } ?? "Showing everything"
            ).post()
        }
        .onChange(of: model.settings.board) { _, new in
            // A board chosen from the menu (or Settings) while the popover shows.
            guard presence.isShown, new != nil else { return }
            AccessibilityNotification.Announcement("Showing \(model.boardMenuTitle)").post()
        }
        .onChange(of: model.route) { old, new in
            // The hidden list keeps no focus, so typing in the detail never lands in the search field.
            if Self.isDetail(new) || new == .ask {
                fieldFocused = false
                saveName = nil
            }
            // Back from a detail opened in search, or Esc on the Ask screen, puts the caret back in the
            // kept query.
            if Self.isDetail(old) || old == .ask, new == .search {
                fieldOpen = true
                DispatchQueue.main.async { fieldFocused = true }
            }
        }
        // Folding a group drops a highlight on one of its rows, so it doesn't come back on the next unfold.
        .onChange(of: closedExpanded) { _, expanded in if !expanded { dropHiddenListSelection() } }
        .onChange(of: doneExpandedTabs) { old, new in if !old.isSubset(of: new) { dropHiddenListSelection() } }
        .onChange(of: fieldFocused) { _, focused in
            // Back in the search field (a click, ⌘F): its hints show, and the save row gives way.
            if focused {
                fieldOpen = true
                saveName = nil
            }
            guard focused, caretToEnd else { return }
            let window = keyMonitor.window
            DispatchQueue.main.async { placeCaretIfPending(in: window) }
        }
        // "Search @author" opens the field with its text and the caret at the end.
        .onChange(of: model.searchFieldFocusRequest) { _, _ in
            fieldOpen = true
            caretToEnd = true
            if fieldFocused {
                let window = keyMonitor.window
                DispatchQueue.main.async { placeCaretIfPending(in: window) }
            } else {
                DispatchQueue.main.async { fieldFocused = true }
            }
        }
        .onChange(of: model.completion) { old, new in announceCompletion(from: old, to: new) }
        // Any other text (the user's next edit) ends a pending caret.
        .onChange(of: model.searchText) { _, text in
            if let pending = pendingCaret, pending.text != text { pendingCaret = nil }
            hintSelection = nil
            saveName = nil
        }
    }

    private var listAndSearch: some View {
        // Setting up an account crossfades to the list in place; signing out cuts back to first run.
        ZStack {
            if model.showsFirstRun {
                // No account: no tabs or search to offer, and the footer keeps only the gear.
                VStack(spacing: 0) {
                    FirstRunView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    FooterView(model: model, now: .now, accountAnchor: accountMenuAnchor)
                }
                // While it fades out under the list, it takes no clicks.
                .allowsHitTesting(model.showsFirstRun)
                .transition(.opacity)
            } else {
                tabsAndSearch
                    .transition(.opacity)
            }
        }
        // Only a real account fades in: resolving one with none set leaves first run for a moment and cuts.
        .animation(
            model.showsFirstRun || model.settings.account == nil ? nil : .easeInOut(duration: 0.25),
            value: model.showsFirstRun)
    }

    private var tabsAndSearch: some View {
        VStack(spacing: 0) {
            HeaderView(
                model: model, searching: searchShown, searchOpen: searchOpen, fieldFocused: $fieldFocused,
                ghostDrawn: $qualifierGhostDrawn, window: { [keyMonitor] in keyMonitor.window },
                onCancelSearch: cancelSearch, onSwitchMode: switchMode(to:), onSaveSearch: openSaveRow)
            if searchOpen, saveName != nil {
                Hairline()
                SaveSearchRow(
                    name: Binding(get: { saveName ?? "" }, set: { saveName = $0 }), focused: $saveNameFocused,
                    onSave: saveSearch, onCancel: closeSaveRow)
                if filterRow != nil { Hairline() }
            }
            // One line between the header and the list: the filter row draws it when shown.
            if filterRow == nil { Hairline() }
            VStack(spacing: 0) {
                // Kept in search too: the focus scopes the hints' list and the results alike.
                VStack(spacing: 0) {
                    if let filterRow { FilterBar(model: model, row: filterRow, boardAnchor: boardMenuAnchor) }
                }
                // Full width, so the menu opens at the left edge even when the container is empty.
                .frame(maxWidth: .infinity)
                .background(MenuAnchorView(anchor: repoMenuAnchor))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        if searchShown {
                            SearchResultsView(model: model, now: context.date)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            footer { SearchFooter(model: model) }
                        } else {
                            // The empty field: hints over the top of the current list, which never moves.
                            // VoiceOver skips the rows while they are covered, so it reads what is on screen.
                            content(now: context.date)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityHidden(fieldOpen)
                                .overlay(alignment: .top) {
                                    ZStack(alignment: .top) {
                                        if fieldOpen {
                                            SearchHints(
                                                model: model, cloud: hintCloud, expanded: savedExpanded,
                                                selection: hintSelection
                                            ) { item in
                                                pickHintItem(item, fromKeyboard: false, in: keyMonitor.window)
                                            }
                                            .overList(solid: model.settings.solidBackground, shadow: !completionShown)
                                            .transition(.opacity)
                                        }
                                    }
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: fieldOpen)
                                }
                            footer { FooterView(model: model, now: context.date, accountAnchor: accountMenuAnchor) }
                        }
                    }
                }
            }
            // The people or label list covers the top of the hints or results, which don't change while you pick.
            // It comes and goes without animation, with or without Reduce Motion.
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if completionShown { CompletionList(model: model) { acceptCompletion(in: keyMonitor.window) } }
                }
                .transaction { Self.disableAnimations(&$0) }
            }
        }
    }

    /// `CompletionFooter` while a completion list is open, else `regular`; swapped without animation.
    private func footer(@ViewBuilder _ regular: () -> some View) -> some View {
        VStack(spacing: 0) {
            if completionShown { CompletionFooter() } else { regular() }
        }
        .transaction { Self.disableAnimations(&$0) }
    }

    private static func disableAnimations(_ transaction: inout Transaction) {
        transaction.animation = nil
        transaction.disablesAnimations = true
    }

    // MARK: Search entry

    private func popoverDidShow(_ window: NSWindow) {
        // Only the detail it was closed on goes stale: one a notification click opened while closed
        // shows as it is, even if it is the same PR or issue.
        if let closedAt = closedOnDetail, !model.detailOpenedWhileClosed {
            // The Ask screen, and details opened from it, follow `AskReturn.reopen`.
            if model.askOnScreen {
                model.reopenAsk(closedAt: closedAt, now: Date())
            } else if PopoverReopen.showsList(closedAt: closedAt, now: Date()) {
                model.showListInsteadOfDetail()
            }
        }
        shown = true
        closedOnDetail = nil
        model.detailOpenedWhileClosed = false
        // A route changed while closed (a notification click) shows as it is, with no slide.
        syncLayers(animated: false)
        model.popoverDidOpen()
        keyMonitor.install(on: window) { event, window in handleKey(event, in: window) }
        // A selection change can arrive before the field's binding delivers the new text; a caret is
        // passed on only with the text it belongs to.
        caretObserver.install(on: window) { caret, text in
            // While a completed name waits for its caret, the field's own moves (such as to the end when
            // it takes the new text) are not the user's: passing one on could reopen the list elsewhere.
            if let pending = pendingCaret {
                switch pending.selectionChanged(editorText: text, searchText: model.searchText) {
                case .wait:
                    return
                case .apply(let target):
                    // Used up here; set on the next turn, not from inside the editor's own selection change.
                    pendingCaret = nil
                    DispatchQueue.main.async { FieldCaret.set(target, in: window, text: pending.text) }
                    return
                case .drop:
                    pendingCaret = nil
                }
            }
            guard text == model.searchText else { return }
            model.searchCaretMoved(to: caret)
        } selected: {
            model.searchTextSelected()
        }
        // The kept query comes back in a focused field, selected so typing replaces it.
        if searching {
            fieldFocused = true
        } else {
            // Shown, the window puts the caret in its first text field; the list keeps the keys until
            // the field is picked.
            if (window.firstResponder as? NSTextView)?.isFieldEditor == true { window.makeFirstResponder(nil) }
            fieldFocused = false
            fieldOpen = false
        }
    }

    /// An open search (or a detail opened from it) keeps its query for the next open. Anything else drops
    /// leftover text, such as a bare "#", so type-anywhere never appends to text the user can't see.
    private func popoverDidHide() {
        // Searches nothing on the way out, so a lone pending token keeps no search route and is dropped below.
        model.closeCompletion()
        // A time focus is transient: it ends with the popover, so the next open starts from a fresh "now".
        model.focus(time: nil)
        pendingCaret = nil
        hintSelection = nil
        savedExpanded = false
        saveName = nil
        shown = false
        keyMonitor.remove()
        caretObserver.remove()
        closedOnDetail = Self.isDetail(model.route) || model.route == .ask ? Date() : nil
        syncLayers(animated: false)
        guard !searching else { return }
        fieldOpen = false
        if !model.detailReturnsToSearch, !model.searchText.isEmpty { model.cancelSearch() }
    }

    // MARK: Detail layers

    static let size = CGSize(width: 360, height: 560)
    /// The panel's corner radius (`PopoverPanel.cornerRadius`).
    private static let cornerRadius: CGFloat = 11
    private static let pushAnimation = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.22)
    private static let popAnimation = Animation.easeInOut(duration: 0.2)
    private static let fadeAnimation = Animation.easeInOut(duration: 0.15)
    /// The Ask AI screen and the search it replaces fade through: the leaving one goes quickly, then the
    /// arriving one comes in, so the two never show half on top of each other.
    private static let fadeThroughOut = Animation.easeIn(duration: 0.1)
    private static let fadeThroughIn = Animation.easeOut(duration: 0.22).delay(0.08)

    /// Slides in from, and back out to, the trailing edge; a crossfade with Reduce Motion. A layer on
    /// its way out takes no clicks.
    private var layerTransition: AnyTransition {
        let move: AnyTransition = slides ? .offset(x: Self.size.width) : .opacity
        return .asymmetric(insertion: move, removal: move.combined(with: .modifier(
            active: LeavingLayer(leaving: true), identity: LeavingLayer(leaving: false))))
    }

    /// Brings the layers on screen in line with the route. One level deeper or shallower slides (or
    /// fades); any other change, such as one detail replacing another, swaps at once. Nothing animates
    /// while the popover is closed, so reopening it never replays a slide.
    private func syncLayers(animated: Bool) {
        let new = DetailLayer.stack(for: model)
        let old = layers
        guard new != old else { return }
        // A text view in a leaving detail would keep key focus for the slide, and with it "/" and
        // type-anywhere.
        if old.contains(where: { !new.contains($0) }), let window = presence.window, window.firstResponder is NSText {
            window.makeFirstResponder(nil)
        }
        var animation: Animation?
        // The Ask screen fades in and out in place; details slide (or fade, with Reduce Motion).
        let crossesAsk = old.contains(.ask) != new.contains(.ask)
        if animated, presence.isShown {
            if crossesAsk, new.count != old.count {
                animation = new.count > old.count ? Self.fadeThroughIn : Self.fadeThroughOut
            } else if new.count > old.count, new.starts(with: old) {
                animation = slides ? Self.pushAnimation : Self.fadeAnimation
            } else if new.count < old.count, old.starts(with: new) {
                animation = slides ? Self.popAnimation : Self.fadeAnimation
            }
        }
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = animation == nil
        withTransaction(transaction) { layers = new }
    }

    private static func isDetail(_ route: Route) -> Bool {
        switch route {
        case .detail, .issueDetail: true
        case .list, .search, .ask: false
        }
    }

    private func openSearch() {
        fieldOpen = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func cancelSearch() {
        pendingCaret = nil
        hintSelection = nil
        savedExpanded = false
        saveName = nil
        model.cancelSearch()
        fieldFocused = false
        fieldOpen = false
    }

    private static let commaKeyCode: UInt16 = 43

    /// Returns true when the key was handled here and must not reach the focused view.
    private func handleKey(_ event: NSEvent, in window: NSWindow) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.isARepeat {
            if swallowArrowRepeats,
               event.keyCode == SearchKeyMonitor.leftArrow || event.keyCode == SearchKeyMonitor.rightArrow {
                return true
            }
        } else {
            swallowArrowRepeats = false
        }
        // An input method or dead key is composing in the field: every key belongs to it.
        if (window.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        // ⌘, opens Settings from every route, by key position so it works on any layout.
        if event.keyCode == Self.commaKeyCode, flags.subtracting(.capsLock) == .command {
            SettingsOpener.open()
            return true
        }
        // ⌘W closes the popover from every route, first-run included.
        if flags.subtracting([.capsLock, .numericPad, .function]) == .command, Self.commandKey(event) == "w" {
            MenuBarPopover.hide()
            return true
        }
        if model.showsFirstRun {
            // Nothing to search or switch yet: Esc closes, every other key passes through.
            guard event.keyCode == SearchKeyMonitor.escape, flags.isDisjoint(with: [.command, .control, .option])
            else { return false }
            MenuBarPopover.hide()
            return true
        }
        if Self.isDetail(model.route) { return handleDetailKey(event, flags: flags, in: window) }
        if model.route == .ask { return handleAskKey(event, flags: flags) }
        // The list's own keys work while no search is open and no text field has focus.
        let listKeys = !searchOpen && !(window.firstResponder is NSText)
            ? model.listKeys(closedExpanded: closedExpanded, doneExpanded: doneExpanded) : nil
        // ⌘-chords are commands and never reach type-anywhere.
        if flags.contains(.command) {
            // ⌥⌘C: the selected result, or the highlighted row, as a Markdown link. It edits no text, so
            // it works with the search field focused too.
            if Self.isOptionCommandC(event, flags: flags) {
                return searching ? model.copySearchSelectionMarkdownLink()
                    : listKeys.map(model.copyListSelectionMarkdownLink(in:)) ?? false
            }
            // ⇧⌘↩ and ⌃⌘C: the selected result's or highlighted row's files and checkout command. Neither
            // edits text, so they work with the search field focused too.
            if Self.isShiftCommandReturn(event, flags: flags) {
                guard let key = model.selectedPRKey(in: listKeys), let files = model.filesLink(for: key)
                else { return false }
                NSWorkspace.shared.open(files.url)
                return true
            }
            if Self.isControlCommandC(event, flags: flags) {
                guard let key = model.selectedPRKey(in: listKeys) else { return false }
                model.copyCheckoutCommand(key)
                return true
            }
            // ⌥⌘↩: Ask, whatever row is selected. Only from the open search field, never the save row.
            if Self.isOptionCommandReturn(event, flags: flags) {
                guard searchOpen, saveName == nil, model.settings.askEnabled else { return false }
                model.ask()
                return true
            }
            // Keypad Enter carries .numericPad and fn-Return .function; neither is a modifier here.
            guard flags.subtracting([.command, .shift, .capsLock, .numericPad, .function]).isEmpty else { return false }
            let key = Self.commandKey(event)
            // ⌘⇧C, ⌘⇧F, ⌘⇧B and ⌘⇧A are the only shifted commands.
            if flags.contains(.shift) {
                switch key {
                case "c":
                    guard let link = listKeys.flatMap(model.listSelectionLink(in:)) else { return false }
                    PRActions.copy(ListNavigation.reference(link.key))
                case "f":
                    // In the list, or with the search field open (⌘⇧F edits no text); not in the save row.
                    guard listKeys != nil || (searchOpen && saveName == nil), model.tabs != nil,
                          let view = repoMenuAnchor.view
                    else { return false }
                    showRepoMenu(listKeys: listKeys ?? [], in: view)
                case "b":
                    guard listKeys != nil, boardPartShown, let view = boardMenuAnchor.view else { return false }
                    BoardMenu.show(model: model, in: view, at: .zero)
                case "a":
                    // In the list, with the footer's account button on screen (not first run or an error).
                    guard listKeys != nil, let view = accountMenuAnchor.view, view.window != nil else { return false }
                    AccountMenu.show(model: model, in: view, at: .zero)
                default:
                    return false
                }
                return true
            }
            if event.keyCode == SearchKeyMonitor.return || event.keyCode == SearchKeyMonitor.enter {
                if searching {
                    model.openSearchSelectionOnGitHub()
                } else if let link = listKeys.flatMap(model.listSelectionLink(in:)) {
                    NSWorkspace.shared.open(link.url)
                } else {
                    return false
                }
                return true
            }
            // ⌘1 / ⌘2 by key position too: on layouts like AZERTY those keys don't type digits.
            if event.keyCode == SearchKeyMonitor.digit1 || event.keyCode == SearchKeyMonitor.digit2 {
                switchMode(to: event.keyCode == SearchKeyMonitor.digit1 ? .pullRequests : .issues)
                return true
            }
            switch key {
            case "f": openSearch()
            case "1": switchMode(to: .pullRequests)
            case "2": switchMode(to: .issues)
            case "r": if !model.status.isRefreshing { model.refresh() }
            case "c":
                guard let link = listKeys.flatMap(model.listSelectionLink(in:)) else { return false }
                PRActions.copy(link.url.absoluteString)
            default: return false
            }
            return true
        }
        if flags.contains(.control) { return false }
        // The save row's name field: Return saves, Esc cancels; every other key is the field's.
        if saveName != nil {
            switch event.keyCode {
            case SearchKeyMonitor.return, SearchKeyMonitor.enter:
                saveSearch()
                return true
            case SearchKeyMonitor.escape:
                closeSaveRow()
                return true
            default:
                return false
            }
        }
        // The open "@user", "~label", "is:" or "status:" list takes the arrows, Return, Tab and Esc; every other key
        // reaches the field.
        // ⇧ or ⌥ with an arrow or Tab is the field's (extend the selection, move focus back).
        if completionShown {
            let plain = flags.subtracting([.capsLock, .numericPad, .function]).isEmpty
            switch event.keyCode {
            case SearchKeyMonitor.upArrow, SearchKeyMonitor.downArrow:
                guard plain else { return false }
                model.moveCompletion(by: event.keyCode == SearchKeyMonitor.downArrow ? 1 : -1)
                return true
            case SearchKeyMonitor.tab:
                guard plain else { return false }
                acceptCompletion(in: window)
                return true
            case SearchKeyMonitor.return, SearchKeyMonitor.enter:
                acceptCompletion(in: window)
                return true
            case SearchKeyMonitor.escape:
                model.dismissCompletion()
                return true
            default:
                break
            }
        }
        // A grey qualifier after the caret (`sta` → `tus:`): plain Tab writes it; every other key is the field's.
        if !completionShown, fieldFocused, event.keyCode == SearchKeyMonitor.tab,
           flags.subtracting([.capsLock, .numericPad, .function]).isEmpty,
           qualifierGhostDrawn, let caret = model.acceptQualifierGhost()
        {
            placeCaretAfterUpdate(caret, in: window)
            return true
        }
        // The panel under the empty field: the arrows move one cursor over the saved chips and tokens
        // (← / → only once it is in the panel, ↑ from the first item back to the field), Return picks,
        // and Esc clears the cursor before it closes the search.
        if hintsActive {
            switch event.keyCode {
            case SearchKeyMonitor.upArrow, SearchKeyMonitor.downArrow, SearchKeyMonitor.leftArrow,
                 SearchKeyMonitor.rightArrow:
                guard flags.subtracting([.capsLock, .numericPad, .function]).isEmpty else { return false }
                let key: HintPanelKey = switch event.keyCode {
                case SearchKeyMonitor.upArrow: .up
                case SearchKeyMonitor.downArrow: .down
                case SearchKeyMonitor.leftArrow: .left
                default: .right
                }
                switch HintPanelItem.move(hintSelection, key, in: hintItems) {
                case .select(let item):
                    hintSelection = item
                    return true
                case .field:
                    hintSelection = nil
                    return true
                case .pass:
                    break
                }
            case SearchKeyMonitor.return, SearchKeyMonitor.enter:
                guard let item = hintSelection else { break }
                pickHintItem(item, fromKeyboard: true, in: window)
                return true
            case SearchKeyMonitor.escape:
                guard hintSelection != nil else { break }
                hintSelection = nil
                return true
            default:
                break
            }
        }
        switch event.keyCode {
        case SearchKeyMonitor.escape:
            if model.asking != nil {
                // Esc while asking cancels the Ask; the results and the query stay.
                model.cancelAsk()
            } else if searchOpen {
                cancelSearch()
            } else if model.listFocus.isActive {
                model.clearFocus()
            } else {
                MenuBarPopover.hide()
            }
            return true
        case SearchKeyMonitor.upArrow, SearchKeyMonitor.downArrow:
            let offset = event.keyCode == SearchKeyMonitor.downArrow ? 1 : -1
            if searching {
                model.moveSearchSelection(by: offset)
            } else if let listKeys {
                model.moveListSelection(by: offset, in: listKeys)
            } else {
                return false
            }
            return true
        case SearchKeyMonitor.leftArrow, SearchKeyMonitor.rightArrow:
            // Arrows carry .numericPad and .function; ⌥ and ⇧ arrows are left alone.
            guard listKeys != nil, flags.subtracting([.capsLock, .numericPad, .function]).isEmpty else { return false }
            model.moveTab(by: event.keyCode == SearchKeyMonitor.rightArrow ? 1 : -1)
            return true
        case SearchKeyMonitor.return, SearchKeyMonitor.enter:
            if searching {
                model.openSearchSelection()
                return true
            }
            guard let listKeys else { return false }
            return model.openListSelection(in: listKeys)
        default:
            break
        }
        // A focused text field (the search field or any other) types the character itself. Right after
        // type-anywhere focuses the field, its text is all selected; the caret moves to the end first
        // so this key appends instead of replacing.
        if window.firstResponder is NSText {
            placeCaretIfPending(in: window)
            return false
        }
        guard let text = SearchKeyMonitor.printableText(event) else { return false }
        // "/" opens an empty search field, as on GitHub; inside an open search it is just a character.
        if text == "/", !searchOpen {
            openSearch()
            return true
        }
        let base = model.searchText
        if base.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        model.updateSearch(base + text, caret: (base + text).utf16.count, startedOnTab: model.shownTab)
        fieldOpen = true
        caretToEnd = true
        DispatchQueue.main.async { fieldFocused = true }
        return true
    }

    /// The detail views have no search: Esc, ← and ⌘[ go back, ⌘↩ opens the page on GitHub, ⌘C copies its
    /// link (unless text is selected), ⌘⇧C its reference, ⌥⌘C its Markdown link, ⌘R fetches it again.
    /// Every other key passes through.
    private func handleDetailKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, in window: NSWindow) -> Bool {
        guard flags.contains(.command) else {
            if event.keyCode == SearchKeyMonitor.leftArrow {
                // Arrows carry .numericPad and .function; ⌥ and ⇧ arrows are left alone. SwiftUI's selectable
                // text doesn't report a selection, so ← goes back even with text selected.
                guard flags.subtracting([.capsLock, .numericPad, .function]).isEmpty else { return false }
                // Holding ← goes back once, not on through a stack and into the list's tab switching.
                if event.isARepeat { return true }
                swallowArrowRepeats = true
                model.closeShownDetail()
                return true
            }
            guard event.keyCode == SearchKeyMonitor.escape, flags.isDisjoint(with: [.control, .option])
            else { return false }
            model.closeShownDetail()
            return true
        }
        if Self.isOptionCommandC(event, flags: flags) { return model.copyShownDetailMarkdownLink() }
        // ⇧⌘↩ and ⌃⌘C act on a PR detail only.
        if Self.isShiftCommandReturn(event, flags: flags) {
            guard case .detail(let key) = model.route, let files = model.filesLink(for: key) else { return false }
            NSWorkspace.shared.open(files.url)
            return true
        }
        if Self.isControlCommandC(event, flags: flags) {
            guard case .detail(let key) = model.route else { return false }
            model.copyCheckoutCommand(key)
            return true
        }
        guard flags.subtracting([.command, .shift, .capsLock, .numericPad, .function]).isEmpty,
              let link = model.shownDetailLink else { return false }
        let key = Self.commandKey(event)
        if flags.contains(.shift) {
            guard key == "c" else { return false }
            PRActions.copy(ListNavigation.reference(link.key))
            return true
        }
        if event.keyCode == SearchKeyMonitor.return || event.keyCode == SearchKeyMonitor.enter {
            NSWorkspace.shared.open(link.url)
            return true
        }
        switch key {
        case "[": model.closeShownDetail()
        case "r": model.reloadShownDetail()
        case "c":
            // Selected description or comment text copies as text: the responder chain copies first, and
            // the link only when that put nothing on the pasteboard. SwiftUI's selectable text doesn't
            // report its selection, so asking it to copy is the only way to tell.
            let before = NSPasteboard.general.changeCount
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            if NSPasteboard.general.changeCount == before { PRActions.copy(link.url.absoluteString) }
        default: return false
        }
        return true
    }

    /// The Ask screen: ↑/↓ move the highlight, ↩ opens it in its mode, ⌘↩ opens it on GitHub, ⌘C copies
    /// its link, ⌘⇧C its reference, ⌥⌘C its Markdown link, Esc goes back to the field with the question to
    /// edit. Every other key passes through.
    private func handleAskKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let plain = flags.subtracting([.capsLock, .numericPad, .function])
        if flags.contains(.command) {
            if Self.isOptionCommandC(event, flags: flags) { return model.copyAskSelectionMarkdownLink() }
            guard plain.subtracting([.command, .shift]).isEmpty else { return false }
            if event.keyCode == SearchKeyMonitor.return || event.keyCode == SearchKeyMonitor.enter {
                return !plain.contains(.shift) && model.openAskSelectionOnGitHub()
            }
            guard Self.commandKey(event) == "c" else { return false }
            if plain.contains(.shift) { return model.copyAskSelectionReference() }
            // Selected answer text copies as text; otherwise ⌘C copies the highlighted row's link.
            let before = NSPasteboard.general.changeCount
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            return NSPasteboard.general.changeCount != before || model.copyAskSelectionLink()
        }
        switch event.keyCode {
        case SearchKeyMonitor.escape:
            guard flags.isDisjoint(with: [.control, .option]) else { return false }
            model.closeAsk()
            return true
        case SearchKeyMonitor.leftArrow:
            guard plain.isEmpty else { return false }
            model.closeAsk()
            return true
        case SearchKeyMonitor.upArrow, SearchKeyMonitor.downArrow:
            guard plain.isEmpty else { return false }
            model.moveAskSelection(by: event.keyCode == SearchKeyMonitor.downArrow ? 1 : -1)
            return true
        case SearchKeyMonitor.return, SearchKeyMonitor.enter:
            guard plain.isEmpty else { return false }
            model.openAskSelection()
            return true
        default:
            return false
        }
    }

    /// The filter row's leading padding, so the menu lines up with the row's leading edge.
    private static let repoMenuInset: CGFloat = 14

    /// ⌘⇧F: the repo menu under the filter row (or under the header without one), with the highlighted
    /// row's repository, else the focused one, positioned there. `popUp(positioning:)` puts that item
    /// under the point; whether AppKit also gives it the keyboard highlight is on the manual checklist,
    /// as no public API sets a menu's highlighted item.
    private func showRepoMenu(listKeys: [PRKey], in view: NSView) {
        let repo = model.listSelectionLink(in: listKeys)?.key.repo ?? model.repoFocus?.repo
        // The anchor is flipped: its bottom edge is at y = height.
        let point = NSPoint(x: Self.repoMenuInset, y: view.bounds.height)
        RepoMenu.show(model: model, highlighting: repo, in: view, at: point)
    }

    /// ⌥⌘↩ (or keypad Enter) exactly: no ⇧ or ⌃.
    private static func isOptionCommandReturn(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        flags.subtracting([.capsLock, .numericPad, .function]) == [.command, .option]
            && (event.keyCode == SearchKeyMonitor.return || event.keyCode == SearchKeyMonitor.enter)
    }

    /// ⇧⌘↩ (or keypad Enter) exactly: no ⌥ or ⌃.
    private static func isShiftCommandReturn(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        flags.subtracting([.capsLock, .numericPad, .function]) == [.command, .shift]
            && (event.keyCode == SearchKeyMonitor.return || event.keyCode == SearchKeyMonitor.enter)
    }

    /// ⌃⌘C exactly: no ⇧ or ⌥.
    private static func isControlCommandC(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        flags.subtracting([.capsLock, .numericPad, .function]) == [.control, .command] && commandKey(event) == "c"
    }

    /// ⌥⌘C exactly: no ⇧ or ⌃.
    private static func isOptionCommandC(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        flags.subtracting([.capsLock, .numericPad, .function]) == [.command, .option] && commandKey(event) == "c"
    }

    /// The key of a ⌘-chord, lowercased. Non-Latin layouts (Cyrillic, Greek…) fall back to the key
    /// position for the shortcut letters, as menu shortcuts do.
    private static func commandKey(_ event: NSEvent) -> String? {
        guard let typed = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        guard !typed.isEmpty, !typed.allSatisfy(\.isASCII) else { return typed }
        switch event.keyCode {
        case SearchKeyMonitor.letterF: return "f"
        case SearchKeyMonitor.letterR: return "r"
        case SearchKeyMonitor.letterC: return "c"
        case SearchKeyMonitor.leftBracket: return "["
        case SearchKeyMonitor.letterW: return "w"
        case SearchKeyMonitor.letterB: return "b"
        default: return typed
        }
    }

    private func dropHiddenListSelection() {
        let keys = model.listKeys(closedExpanded: closedExpanded, doneExpanded: doneExpanded)
        if ListNavigation.shown(model.listSelection, in: keys) == nil { model.listSelection = nil }
    }

    /// ⌘1 / ⌘2 or the mode switch. A query in the field stays and shows the new mode's results; an
    /// open field without one closes, so the new mode's tab shows its list.
    private func switchMode(to mode: PopoverMode) {
        if searchOpen, model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cancelSearch() }
        model.mode = mode
    }

    /// Puts the caret after the text in the active field editor (focusing a field selects all of it).
    private func placeCaretIfPending(in window: NSWindow?) {
        guard caretToEnd, let editor = window?.firstResponder as? NSTextView else { return }
        caretToEnd = false
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }

    /// Return, Tab or a row click: completes with the selected person or label, puts the caret after the
    /// inserted token once the field shows the new text, and says so. With no candidate the list just closes.
    private func acceptCompletion(in window: NSWindow?) {
        let speech: String? = switch model.completion {
        case .people(let people): people.selectedCandidate.map(CompletionSpeech.completed)
        case .labels(let labels): labels.selectedCandidate.map(CompletionSpeech.completed)
        case .states(let states): states.selectedCandidate.map(CompletionSpeech.completed)
        case .statuses(let statuses): statuses.selectedCandidate.map(CompletionSpeech.completed)
        case .updated(let steps): steps.selectedCandidate.map(CompletionSpeech.completed)
        case .reviews(let reviews): reviews.selectedCandidate.map(CompletionSpeech.completed)
        case .repos(let repos): repos.selectedCandidate.map(CompletionSpeech.completed)
        case nil: nil
        }
        guard let caret = model.acceptCompletion() else { return }
        placeCaretAfterUpdate(caret, in: window)
        if let speech { AccessibilityNotification.Announcement(speech).post() }
    }

    /// An item under the empty field, by click or Return: a saved search applies, "+N" expands the
    /// chips (from the keyboard, the first revealed one takes the cursor) and "Show less" folds them
    /// (the cursor stays on "+N"), a token starts its token.
    private func pickHintItem(_ item: HintPanelItem, fromKeyboard: Bool, in window: NSWindow?) {
        switch item {
        case .saved(let id):
            guard let saved = model.settings.savedSearches.items.first(where: { $0.id == id }) else { return }
            hintSelection = nil
            savedExpanded = false
            model.applySavedSearch(saved)
            caretAtEndOfField(in: window)
        case .more:
            if savedExpanded {
                savedExpanded = false
                hintSelection = fromKeyboard ? .more : nil
            } else {
                hintSelection = fromKeyboard ? hintCloud.firstHidden.map { .saved($0.id) } : nil
                savedExpanded = true
            }
        case .hint(let hint):
            pickHint(hint, in: window)
        }
    }

    /// A token: types its sigil into the empty field, which opens the `@`, `~`, `is:`, `status:` or `updated:` list.
    private func pickHint(_ hint: SearchHint, in window: NSWindow?) {
        hintSelection = nil
        model.startToken(hint.sigil)
        caretAtEndOfField(in: window)
    }

    /// After the model filled the field: the caret goes after its text, focusing the field if needed.
    private func caretAtEndOfField(in window: NSWindow?) {
        if fieldFocused {
            placeCaretAfterUpdate(model.searchText.utf16.count, in: window)
        } else {
            caretToEnd = true
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    /// The field's bookmark: the save row opens with the query as the name, selected for typing over.
    private func openSaveRow() {
        if completionShown { model.dismissCompletion() }
        hintSelection = nil
        saveName = SavedSearch.defaultName(for: model.searchText)
        DispatchQueue.main.async { saveNameFocused = true }
    }

    /// Save or Return: saves the field's query under the name and goes back to the search field.
    private func saveSearch() {
        guard let name = saveName, model.saveSearch(named: name) else { return }
        AccessibilityNotification.Announcement("Saved search \(SavedSearch.validName(name) ?? name)").post()
        closeSaveRow()
    }

    /// Cancel or Esc: the row closes and the caret goes back to the end of the search field.
    private func closeSaveRow() {
        saveName = nil
        caretToEnd = true
        DispatchQueue.main.async { fieldFocused = true }
    }

    /// Sets `caret` once the field editor shows the model's text (it lags the model by a run loop turn).
    private func placeCaretAfterUpdate(_ caret: Int, in window: NSWindow?) {
        pendingCaret = PendingCaret(text: model.searchText, caret: caret)
        DispatchQueue.main.async { applyPendingCaret(in: window) }
    }

    /// The one hop after completing: sets the caret if the field editor shows the completed text. If the
    /// editor still lags, the next selection change gets one chance; without a focused field (a click
    /// moved focus) or with other text, the caret is dropped.
    private func applyPendingCaret(in window: NSWindow?) {
        guard var pending = pendingCaret else { return }
        let editor = (window?.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0 : nil }
        let outcome = pending.afterHop(editorText: editor?.string, searchText: model.searchText)
        switch outcome {
        case .wait:
            pendingCaret = pending
        case .apply(let caret):
            pendingCaret = nil
            FieldCaret.set(caret, in: window, text: pending.text)
        case .drop:
            pendingCaret = nil
        }
    }

    /// VoiceOver hears the list open on a new token, the selection move, and narrowing leave no one;
    /// completing speaks for itself.
    private func announceCompletion(from old: SearchCompletion?, to new: SearchCompletion?) {
        guard presence.isShown,
              let speech = CompletionSpeech.change(from: old, to: new, loaded: model.snapshot != nil) else { return }
        AccessibilityNotification.Announcement(speech).post()
    }

    /// The tab on screen, PR or issue.
    private var pane: ListPane {
        switch model.mode {
        case .pullRequests: .pullRequests(model.selectedTab)
        case .issues: .issues(model.selectedIssueTab)
        }
    }

    /// The pane shows its rows rather than skeleton rows or why they are missing.
    private var paneHasRows: Bool {
        switch model.mode {
        case .pullRequests:
            model.scopedContents(of: model.selectedTab) != nil
        case .issues:
            model.issueTabs?.isLoaded(model.selectedIssueTab) == true
                && model.scopedContents(of: model.selectedIssueTab) != nil
        }
    }

    /// The rows' first arrival crossfades over the skeleton in place (it is laid out like them). A tab
    /// switch or a refresh stays instant, as do rows going away.
    private var rowsArrival: Animation? {
        paneHasRows && fadePane == pane ? .easeInOut(duration: 0.2) : nil
    }

    private func content(now: Date) -> some View {
        ZStack {
            switch model.mode {
            case .pullRequests:
                if let scoped = model.scopedContents(of: model.selectedTab) {
                    PRListView(
                        model: model, tab: model.selectedTab, scoped: scoped, total: total(of: model.selectedTab),
                        recentlyClosed: model.scopedRecentlyClosed, now: now,
                        closedExpanded: $closedExpanded)
                    .transition(.opacity)
                } else {
                    // While it fades out under the arriving rows, it takes no clicks.
                    emptyState
                        .allowsHitTesting(!paneHasRows)
                        .transition(.opacity)
                }
            case .issues:
                if let issueTabs = model.issueTabs {
                    issueList(issueTabs, now: now)
                } else {
                    emptyState
                        .transition(.opacity)
                }
            }
        }
        .animation(rowsArrival, value: paneHasRows)
        // Read on the next pass: a change of tab sees the old pane, so it doesn't fade.
        .onChange(of: pane, initial: true) { _, new in fadePane = new }
    }

    @ViewBuilder private func issueList(_ issueTabs: BuiltIssueTabs, now: Date) -> some View {
        if !issueTabs.isLoaded(model.selectedIssueTab) {
            IssueListNotLoadedView(model: model, tab: model.selectedIssueTab)
                .transition(.opacity)
        } else if let scoped = model.scopedContents(of: model.selectedIssueTab) {
            IssueListView(
                model: model, tab: model.selectedIssueTab, scoped: scoped,
                total: model.contents(of: model.selectedIssueTab)?.issues.count ?? 0, now: now,
                doneExpanded: doneExpanded(model.selectedIssueTab))
            .transition(.opacity)
        } else {
            BoardUnavailableView(model: model)
                .transition(.opacity)
        }
    }

    /// Everything the tab holds across repositories; on Mine the recently closed PRs count too, as a focus
    /// can hide only those.
    private func total(of tab: PRTab) -> Int {
        let rows = model.contents(of: tab)?.rows.count ?? 0
        return tab == .mine ? rows + (model.tabs?.recentlyClosed.count ?? 0) : rows
    }

    /// No snapshot yet: the install on the user's own account or the org approval an app account waits
    /// for, the SSO page to open, the error with Retry, or skeleton rows.
    @ViewBuilder private var emptyState: some View {
        if case .personalInstall = model.orgAccessNotice, let target = model.personalInstallTarget {
            PersonalInstallView(model: model, target: target, alignment: .center)
                .padding(.horizontal, 24)
        } else if let notice = model.orgAccessNotice, notice.blocksPolling {
            OrgApprovalView(notice: notice, checking: model.checkingAccess, alignment: .center) {
                Task { await model.checkOrgAccessAgain() }
            }
            .padding(.horizontal, 24)
        } else if case .ssoRequired(let url) = model.status.error, let org = model.settings.org {
            // SSO found while polling: the same block as when the installations check finds it.
            OrgApprovalView(
                notice: .ssoRequired(org: org, url: url), checking: model.status.isRefreshing, alignment: .center
            ) {
                model.refresh()
            }
            .padding(.horizontal, 24)
        } else if let error = model.status.error {
            VStack(spacing: 10) {
                Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.amberGlyph)
                Text(model.message(for: error))
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") { model.refresh() }
                    .controlSize(.small)
                    .disabled(model.status.isRefreshing)
            }
            .padding(.horizontal, 40)
        } else if model.mode == .issues {
            SkeletonList.issues(model, tab: model.selectedIssueTab)
        } else {
            SkeletonList.pullRequests(model)
        }
    }
}

/// No account yet, or the current app account is signed out: what PullBull is for and how to start.
/// With no account the buttons follow what launch found (`FirstRunChoice`): a `gh` login leads,
/// else Sign in with GitHub, else the GitHub CLI checklist.
private struct FirstRunView: View {
    let model: AppModel

    private var heading: String {
        model.isSignedOut ? "Signed out of GitHub" : "Welcome to PullBull"
    }

    /// "Use X from GitHub CLI" is running: the rest of the screen waits.
    private var usingGh: Bool { model.ghUse != nil && model.ghUse?.failure == nil }

    var body: some View {
        VStack(spacing: 0) {
            // The title names the app, so VoiceOver skips the icon.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(heading)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            // Signed out, the heading says it all.
            if !model.isSignedOut {
                note("See the pull requests that need you")
                    .padding(.top, 4)
            }
            if let error = model.status.error, !model.isSignedOut {
                note(model.message(for: error))
                    .padding(.top, 6)
            }
            if model.isSignedOut {
                Button("Sign In") { model.showSignIn() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canSignInWithGitHub)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 18)
            } else {
                choices(FirstRunChoice.make(gh: model.ghDetection, signIn: model.signInAvailability))
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    @ViewBuilder private func choices(_ choice: FirstRunChoice) -> some View {
        switch choice.primary {
        case .useGh(let login):
            useGhButton(login, others: choice.otherLogins)
                .padding(.top, 18)
            if let use = model.ghUse, let failure = use.failure {
                note(FirstRunChoice.failure(use.login, message: failure))
                    .padding(.top, 6)
            }
            note(FirstRunChoice.ghLine)
                .padding(.top, 6)
            if choice.offersSignIn {
                Button("Sign in with GitHub") { model.showSignIn() }
                    .buttonStyle(.bordered)
                    .disabled(usingGh)
                    .padding(.top, 16)
                note(FirstRunChoice.signInLine)
                    .padding(.top, 6)
            }
        case .signIn:
            Button("Sign in with GitHub") { model.showSignIn() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 18)
            note(FirstRunChoice.signInLine)
                .padding(.top, 6)
        case .setUpGh:
            Button("Set Up GitHub CLI…") { showChecklist() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 18)
        }
        if let note = choice.note {
            self.note(note)
                .padding(.top, 8)
        }
        if let link = choice.link {
            Button(link.title) { showChecklist() }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.top, 12)
        }
    }

    /// The lead button; Try Again after a failure, "Using X…" while it runs, X being whichever login
    /// was picked (`FirstRunChoice.ghButtonText`). With other logins it is a split button whose ▾ lists
    /// them. Return uses the lead. It is as wide as its widest title, so switching titles moves nothing.
    @ViewBuilder private func useGhButton(_ lead: String, others: [String]) -> some View {
        let use = model.ghUse
        let text = FirstRunChoice.ghButtonText(
            lead: lead, using: use?.failure == nil ? use?.login : nil,
            failed: use?.failure != nil ? use?.login : nil)
        let states = FirstRunChoice.ghButtonStates(lead: lead, others: others)
        if others.isEmpty {
            Button {
                Task { await model.useGhLogin(lead) }
            } label: {
                GhButtonLabel(text: text, states: states, darkSpinner: false)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(usingGh)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(text.label)
        } else {
            GhSplitButton(
                text: text, states: states, others: others,
                useLead: { Task { await model.useGhLogin(lead) } },
                use: { other in Task { await model.useGhLogin(other) } })
                .disabled(usingGh)
        }
    }

    private func showChecklist() {
        GhSetupWindowController.shared.show(app: model, purpose: .firstRun)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The gh button's title, with a spinner while it runs, laid over every title it can show (hidden), so
/// it is always as wide as the widest. Sized by the text, so the spinner can't make it taller.
private struct GhButtonLabel: View {
    let text: FirstRunChoice.GhButtonText
    let states: [FirstRunChoice.GhButtonText]
    /// White, for the split button's accent capsule.
    let darkSpinner: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            ForEach(states, id: \.self) { state in
                content(state).hidden()
            }
            content(text)
        }
    }

    private func content(_ state: FirstRunChoice.GhButtonText) -> some View {
        HStack(spacing: 6) {
            if state.running {
                ProgressView()
                    .controlSize(.small)
                    .environment(\.colorScheme, darkSpinner ? .dark : colorScheme)
                    .frame(height: 0)
            }
            Text(state.title)
        }
    }
}

/// [Use X from GitHub CLI | ▾] for several `gh` logins, drawn to match the plain `.borderedProminent`
/// button of the one-login case: macOS's own split menu (`Menu(primaryAction:)`) ignores that style and
/// draws grey. The main half uses the lead login and takes Return; the ▾ lists the others.
private struct GhSplitButton: View {
    let text: FirstRunChoice.GhButtonText
    let states: [FirstRunChoice.GhButtonText]
    let others: [String]
    let useLead: () -> Void
    let use: (String) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    /// The large `.borderedProminent` button's height, so both variants line up.
    private static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            Button(action: useLead) {
                GhButtonLabel(text: text, states: states, darkSpinner: true)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(HalfStyle())
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(text.label)
            // The other logins, also as actions on the main half.
            .accessibilityActions {
                ForEach(others, id: \.self) { other in
                    Button(FirstRunChoice.useTitle(other)) { use(other) }
                }
            }
            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 6)
                .accessibilityHidden(true)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .padding(.leading, 7)
                .padding(.trailing, 11)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
                // The whole ▾ half opens the menu: a SwiftUI borderless `Menu` takes clicks only on its
                // glyph and drops padding in its label.
                .overlay { LoginsMenu(others: others, use: use) }
        }
        .foregroundStyle(.white)
        .frame(height: Self.height)
        .background(Capsule().fill(Color.accentColor))
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .clipShape(Capsule())
        .opacity(isEnabled ? 1 : 0.5)
        .fixedSize()
    }

    /// The main half darkens while pressed, as the system's prominent button does.
    private struct HalfStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .contentShape(Rectangle())
                .background(Color.black.opacity(configuration.isPressed ? 0.15 : 0))
        }
    }

    /// An invisible pull-down that fills the ▾ half and lists the other logins.
    private struct LoginsMenu: NSViewRepresentable {
        let others: [String]
        let use: (String) -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSPopUpButton {
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            button.isBordered = false
            (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
            button.setAccessibilityLabel("More GitHub CLI logins")
            return button
        }

        func updateNSView(_ button: NSPopUpButton, context: Context) {
            context.coordinator.use = use
            button.isEnabled = context.environment.isEnabled
            // Rebuild only when the logins change, so an update while the menu is open leaves it alone.
            let shown = button.itemArray.dropFirst().compactMap { $0.representedObject as? String }
            guard shown != others || button.numberOfItems == 0 else { return }
            button.removeAllItems()
            // A pull-down's first item is its (empty) title, not a menu entry.
            button.addItem(withTitle: "")
            for other in others {
                let item = NSMenuItem(
                    title: FirstRunChoice.useTitle(other), action: #selector(Coordinator.choose(_:)),
                    keyEquivalent: "")
                item.target = context.coordinator
                item.representedObject = other
                button.menu?.addItem(item)
            }
        }

        /// Exactly the ▾ half it overlays.
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
            proposal.replacingUnspecifiedDimensions()
        }

        @MainActor final class Coordinator: NSObject {
            var use: (String) -> Void = { _ in }

            @objc func choose(_ item: NSMenuItem) {
                if let login = item.representedObject as? String { use(login) }
            }
        }
    }
}

/// The list tab on screen, for telling rows arriving apart from a tab switch.
private enum ListPane: Equatable {
    case pullRequests(PRTab), issues(IssueTab)
}

/// A detail view, or the Ask screen, stacked over the list.
private enum DetailLayer: Equatable {
    case ask, issue(PRKey), pr(PRKey)

    /// The layers the model's route shows, bottom to top: a linked PR's detail sits on the issue it was
    /// opened from, and details opened from Ask sit on the Ask screen.
    @MainActor static func stack(for model: AppModel) -> [DetailLayer] {
        let ask: [DetailLayer] = model.askReturn.isEmpty ? [] : [.ask]
        switch model.route {
        case .list, .search:
            return []
        case .ask:
            return [.ask]
        case .issueDetail(let key):
            return ask + [.issue(key)]
        case .detail(let key):
            if case .issueDetail(let issue) = model.detailReturnRoute { return ask + [.issue(issue), .pr(key)] }
            return ask + [.pr(key)]
        }
    }
}

/// A layer with a detail over it: it shifts a little toward the leading edge as the detail slides in,
/// shows only the part the detail has not reached yet, and fades out. Hidden, it takes no clicks, Tab
/// (Full Keyboard Access) or VoiceOver.
private struct CoveredLayer: ViewModifier {
    static let parallax: CGFloat = 80
    let covered: Bool
    let slides: Bool
    @Environment(\.skeletonAnimates) private var skeletonAnimates

    func body(content: Content) -> some View {
        let hiddenBySlide = covered && slides
        content
            .environment(\.skeletonAnimates, skeletonAnimates && !covered)
            .offset(x: hiddenBySlide ? -Self.parallax : 0)
            // In panel coordinates: ends where the sliding detail's leading edge is.
            .mask(alignment: .leading) {
                Rectangle().frame(width: hiddenBySlide ? 0 : PopoverView.size.width)
            }
            .opacity(covered ? 0 : 1)
            .allowsHitTesting(!covered)
            .accessibilityHidden(covered)
            .disabled(covered)
    }
}

/// A detail layer: a soft shadow just outside its leading edge marks it while it slides. At rest the
/// shadow is outside the panel.
private struct PushedLayer: ViewModifier {
    let slides: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if slides {
                LinearGradient(colors: [.clear, .black.opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 10)
                    .offset(x: -10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A detail sliding out after Back: clicks go to the layer it uncovers.
private struct LeavingLayer: ViewModifier {
    let leaving: Bool

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!leaving)
            .accessibilityHidden(leaving)
    }
}

#if DEBUG
enum PreviewData {
    /// The kit's `search_page.json` fixture, decoded the same way live search pages are.
    static let snapshot: Snapshot = {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packages/PullBullKit/Tests/PullBullKitTests/Fixtures/search_page.json")
        let prs = (try? Data(contentsOf: fixture)).flatMap { try? Decoding.pullRequests(fromSearch: $0).prs } ?? []
        let org = OrgContext(
            org: "initech", viewer: "devon", members: ["alice", "carol", "devon"],
            myTeams: [], repos: ["gadgets", "widgets"])
        return Snapshot(
            fetchedAt: Date().addingTimeInterval(-60), org: org, reviewCandidates: prs, mine: prs,
            team: prs, recentlyClosed: [], boardIssues: [])
    }()
}

#Preview("Team") {
    var settings = AppSettings()
    settings.lastTab = .team
    return PopoverView(model: AppModel(preview: PreviewData.snapshot, settings: settings))
}

#Preview("Team, focused") {
    var settings = AppSettings()
    settings.lastTab = .team
    let model = AppModel(preview: PreviewData.snapshot, settings: settings)
    model.focus(on: "initech/widgets")
    return PopoverView(model: model)
}

#Preview("Mine, compact") {
    var settings = AppSettings()
    settings.lastTab = .mine
    settings.compact = true
    return PopoverView(model: AppModel(preview: PreviewData.snapshot, settings: settings))
}

#Preview("Search, people list") {
    var settings = AppSettings()
    settings.lastTab = .team
    let model = AppModel(preview: PreviewData.snapshot, settings: settings)
    model.updateSearch("login @a", caret: 8)
    return PopoverView(model: model)
}

#Preview("Search, @alice") {
    var settings = AppSettings()
    settings.lastTab = .team
    let model = AppModel(preview: PreviewData.snapshot, settings: settings)
    model.updateSearch("@alice login")
    return PopoverView(model: model)
}

#Preview("First run") {
    var settings = AppSettings()
    settings.account = nil
    let model = AppModel(preview: PreviewData.snapshot, settings: settings)
    return PopoverView(model: model)
}

#Preview("Offline") {
    let snap = PreviewData.snapshot
    var settings = AppSettings()
    settings.lastTab = .team
    return PopoverView(model: AppModel(
        preview: snap, settings: settings,
        status: RefreshStatus(lastSuccess: snap.fetchedAt.addingTimeInterval(-660), error: .offline, isRefreshing: false)))
}
#endif
