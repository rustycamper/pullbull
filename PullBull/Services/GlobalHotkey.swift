import AppKit
import Carbon.HIToolbox
import Observation
import PullBullKit

/// The system-wide shortcut that toggles the popover, registered with Carbon's `RegisterEventHotKey`
/// (no Accessibility permission needed).
@Observable @MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// Why the last change could not be applied; nil once one succeeds.
    private(set) var error: String?
    /// The combo in effect (also while the recorder has it suspended).
    private(set) var combo: KeyCombo?

    @ObservationIgnored var onPress: (@MainActor () -> Void)?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?

    fileprivate static let signature: OSType = 0x504C_4252  // "PLBR"
    fileprivate static let hotKeyID: UInt32 = 1

    /// Makes `newCombo` the shortcut (nil turns it off). When it can't be registered the previous one
    /// stays in effect, `error` says why, and this returns false.
    @discardableResult
    func apply(_ newCombo: KeyCombo?) -> Bool {
        guard let newCombo else {
            unregister()
            combo = nil
            error = nil
            return true
        }
        if newCombo == combo, hotKeyRef != nil {
            error = nil
            return true
        }
        if Self.isSystemShortcut(newCombo) {
            error = "\(newCombo.localizedDisplayString) is a macOS shortcut (System Settings › Keyboard › Keyboard Shortcuts)"
            return false
        }
        var ref: EventHotKeyRef?
        let status = register(newCombo, into: &ref)
        guard status == noErr, let ref else {
            error = status == eventHotKeyExistsErr
                ? "This shortcut is already in use."
                : "Couldn’t register \(newCombo.localizedDisplayString) (error \(status))"
            return false
        }
        unregister()
        hotKeyRef = ref
        combo = newCombo
        error = nil
        return true
    }

    /// Lets the combo reach the app as ordinary key events, for the shortcut recorder.
    func suspend() {
        unregister()
    }

    /// Registers the combo again after `suspend()`.
    func resume() {
        guard let combo, hotKeyRef == nil else { return }
        var ref: EventHotKeyRef?
        if register(combo, into: &ref) == noErr { hotKeyRef = ref }
    }

    private func register(_ combo: KeyCombo, into ref: inout EventHotKeyRef?) -> OSStatus {
        installHandlerIfNeeded()
        return RegisterEventHotKey(
            UInt32(combo.keyCode), combo.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
            GetApplicationEventTarget(), 0, &ref)
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalHotkey.signature, id.id == GlobalHotkey.hotKeyID else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { GlobalHotkey.shared.onPress?() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }

    /// True when an enabled macOS shortcut (System Settings › Keyboard Shortcuts) uses `combo`.
    private static func isSystemShortcut(_ combo: KeyCombo) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let list = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        let relevant = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return list.contains { entry in
            let enabled = (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true
            let code = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint16Value
            let mods = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value ?? 0
            return enabled && code == combo.keyCode && mods & relevant == combo.carbonModifiers
        }
    }
}
