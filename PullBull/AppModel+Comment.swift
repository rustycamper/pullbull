import Foundation
import PullBullKit
import SwiftUI

/// Bumped to tell the comment field on `key` to act; the field acts only when `key` is its own.
struct CommentFieldSignal: Equatable {
    let key: PRKey
    let n: Int
}

/// The @ list over the comment field on `key`: the token at the caret, its rows (at most 8), the
/// highlighted one, and whether people are still loading with nothing to show yet ("Loading people…").
struct MentionState: Equatable {
    let key: PRKey
    let token: MentionToken
    var rows: [MentionCandidate]
    var selection: Int
    var loading: Bool

    var speech: MentionSpeechState {
        MentionSpeechState(start: token.range.lowerBound, rows: rows, selection: selection, loading: loading)
    }
}

/// The focused comment field as the @ list reads it. `caret` is nil while text is selected.
struct MentionField {
    let key: PRKey
    let isPullRequest: Bool
    var text: String
    var caret: Int?
    /// Where the token Esc closed starts: caret moves leave it closed; typing opens it again.
    var dismissedAt: Int?
}

/// A row taken from the @ list, for the comment field on `key` to put in its text with its own undo.
struct MentionInsertion: Equatable {
    let key: PRKey
    let range: Range<Int>
    let replacement: String
    let caret: Int
    let n: Int
}

// MARK: - Commenting

extension AppModel {
    /// Lets each posted comment a stored detail now holds leave that detail for good, so deleting it on
    /// GitHub isn't undone by the overlay. `comments` reads the stored detail's comments for a key.
    func settlePostedComments(_ comments: (PRKey) -> [Comment]?) {
        for key in postedComments.unsettledKeys {
            if let held = comments(key) { postedComments.detailFetched(key, comments: held) }
        }
    }

    /// Whether this account may comment on `key`. `isPullRequest` comes from the route (`.detail` is a PR,
    /// `.issueDetail` an issue), so a PR in no list is gated as a PR.
    func commentPermission(for key: PRKey, isPullRequest: Bool) -> EditPermission {
        guard let account = runningAccount else { return .unavailable }
        let owner = key.repo.split(separator: "/").first.map(String.init) ?? ""
        return EditPermission.of(
            .comment, account: account, boardOwner: nil, installation: installation(named: owner), ghAccounts: accounts,
            onPullRequest: isPullRequest)
    }

    /// Whether the detail shows the comment field, or the note saying what it needs.
    func isCommentShown(for key: PRKey, isPullRequest: Bool) -> Bool {
        runningAccount != nil && commentPermission(for: key, isPullRequest: isPullRequest) != .unavailable
    }

    /// Whether the current account's post on `key` is waiting for its outcome; the field is read-only and
    /// its button reads "Sending…" meanwhile. Lasts across account and org switches, unlike the overlay.
    func isPostInFlight(for key: PRKey) -> Bool {
        guard let account = runningAccount else { return false }
        return postsInFlight.contains(account: account.login, key: key)
    }

