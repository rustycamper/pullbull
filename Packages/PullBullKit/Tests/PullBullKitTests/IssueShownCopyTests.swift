import Foundation
import Testing
@testable import PullBullKit

private let early = Date(timeIntervalSince1970: 1_800_000_000)
private let late = Date(timeIntervalSince1970: 1_800_000_500)
private let bug = LabelRef(id: "LA_bug", name: "bug", color: "d73a4a")

private func issue(labels: [String] = [], updatedAt: Date?) -> BoardIssue {
    BoardIssue(
        key: editKey(7), title: "Issue 7", url: URL(string: "https://github.com/o/r/issues/7")!, isOpen: true,
        updatedAt: updatedAt, labels: labels, labelColors: labels.map { _ in nil })
}

private func detail(_ issue: BoardIssue) -> IssueDetail {
    IssueDetail(key: issue.key, issue: issue, body: "", commentTotal: 0, lastComments: [], linkedPRs: [])
}

@Suite struct IssueShownCopyTests {
    @Test func newerListCopyWinsOnceTheOverlayIsRetired() {
        let list = issue(labels: ["bug"], updatedAt: late)
        let shown = IssueDetail.shownIssue(detail: detail(issue(updatedAt: early)), list: list, overrides: EditOverrides())
        #expect(shown?.labels == ["bug"])
    }

    @Test func newerDetailWinsWithPendingEditsOverIt() {
        var overrides = EditOverrides()
        overrides.record(.labels(added: [bug], removed: []), on: editKey(7), at: early)
        let shown = IssueDetail.shownIssue(
            detail: detail(issue(labels: ["docs"], updatedAt: late)), list: issue(updatedAt: early), overrides: overrides)
        #expect(shown?.labels == ["docs", "bug"])
    }

    @Test func equalUpdatedAtKeepsTheDetail() {
        let shown = IssueDetail.shownIssue(
            detail: detail(issue(labels: ["docs"], updatedAt: early)), list: issue(labels: ["bug"], updatedAt: early),
            overrides: EditOverrides())
        #expect(shown?.labels == ["docs"])
    }

    @Test func noListCopyShowsTheDetailWithEdits() {
        var overrides = EditOverrides()
        overrides.record(.labels(added: [bug], removed: []), on: editKey(7), at: early)
        let shown = IssueDetail.shownIssue(detail: detail(issue(updatedAt: early)), list: nil, overrides: overrides)
        #expect(shown?.labels == ["bug"])
    }

    @Test func noDetailShowsTheListCopy() {
        let list = issue(labels: ["bug"], updatedAt: early)
        #expect(IssueDetail.shownIssue(detail: nil, list: list, overrides: EditOverrides()) == list)
    }

    @Test func neitherShowsNothing() {
        #expect(IssueDetail.shownIssue(detail: nil, list: nil, overrides: EditOverrides()) == nil)
    }

    @Test func nilUpdatedAtOnTheDetailKeepsTheDetail() {
        let shown = IssueDetail.shownIssue(
            detail: detail(issue(labels: ["docs"], updatedAt: nil)), list: issue(labels: ["bug"], updatedAt: late),
            overrides: EditOverrides())
        #expect(shown?.labels == ["docs"])
    }

    @Test func nilUpdatedAtOnTheListKeepsTheDetail() {
        let shown = IssueDetail.shownIssue(
            detail: detail(issue(labels: ["docs"], updatedAt: early)), list: issue(labels: ["bug"], updatedAt: nil),
            overrides: EditOverrides())
        #expect(shown?.labels == ["docs"])
    }
}
