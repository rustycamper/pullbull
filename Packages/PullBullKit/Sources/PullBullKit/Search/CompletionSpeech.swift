import Foundation

/// What VoiceOver says for the "@user", "~label", "is:", "status:", "updated:", "review:", "repo:" and "size:" completion lists, which never take focus from the
/// search field.
public enum CompletionSpeech {
    /// The list opened on a new token. `loaded` is false before the first snapshot.
    public static func opened(_ completion: PersonCompletion, loaded: Bool) -> String {
        guard loaded else { return "People appear once PullBull has loaded" }
        switch completion.candidates.count {
        case 0: return "No matching people. Return to search anyway."
        case 1: return "1 person. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) people. Up and down arrows to choose, Return to complete."
        }
    }

    public static func opened(_ completion: LabelCompletion, loaded: Bool) -> String {
        guard loaded else { return "Labels appear once PullBull has loaded" }
        switch completion.candidates.count {
        case 0: return "No matching labels. Return to search anyway."
        case 1: return "1 label. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) labels. Up and down arrows to choose, Return to complete."
        }
    }

    /// The states never wait for a snapshot.
    public static func opened(_ completion: StateCompletion) -> String {
        switch completion.candidates.count {
        case 0: return "No matching states. Return to search anyway."
        case 1: return "1 state. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) states. Up and down arrows to choose, Return to complete."
        }
    }

    /// The steps never wait for a snapshot.
    public static func opened(_ completion: UpdatedCompletion) -> String {
        switch completion.candidates.count {
        case 0: return "No matching steps. Return to search anyway."
        case 1: return "1 step. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) steps. Up and down arrows to choose, Return to complete."
        }
    }

    /// The review filters never wait for a snapshot.
    public static func opened(_ completion: ReviewCompletion) -> String {
        switch completion.candidates.count {
        case 0: return "No matching review filters. Return to search anyway."
        case 1: return "1 review filter. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) review filters. Up and down arrows to choose, Return to complete."
        }
    }

    /// The sizes never wait for a snapshot.
    public static func opened(_ completion: SizeCompletion) -> String {
        switch completion.candidates.count {
        case 0: return "No matching sizes. Return to search anyway."
        case 1: return "1 size. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) sizes. Up and down arrows to choose, Return to complete."
        }
    }

    public static func opened(_ completion: RepoCompletion, loaded: Bool) -> String {
        guard loaded else { return "Repositories appear once PullBull has loaded" }
        switch completion.candidates.count {
        case 0: return "No matching repositories. Return to search anyway."
        case 1: return "1 repository. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) repositories. Up and down arrows to choose, Return to complete."
        }
    }

    public static func opened(_ completion: StatusCompletion, loaded: Bool) -> String {
        guard loaded else { return "Status columns appear once PullBull has loaded" }
        switch completion.candidates.count {
        case 0: return "No matching Status columns. Return to search anyway."
        case 1: return "1 Status column. Up and down arrows to choose, Return to complete."
        case let count: return "\(count) Status columns. Up and down arrows to choose, Return to complete."
        }
    }

    /// One row: `<login>, member, on <n> items`, the member and count parts only when they apply.
    public static func label(_ candidate: PersonCandidate) -> String {
        var parts = [candidate.login]
        if candidate.isMember { parts.append("member") }
        if let items = items(candidate.openCount) { parts.append(items) }
        return parts.joined(separator: ", ")
    }

    /// One row: `<name>, on <n> items`, the count part only when it applies.
    public static func label(_ candidate: LabelCandidate) -> String {
        [candidate.name, items(candidate.openCount)].compactMap { $0 }.joined(separator: ", ")
    }

    /// One row: `<name>, on <n> items`, the count part only when it applies.
    public static func label(_ candidate: StatusCandidate) -> String {
        [candidate.name, items(candidate.openCount)].compactMap { $0 }.joined(separator: ", ")
    }

    /// One row: `<state>, <summary>`.
    public static func label(_ candidate: StateCandidate) -> String {
        "\(candidate.value.name), \(candidate.value.summary)"
    }

    /// One row: `<filter>, <summary>`.
    public static func label(_ candidate: ReviewCandidate) -> String {
        "\(candidate.review.rawValue), \(candidate.review.summary)"
    }

