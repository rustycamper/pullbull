import Foundation

enum Queries {
    /// The rollup's context counts, which tell a run of only skipped or neutral checks from a passing one
    /// (`Decoding.ciState(rollup:)`). Counts only, so `contexts` needs no page size.
    static let rollupCounts = "checkRunCount checkRunCountsByState{state count} statusContextCount"

    static let prFields = """
    fragment prFields on PullRequest {
      number title url isDraft state mergeable createdAt updatedAt closedAt headRefName baseRefName
      repository{nameWithOwner}
      author{login avatarUrl}
      comments(last:1){totalCount nodes{author{__typename login}}}
      commits(last:1){nodes{commit{oid committedDate statusCheckRollup{state contexts{\(rollupCounts)}}}}}
      latestReviews(first:20){nodes{author{login} state submittedAt commit{oid}}}
      reviewRequests(first:20){nodes{requestedReviewer{__typename ... on User{login} ... on Team{slug}}}}
      labels(first:20){nodes{name color}}
      mergedBy{login}
    }
    """

    static let issueRowFields = """
    fragment issueRowFields on Issue {
      number title url state stateReason createdAt updatedAt closedAt
      repository{nameWithOwner} author{login} comments{totalCount}
      labels(first:20){nodes{name color}} assignees(first:10){nodes{login avatarUrl}}
    }
    """

    /// The AssignedEvents an Assigned search reads to tell who assigned the viewer, and when.
    static let assignedEvents = """
    timelineItems(itemTypes:[ASSIGNED_EVENT], last:10){nodes{... on AssignedEvent{\
    createdAt actor{login} assignee{__typename ... on User{login}}}}}
    """

    /// An issue that left Assigned or Created, with who last closed it.
    static let closedIssue = """
    query($owner:String!,$name:String!,$n:Int!){
      repository(owner:$owner, name:$name){
        issue(number:$n){
          ...issueRowFields
          lastClose: timelineItems(itemTypes:[CLOSED_EVENT], last:1){nodes{... on ClosedEvent{createdAt actor{login}}}}
        }
      }
    }
    \(issueRowFields)
    """

    static let viewer = "query{viewer{login}}"

    static let organizations = "query{viewer{organizations(first:100){nodes{login}}}}"

    /// The owner's Projects (v2) boards. A board's owner is an organization or a user, each read
    /// through its own root field.
    static func projects(_ owner: BoardOwner) -> String {
        """
        query($login:String!){
          \(root(owner))(login:$login){
            projectsV2(first:100, orderBy:{field:NUMBER, direction:ASC}){nodes{number title}}
          }
        }
        """
    }

    /// The root field that reads `owner`, and the key its data comes back under.
    static func root(_ owner: BoardOwner) -> String {
        owner.isUser ? "user" : "organization"
    }

    static let orgContext = """
    query($org:String!,$logins:[String!]){
      organization(login:$org){
        membersWithRole(first:100){pageInfo{endCursor hasNextPage} nodes{login}}
        teams(first:100, userLogins:$logins){nodes{slug}}
        repositories(first:100){pageInfo{endCursor hasNextPage} nodes{name}}
      }
    }
    """

    /// The viewer and the repositories they own, for an account in no org; also each next page.
    static let personalContext = """
    query($after:String){
      viewer{
        login
        repositories(first:100, after:$after, ownerAffiliations:OWNER){pageInfo{endCursor hasNextPage} nodes{name}}
      }
    }
    """

    static let orgMembers = """
    query($org:String!,$after:String){
      organization(login:$org){
        membersWithRole(first:100, after:$after){pageInfo{endCursor hasNextPage} nodes{login}}
      }
    }
    """

    static let orgRepos = """
    query($org:String!,$after:String){
      organization(login:$org){
        repositories(first:100, after:$after){pageInfo{endCursor hasNextPage} nodes{name}}
      }
    }
    """

    static let search = """
    query($q:String!,$after:String,$first:Int=50){
      search(query:$q, type:ISSUE, first:$first, after:$after){
        pageInfo{endCursor hasNextPage}
        nodes{... on PullRequest{...prFields}}
      }
    }
    \(prFields)
    """

    /// The Ask index's search: PRs and issues with their text, `__typename` telling them apart.
    static let askSearch = """
    query($q:String!,$first:Int!,$after:String){
      search(query:$q, type:ISSUE, first:$first, after:$after){
        issueCount
        pageInfo{endCursor hasNextPage}
        nodes{
          __typename
          ... on PullRequest{
            number title body state isDraft createdAt updatedAt mergedAt baseRefName
            author{login} repository{nameWithOwner} labels(first:20){nodes{name}}
          }
          ... on Issue{
            number title body state createdAt updatedAt
            author{login} repository{nameWithOwner} labels(first:20){nodes{name}}
          }
        }
      }
    }
    """

