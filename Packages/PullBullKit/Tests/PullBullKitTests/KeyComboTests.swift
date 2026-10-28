import Foundation
import Testing
@testable import PullBullKit

@Suite struct KeyComboTests {
    @Test func defaultIsControlOptionP() {
        #expect(KeyCombo.togglePopoverDefault.displayString == "⌃⌥P")
        #expect(KeyCombo.togglePopoverDefault.carbonModifiers == 0x1000 | 0x0800)
    }

    @Test func displayUsesMenuOrder() {
        let combo = KeyCombo(keyCode: 49, modifiers: [.command, .shift, .option, .control])
        #expect(combo.displayString == "⌃⌥⇧⌘Space")
        #expect(KeyCombo(keyCode: 122, modifiers: [.command]).displayString == "⌘F1")
        #expect(KeyCombo(keyCode: 90, modifiers: [.option]).displayString == "⌥F20")
        #expect(KeyCombo(keyCode: 126, modifiers: [.control]).displayString == "⌃↑")
    }

    @Test func layoutCharacterNamesCharacterKeys() {
        let p = KeyCombo.togglePopoverDefault
        // Dvorak types "l" on the ANSI P key; AZERTY types "a" on the ANSI Q key.
        #expect(p.displayString(layoutCharacter: "l") == "⌃⌥L")
        #expect(KeyCombo(keyCode: 12, modifiers: [.command]).displayString(layoutCharacter: "a") == "⌘A")
        #expect(KeyCombo(keyCode: 10, modifiers: [.option]).displayString(layoutCharacter: "<") == "⌥<")
    }

    @Test func fallsBackToANSINamesWithoutAUsableCharacter() {
        let p = KeyCombo.togglePopoverDefault
        #expect(p.displayString(layoutCharacter: nil) == "⌃⌥P")
        #expect(p.displayString(layoutCharacter: "") == "⌃⌥P")
        #expect(p.displayString(layoutCharacter: " ") == "⌃⌥P")
        #expect(p.displayString(layoutCharacter: "\u{10}") == "⌃⌥P")
        #expect(p.displayString(layoutCharacter: "ab") == "⌃⌥P")
        #expect(KeyCombo(keyCode: 10, modifiers: [.option]).displayString == "⌥§")
        // Keys with fixed names ignore the layout.
        #expect(KeyCombo(keyCode: 49, modifiers: [.control]).displayString(layoutCharacter: "x") == "⌃Space")
        #expect(KeyCombo(keyCode: 122, modifiers: [.control]).displayString(layoutCharacter: "x") == "⌃F1")
    }

    @Test func carbonModifierBits() {
        #expect(KeyCombo(keyCode: 0, modifiers: [.command]).carbonModifiers == 0x0100)
        #expect(KeyCombo(keyCode: 0, modifiers: [.shift]).carbonModifiers == 0x0200)
        #expect(KeyCombo(keyCode: 0, modifiers: [.option]).carbonModifiers == 0x0800)
        #expect(KeyCombo(keyCode: 0, modifiers: [.control]).carbonModifiers == 0x1000)
    }

    @Test func validationNeedsCommandControlOrOption() {
        #expect(KeyCombo.validated(keyCode: 35, modifiers: []) == .failure(.needsModifier))
        #expect(KeyCombo.validated(keyCode: 35, modifiers: [.shift]) == .failure(.needsModifier))
        for modifier: KeyCombo.Modifiers in [.command, .control, .option] {
            #expect(KeyCombo.validated(keyCode: 35, modifiers: [modifier, .shift])
                == .success(KeyCombo(keyCode: 35, modifiers: [modifier, .shift])))
        }
    }

    @Test func validationRejectsModifierAndUnknownKeys() {
        // Left ⇧, left ⌘, fn, Esc and a keypad key.
        for code: UInt16 in [56, 55, 63, 53, 82] {
            #expect(KeyCombo.validated(keyCode: code, modifiers: [.control]) == .failure(.unsupportedKey))
        }
    }

    @Test func codableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 40, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
