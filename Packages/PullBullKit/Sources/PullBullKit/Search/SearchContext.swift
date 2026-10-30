import Foundation

/// The line above `@`, `~`, `is:`, `status:` and `updated:` search results, and what VoiceOver says for it.
public enum SearchContext {
    /// `<tokens> in all of <org>`, with words `<tokens> · “<words>” in all of <org>`,
    /// prefixed `Started typing on <tab> · ` after type-anywhere. `<tokens>` lists the filter's `tokens`: the
    /// included `@` names, `~` labels, `is:` states, `status:` columns and `updated:` step, then the excluded
    /// ones with their `-`. With a focused `repo`, `in <repo>` instead.
    public static func text(filter: SearchFilter, org: String, repo: String? = nil, startedOnTab: String?) -> String {
        var line = SearchQuery.joinedList(filter.tokens)
        if !filter.words.isEmpty { line += " · “\(filter.words.joined(separator: " "))”" }
        line += " " + place(org: org, repo: repo)
        if let tab = startedOnTab { line = "Started typing on \(tab) · " + line }
        return line
    }

    /// As above, for included terms only.
    public static func text(
        logins: [String], labels: [String] = [], states: [StateFilter] = [], statuses: [BoardStatusFilter] = [],
        updated: UpdatedFilter? = nil, words: [String], org: String, repo: String? = nil, startedOnTab: String?
    ) -> String {
        text(
            filter: .included(logins: logins, labels: labels, states: states, statuses: statuses, updated: updated, words: words),
            org: org, repo: repo, startedOnTab: startedOnTab)
    }

    /// `Filtered by <logins>, labels <labels>, states <states>, <statuses>, excluding <…>, titles matching
    /// <words>, in all of <org>` (`in <repo>` when focused); each part only when it applies.
    public static func accessibilityLabel(filter: SearchFilter, org: String, repo: String? = nil) -> String {
        filterDescription(filter) + ", " + place(org: org, repo: repo)
    }

    /// As above, for included terms only.
    public static func accessibilityLabel(
        logins: [String], labels: [String] = [], states: [StateFilter] = [], statuses: [BoardStatusFilter] = [],
        updated: UpdatedFilter? = nil, words: [String], org: String, repo: String? = nil
    ) -> String {
        accessibilityLabel(
            filter: .included(logins: logins, labels: labels, states: states, statuses: statuses, updated: updated, words: words),
            org: org, repo: repo)
    }

    /// `Filtered by <logins>, labels <labels>, states <states>, <statuses>, updated <step>, excluding <…>, titles
    /// matching <words>`, where a status reads `Status In progress`, or `Status containing prog` for part of a
    /// name, and a raw `updated:` value reads as its token. The excluded terms read the same way after
    /// `excluding`, listed with `and`; with nothing included it starts `Filtered, excluding`.
    static func filterDescription(_ filter: SearchFilter) -> String {
        let included = descriptions(of: filter.include)
        var label = included.isEmpty ? "Filtered" : "Filtered by \(included.joined(separator: ", "))"
        let excluded = descriptions(of: filter.exclude)
        if !excluded.isEmpty { label += ", excluding " + SearchQuery.joinedList(excluded) }
        if !filter.words.isEmpty { label += ", titles matching \(filter.words.joined(separator: " "))" }
        return label
    }

    /// As above, for included terms only.
    static func filterDescription(
        logins: [String], labels: [String], states: [StateFilter], statuses: [BoardStatusFilter] = [],
        updated: UpdatedFilter? = nil, words: [String]
    ) -> String {
        filterDescription(
            .included(logins: logins, labels: labels, states: states, statuses: statuses, updated: updated, words: words))
    }

    /// One phrase per kind of term in `terms`, in kind order.
    private static func descriptions(of terms: SearchTerms) -> [String] {
        var filters: [String] = []
        if !terms.logins.isEmpty { filters.append(SearchQuery.mentionList(terms.logins)) }
        if !terms.labels.isEmpty {
            filters.append((terms.labels.count == 1 ? "label " : "labels ") + SearchQuery.joinedList(terms.labels))
        }
        if !terms.states.isEmpty {
            filters.append(
                (terms.states.count == 1 ? "state " : "states ") + SearchQuery.joinedList(terms.states.map(\.rawValue)))
        }
        filters += terms.conditions.map(\.summary)
        if !terms.statuses.isEmpty {
            filters.append(
                SearchQuery.joinedList(terms.statuses.map { "Status \($0.exact ? "" : "containing ")\($0.name)" }))
        }
        for updated in terms.updated {
            if case .step(let step) = updated { filters.append("updated \(step.title)") } else { filters.append(updated.token) }
        }
        filters += terms.reviews.map { "review: \($0.summary)" }
        if !terms.repos.isEmpty {
            filters.append((terms.repos.count == 1 ? "repo " : "repos ") + SearchQuery.joinedList(terms.repos.map(\.text)))
        }
        return filters
    }

    /// `in <repo>` with a focus, else `in all of <org>`.
    private static func place(org: String, repo: String?) -> String {
        if let repo { return "in \(repo)" }
        return "in all of \(org.isEmpty ? "the organization" : org)"
    }
}
