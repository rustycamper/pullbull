import AppKit
import SwiftUI

/// The popover: shows, hides and toggles the panel under the status item. Calls made before the status
/// item exists (a notification click that launched the app) wait for it.
@MainActor
enum MenuBarPopover {
    private static var controller: PopoverController?
    private static var showWhenInstalled = false

    static var isShown: Bool { controller?.isShown ?? false }

    static func install(_ controller: PopoverController) {
        self.controller = controller
        guard showWhenInstalled else { return }
        showWhenInstalled = false
        // The status item gets its place in the menu bar on the next pass of the run loop.
        DispatchQueue.main.async { controller.show() }
    }

    static func show() {
        guard let controller else {
            showWhenInstalled = true
            return
        }
        controller.show()
    }

    static func hide() {
        showWhenInstalled = false
        controller?.hide()
    }

    static func toggle() {
        guard let controller else { return show() }
        controller.toggle()
    }
}

/// Open and close signals for the SwiftUI content, sent by the controller as they happen.
@MainActor
final class PopoverPresence {
    fileprivate(set) var isShown = false
    fileprivate(set) weak var window: NSWindow?
    var onShow: ((NSWindow) -> Void)?
    var onHide: (() -> Void)?
}

/// Owns the status item and the panel that hosts `PopoverView`.
///
/// The panel is non-activating: it takes key focus without making PullBull the active app, so typing
/// works at once whichever app is frontmost (macOS may refuse an activation request from a hotkey), and
/// closing it leaves that app in front. PullBull is activated only for the Settings window.
@MainActor
final class PopoverController: NSObject {
    static let size = NSSize(width: 360, height: 560)

    /// Open or closed, as this controller last left it. AppKit can order the panel out behind its back
    /// (Hide PullBull), so this is not the same as `panel.isVisible`.
    private(set) var isShown = false

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: PopoverPanel
    private let presence = PopoverPresence()
    private var label: StatusItemLabel?
    private var statusTooltip = ""
    private var labelTimer: Timer?
    private var outsideClickMonitor: Any?
    private var observers: [any NSObjectProtocol] = []
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var lockObserver: (any NSObjectProtocol)?