    /// Posts the draft on `key`, trimmed. Shows it as sending at once; GitHub's answer makes it the real
    /// comment, takes it back with the reason, or, when the outcome is unknown, a fresh detail decides.
    func postComment(on key: PRKey, isPullRequest: Bool) {
        // In review mode the field's text is the review's, and goes nowhere else.
        guard reviewMode?.key != key else { return }
        guard let account = runningAccount,
              commentPermission(for: key, isPullRequest: isPullRequest) == .ready,
              let draft = commentDrafts[account: account.login, key: key] else { return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPostInFlight(for: key), !postedComments.isSending(key) else { return }
        // Another post replaces the failure line, as an edit does; ⌘Z and the last edit stay.
        edits.dismissFailure()
        endMentions()
        let start = Date()
        let url = fetchedPullRequest(for: key)?.url ?? GitHubLinks.issue(key)
        let listCount = fetchedPullRequest(for: key)?.commentCount ?? fetchedIssue(for: key)?.commentCount
        postsInFlight.insert(account: account.login, key: key)
        let id = postedComments.begin(on: key, text: text, viewer: account.login, listCount: listCount, at: start)
        refreshShown()
        AccessibilityNotification.Announcement("Sending comment").post()
        let client = api(for: account)
        let post = PendingComment(
            id: id, key: key, isPullRequest: isPullRequest, text: text, account: account, start: start, url: url)
        Task { [weak self] in
            do {
                let comment = try await client.postComment(on: key, body: text)
                self?.commentPosted(post, as: comment, reload: true)
            } catch {
                guard let self else { return }
                switch CommentFailure.classify(error) {
                case .refused(let reason):
                    self.commentFailed(post, text: EditMessage.commentRefused(on: key, reason: reason), focus: true)
                case .unknown:
                    self.confirmComment(post)
                }
            }
        }
    }

    /// One post on its way, with what its answer needs.
    private struct PendingComment {
        let id: UUID
        let key: PRKey
        /// From the route the post was made on: whether `key` is a pull request.
        let isPullRequest: Bool
        /// As sent: the draft, trimmed.
        let text: String
        let account: AccountRef
        let start: Date
        /// The item on GitHub, for the failure line's **Open on GitHub**.
        let url: URL
    }

    /// GitHub has the comment. The posting account's draft goes even when another account now runs;
    /// the rest only while the posting account does. `reload` fetches the item's detail again, whether
    /// it's on screen or held under another layer, so the comment stays once the overlay lets it go.
    private func commentPosted(_ post: PendingComment, as comment: Comment, reload: Bool) {
        postsInFlight.remove(account: post.account.login, key: post.key)
        commentDrafts[account: post.account.login, key: post.key] = nil
        guard runningAccount == post.account else { return }
        postedComments.posted(post.id, as: comment)
        // The unknown-outcome check found it in a detail already stored.
        settlePostedComments { details[$0]?.comments ?? issueDetails[$0]?.lastComments }
        refreshShown()
        resetCommentField(on: post.key)
        if reload {
            if route == .detail(post.key) {
                reloadDetail()
            } else if route == .issueDetail(post.key) {
                reloadIssueDetail()
            } else if post.isPullRequest ? details[post.key] != nil : issueDetails[post.key] != nil {
                Task { [weak self] in
                    _ = try? await self?.fetchDetailComments(
                        post.key, isPullRequest: post.isPullRequest, account: post.account)
                }
            }
        }
        AccessibilityNotification.Announcement("Comment posted").post()
    }

    /// The comment isn't on GitHub, or can't be shown to be: it goes, the draft stays, the failure line
    /// says why. `focus` hands the field back for a refusal, only while the item's detail is on top with
    /// no picker over it: a field under another layer can still take focus, and ⌘↩ would post from it.
    /// Only `postsInFlight` changes once another account runs.
    private func commentFailed(_ post: PendingComment, text: String, focus: Bool) {
        postsInFlight.remove(account: post.account.login, key: post.key)
        guard runningAccount == post.account else { return }
        postedComments.drop(post.id)
        refreshShown()
        edits.showFailure(EditFailure(text: text, url: post.url))
        let shown: Route = post.isPullRequest ? .detail(post.key) : .issueDetail(post.key)
        if focus, route == shown, statusPicker == nil, setPicker == nil { requestCommentFieldFocus(on: post.key) }
    }

    /// The post's outcome is unknown: it stays sending while a fresh detail is read. A comment by the
    /// viewer with the sent text, made since the post started, counts as posted; anything else, or a
    /// failed read, as unconfirmed. Never sends again. Runs with the posting account even after a switch,
    /// so the post's outcome becomes final and it leaves `postsInFlight`.
    private func confirmComment(_ post: PendingComment) {
        Task { [weak self] in
            guard let self else { return }
            let comments = try? await self.fetchDetailComments(
                post.key, isPullRequest: post.isPullRequest, account: post.account)
            if let comments,
               let landed = CommentCheck.landed(post.text, by: post.account.login, since: post.start, in: comments) {
                self.commentPosted(post, as: landed, reload: false)
            } else {
                self.commentFailed(post, text: EditMessage.commentUnconfirmed(on: post.key), focus: false)
            }
        }
    }
}

// MARK: - Mentions

extension AppModel {
    /// The comment field on `key` took focus: the repo's mentionable people and its owner's teams are
    /// fetched unless cached, so they are usually there by the first "@".
    func commentFieldFocused(key: PRKey, isPullRequest: Bool, text: String, caret: Int?) {
        mentionField = MentionField(key: key, isPullRequest: isPullRequest, text: text, caret: caret)
        loadMentionCandidates(for: key)
        updateMention(typed: false)
    }

    /// The comment field on `key` lost focus: review mode ends and its @ list closes. After a refused
    /// review `mentionField` is nil, so review mode can't wait for the guard.
    func commentFieldBlurred(key: PRKey) {
        endReviewMode(on: key)
        guard mentionField?.key == key else { return }
        endMentions()
    }