    /// One row: `<letter>, <summary>, <limit>`.
    public static func label(_ candidate: SizeCandidate) -> String {
        "\(candidate.size.rawValue), \(candidate.size.summary), \(candidate.size.limit)"
    }

    /// One row: `<owner/name>, on <n> items`, the count part only when it applies.
    public static func label(_ candidate: RepoCandidate) -> String {
        [candidate.repo, items(candidate.openCount)].compactMap { $0 }.joined(separator: ", ")
    }

    /// One row: `<token>, <title>`.
    public static func label(_ candidate: TimeStepCandidate) -> String {
        "\(candidate.insertText), \(candidate.step.title)"
    }

    /// The selected row after ↑ / ↓, with its position: `<label>, <i> of <count>`; nil with no candidate.
    public static func selected(_ completion: PersonCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    public static func selected(_ completion: LabelCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    public static func selected(_ completion: StateCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    public static func selected(_ completion: StatusCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    public static func selected(_ completion: UpdatedCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    public static func selected(_ completion: ReviewCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    public static func selected(_ completion: SizeCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    public static func selected(_ completion: RepoCompletion) -> String? {
        completion.selectedCandidate.map { position(label($0), in: completion) }
    }

    /// What to say when the list changes from `old` to `new`: open on a new token, or when the candidates
    /// go from none to some or some to none on the same token; the selection after ↑ / ↓; else nothing.
    public static func change(from old: PersonCompletion?, to new: PersonCompletion?, loaded: Bool) -> String? {
        change(from: old, to: new, opened: { opened($0, loaded: loaded) }, selected: selected)
    }

    public static func change(from old: LabelCompletion?, to new: LabelCompletion?, loaded: Bool) -> String? {
        change(from: old, to: new, opened: { opened($0, loaded: loaded) }, selected: selected)
    }

    public static func change(from old: StateCompletion?, to new: StateCompletion?) -> String? {
        change(from: old, to: new, opened: opened, selected: selected)
    }

    public static func change(from old: StatusCompletion?, to new: StatusCompletion?, loaded: Bool) -> String? {
        change(from: old, to: new, opened: { opened($0, loaded: loaded) }, selected: selected)
    }

    public static func change(from old: UpdatedCompletion?, to new: UpdatedCompletion?) -> String? {
        change(from: old, to: new, opened: opened, selected: selected)
    }

    public static func change(from old: ReviewCompletion?, to new: ReviewCompletion?) -> String? {
        change(from: old, to: new, opened: opened, selected: selected)
    }

    public static func change(from old: SizeCompletion?, to new: SizeCompletion?) -> String? {
        change(from: old, to: new, opened: opened, selected: selected)
    }

    public static func change(from old: RepoCompletion?, to new: RepoCompletion?, loaded: Bool) -> String? {
        change(from: old, to: new, opened: { opened($0, loaded: loaded) }, selected: selected)
    }

    /// As for one kind; a list of another kind counts as a new token.
    public static func change(from old: SearchCompletion?, to new: SearchCompletion?, loaded: Bool) -> String? {
        switch (old, new) {
        case (_, nil): return nil
        case (.people(let o), .people(let n)): return change(from: o, to: n, loaded: loaded)
        case (.labels(let o), .labels(let n)): return change(from: o, to: n, loaded: loaded)
        case (.states(let o), .states(let n)): return change(from: o, to: n)
        case (.statuses(let o), .statuses(let n)): return change(from: o, to: n, loaded: loaded)
        case (.updated(let o), .updated(let n)): return change(from: o, to: n)
        case (.reviews(let o), .reviews(let n)): return change(from: o, to: n)
        case (.repos(let o), .repos(let n)): return change(from: o, to: n, loaded: loaded)
        case (.sizes(let o), .sizes(let n)): return change(from: o, to: n)
        case (_, .repos(let n)): return opened(n, loaded: loaded)
        case (_, .people(let n)): return opened(n, loaded: loaded)
        case (_, .labels(let n)): return opened(n, loaded: loaded)
        case (_, .states(let n)): return opened(n)
        case (_, .statuses(let n)): return opened(n, loaded: loaded)
        case (_, .updated(let n)): return opened(n)
        case (_, .reviews(let n)): return opened(n)
        case (_, .sizes(let n)): return opened(n)
        }
    }

    public static func completed(_ candidate: PersonCandidate) -> String {
        "Showing items \(candidate.login) is on"
    }

    public static func completed(_ candidate: LabelCandidate) -> String {
        "Showing items labelled \(candidate.name)"
    }

    public static func completed(_ candidate: StateCandidate) -> String {
        switch candidate.value {
        case .state(.open), .state(.closed): "Showing \(candidate.value.name) items"
        case .state(.merged), .state(.draft): "Showing \(candidate.value.name) pull requests"
        case .condition(let condition): "Showing pull requests: \(condition.summary)"
        }
    }

    public static func completed(_ candidate: ReviewCandidate) -> String {
        "Showing pull requests: \(candidate.review.summary)"
    }

    public static func completed(_ candidate: SizeCandidate) -> String {
        "Showing pull requests: \(candidate.size.summary), \(candidate.size.limit)"
    }

    public static func completed(_ candidate: TimeStepCandidate) -> String {
        "Showing items updated \(candidate.step.title)"
    }

    public static func completed(_ candidate: RepoCandidate) -> String {
        "Showing items in \(candidate.repo)"
    }

    public static func completed(_ candidate: StatusCandidate) -> String {
        "Showing issues in \(candidate.name)"
    }

    // MARK: The comment field's @ list

    /// One row: the login, or `<team name>, team <owner/slug>`.
    public static func label(_ candidate: MentionCandidate) -> String {
        candidate.isTeam ? "\(candidate.title), team \(candidate.insertText)" : candidate.title
    }

    /// The @ list opened on a new token, or went from no rows to some.
    public static func mentionsOpened(rows: [MentionCandidate], loading: Bool) -> String {
        switch rows.count {
        case 0: return loading ? "Loading people" : "No suggestions"
        case 1: return "1 suggestion. Up and down arrows to choose, Return to insert."
        case let count: return "\(count) suggestions. Up and down arrows to choose, Return to insert."
        }
    }

    /// As `change` for search's lists: open on a new token, or when the rows go from none to some or some
    /// to none on the same token; the selected row and its place after ↑ / ↓; else nothing.
    public static func mentionChange(from old: MentionSpeechState?, to new: MentionSpeechState?) -> String? {
        guard let new else { return nil }
        guard let old, old.start == new.start, old.rows.isEmpty == new.rows.isEmpty else {
            return mentionsOpened(rows: new.rows, loading: new.loading)
        }
        guard old.rows == new.rows, old.selection != new.selection, new.rows.indices.contains(new.selection) else {
            return nil
        }
        return "\(label(new.rows[new.selection])), \(new.selection + 1) of \(new.rows.count)"
    }

    private static func items(_ count: Int) -> String? {
        switch count {
        case 0: return nil
        case 1: return "on 1 item"
        case let count: return "on \(count) items"
        }
    }

    private static func position<C>(_ label: String, in completion: TokenCompletion<C>) -> String {
        "\(label), \(completion.selection + 1) of \(completion.candidates.count)"
    }

    private static func change<C>(
        from old: TokenCompletion<C>?, to new: TokenCompletion<C>?,
        opened: (TokenCompletion<C>) -> String, selected: (TokenCompletion<C>) -> String?
    ) -> String? {
        guard let new else { return nil }
        guard let old, old.token.start == new.token.start else { return opened(new) }
        if old.candidates.isEmpty != new.candidates.isEmpty { return opened(new) }
        guard old.candidates == new.candidates, old.selection != new.selection else { return nil }
        return selected(new)
    }
}

/// What VoiceOver needs of the comment field's @ list: where its token starts, its rows and selection, and
/// whether people are still loading.
public struct MentionSpeechState: Equatable, Sendable {
    public let start: Int
    public let rows: [MentionCandidate]
    public let selection: Int
    public let loading: Bool

    public init(start: Int, rows: [MentionCandidate], selection: Int, loading: Bool) {
        self.start = start
        self.rows = rows
        self.selection = selection
        self.loading = loading
    }
}