    init(model: AppModel) {
        self.model = model
        panel = PopoverPanel(size: Self.size)
        super.init()
        let hosting = NSHostingView(rootView: PopoverView(model: model, presence: presence))
        hosting.sizingOptions = []
        panel.setContent(hosting)
        applySolidBackground()
        presence.window = panel

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            // The button is in the menu bar from launch; the panel's content first renders when the panel
            // is first shown. So the anchor lives here, and the status item menu can open Settings at once.
            let anchor = NSHostingView(rootView: SettingsOpenerAnchor())
            anchor.sizingOptions = []
            anchor.frame = .zero
            button.addSubview(anchor)
        }
        trackLabel()
        // The stale state depends on the clock as well as the model; common modes keep it running while
        // a menu is open.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        RunLoop.main.add(timer, forMode: .common)
        labelTimer = timer
        observeWindowsAndApps()
    }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func show() {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard !isShown else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let frame = frameUnderStatusItem() else { return }
        isShown = true
        applyTooltip()
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        showOpenHighlight(true)
        presence.isShown = true
        presence.onShow?(panel)
        // Clicks in other apps (or on their menu bar items) close the popover.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                guard let self else { return }
                // The menu bar can deliver a click on our own item to another process first; closing here
                // would let the item's action reopen the panel. That click toggles it instead.
                if self.statusItemFrame()?.contains(location) == true { return }
                self.close()
            }
        }
    }

    /// Closes from the keyboard, the status item or the hotkey. If PullBull is active with nothing else
    /// of ours open, it steps back so the previous app gets focus again.
    func hide() {
        guard isShown else { return }
        close()
        let otherWindowOpen = NSApp.windows.contains { window in
            window !== panel && window.isVisible && window.styleMask.contains(.titled)
        }
        if NSApp.isActive, !otherWindowOpen { NSApp.hide(nil) }
    }

    /// Takes the panel down and undoes everything `show()` set up. Runs whenever the controller thinks
    /// the panel is open, even if AppKit already ordered it out.
    private func close() {
        guard isShown else { return }
        isShown = false
        applyTooltip()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        panel.orderOut(nil)
        showOpenHighlight(false)
        presence.isShown = false
        presence.onHide?()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isMenuClick = event?.type == .rightMouseDown
            || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true)
        if isMenuClick { showMenu() } else { toggle() }
    }

    /// Marks the item as open while the panel is up, as the system does for an item's menu. The menu bar
    /// draws a status button's own `highlight(_:)` only while a menu is attached, so this is drawn here,
    /// as the button layer's background, which sits behind the glyph.
    private func showOpenHighlight(_ open: Bool) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        layer.cornerRadius = 6
        var color: CGColor?
        if open {
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                color = NSColor.labelColor.withAlphaComponent(0.16).cgColor
            }
        }
        layer.backgroundColor = color
    }

    /// The right-click menu. It is attached to the status item for this one click only: a permanent
    /// `statusItem.menu` would swallow the left-click toggle. `performClick` blocks until the menu
    /// closes, and the system highlights the item for exactly that long.
    private func showMenu() {
        close()
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let about = NSMenuItem(title: "About PullBull", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if Updater.shared.isAvailable {
            // No action while Sparkle is busy, which the menu's auto-enabling shows as disabled.
            let action = Updater.shared.canCheckForUpdates ? #selector(checkForUpdates) : nil
            let updates = NSMenuItem(title: "Check for Updates…", action: action, keyEquivalent: "")
            updates.target = self
            menu.addItem(updates)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PullBull", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        aboutChosen = false
        settingsChosen = false
        updatesChosen = false
        button.performClick(nil)
        statusItem.menu = nil
        button.highlight(false)
        // Opened only now: the menu has closed, so its closing can't take focus back from Settings.
        if aboutChosen {
            // As for Settings: a plain activate() is refused, and the panel would open behind the front app.
            SettingsOpener.forceActivate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        if settingsChosen { SettingsOpener.open() }
        if updatesChosen { Updater.shared.checkForUpdates() }
    }

    /// Set by the menu's About item while the menu is still up, like Settings below.
    private var aboutChosen = false
    /// Set by the menu's Settings item while the menu is still up; `showMenu()` acts on it.
    private var settingsChosen = false
    /// The same for Check for Updates…, whose window would otherwise open under the closing menu.
    private var updatesChosen = false

    @objc private func openAbout() {
        aboutChosen = true
    }

    @objc private func openSettings() {
        settingsChosen = true
    }

    @objc private func checkForUpdates() {
        updatesChosen = true
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func observeWindowsAndApps() {
        let center = NotificationCenter.default
        // Another of the app's own windows (Settings) came forward while the popover is open: close,
        // and bring PullBull to the front with it. Losing key focus alone does not close the panel:
        // the input-source indicator briefly takes key when the search field gets focus.
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, self.isShown, let window, window !== self.panel,
                      window.sheetParent !== self.panel, window.styleMask.contains(.titled) else { return }
                NSApp.activate()
                self.close()
            }
        })
        // Hide PullBull (⌘H, or Hide Others from another app) orders the panel out without asking.
        observers.append(center.addObserver(
            forName: NSApplication.didHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        // A display was added, removed or rearranged; the status item may now be elsewhere.
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followStatusItem() }
        })
        // A new status item gets its place in the menu bar a moment after launch, and items can shift
        // later; the open panel follows it. Matched by identity so it works even if the status bar
        // window didn't exist yet at this point.
        observers.append(center.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window, window === self.statusItem.button?.window else { return }
                self.followStatusItem()
            }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        // Another app came to the front (⌘-Tab, Mission Control, a Dock click). The panel never
        // activates PullBull, so this replaces "PullBull resigned active".
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isOther = app?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                guard isOther else { return }
                self?.close()
            }
        })
        // Leaving the screen without an activation change: a Space switch (the panel would stay on the
        // old Space and the next hotkey press would only close it), sleep, or a user switch.
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
        ] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func followStatusItem() {
        guard isShown, let frame = frameUnderStatusItem() else { return }
        panel.setFrame(frame, display: true)
    }

    // MARK: Background

    private func applySolidBackground() {
        let solid = withObservationTracking {
            model.settings.solidBackground
        } onChange: { [weak self] in
            Task { @MainActor in self?.applySolidBackground() }
        }
        panel.setSolidBackground(solid)
    }

    // MARK: Label

    private func labelState(now: Date) -> (StatusItemLabel, String) {
        (StatusItemLabel(model: model, now: now), model.statusTooltip(now: now))
    }

    /// The only caller besides setup is its own `onChange`, so exactly one registration is live.
    private func trackLabel() {
        let (next, tooltip) = withObservationTracking {
            labelState(now: Date())
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackLabel() }
        }
        apply(label: next, tooltip: tooltip)
    }

    /// Re-renders without registering tracking; the timer uses this so registrations don't pile up.
    private func render() {
        let (next, tooltip) = labelState(now: Date())
        apply(label: next, tooltip: tooltip)
    }

    private func apply(label next: StatusItemLabel, tooltip: String) {
        statusTooltip = tooltip
        applyTooltip()
        guard next != label, let button = statusItem.button else { return }
        label = next
        button.image = next.image()
        button.setAccessibilityLabel(next.accessibilityText)
    }

    /// No tooltip while the panel is open: it would cover the panel.
    private func applyTooltip() {
        statusItem.button?.toolTip = isShown ? nil : statusTooltip
    }

    // MARK: Placement

    /// Centered under the status item on its screen, inside that screen's visible frame. Until the item
    /// is in the menu bar (just after launch, or hidden for lack of room) the panel sits at the top right
    /// of the main screen. Nil when there is no screen at all.
    /// The status item's button in screen coordinates, if it is on screen.
    private func statusItemFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window, window.isVisible else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func frameUnderStatusItem() -> NSRect? {
        let size = Self.size
        let margin: CGFloat = 6
        guard let button = statusItem.button, let window = button.window, let screen = window.screen,
              window.isVisible, window.frame.maxY >= screen.frame.maxY - 1 else {
            guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return nil }
            return NSRect(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin,
                          width: size.width, height: size.height)
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        var y = min(anchor.minY, visible.maxY) - size.height - 4
        y = max(y, visible.minY + margin)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// A borderless, rounded, non-activating panel with the system popover material. It becomes key (so
/// the search field takes typing) without activating the app.
private final class PopoverPanel: NSPanel {
    static let cornerRadius: CGFloat = 11

    init(size: NSSize) {
        // .nonactivatingPanel only takes effect reliably when set at creation.
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private let solidView = SolidBackgroundView()
    private var material: NSVisualEffectView?

    func setSolidBackground(_ solid: Bool) {
        solidView.isHidden = !solid
        // Solid keeps the effect view active for text vibrancy, over the opaque fill beneath it.
        material?.material = solid ? .windowBackground : .popover
        material?.blendingMode = solid ? .withinWindow : .behindWindow
    }

    func setContent(_ view: NSView) {
        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.cornerMask(radius: Self.cornerRadius)
        view.frame = material.bounds
        view.autoresizingMask = [.width, .height]
        let container = NSView(frame: material.frame)
        solidView.frame = container.bounds
        solidView.autoresizingMask = [.width, .height]
        solidView.cornerRadius = Self.cornerRadius
        solidView.isHidden = true
        material.autoresizingMask = [.width, .height]
        container.addSubview(solidView)
        container.addSubview(material)
        material.addSubview(view)
        self.material = material
        contentView = container
    }

    private static func cornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// An opaque rounded fill in the window background colour, redrawn when the appearance changes.
private final class SolidBackgroundView: NSView {
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}