    /// The focused field's text or caret changed (`typed` when the text did): the @ list follows the
    /// token at the caret, and typing takes the warning off an empty Request changes.
    func commentTextChanged(key: PRKey, isPullRequest: Bool, text: String, caret: Int?, typed: Bool) {
        if typed, reviewMode?.key == key, reviewMode?.missingText == true { reviewMode?.missingText = false }
        let dismissed = typed ? nil : mentionField.flatMap { $0.key == key ? $0.dismissedAt : nil }
        mentionField = MentionField(
            key: key, isPullRequest: isPullRequest, text: text, caret: caret, dismissedAt: dismissed)
        updateMention(typed: typed)
    }

    /// Esc: the list closes and the typed text stays.
    func closeMentions() {
        guard let mention else { return }
        mentionField?.dismissedAt = mention.token.range.lowerBound
        self.mention = nil
        mentionFilterTask?.cancel()
        mentionFilterTask = nil
    }

    /// ↑ or ↓ in the open list. False with no row ("Loading people…"), so the key moves the caret.
    @discardableResult
    func moveMention(by offset: Int) -> Bool {
        guard var mention, !mention.rows.isEmpty else { return false }
        mention.selection = min(max(mention.selection + offset, 0), mention.rows.count - 1)
        self.mention = mention
        return true
    }

    /// A click on row `index`.
    func selectMention(_ index: Int) {
        guard mention?.rows.indices.contains(index) == true else { return }
        mention?.selection = index
    }

    /// Return or Tab: puts "@login " or "@owner/slug " in place of the token. False with no row to take,
    /// so the key types as usual.
    @discardableResult
    func acceptMention() -> Bool {
        guard let mention, mention.rows.indices.contains(mention.selection),
              let field = mentionField, field.key == mention.key else { return false }
        let row = mention.rows[mention.selection]
        let edit = mention.token.edit(inserting: row.insertText, into: field.text)
        // The field's text as it will be, so nothing arriving before the view applies it reopens the list.
        let after = mention.token.inserting(row.insertText, into: field.text)
        mentionField?.text = after.text
        mentionField?.caret = after.caret
        self.mention = nil
        mentionFilterTask?.cancel()
        mentionFilterTask = nil
        requestMentionInsertion(on: mention.key, range: edit.range, replacement: edit.replacement, caret: edit.caret)
        return true
    }

    /// Closes the list and forgets the field: on a post, on leaving the field, on another screen.
    func endMentions() {
        mentionField = nil
        mention = nil
        mentionFilterTask?.cancel()
        mentionFilterTask = nil
    }

    /// The token at the caret, ranked against the thread, the cached candidates and PeopleIndex. With no
    /// row and nothing still loading, the list is closed, so Return and Esc act on the field.
    private func updateMention(typed: Bool) {
        if typed {
            mentionFilterTask?.cancel()
            mentionFilterTask = nil
        }
        guard let field = mentionField, let account = runningAccount, let caret = field.caret,
              let token = MentionToken.at(field.text, caret: caret),
              token.range.lowerBound != field.dismissedAt,
              // Once a review is submitted Esc is Cancel, so no list opens to take it.
              reviewMode?.key != field.key || reviewMode?.phase == .composing else {
            mention = nil
            return
        }
        let key = field.key
        let peopleKey = Self.mentionableKey(key)
        let teamsKey = Self.teamCandidatesKey(key)
        let owner = key.repo.split(separator: "/").first.map(String.init) ?? ""
        let rows = MentionCandidates.rank(
            prefix: token.prefix, thread: mentionThread(for: key, isPullRequest: field.isPullRequest),
            mentionable: setCandidates[peopleKey]?.all ?? [], known: people.people(prefix: token.prefix, limit: 50),
            teams: setCandidates[teamsKey]?.all, owner: owner, viewer: account.login)
        let loading = rows.isEmpty && (mentionFetches[peopleKey] != nil || mentionFetches[teamsKey] != nil)
        if rows.isEmpty && !loading {
            mention = nil
        } else {
            let selection = mention.flatMap { old in
                old.key == key && old.token.range.lowerBound == token.range.lowerBound
                    ? MentionCandidates.selection(keeping: old.selection, of: old.rows, in: rows) : nil
            } ?? 0
            mention = MentionState(key: key, token: token, rows: rows, selection: selection, loading: loading)
        }
        if typed, MentionCandidates.wantsRemote(
            prefix: token.prefix, rowCount: rows.count, mentionableComplete: setCandidates[peopleKey]?.complete) {
            filterMentions(key: key, prefix: token.prefix, account: account)
        }
    }

