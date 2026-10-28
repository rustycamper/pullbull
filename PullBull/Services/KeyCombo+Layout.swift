import Carbon.HIToolbox
import Foundation
import PullBullKit

extension KeyCombo {
    /// The shortcut as the current keyboard layout labels it ("⌃⌥L" for the ANSI P key on Dvorak).
    @MainActor var localizedDisplayString: String {
        displayString(layoutCharacter: Self.layoutCharacter(for: keyCode))
    }

    /// The character the current keyboard layout types for `keyCode` with no modifiers, or nil.
    /// Text Input Sources must be read on the main thread.
    @MainActor private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        // The layout data belongs to `source`; keep it alive until the translation is done.
        return withExtendedLifetime(source) { () -> String? in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = data.withUnsafeBytes { buffer -> OSStatus in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                    return OSStatus(paramErr)
                }
                // No dead-key processing, so a dead key (German ´) reports its own character.
                return UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length,
                    &characters)
            }
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
