import AppKit
import PullBullKit
import SwiftUI

/// Records one key combo from the keyboard. While recording, every key goes here and the global
/// shortcut is set aside so pressing it again can be recorded; Esc cancels.
@Observable @MainActor
final class KeyRecorder {
    private(set) var isRecording = false
    /// Why the last combo pressed was not accepted.
    private(set) var hint: String?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: (any NSObjectProtocol)?

    func start(onRecord: @escaping @MainActor (KeyCombo) -> Void) {
        stop()
        isRecording = true
        GlobalHotkey.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread; the event never leaves it.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isRecording else { return false }
                self.handle(event, onRecord: onRecord)
                return true
            }
            return consumed ? nil : event
        }
        // Leaving the Settings window (or the app) ends recording, so the shortcut isn't left off.
        if let window = NSApp.keyWindow {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        hint = nil
        guard isRecording else { return }
        isRecording = false
        GlobalHotkey.shared.resume()
    }

    private func handle(_ event: NSEvent, onRecord: @MainActor (KeyCombo) -> Void) {
        let modifiers = Self.modifiers(event.modifierFlags)
        if event.keyCode == 53, modifiers.isEmpty {  // Esc
            stop()
            return
        }
        switch KeyCombo.validated(keyCode: event.keyCode, modifiers: modifiers) {
        case .success(let combo):
            stop()
            onRecord(combo)
        case .failure(let invalid):
            hint = invalid.message
        }
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}

/// The recorder control: the current combo (click to record a new one) and a button that turns the
/// shortcut off.
struct ShortcutRecorderField: View {
    let recorder: KeyRecorder
    let combo: KeyCombo?
    let onRecord: @MainActor (KeyCombo) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if recorder.isRecording { recorder.stop() } else { recorder.start(onRecord: onRecord) }
            } label: {
                Text(title)
                    .monospacedDigit()
                    .foregroundStyle(recorder.isRecording || combo == nil ? .secondary : .primary)
                    .frame(minWidth: 110)
            }
            .help(recorder.isRecording ? "Press a shortcut, or Esc to cancel" : "Click to record a new shortcut")
            .accessibilityLabel(recorder.isRecording ? "Recording shortcut" : "Shortcut, \(combo?.localizedDisplayString ?? "none")")
            if combo != nil, !recorder.isRecording {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Turn off the shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear { recorder.stop() }
    }

    private var title: String {
        if recorder.isRecording { return "Type shortcut…" }
        return combo?.localizedDisplayString ?? "Record Shortcut"
    }
}