    /// After a 0.3 s pause in typing, GitHub is asked for mentionable people matching `prefix`; they join
    /// the cached ones. The answer is used only while the same field shows the same token.
    private func filterMentions(key: PRKey, prefix: String, account: AccountRef) {
        let client = api(for: account)
        mentionFilterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let answer = try? await client.mentionableCandidates(repo: key.repo, query: prefix)
            guard let answer, let self, !Task.isCancelled, self.runningAccount == account,
                  self.isMentionCurrent(key: key, prefix: prefix) else { return }
            self.mentionFilterTask = nil
            self.addMentionable(answer.all, complete: nil, for: key)
            self.updateMention(typed: false)
        }
    }

    private func isMentionCurrent(key: PRKey, prefix: String) -> Bool {
        guard let field = mentionField, field.key == key, let caret = field.caret else { return false }
        return MentionToken.at(field.text, caret: caret)?.prefix == prefix
    }

    /// Starts the fetches `key`'s @ list needs that aren't cached or under way. A failed one caches
    /// nothing and leaves its group out, so the next focus asks again.
    private func loadMentionCandidates(for key: PRKey) {
        guard let account = runningAccount else { return }
        let client = api(for: account)
        let peopleKey = Self.mentionableKey(key)
        if setCandidates[peopleKey] == nil, mentionFetches[peopleKey] == nil {
            mentionFetches[peopleKey] = Task { [weak self] in
                let answer = try? await client.mentionableCandidates(repo: key.repo, query: nil)
                guard let self, !Task.isCancelled, self.runningAccount == account else { return }
                self.mentionFetches[peopleKey] = nil
                if let answer { self.addMentionable(answer.all, complete: answer.complete, for: key) }
                self.updateMention(typed: false)
            }
        }
        let teamsKey = Self.teamCandidatesKey(key)
        let owner = key.repo.split(separator: "/").first.map(String.init) ?? ""
        if setCandidates[teamsKey] == nil, mentionFetches[teamsKey] == nil, !owner.isEmpty {
            mentionFetches[teamsKey] = Task { [weak self] in
                // GitHub's nil (a user's repo, no read:org, no Members permission) is cached as no teams,
                // so it isn't asked again on each focus; a fetch that failed is not.
                let teams: [SetCandidate]?
                do {
                    teams = try await client.teams(owner: owner, query: nil) ?? []
                } catch {
                    teams = nil
                }
                guard let self, !Task.isCancelled, self.runningAccount == account else { return }
                self.mentionFetches[teamsKey] = nil
                if let teams { self.setCandidates[teamsKey] = SetCandidates(all: teams, current: [], complete: true) }
                self.updateMention(typed: false)
            }
        }
    }

    /// Adds `found` to the cached mentionable people of `key`'s repo; `complete` is the full list's
    /// (nil keeps what the cache says).
    private func addMentionable(_ found: [SetCandidate], complete: Bool?, for key: PRKey) {
        let cacheKey = Self.mentionableKey(key)
        let held = setCandidates[cacheKey]
        let known = Set((held?.all ?? []).map(\.key))
        let all = (held?.all ?? []) + found.filter { !known.contains($0.key) }
        setCandidates[cacheKey] = SetCandidates(all: all, current: [], complete: complete ?? held?.complete ?? false)
    }

    /// People in the thread on `key` as the detail holds them: comment authors, then the item's author,
    /// assignees, requested reviewers and reviewers.
    private func mentionThread(for key: PRKey, isPullRequest: Bool) -> [String] {
        if isPullRequest {
            let pr = pullRequest(for: key)
            let held = detail(for: key)
            return MentionCandidates.thread(
                comments: held?.comments ?? [], author: pr?.author, assignees: pr?.assignees.map(\.login) ?? [],
                requested: pr?.reviewRequests ?? held?.requests ?? [],
                reviewers: (held?.reviews ?? pr?.latestReviews ?? []).map(\.author))
        }
        let held = issueDetails[key]
        let item = issue(for: key) ?? held?.issue
        return MentionCandidates.thread(
            comments: held?.lastComments ?? [], author: item?.author,
            assignees: item?.assignees.map(\.login) ?? [], requested: [], reviewers: [])
    }

    /// The mentionable people of `key`'s repo in `setCandidates`.
    private static func mentionableKey(_ key: PRKey) -> String {
        "mentionable|\(key.repo)"
    }
}

