import Foundation
import Testing
@testable import PullBullKit

private let k7 = PRKey(repo: "acme/widgets", number: 7)
private let k8 = PRKey(repo: "acme/widgets", number: 8)

@Suite struct CommentDraftsTests {
    @Test func draftsAreKeptPerAccountAndKey() {
        var drafts = CommentDrafts()
        drafts[account: "pb", key: k7] = CommentDraft(text: "hello", caret: 5)
        drafts[account: "pb", key: k8] = CommentDraft(text: "other", caret: 2)
        drafts[account: "work", key: k7] = CommentDraft(text: "work's", caret: 0)
        #expect(drafts[account: "pb", key: k7] == CommentDraft(text: "hello", caret: 5))
        #expect(drafts[account: "pb", key: k8] == CommentDraft(text: "other", caret: 2))
        #expect(drafts[account: "work", key: k7] == CommentDraft(text: "work's", caret: 0))
        #expect(drafts[account: "work", key: k8] == nil)
    }

    @Test func emptyTextRemovesTheDraft() {
        var drafts = CommentDrafts()
        drafts[account: "pb", key: k7] = CommentDraft(text: "hello", caret: 5)
        drafts[account: "pb", key: k7] = CommentDraft(text: "", caret: 0)
        #expect(drafts[account: "pb", key: k7] == nil)
        #expect(drafts == CommentDrafts())
        drafts[account: "pb", key: k7] = CommentDraft(text: "again", caret: 5)
        drafts[account: "pb", key: k7] = nil
        #expect(drafts == CommentDrafts())
    }

    @Test func dropAccountRemovesOnlyThatAccounts() {
        var drafts = CommentDrafts()
        drafts[account: "pb", key: k7] = CommentDraft(text: "mine", caret: 4)
        drafts[account: "pb", key: k8] = CommentDraft(text: "mine too", caret: 4)
        drafts[account: "work", key: k7] = CommentDraft(text: "work's", caret: 0)
        drafts.dropAccount("PB")
        #expect(drafts[account: "pb", key: k7] == nil)
        #expect(drafts[account: "pb", key: k8] == nil)
        #expect(drafts[account: "work", key: k7] == CommentDraft(text: "work's", caret: 0))
    }

    @Test func aLowercaseLoginMatches() {
        var drafts = CommentDrafts()
        drafts[account: "PBojkov", key: k7] = CommentDraft(text: "hello", caret: 1)
        #expect(drafts[account: "pbojkov", key: k7] == CommentDraft(text: "hello", caret: 1))
        drafts[account: "pbojkov", key: k7] = CommentDraft(text: "hello!", caret: 6)
        #expect(drafts[account: "PBojkov", key: k7] == CommentDraft(text: "hello!", caret: 6))
    }
}
