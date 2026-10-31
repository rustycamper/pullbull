import Foundation

/// A global keyboard shortcut: a virtual key code (the layout-independent code AppKit and Carbon report)
/// plus modifiers.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public enum Invalid: Error, Equatable, Sendable {
        /// None of ⌘, ⌃ or ⌥ is held (⇧ alone would steal plain typing).
        case needsModifier
        /// A modifier key on its own, or a key without a name here.
        case unsupportedKey

        public var message: String {
            switch self {
            case .needsModifier: "Use at least one of ⌘, ⌃ or ⌥"
            case .unsupportedKey: "That key can’t be used in a shortcut"
            }
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥P.
    public static let togglePopoverDefault = KeyCombo(keyCode: 35, modifiers: [.control, .option])

    /// A recorded combo, or why it can't be a global shortcut.
    public static func validated(keyCode: UInt16, modifiers: Modifiers) -> Result<KeyCombo, Invalid> {
        guard keyNames[keyCode] != nil else { return .failure(.unsupportedKey) }
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return .failure(.needsModifier) }
        return .success(KeyCombo(keyCode: keyCode, modifiers: modifiers))
    }

    /// Modifiers in the standard menu order (⌃⌥⇧⌘), then the key as on a US ANSI keyboard: "⌃⌥P".
    public var displayString: String { displayString(layoutCharacter: nil) }

    /// As `displayString`, with the key named by the character the current keyboard layout types for it
    /// (a Dvorak user's keycode 35 is "L", not "P"). Keys without a typed character (arrows, F-keys,
    /// Space, Return…) and a missing or blank character keep their fixed names.
    public func displayString(layoutCharacter: String?) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyName(layoutCharacter: layoutCharacter)
    }

    /// As `displayString`, one keycap per modifier and one for the key: `["⌃", "⌥", "P"]`.
    public func keycaps(layoutCharacter: String?) -> [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        return caps + [keyName(layoutCharacter: layoutCharacter)]
    }

    func keyName(layoutCharacter: String?) -> String {
        let fixed = Self.keyNames[keyCode] ?? "?"
        guard Self.characterKeys.contains(keyCode), let character = layoutCharacter?.uppercased(),
              character.count == 1, character.unicodeScalars.allSatisfy({ scalar in
                  !CharacterSet.whitespacesAndNewlines.contains(scalar)
                      && !CharacterSet.controlCharacters.contains(scalar)
              })
        else { return fixed }
        return character
    }

    /// Keys whose name is the character they type, so the keyboard layout decides it.
    static let characterKeys: Set<UInt16> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27,
        28, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50,
    ]

    /// The modifier mask `RegisterEventHotKey` takes (cmdKey, shiftKey, optionKey, controlKey).
    public var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= 1 << 8 }
        if modifiers.contains(.shift) { mask |= 1 << 9 }
        if modifiers.contains(.option) { mask |= 1 << 11 }
        if modifiers.contains(.control) { mask |= 1 << 12 }
        return mask
    }

    /// Names for the keys a shortcut may use, by virtual key code (ANSI layout).
    static let keyNames: [UInt16: String] = {
        var names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
            50: "`", 10: "§",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        let functionKeys: [UInt16] = [
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
        ]
        for (index, code) in functionKeys.enumerated() { names[code] = "F\(index + 1)" }
        return names
    }()
}
