import Testing
@testable import PullBullKit

@Suite struct PRGlyphTests {
    @Test func openAndDraft() {
        #expect(PRGlyph(state: .open, isDraft: false) == .open)
        #expect(PRGlyph(state: .open, isDraft: true) == .draft)
    }

    @Test func mergedAndClosedIgnoreDraft() {
        #expect(PRGlyph(state: .merged, isDraft: false) == .merged)
        #expect(PRGlyph(state: .merged, isDraft: true) == .merged)
        #expect(PRGlyph(state: .closed, isDraft: false) == .closed)
        #expect(PRGlyph(state: .closed, isDraft: true) == .closed)
    }

    @Test func pullRequestGlyph() {
        #expect(ReadyToMergeTests.pr(isDraft: true).glyph == .draft)
        #expect(ReadyToMergeTests.pr(state: .merged, isDraft: true).glyph == .merged)
    }
}
