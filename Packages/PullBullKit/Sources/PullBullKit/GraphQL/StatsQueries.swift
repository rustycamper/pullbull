import Foundation

/// The queries behind the Stats screen, and the search strings they and the issue counts use.
enum StatsQueries {
    static let organizationID = """
    query($org:String!){organization(login:$org){id}}
    """

    /// One page of the PRs the viewer reviewed in `$from`..`$to`, newest first, with the review requests
    /// and the viewer's own reviews on each.
    static let contributions = """
    query($from:DateTime!,$to:DateTime!,$org:ID,$login:String!,$after:String){
      viewer{
        contributionsCollection(organizationID:$org,from:$from,to:$to){
          pullRequestReviewContributions(first:100,after:$after,orderBy:{direction:DESC}){
            pageInfo{hasNextPage endCursor}
            nodes{
              pullRequest{
                author{login}
                repository{nameWithOwner}
                timelineItems(itemTypes:[REVIEW_REQUESTED_EVENT],last:20){
                  nodes{... on ReviewRequestedEvent{createdAt
                    requestedReviewer{__typename ... on User{login} ... on Team{slug}}}}
                }
                reviews(author:$login,last:50){nodes{submittedAt state}}
              }
            }
          }
        }
      }
    }
    """

    static let merged = """
    query($q:String!){
      search(query:$q,type:ISSUE,first:100){
        issueCount
        nodes{... on PullRequest{createdAt mergedAt}}
      }
    }
    """

    static let opened = """
    query($q:String!){
      search(query:$q,type:ISSUE,first:100){
        issueCount
        nodes{... on PullRequest{
          createdAt isDraft state
          readyEvent:timelineItems(itemTypes:[READY_FOR_REVIEW_EVENT],last:1){nodes{... on ReadyForReviewEvent{createdAt}}}
          reviews(first:50){nodes{submittedAt state author{__typename login avatarUrl}}}
        }}
      }
    }
    """

    static let count = """
    query($q:String!){search(query:$q,type:ISSUE,first:0){issueCount}}
    """

    /// The viewer's issue comments, newest page first; `$before` is the previous page's `startCursor`.
    static let comments = """
    query($before:String){
      viewer{
        issueComments(last:100,before:$before){
          pageInfo{hasPreviousPage startCursor}
          nodes{createdAt repository{nameWithOwner}}
        }
      }
    }
    """

    /// ISO 8601 UTC with seconds, as GitHub's date ranges and `DateTime` variables take it.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func range(_ window: StatsWindow) -> String {
        "\(timestamp(window.start))..\(timestamp(window.githubEnd))"
    }

    static func openedPRs(window: StatsWindow, scope: FetchScope) -> String {
        "is:pr author:@me created:\(range(window)) archived:false sort:created-desc \(scope.searchQualifier)"
    }

    static func mergedPRs(window: StatsWindow, scope: FetchScope) -> String {
        "is:pr author:@me is:merged merged:\(range(window)) archived:false sort:created-desc \(scope.searchQualifier)"
    }

    static func closedIssues(window: StatsWindow, scope: FetchScope) -> String {
        "is:issue assignee:@me closed:\(range(window)) archived:false \(scope.searchQualifier)"
    }

    static func openedIssues(window: StatsWindow, scope: FetchScope) -> String {
        "is:issue author:@me created:\(range(window)) archived:false \(scope.searchQualifier)"
    }
}
