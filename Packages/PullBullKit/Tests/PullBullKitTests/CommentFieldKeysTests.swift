import Foundation
import Testing
@testable import PullBullKit

private enum Key {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let c: UInt16 = 8
    static let r: UInt16 = 15
    static let z: UInt16 = 6
    static let l: UInt16 = 37
    static let m: UInt16 = 46
    static let leftBracket: UInt16 = 33
}

private typealias Mods = KeyCombo.Modifiers

private func route(_ keyCode: UInt16, _ flags: Mods = [], mentionsOpen: Bool = false,
                   composing: Bool = false, review: ReviewPhase? = nil) -> CommentKeyAction {
    CommentFieldKeys.route(keyCode: keyCode, flags: flags, mentionsOpen: mentionsOpen, composing: composing,
                           review: review)
}

@Suite struct CommentFieldKeysTests {
    @Test(arguments: [ReviewPhase.composing, .checking, .sending])
    func commandReturnSubmitsInReviewMode(phase: ReviewPhase) {
        #expect(route(Key.returnKey, .command, review: phase) == .submitReview)
        #expect(route(Key.keypadEnter, .command, review: phase) == .submitReview)
        #expect(route(Key.returnKey, .command, review: nil) == .post)
    }

    @Test(arguments: [Key.left, Key.right])
    func optionArrowsChangeVerdictOnlyWhileComposing(keyCode: UInt16) {
        #expect(route(keyCode, .option, review: .composing) == .changeVerdict)
        #expect(route(keyCode, .option, review: .checking) == .text)
        #expect(route(keyCode, .option, review: .sending) == .text)
        #expect(route(keyCode, .option, review: nil) == .text)
    }

    @Test func escLeavesReviewBeforeField() {
        #expect(route(Key.escape, review: .composing) == .leaveReview)
        #expect(route(Key.escape, mentionsOpen: true, review: .composing) == .closeMentions)
        #expect(route(Key.escape, review: nil) == .leaveField)
    }

    @Test func escDuringSendGoesToTheModel() {
        #expect(route(Key.escape, review: .sending) == .leaveReview)
    }

    @Test(arguments: [
        (Key.escape, Mods()), (Key.returnKey, Mods.command), (Key.left, Mods.option), (Key.right, Mods.option),
    ])
    func composingKeepsEveryKeyInReviewMode(keyCode: UInt16, flags: KeyCombo.Modifiers) {
        #expect(route(keyCode, flags, composing: true, review: .composing) == .text)
    }

    /// An input method composing keeps every key, Esc and ⌘↩ included, with the list open or not.
    @Test(arguments: [
        (Key.escape, Mods()), (Key.returnKey, Mods.command), (Key.keypadEnter, Mods.command),
        (Key.returnKey, Mods()), (Key.tab, Mods()), (Key.up, Mods()), (Key.down, Mods()), (Key.left, Mods()),
        (Key.z, Mods.command),
    ])
    func composingKeepsEveryKey(keyCode: UInt16, flags: KeyCombo.Modifiers) {
        #expect(route(keyCode, flags, composing: true) == .text)
        #expect(route(keyCode, flags, mentionsOpen: true, composing: true) == .text)
    }

    @Test(arguments: [Key.returnKey, Key.keypadEnter])
    func commandReturnPosts(keyCode: UInt16) {
        #expect(route(keyCode, [.command]) == .post)
        #expect(route(keyCode, [.command], mentionsOpen: true) == .post)
    }

    /// ⇧⌘↩ and ⌥⌘↩ are the detail's Files changed and Ask AI; in the field they're text.
    @Test(arguments: [Key.returnKey, Key.keypadEnter])
    func otherCommandReturnsAreText(keyCode: UInt16) {
        #expect(route(keyCode, [.command, .shift]) == .text)
        #expect(route(keyCode, [.command, .option]) == .text)
    }

    @Test func plainReturnIsText() {
        #expect(route(Key.returnKey) == .text)
    }

    @Test func escapeLeavesTheFieldOrClosesTheList() {
        #expect(route(Key.escape) == .leaveField)
        #expect(route(Key.escape, mentionsOpen: true) == .closeMentions)
    }

    /// The detail's shortcuts act on the text, or do nothing, while the field has focus.
    @Test(arguments: [
        (Key.z, Mods.command), (Key.r, Mods.command), (Key.leftBracket, Mods.command), (Key.c, Mods.command),
        (Key.c, Mods([.command, .shift])), (Key.c, Mods([.command, .option])), (Key.c, Mods([.command, .control])),
        (Key.a, Mods([.command, .option])), (Key.l, Mods([.command, .option])), (Key.r, Mods([.command, .option])),
        (Key.s, Mods([.command, .option])), (Key.m, Mods([.command, .option])),
        (Key.left, Mods()), (Key.up, Mods.option),
    ] as [(UInt16, Mods)])
    func detailShortcutsAreText(keyCode: UInt16, flags: KeyCombo.Modifiers) {
        #expect(route(keyCode, flags) == .text)
    }

    @Test func arrowsMoveTheMentionHighlight() {
        #expect(route(Key.up, mentionsOpen: true) == .moveMention(-1))
        #expect(route(Key.down, mentionsOpen: true) == .moveMention(1))
    }

    @Test(arguments: [Key.returnKey, Key.tab])
    func returnAndTabAcceptTheMention(keyCode: UInt16) {
        #expect(route(keyCode, mentionsOpen: true) == .acceptMention)
    }

    /// Mention keys apply only with no modifiers.
    @Test(arguments: [(Key.down, Mods.option), (Key.tab, Mods.shift), (Key.returnKey, Mods.shift)] as [(UInt16, Mods)])
    func modifiedMentionKeysAreText(keyCode: UInt16, flags: KeyCombo.Modifiers) {
        #expect(route(keyCode, flags, mentionsOpen: true) == .text)
    }

    @Test func mentionKeysAreTextWithTheListClosed() {
        #expect(route(Key.tab) == .text)
        #expect(route(Key.up) == .text)
        #expect(route(Key.down) == .text)
    }
}
