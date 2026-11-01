import Foundation

/// The writes PullBull makes: a board item's Status, adding an issue to the board and taking it off,
/// and labels and assignees. Each document names its payload field, which is null when GitHub refused.
enum Mutations {
    static let setStatus = """
    mutation($project:ID!,$item:ID!,$field:ID!,$option:String!){
      updateProjectV2ItemFieldValue(input:{projectId:$project, itemId:$item, fieldId:$field, \
    value:{singleSelectOptionId:$option}}){projectV2Item{id}}
    }
    """

    static let clearStatus = """
    mutation($project:ID!,$item:ID!,$field:ID!){
      clearProjectV2ItemFieldValue(input:{projectId:$project, itemId:$item, fieldId:$field}){projectV2Item{id}}
    }
    """

    static let addToProject = """
    mutation($project:ID!,$content:ID!){
      addProjectV2ItemById(input:{projectId:$project, contentId:$content}){item{id}}
    }
    """

    static let deleteProjectItem = """
    mutation($project:ID!,$item:ID!){
      deleteProjectV2Item(input:{projectId:$project, itemId:$item}){deletedItemId}
    }
    """

    /// Adds and removes labels in one request, aliased `add` and `remove`; nil when neither has IDs.
    static func labels(adding: Bool, removing: Bool) -> String? {
        setChange(
            adding: adding, removing: removing, add: "addLabelsToLabelable", remove: "removeLabelsFromLabelable",
            subject: "labelableId", ids: "labelIds")
    }

    /// As `labels`, for assignees.
    static func assignees(adding: Bool, removing: Bool) -> String? {
        setChange(
            adding: adding, removing: removing, add: "addAssigneesToAssignable",
            remove: "removeAssigneesFromAssignable", subject: "assignableId", ids: "assigneeIds")
    }

    private static func setChange(
        adding: Bool, removing: Bool, add: String, remove: String, subject: String, ids: String
    ) -> String? {
        guard adding || removing else { return nil }
        var variables = ["$subject:ID!"]
        var fields: [String] = []
        if adding {
            variables.append("$add:[ID!]!")
            fields.append("  add: \(add)(input:{\(subject):$subject, \(ids):$add}){clientMutationId}")
        }
        if removing {
            variables.append("$remove:[ID!]!")
            fields.append("  remove: \(remove)(input:{\(subject):$subject, \(ids):$remove}){clientMutationId}")
        }
        return "mutation(\(variables.joined(separator: ","))){\n\(fields.joined(separator: "\n"))\n}"
    }

    /// The board items of an issue (`content`, its node ID), archived ones too, with their boards.
    static let projectItems = """
    query($content:ID!){
      node(id:$content){... on Issue{projectItems(first:100, includeArchived:true){nodes{id project{id}}}}}
    }
    """

    /// A page of the repo's labels by name, and on the first page (`withIssue`) the issue's own.
    static let labelCandidates = """
    query($owner:String!,$name:String!,$n:Int!,$after:String,$withIssue:Boolean!){
      repository(owner:$owner, name:$name){
        issue(number:$n) @include(if:$withIssue){labels(first:100){nodes{id name color description}}}
        labels(first:100, after:$after, orderBy:{field:NAME,direction:ASC}){
          nodes{id name color description}
          pageInfo{hasNextPage endCursor}
        }
      }
    }
    """

    /// The first hundred people assignable in the repo (matching `$q` when given) and the issue's assignees.
    static let assigneeCandidates = """
    query($owner:String!,$name:String!,$n:Int!,$q:String){
      repository(owner:$owner, name:$name){
        issue(number:$n){assignees(first:10){nodes{id login avatarUrl}}}
        assignableUsers(first:100, query:$q){nodes{id login avatarUrl} pageInfo{hasNextPage}}
      }
    }
    """

    /// The node ID of an issue or pull request, by owner, name and number.
    static let nodeId = """
    query($owner:String!,$name:String!,$n:Int!){
      repository(owner:$owner, name:$name){
        issueOrPullRequest(number:$n){... on Issue{id} ... on PullRequest{id}}
      }
    }
    """
}
