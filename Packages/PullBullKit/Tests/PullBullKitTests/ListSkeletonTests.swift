import Foundation
import Testing
@testable import PullBullKit

@Suite struct ListSkeletonTests {
    @Test func prHeaderFollowsGroupingAndFocus() {
        #expect(ListSkeleton.prLeadsWithHeader(grouping: .repository, focused: false))
        #expect(!ListSkeleton.prLeadsWithHeader(grouping: .repository, focused: true))
        #expect(!ListSkeleton.prLeadsWithHeader(grouping: .none, focused: false))
    }

    @Test func createdFollowsGroupingAndFocus() {
        #expect(ListSkeleton.issueLeadsWithHeader(tab: .created, grouping: .repository, focused: false, statusKnown: true))
        #expect(!ListSkeleton.issueLeadsWithHeader(tab: .created, grouping: .none, focused: false, statusKnown: true))
        #expect(!ListSkeleton.issueLeadsWithHeader(tab: .created, grouping: .repository, focused: true, statusKnown: true))
    }

    @Test func assignedAndBoardKeepStatusHeadersUnderFocus() {
        for tab in [IssueTab.assigned, .board] {
            #expect(ListSkeleton.issueLeadsWithHeader(tab: tab, grouping: .none, focused: false, statusKnown: false))
            #expect(ListSkeleton.issueLeadsWithHeader(tab: tab, grouping: .none, focused: true, statusKnown: true))
            #expect(!ListSkeleton.issueLeadsWithHeader(tab: tab, grouping: .repository, focused: true, statusKnown: false))
            #expect(ListSkeleton.issueLeadsWithHeader(tab: tab, grouping: .repository, focused: true, statusKnown: nil))
        }
    }

    /// The kit's own grouping agrees: under a focus, repo groups merge into an untitled group.
    @Test func matchesFocusedRepoGroups() {
        let issue = BoardIssue(
            key: PRKey(repo: "o/a", number: 1), title: "i", url: URL(string: "https://x/1")!, isOpen: true)
        let contents = IssueTabContents(groups: [IssueGroup(kind: .repo("o/a"), issues: [issue], counted: true)])
        let scoped = RepoFocus(repo: "o/a").scope(contents)
        #expect(scoped.contents.groups.first?.title.isEmpty == true)
        #expect(!ListSkeleton.issueLeadsWithHeader(tab: .assigned, grouping: .repository, focused: true, statusKnown: false))
    }
}
