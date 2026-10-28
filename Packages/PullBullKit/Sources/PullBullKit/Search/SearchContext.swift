import Foundation

/// The line above `@`, `~` and `is:` search results, and what VoiceOver says for it.
public enum SearchContext {
    /// `<tokens> in all of <org>`, with words `<tokens> · “<words>” in all of <org>`,
    /// prefixed `Started typing on <tab> · ` after type-anywhere. `<tokens>` lists the
    /// `@` names, then the `~` labels, then the `is:` states. With a focused `repo`, `in <repo>` instead.
    public static func text(
        logins: [String], labels: [String] = [], states: [StateFilter] = [], words: [String], org: String,
        repo: String? = nil, startedOnTab: String?
    ) -> String {
        var line = SearchQuery.tokenList(logins: logins, labels: labels, states: states)
        if !words.isEmpty { line += " · “\(words.joined(separator: " "))”" }
        line += " " + place(org: org, repo: repo)
        if let tab = startedOnTab { line = "Started typing on \(tab) · " + line }
        return line
    }

    /// `Filtered by <logins>, labels <labels>, states <states>, titles matching <words>, in all of <org>`
    /// (`in <repo>` when focused); each part only when it applies.
    public static func accessibilityLabel(
        logins: [String], labels: [String] = [], states: [StateFilter] = [], words: [String], org: String,
        repo: String? = nil
    ) -> String {
        filterDescription(logins: logins, labels: labels, states: states, words: words) + ", "
            + place(org: org, repo: repo)
    }

    /// `Filtered by <logins>, labels <labels>, states <states>, titles matching <words>`.
    static func filterDescription(
        logins: [String], labels: [String], states: [StateFilter], words: [String]
    ) -> String {
        var filters: [String] = []
        if !logins.isEmpty { filters.append(SearchQuery.mentionList(logins)) }
        if !labels.isEmpty { filters.append((labels.count == 1 ? "label " : "labels ") + SearchQuery.joinedList(labels)) }
        if !states.isEmpty {
            filters.append((states.count == 1 ? "state " : "states ") + SearchQuery.joinedList(states.map(\.rawValue)))
        }
        var label = "Filtered by \(filters.joined(separator: ", "))"
        if !words.isEmpty { label += ", titles matching \(words.joined(separator: " "))" }
        return label
    }

    /// `in <repo>` with a focus, else `in all of <org>`.
    private static func place(org: String, repo: String?) -> String {
        if let repo { return "in \(repo)" }
        return "in all of \(org.isEmpty ? "the organization" : org)"
    }
}
