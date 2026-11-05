import Foundation
import Testing
@testable import PullBullKit

private enum Key {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let escape: UInt16 = 53
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    static let g: UInt16 = 5
    static let v: UInt16 = 9
    static let m: UInt16 = 46
}

private typealias Mods = KeyCombo.Modifiers

private func route(_ keyCode: UInt16, _ flags: Mods = [], isRepeat: Bool = false) -> MergeKeyAction {
    MergePanelKeys.route(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
}

@Suite struct MergePanelKeysTests {
    @Test(arguments: [Key.returnKey, Key.keypadEnter])
    func controlCommandReturnConfirms(key: UInt16) {
        #expect(route(key, [.control, .command]) == .confirm)
    }

    /// ⌘↩ posts, submits and opens GitHub everywhere else; plain ↩ opens things. Neither may get past the panel.
    @Test(arguments: [Key.returnKey, Key.keypadEnter])
    func commandReturnIsSwallowed(key: UInt16) {
        #expect(route(key, .command) == .swallow)
        #expect(route(key) == .swallow)
    }

    @Test(arguments: [Mods.control, [.option, .command], [.shift, .command], [.control, .option, .command],
                      [.control, .shift, .command]])
    func otherChordsOnReturnNeverConfirm(flags: KeyCombo.Modifiers) {
        #expect(route(Key.returnKey, flags) == .swallow)
    }

    @Test(arguments: [Key.returnKey, Key.keypadEnter])
    func heldKeyNeverConfirms(key: UInt16) {
        #expect(route(key, [.control, .command], isRepeat: true) == .swallow)
    }

    @Test func optionArrowsChangeMethod() {
        #expect(route(Key.left, .option) == .changeMethod(-1))
        #expect(route(Key.right, .option) == .changeMethod(1))
    }

    /// One press, one step: a held key can't run on past the method the viewer stopped at.
    @Test func heldArrowChangesTheMethodOnce() {
        #expect(route(Key.right, .option, isRepeat: true) == .swallow)
    }

    @Test(arguments: [Mods(), .command, [.option, .shift]])
    func arrowsWithoutOptionAloneDoNothing(flags: KeyCombo.Modifiers) {
        #expect(route(Key.left, flags) == .swallow)
        #expect(route(Key.right, flags) == .swallow)
    }

    @Test func escapeCloses() {
        #expect(route(Key.escape) == .close)
    }

    @Test(arguments: [Mods.command, .option, .control, .shift])
    func escapeWithAModifierDoesNothing(flags: KeyCombo.Modifiers) {
        #expect(route(Key.escape, flags) == .swallow)
    }

    @Test func everyOtherKeyIsSwallowed() {
        #expect(route(Key.tab) == .swallow)
        #expect(route(Key.space) == .swallow)
        #expect(route(Key.up, .option) == .swallow)
        #expect(route(Key.down, .option) == .swallow)
        #expect(route(Key.g) == .swallow)
        #expect(route(Key.g, [.option, .command]) == .swallow)
        #expect(route(Key.v, [.option, .command]) == .swallow)
        #expect(route(Key.m, [.option, .command]) == .swallow)
    }
}
