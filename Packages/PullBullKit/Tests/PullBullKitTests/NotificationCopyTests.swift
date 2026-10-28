import Foundation
import Testing
@testable import PullBullKit

private func event(_ kind: PREventKind, actor: String?) -> PREvent {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let pr = PullRequest(
        key: PRKey(repo: "initech/api", number: 42), title: "Fix the thing", url: URL(string: "https://x/42")!,
        author: "me", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: date, updatedAt: date, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
        headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
    return PREvent(kind: kind, pr: pr, actor: actor)
}

@Suite struct NotificationCopyTests {
    @Test func titlesLeadWithIdentity() {
        #expect(event(.reviewRequested, actor: "bob").notificationTitle == "api #42 · Review requested")
        #expect(event(.approved, actor: "bob").notificationTitle == "api #42 · Approved")
        #expect(event(.changesRequested, actor: "bob").notificationTitle == "api #42 · Changes requested")
        #expect(event(.ciFailed, actor: nil).notificationTitle == "api #42 · CI failed")
        #expect(event(.newComment, actor: "bob").notificationTitle == "api #42 · New comment")
    }

    @Test func subtitleNamesTheActor() {
        #expect(event(.reviewRequested, actor: "bob").notificationSubtitle == "by bob")
        #expect(event(.changesRequested, actor: "bob").notificationSubtitle == "by bob")
        #expect(event(.newComment, actor: "bob").notificationSubtitle == "by bob")
        #expect(event(.ciFailed, actor: nil).notificationSubtitle == nil)
        #expect(event(.ciFailed, actor: "bob").notificationSubtitle == nil)
    }

    @Test func ciSubtitleNamesOneFailureAndCountsSeveral() {
        func check(_ name: String, _ state: CIState) -> Check { Check(name: name, state: state, url: nil) }
        #expect(PREvent.ciSubtitle([]) == nil)
        #expect(PREvent.ciSubtitle([check("lint", .success), check("build", .pending)]) == nil)
        #expect(PREvent.ciSubtitle([check("lint", .success), check("test", .failure)]) == "test failed")
        #expect(PREvent.ciSubtitle([check("test", .failure), check("build", .failure), check("lint", .success)])
            == "2 checks failed")
    }

    @Test func missingActorHasNoSubtitle() {
        #expect(event(.reviewRequested, actor: nil).notificationSubtitle == nil)
        #expect(event(.approved, actor: nil).notificationSubtitle == nil)
        #expect(event(.newComment, actor: nil).notificationSubtitle == nil)
    }

    @Test func mergedCopy() {
        #expect(event(.merged, actor: "anna").notificationTitle == "api #42 · Merged")
        #expect(event(.merged, actor: "anna").notificationSubtitle == "by anna")
        #expect(event(.merged, actor: nil).notificationSubtitle == nil)
        #expect(event(.merged, actor: "anna").notificationBody == "Fix the thing")
    }

    @Test func bodyIsThePRTitle() {
        #expect(event(.ciFailed, actor: nil).notificationBody == "Fix the thing")
    }
}

@Suite struct IssueNotificationCopyTests {
    private func issueEvent(actor: String?) -> IssueEvent {
        let issue = BoardIssue(
            key: PRKey(repo: "initech/gadgets", number: 231),
            title: "Webhook retries exhaust the DB connection pool under load",
            url: URL(string: "https://x/231")!, isOpen: true)
        return IssueEvent(kind: .assigned, issue: issue, actor: actor)
    }

    @Test func issueAssignedCopy() {
        let event = issueEvent(actor: "dev-b")
        #expect(event.notificationTitle == "gadgets #231 · Assigned to you")
        #expect(event.notificationSubtitle == "by dev-b")
        #expect(event.notificationBody == "Webhook retries exhaust the DB connection pool under load")
        #expect(issueEvent(actor: nil).notificationSubtitle == nil)
    }
}