    /// The newest comment's author, aliased: `issueRowFields` already selects `comments{totalCount}`.
    static let lastCommentAuthor = "lastComment: comments(last:1){nodes{author{__typename login}}}"

    /// The latest Status moves on any board (a few, as the last may be on another board) and the latest
    /// reopening, for issue notifications.
    static let stateActivity = """
    statusMoves: timelineItems(itemTypes:[PROJECT_V2_ITEM_STATUS_CHANGED_EVENT], last:5){nodes{\
    ... on ProjectV2ItemStatusChangedEvent{createdAt actor{__typename login} previousStatus status \
    project{number owner{... on Organization{login} ... on User{login}}}}}} \
    lastReopen: timelineItems(itemTypes:[REOPENED_EVENT], last:1){nodes{... on ReopenedEvent{createdAt actor{login}}}}
    """

    /// `withActivity` adds what issue notifications read: the newest comment's author, Status moves and
    /// the latest reopening.
    static func issueSearch(withAssignment: Bool, withActivity: Bool = false) -> String {
        let extra = (withAssignment ? " " + assignedEvents : "")
            + (withActivity ? " " + lastCommentAuthor + " " + stateActivity : "")
        return """
        query($q:String!,$after:String,$first:Int=50){
          search(query:$q, type:ISSUE, first:$first, after:$after){
            pageInfo{endCursor hasNextPage}
            nodes{... on Issue{...issueRowFields\(extra)}}
          }
        }
        \(issueRowFields)
        """
    }

    /// The same board query for either owner; the item and field shapes are identical.
    static func board(_ owner: BoardOwner) -> String {
        """
        query($login:String!,$n:Int!,$after:String){
          \(root(owner))(login:$login){
            projectV2(number:$n){
              title
              field(name:"Status"){... on ProjectV2SingleSelectField{options{id name color}}}
              items(first:100, after:$after){
                pageInfo{endCursor hasNextPage}
                nodes{
                  databaseId
                  fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name optionId}}
                  content{__typename ... on Issue{...issueRowFields}}
                }
              }
            }
          }
        }
        \(issueRowFields)
        """
    }

    /// Aliases are `r0...rN`, one per repo name. Names must already be validated.
    static func lookup(repoNames: [String]) -> String {
        let aliases = repoNames.enumerated().map { index, name in
            """
            r\(index): repository(owner:$org, name:"\(name)"){
              issueOrPullRequest(number:$n){
                __typename
                ... on PullRequest{...prFields}
                ... on Issue{...issueRowFields}
              }
            }
            """
        }.joined(separator: "\n")
        return "query($org:String!,$n:Int!){\n\(aliases)\n}\n\(prFields)\n\(issueRowFields)"
    }

    /// One issue with its row fields, body, last two comments and the PRs that close it. The comments
    /// are aliased: `issueRowFields` already selects `comments{totalCount}` without arguments.
    static let issueDetail = """
    query($owner:String!,$name:String!,$n:Int!){
      repository(owner:$owner, name:$name){
        issue(number:$n){
          ...issueRowFields
          body
          lastComments: comments(last:2){totalCount nodes{author{login} body createdAt}}
          closedByPullRequestsReferences(first:5, includeClosedPrs:true){nodes{
            number title url state isDraft author{login} repository{nameWithOwner}
            commits(last:1){nodes{commit{statusCheckRollup{state contexts{\(rollupCounts)}}}}}
          }}
        }
      }
    }
    \(issueRowFields)
    """

    static let detail = """
    query($owner:String!,$name:String!,$n:Int!){
      repository(owner:$owner, name:$name){
        pullRequest(number:$n){
          body updatedAt changedFiles additions deletions
          commits(last:1){nodes{commit{statusCheckRollup{state contexts(first:50){totalCount \(rollupCounts) nodes{
            __typename
            ... on CheckRun{name conclusion status detailsUrl}
            ... on StatusContext{context state targetUrl}
          }}}}}}
          latestReviews(first:20){nodes{author{login} state submittedAt}}
          comments(first:50){nodes{author{login} body createdAt}}
          files(first:100){totalCount nodes{path additions deletions}}
        }
      }
    }
    """
}
