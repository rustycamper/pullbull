import Foundation

/// How a person is on a pull request or issue.
public enum PersonRole: Hashable, Sendable {
    case author, assignee, requested
    case reviewed(ReviewState)
}

public enum PersonMatch {
    /// The roles `login` has on `pr`. `me` resolves to `viewer`; comparison ignores case.
    public static func roles(of pr: PullRequest, login: String, viewer: String) -> Set<PersonRole> {
        let target = resolve(login, viewer: viewer)
        var roles = Set<PersonRole>()
        if same(pr.author, target) { roles.insert(.author) }
        for request in pr.reviewRequests {
            if case .user(let user) = request, same(user, target) { roles.insert(.requested) }
        }
        for review in pr.latestReviews where same(review.author, target) {
            roles.insert(.reviewed(review.state))
        }
        return roles
    }

    public static func roles(of issue: BoardIssue, login: String, viewer: String) -> Set<PersonRole> {
        let target = resolve(login, viewer: viewer)
        var roles = Set<PersonRole>()
        if let author = issue.author, same(author, target) { roles.insert(.author) }
        if issue.assignees.contains(where: { same($0.login, target) }) { roles.insert(.assignee) }
        return roles
    }

    /// The row label for the first `@` token: the first row of the spec's table that applies.
    /// `author` is the issue's author, or nil for a pull request, whose meta line already shows it.
    public static func label(for roles: Set<PersonRole>, author: String?) -> String? {
        if roles.contains(.reviewed(.approved)) { return "approved" }
        if roles.contains(.reviewed(.changesRequested)) { return "changes requested" }
        let reviewed = roles.contains {
            if case .reviewed = $0 { return true }
            return false
        }
        if reviewed { return "reviewer" }
        if roles.contains(.requested) { return "review requested" }
        if roles.contains(.assignee) { return "assigned" }
        if roles.contains(.author), let author { return "by \(author)" }
        return nil
    }

    private static func resolve(_ login: String, viewer: String) -> String {
        login.lowercased() == "me" ? viewer : login
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}
