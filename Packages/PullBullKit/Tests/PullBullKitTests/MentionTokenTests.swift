import Testing
@testable import PullBullKit

@Suite struct MentionTokenTests {
    private func token(_ text: String, caret: Int? = nil) -> MentionToken? {
        MentionToken.at(text, caret: caret ?? text.utf16.count)
    }

    @Test func bareAtAtTheStart() {
        let t = token("@")
        #expect(t?.prefix == "")
        #expect(t?.range == 0..<1)
    }

    @Test func afterWhitespace() {
        let t = token("hi @da")
        #expect(t?.prefix == "da")
        #expect(t?.range == 3..<6)
    }

    @Test(arguments: ["(@da", "[@da", "{@da", "\"@da", "'@da"])
    func afterAnOpeningCharacter(_ text: String) {
        #expect(token(text)?.prefix == "da")
    }

    @Test func insideAWordIsNoToken() {
        #expect(token("a@b.com") == nil)
        #expect(token("a@b") == nil)
    }

    @Test func teamSlug() {
        #expect(token("@acme/back")?.prefix == "acme/back")
    }

    @Test func twoSlashesIsNoToken() {
        #expect(token("@a/b/c") == nil)
    }

    @Test func caretAfterASpaceIsNoToken() {
        #expect(token("@da ") == nil)
    }

    @Test func caretInTheMiddle() {
        let t = token("@dana", caret: 3)
        #expect(t?.prefix == "da")
        #expect(t?.range == 0..<3)
    }

    @Test func afterANewline() {
        let t = token("hello\n@da")
        #expect(t?.prefix == "da")
        #expect(t?.range == 6..<9)
    }

    @Test func emojiKeepsUTF16Offsets() {
        let t = token("😀 @da")
        #expect(t?.prefix == "da")
        #expect(t?.range == 3..<6)
    }

    @Test func nonASCIIIsNoToken() {
        #expect(token("@дана") == nil)
    }

    @Test func caretOutOfBoundsIsNoToken() {
        #expect(MentionToken.at("@a", caret: 9) == nil)
        #expect(MentionToken.at("@a", caret: -1) == nil)
    }

    @Test func insertsWithATrailingSpace() throws {
        let text = "hi @da"
        let t = try #require(token(text))
        let result = t.inserting("dana", into: text)
        #expect(result.text == "hi @dana ")
        #expect(result.caret == 9)
    }

    @Test func insertReplacesOnlyTheToken() throws {
        let text = "x @ac y"
        let t = try #require(token(text, caret: 5))
        let result = t.inserting("acme/backend", into: text)
        #expect(result.text == "x @acme/backend y")
        #expect(result.caret == 16)
    }

    @Test func insertBeforeASpaceDoesNotDoubleIt() throws {
        let text = "hi @da world"
        let t = try #require(token(text, caret: 6))
        let result = t.inserting("dana", into: text)
        #expect(result.text == "hi @dana world")
        #expect(result.caret == 9)
    }

    @Test func insertAfterAnEmoji() throws {
        let text = "😀 @da"
        let t = try #require(token(text))
        let result = t.inserting("dana", into: text)
        #expect(result.text == "😀 @dana ")
        #expect(result.caret == 9)
    }
}
