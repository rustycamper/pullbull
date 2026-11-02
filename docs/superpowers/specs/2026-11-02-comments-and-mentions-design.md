# Comment on issues and pull requests, with @mentions

PullBull lets you write a comment on an issue or pull request from its detail page, and tag people in it with `@` and a completion list. Today the Conversation section is read-only: a notification says someone asked you something, you open the item in PullBull, read the thread, and then go to the browser to answer. With this, you open the item, press ⌥⌘M, type, `@` a colleague, ⌘↩.

This builds on `2026-10-31-edit-status-assignees-labels-design.md` (the edit spec) and `2026-11-01-edit-pr-reviewers-assignees-labels-design.md` (the reviewers spec): their permission handling, failure line and REST transport. This document states what is new. Where it is silent, those specs apply.

## Why

- The read side is already there: the detail shows the newest comments, new comments notify, and `is:unanswered` finds the threads where a reply is owed. Each of those ends with a trip to the browser for a short answer.
- Tagging someone is how work gets handed on in a thread ("@dana can you check the migration?"). Without the right login at hand, people guess, mistype, or go and look it up.
- PullBull is open source. Other teams use the same flow, so the design covers organisation teams (`@acme/backend`) as well as people, though the author's own use is people.

## Goals

- Write a comment on an open, closed or merged issue or pull request from its detail page, and post it.
- `@` in the comment offers people (and teams, on organisation repos) to tag, with the people in the thread first.
- The posted comment shows at once in the Conversation, the row's comment count goes up, and the item leaves `is:unanswered`, without waiting for a refresh.
- What you've typed is never lost to a popover closing, a click elsewhere, a failed post, or moving between items.

## Non-goals

- Review comments on lines of a diff, replying in a review thread, submitting a review. PullBull has no diff view, and these need one.
- Editing or deleting comments, yours or anyone's. GitHub does that.
- Reactions, quote reply, saved replies, a Markdown preview, attaching images or files.
- Commenting from a row without opening the item: a reply needs the thread in view.
- Mentioning bots and apps from the completion list. Typing `@name` by hand still works, since the text is sent as written.
- Closing or reopening with the comment ("Close with comment").

## Anti-goals

The edit specs' anti-goals hold. In addition, the feature fails if:

- a comment goes out by accident, or twice. GitHub emails everyone tagged and subscribed the moment it posts, and no undo takes that back. Only ⌘↩ in the field, or VoiceOver's "Post comment" action on it, sends; Return writes a new line; a post whose outcome is unknown is never presented as "not sent";
- text the user typed disappears: on a popover close, on Esc, on a failed post, on moving to another item and back;
- a keystroke meant for the comment does something to the popover (goes Back, opens a picker, switches tab, starts a search, opens the browser);
- the field takes the keyboard without being asked: opening a detail, or the popover, never puts the caret in it;
- the user is notified about their own comment.

## What PullBull writes

PullBull writes exactly these to GitHub, each only when the user picks or sends it:

- an issue's board Status, assignees and labels;
- a pull request's review requests, assignees and labels;
- a comment on an issue or pull request.

Nothing else, ever. This replaces the reviewers spec's sentence wherever the product promises it (see Docs and copy).

## Interaction

### Where the comment field lives

- Both detail pages end in one row, 12 pt in from the sides and 8 pt above and below: the comment field, then the item's buttons (Copy branch / Open on GitHub on a PR; View on board / Open on GitHub on an issue). The field takes the width the buttons leave. It is reachable without scrolling past 50 comments and the file list, and sharing the buttons' row costs the scroll area no second row.
- Unfocused, the field is one line, 24 pt tall like the buttons, so the row is 40 pt. Empty, it reads "Comment…" with ⌥⌘M at its trailing edge, both in the tertiary colour. Holding a draft, it shows a `pencil` symbol and the draft's first line, dimmed, so a waiting draft is visible, and no shortcut; VoiceOver reads its value as "Draft: " and that line. Its border is the separator colour. Its tooltip reads "Comment (⌥⌘M) · ⌘↩ to post".
- Focused, its border takes the accent colour, so the focus shows, and ⌘↩ shows at its trailing end, in the tertiary colour, beside the last line rather than under the text. The buttons never change, so Open on GitHub never moves and stays reachable by mouse and VoiceOver while the field has focus; only Esc or anything else that takes focus leaves the field, and a click elsewhere in the detail doesn't. The field grows upward with the text up to 8 lines, then scrolls inside, and the detail's scroll area shrinks to make room. The field's tooltip shows only while it is unfocused, so it never covers the text being written.
- There is no Comment button. Typing a comment needs the keyboard, so ⌘↩ is always to hand, and the hint names it where a button would; a button would also have to take a place in the row, moving the item's buttons as focus comes and goes. While a post is in flight, "Sending…" takes the hint's place, focused or not, so the post stays visible after focus moves away. VoiceOver gets a "Post comment" action on the field, which does what ⌘↩ does.
- Any detail page takes a comment, including a PR or issue that PullBull holds in no list (opened from linked PRs, Ask, a notification or a pasted link). Posting needs only the repo and number.

### The text view

- An `NSTextView` wrapped for SwiftUI (`NSViewRepresentable`), not `TextEditor`: the mention list, the caret position and the key routing need its selection and delegate.
- Plain text only: rich text off, paste as plain text, and smart quotes, smart dashes, text replacement and automatic link detection off, so Markdown and code arrive as typed. Automatic spelling correction and text completion are off too; spell checking stays on.
- PullBull has no Edit menu, so the view handles ⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V and ⌘A itself. ⌘X and ⌘V also work by key position on non-Latin layouts. Any other ⌘-chord with no binding in the field does nothing, without a beep.
- `allowsUndo` is on. The undo stack is cleared when a draft is loaded into the field and when a post succeeds, so ⌘Z after a post never brings back the sent text. Taking a row from the `@` list is an undo step of its own: ⌘Z takes back the inserted mention and leaves the `@` and prefix typed before it.
- The field never becomes first responder on its own. The popover's show-time rule that drops the caret from a field editor (`PopoverView`, "Shown, the window puts the caret in its first text field") covers any `NSText`, and the view refuses first responder until something asks for it: ⌥⌘M, a click, or a refused post returning focus to that same item's field. A field in a covered layer (an issue under a linked PR's detail) ignores focus requests: it is hidden but could still become first responder, and ⌘↩ would post from it. Any change of the detail stack (a linked PR pushed over an issue, for one) takes focus out of a comment field.
- Clicking an unfocused field puts the caret where it was. Leaving the field scrolls it to the top.

### Keys

| Key | Does | Where |
|---|---|---|
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd> | Focus the comment field | Issue or PR detail |
| <kbd>⌘</kbd><kbd>↩</kbd> | Post the comment | Comment field focused |
| <kbd>⌘</kbd><kbd>↩</kbd> | Open on GitHub (unchanged) | Detail, comment field not focused |
| <kbd>Esc</kbd> | Close the mention list if open; otherwise leave the field, keeping the draft | Comment field focused |

- ⌥⌘M is free today. On a row or search result it does nothing: a reply needs the thread in view (see Non-goals). Non-Latin layouts reach it by key position: `SearchKeyMonitor` gains `letterM` (`kVK_ANSI_M`, 46) and `commandKey` maps it, as for the other shortcut letters.
- ⌘↩ posts only with the field focused, matched as ⌘ alone (ignoring caps lock, numeric pad and function flags), on Return and on keypad Enter, as the detail's Open on GitHub matches today. Unfocused, ⌘↩ opens on GitHub as before.
- Clicking the field focuses it too.
- **While the field has focus it owns the keyboard.** `PopoverView.handleDetailKey` returns `false` (the key goes to the text view) for every key when `window.firstResponder` is the comment view, except: ⌘↩ (post), Esc (as above), ⌘W, ⌘, and ⌘/ (which work from every route today), and the mention list's keys while it is open. So ←, ⌥↑ ⌥↓, ⌘Z, ⌘C, ⇧⌘C, ⌘R, ⌘[, Return, ⇧⌘↩, ⌥⌘↩, ⌥⌘C, ⌃⌘C and ⌥⌘A/L/R/S/M all act on the text or do nothing. ⌘Z is the text's undo, never the edit undo.
- After Esc has left the field, Esc again closes the detail as today. Two presses from typing to the list is deliberate: one Esc never costs the draft, and the second can't be mistaken for the first.
- An input method composing in the field keeps every key, as the search field does today (`hasMarkedText`).
- The Keyboard Shortcuts window adds a Commenting section: Comment ⌥⌘M; Post ⌘↩, noted "In the comment field; elsewhere ⌘↩ opens on GitHub". The manual's key tables say the same.

### Drafts

- One draft per item, per account, keyed by the account and the item's `PRKey`, in memory. Typing writes it; a confirmed post clears it.
- A draft survives the popover closing (click outside, ⌘W, the hotkey), going Back and opening the item again, opening another item, the reopen-after-a-long-while reset (`showListInsteadOfDetail`), and switching accounts or orgs and back. `clearAccountData` leaves drafts alone.
- Signing an account out drops its drafts. Quitting PullBull drops all drafts. Nothing is written to disk.
- Drafts never feed notifications, search or Ask.
- The caret goes back where it was when the field is focused again in the same session.
- Clearing a draft is ordinary text editing (⌘A, Delete). There is no discard button.

### Mentions

The comment field has its own completion, in PullBullKit, separate from search's: search's tokens follow search syntax (`QueryScanner`, `SearchQuery.isLogin`) and its list reads `AppModel.completion` and the search text.

- **The token** (`MentionToken`): an `@` at the start of the text, or after whitespace or one of `(` `[` `{` `"` `'`, followed by ASCII letters, digits, `-`, `_`, and at most one `/` (for `owner/team`), up to the caret. An `@` inside a word (`a@b.com`) is no token. The token is read from the text and caret after every change, never from key events, so `@` typed with ⌥, a dead key or an input method works.
- **The list** shows over the comment field, its bottom on the field's top, styled as search completion's rows (`CompletionRow`), at most 8 rows. A person's row shows their avatar; one with no avatar from the mentionable or known people (a thread person seen only in comments) shows `https://github.com/<login>.png`, as the Conversation's comment lines do. A team's row shows a people glyph, its name, and `owner/slug` at the trailing edge.
- **Rows, in order:**
  1. People in this thread: comment authors held by the detail, newest comment first; then the item's author, assignees, requested reviewers and reviewers (on a PR), in that order.
  2. People who can be mentioned in the repo (`repository.mentionableUsers`), by login.
  3. People PullBull's lists know (`PeopleIndex`: organisation members and the PR authors, reviewers and assignees seen in the snapshot), through a new accessor that returns logins and avatars by prefix. `PersonCandidate.insertText` (`@me`) is not used.
  4. The organisation's teams, as `owner/slug` with the team's name, on organisation repos when the team list can be read.
  Each person or team appears once, in its first group.
- **Left out:** the viewer, `ghost`, and bots: a comment author whose `__typename` is `Bot` (see Data), and any login ending in `[bot]`.
- **Filtering:** case-insensitive prefix match on the login; for teams, on the slug or any word of the name. Within groups 2 to 4, logins sort alphabetically. A token with a `/` (`@acme/`, `@acme/back`) lists only the teams of the repo's owner (owner matched ignoring case) whose slug or a word of whose name starts with the part after the `/`; another owner's prefix lists nothing, and no person matches. With fewer than 8 matches and a token of at least one character, a remote `mentionableUsers(query:)` runs 300 ms after typing pauses (the assignees picker's wait), and its results join group 2 and the cache. It doesn't run for a token with a `/`, nor once the repo's mentionable people were all read (`complete`), since GitHub has no one more to add. The next keystroke cancels it, and its answer is used only while the same item's field is focused and the token's prefix is unchanged.
- **Keys:** ↑ ↓ choose (stopping at the ends), Return or Tab inserts, a click on a row inserts it, Esc closes the list and leaves the typed text. The keys come through `CommentFieldKeys` with the list counted open whenever `AppModel.mention` is set; ⌘↩ still posts with it open. A space, or moving the caret out of the token, closes the list. After Esc, caret moves inside the same token leave it closed; typing opens it again. With no row and nothing still loading the list is closed, so Return and Esc act on the field; while it reads "Loading people…", Return and Tab type as usual and ↑ ↓ move the caret. Typing on with no match leaves what was typed; it is sent as written.
- **Inserting** replaces the token with `@login ` or `@owner/slug ` (trailing space). With the caret inside a name (`@da|na`), the rest of the name after the caret (letters, digits, `-`, `_`, and a `/` if the token has none yet) is replaced too, so `@da|na` becomes `@dana `, not `@dana na`. A space already after the name is reused rather than doubled. The field makes the replacement as one edit through the text view, so ⌘Z takes it back. Nothing else marks it: GitHub turns the text into the mention when it posts.
- **Loading:** focusing the field starts the candidate fetches for the item's repo when they aren't cached or already under way (mentionable people, and the owner's teams), so they are usually ready by the first `@`. The teams fetch answers nothing for a user's repo, so teams show only on organisation repos. Thread people and `PeopleIndex` (asked for 50 by prefix, since it cuts before the ranking removes duplicates) show at once. While a fetch is under way and the token matches nothing, the list reads "Loading people…". A teams answer of none (a user's repo, no `read:org`, no Members permission) is cached as an empty, complete team list, so it isn't asked again on each focus. A fetch that didn't reach GitHub (offline, a 5xx, a rate limit) caches nothing and leaves those groups out without a note; the next focus tries again. The list still offers what it has, and typed text still sends.
- **The list closes** when the field loses focus, when the route changes (another detail or screen), when a comment is posted, and on an account or org change, which also cancels the fetches and the remote wait.
- **Accessibility:** rows read as search completion's do (`CompletionSpeech`): a person by login, a team as "Back End, team acme/backend". Opening on a new token, or rows going from none to some, says "3 suggestions. Up and down arrows to choose, Return to insert." ("Loading people" while loading); ↑ ↓ read the row and its place ("dana, 2 of 3"); narrowing on the same token says nothing. The field is labelled "Comment on acme/widgets#88".

### Posting

- ⌘↩ (or VoiceOver's "Post comment" action) posts the trimmed text. Empty or whitespace-only text sends nothing and the key is taken. A second ⌘↩ while one is posting does nothing.
- While posting, the field is read-only with its text kept, and the comment shows at the end of the Conversation, dimmed, by the viewer, aged "now", marked "Sending…". The Conversation's count goes up by one. VoiceOver announces "Sending comment".
- **On success** (201):
  - the field empties, the draft is cleared, the field's undo stack is cleared, and focus stays in the field;
  - the dimmed comment becomes the real one, from GitHub's answer (its node ID, body and creation time);
  - the item's row, wherever it shows, counts the comment and has the viewer as its last commenter, so it drops out of `is:unanswered` at once;
  - the detail is fetched again once, so the page holds GitHub's own copy. A detail held under another layer (an issue under a linked PR's detail) is fetched too, so the comment is still there when Back returns to it;
  - VoiceOver announces "Comment posted"; nothing else is shown, as for edits.
- **Refused** (GitHub answered no):
  - the dimmed comment goes, the count goes back, and the text stays in the field as the draft, editable. Focus goes back to the field only when that item's detail is on top with no Status or set picker open; otherwise the draft waits there unfocused;
  - the failure line says "Couldn't comment on #88: …" with GitHub's reason (a locked conversation, an archived repo, a body too long, issues turned off) and **Open on GitHub**; VoiceOver announces it.
- **Outcome unknown** (timeout, dropped connection, a 5xx: GitHub may have made the comment):
  - the comment stays dimmed and marked "Sending…", and the field stays read-only, while PullBull checks. ⌘↩ can't send it twice meanwhile;
  - the detail is fetched again at once. If that fetch fails, the check fails. An issue page holds only its last two comments, so the check sees only those. If it holds a comment by the viewer, created no earlier than 60 s before the post started (clock skew), whose body equals the sent text, the post counts as a success (above) without sending again;
  - otherwise the dimmed comment goes, the text stays in the field as the draft, and the failure line says "Couldn't confirm your comment on #88. Check the Conversation before sending again." with **Open on GitHub**.
- There is no undo. ⌘Z inside the field is text undo; the edit undo (⌘Z within 10 s) never deletes a comment, and a post, sent or failed, leaves the edit undo's state as it was.
- On a detail, the failure line sits directly above the bottom row (the comment field, or the permission note in its place), following the field as it grows.
- The failure line is the edits' line with a comment variant. An edit, or another post, replaces it, as edits replace each other's failures: a post clears it as it is sent, leaving the edit undo as it was.
- Posting on a closed or merged item is allowed, as GitHub allows it.
- **Account change mid-post:** the answer applies only if the account that posted is still current, as edits guard today. If it isn't, the draft of the posting account is cleared on success and kept otherwise, and nothing else changes.
- In-flight posts are tracked per account and item, and survive account switches, so a post can't be sent twice after a switch mid-post.
- A refused or unconfirmed post shows its failure line even after an org switch on the same account: the guard compares the account, not the org.

### Notifications

- The viewer's own comment raises no "New comment" notification: `ChangeDetector` skips a comment whose last author is the viewer, for PRs and for issues. The snapshot's issue lists are fetched with activity (`RefreshCoordinator`, `activity: true`), so they carry the last author. A test pins it for a comment PullBull posted, on a PR and on an issue.
- The posted-comment overlay never reaches `ChangeDetector`, which compares raw snapshots.
- Someone else commenting between the viewer's comment and the next poll leaves them as the last author, so that comment notifies as today.

## Data and GitHub API

### The write

| Write | Request |
|---|---|
| Comment on an issue or a PR | REST `POST /repos/{owner}/{repo}/issues/{number}/comments` with `{"body": …}` |

- One endpoint for both: on GitHub a PR's conversation comments are issue comments. No node ID is needed, so any detail can post.
- `GitHubAPI` gains a REST write that returns the response body; today `rest(_:_:_:)` throws or returns nothing. Posting reads `node_id`, `body`, `created_at` and `user.login` from the 201.
- `sendAuthorized` retries once after a 401. That is safe for a POST: GitHub rejected the first send before acting on it.
- Errors: a 403 that isn't a rate limit, a 404, a 410 and a 422 are refusals. The reason is the body's first `errors[].message` when present (a 422's `message` is only "Validation Failed"), else its `message`. Adding 410 and the `errors[]` reading applies to every REST write.
- Answers that mean GitHub never acted are refusals too, in PullBull's usual words:
  - a 401 after the retry, single sign-on required, a rate limit, or any other 403;
  - no connection: no network, cellular data or roaming off, the host not found or not reachable. The request never reached GitHub.
- Any other failure is "outcome unknown" (see Posting): a timeout, a dropped connection, any other transport error, or a 5xx. PullBull's shared send path counts a timeout and a dropped connection as "offline". The post reads the transport's own error code instead, so these two never pass as "never sent".
- The posted body is exactly the field's text, trimmed of leading and trailing whitespace.

### Comment fields

- `Comment` gains `id: String?` (the GraphQL node ID) and `authorIsBot: Bool?`. The PR and issue detail queries select `id` and `author{__typename login}` on their comment nodes. Cached details decode without them (`decodeIfPresent`, nil).
- The posted comment carries GitHub's `node_id` from the REST answer, so the detail can tell when a fetch holds it.

### The posted comment until GitHub's reads catch up

- `PostedComment` (the item's `PRKey`, the `Comment`, the `commentCount` it was posted on top of, called `begin`, and when) is a new type beside the edit overrides, not an `EditChange`. It lives in its own store on the model, cleared by `clearAccountData` like the overrides; a detail opened again after an account change is fetched fresh and shows the comment from GitHub.
- It is applied at display time only. Saved details (`saveDetail`) and the snapshot stay as GitHub sent them.
- **Detail:** a posted comment is appended to the Conversation, and the page's total raised by one, until a detail fetched after the post holds its ID; then it is dropped. It also leaves a detail once the page holds a newer comment (`createdAt` at or after its own), so an issue page's two-comment window can't bring it back. A detail fetched before the post never drops it. Once a stored detail has held it either way, it is gone from that detail for good, so a comment deleted on GitHub stays gone after the next refresh rather than coming back from the overlay. If no fetch after the post holds it within 5 minutes of posting, it is dropped then.
  - On a PR page the posted comment follows the 50 held; on an issue page the page shows the newest two after appending, and "N earlier comments" is recomputed from the raised total.
- **Rows:** a posted comment raises `commentCount` by one and sets `lastCommentAuthor` to the viewer (`lastCommentByBot` false) on every list and search copy of the item. Those three fields on `PullRequest` and `BoardIssue` become `var`. `begin` comes from the raw list copy, else the search copy, else the opened item. Search rows are raised too. Each copy is judged on its own: the post is applied to a copy only while that copy's count is at or below `begin`, and it is dropped once every copy has a `commentCount` above it. Someone else's comment can satisfy that too; the fetched copy then names its true last author, which is right. An item in no list just keeps the overlay until its 5 minutes are up.
- Several posts on one item stack: each adds one. Expired posts are pruned before a new one is counted. A refused post between two others re-bases the later ones, so each still adds exactly one on top of the count that remains.

### Mention candidates

- **Thread people** come from what the detail holds: comments (with `authorIsBot`), the item's author, assignees, `reviewRequests` and `latestReviews`. No fetch.
- **Mentionable people:** `repository(owner:name:){mentionableUsers(first:100, query:){nodes{login avatarUrl}}}`, cached in the set-candidate cache under `mentionable|<repo>`. `mentionableUsers` is GitHub's own list of who can be mentioned in the repo; assignable users would miss people with read access.
- **Teams:** `teamCandidates(owner:query:)`, today private and reached only through the reviewer candidates, gets a public entry point that doesn't need a PR, and caches under `teams|<owner>`, the key the reviewers picker uses (`AppModel.teamCandidatesKey`, shared by both). The public entry point returns nil when GitHub answers without teams (a user's account, no `read:org`, no Members permission) and throws when GitHub couldn't be asked, so the @ list can tell an answer to cache from a failure to retry; the reviewers picker keeps reading both as no teams. An empty cached team list doesn't count as cached candidates for the reviewers picker, which shows it's loading until its own fetch answers rather than an empty list. The whole team list is read on focus, so typing never asks GitHub for teams.
- **`PeopleIndex`** comes from the snapshot, through the new prefix accessor.
- The set-candidate cache is cleared on account change, as today, so mentionable people and teams are fetched again for the new account. Nothing new is written to disk.

## Permissions

### GitHub App

- No new permission. The official app already has **Issues: Read and write** and **Pull requests: Read and write**.
- A comment on an issue gates on `issues: write`; on a pull request, on `pull_requests: write`. GitHub accepts either for a PR comment; the stricter rule is deliberate, matching every other PR edit. `EditPermission.of` takes a new `EditField.comment`.
- Whether the item is a PR comes from the route (`.detail` is a PR, `.issueDetail` an issue), not from a list copy, so a PR opened from Ask or a notification is gated as a PR. The comment field does not use `isSetEditOffered`, which requires a held item.
- An installation without the permission shows the edit note, worded for comments ("Commenting needs PullBull's new permissions for acme. An org owner accepts them on GitHub."), in the field's place in the bottom row: a field-shaped box, 24 pt tall, filling the width the item's buttons leave (they stay), reading the note on one line, cut short with an ellipsis, with the whole note in its tooltip and as its VoiceOver label. When the installation's permission review has a URL, the box is itself the link: a button with a trailing `arrow.up.right` that opens the review, with the VoiceOver hint "Opens GitHub to accept the permissions". A separate **Open on GitHub** button beside it would have squeezed the note to a few words and read as the item's own Open on GitHub. Without a URL the box only reads. `EditPermission.note` takes the field to word it.
- With no installation on the item's owner (`EditPermission.unavailable`), the field isn't shown and ⌥⌘M does nothing.

### GitHub CLI logins

- `repo` covers commenting. No new scope.
- Teams in the mention list need `read:org`; without it, people only, no note.

## Docs and copy

- **README Privacy row:** "An issue's board Status, assignees and labels, a pull request's reviewers, assignees and labels, and comments you write, only when you pick or send them. Never merges, approves or closes".
- **README:** a Problem → solution row: "Answering a question in a thread means opening the browser" → "**Comment** from the detail, ⌥⌘M, `@` to tag people, ⌘↩ to send". The keys table adds ⌥⌘M and the ⌘↩ note.
- **Manual:**
  - A Commenting section: where the field is, ⌥⌘M, ⌘↩ (and that elsewhere it opens on GitHub), Esc twice, drafts kept until quit or sign-out, mentions and their order, refused and unconfirmed posts, no undo.
  - The PR and issue Detail bullets mention the comment field.
  - The Editing section's first line covers comments in "It writes nothing else".
  - The key tables' ⌘Return rows note the comment field.
- **CONTRIBUTING out-of-scope:** "Writing to GitHub beyond Status, assignees, labels, review requests and comments (merge, approve, close, review comments)".
- **GitHub App description:** the Privacy sentence.
- **The edit spec and the reviewers spec:** their Non-goals lines listing "comment" point here.

## Delivery

1. **Commenting:**
   - the REST post with its answer, the 410 and `errors[]` refusal mapping, and outcome-unknown;
   - `Comment.id`, `PostedComment` in the detail and rows, the refetch after posting;
   - the text view, the comment field, drafts, key routing, ⌥⌘M with its layout fallback, the show-time focus rule;
   - the permission gate and its note;
   - the notifications tests;
   - docs for commenting.
2. **Mentions:**
   - `Comment.authorIsBot` and the detail queries' `__typename`;
   - `MentionToken`, the list, its order and filtering;
   - `mentionableUsers`, the public team entry point, the `PeopleIndex` accessor;
   - docs for mentions.

Each step ships as its own PR. Step 1 is useful alone: `@login` typed by hand already tags.

## Testing

Per CONTRIBUTING, logic lives in PullBullKit with tests.

- **Request building:** path, method and body; trimming; the 201 decoded; 403, 404, 410, 422 as refusals, with `errors[].message` preferred to `message`; a timeout and a 5xx as outcome unknown.
- **Outcome unknown:** a refetched detail holding the viewer's comment with the same body, created no earlier than 60 s before the post started (clock skew), counts as success, though an issue page shows only its last two comments to the check; one without it leaves the draft and the "Couldn't confirm" line.
- **Clock skew:** a viewer comment created 59 s before the post started counts; one created 61 s before does not.
- **Org switch:** a refused or unconfirmed post still shows its failure line after an org switch on the same account; an account switch does not show it for the other account.
- **Posted comments:** appended to the detail until a post-post fetch holds the ID; a pre-post detail never drops it; dropped at 5 minutes; the issue page shows the newest two with "earlier" recomputed; rows count it and name the viewer last; dropped on a higher `commentCount`; stacking; cleared on account change; never in saved details or the snapshot.
- **`is:unanswered`:** an item leaves it on posting.
- **Drafts:** kept per account and item; across route changes, `showListInsteadOfDetail` and `clearAccountData`; dropped on sign-out; restored on refusal; cleared on success.
- **Key routing** (at `handleDetailKey`, by first responder): with the field focused, ←, ⌥↑, ⌘Z, ⌘R, ⌘[, ⌘C, ⇧⌘C, ⇧⌘↩, ⌥⌘↩, ⌥⌘A/L/R/S/C, ⌃⌘C and Return don't reach the detail; ⌘↩ posts and doesn't open the browser; Esc leaves the field and a second Esc closes the detail; ⌘↩ with empty text sends nothing; unfocused, ⌘↩ still opens on GitHub; ⌥⌘M by key position on a non-Latin layout.
- **Focus:** opening a detail, and the popover on a detail, leaves the field unfocused.
- **Mention token:** opens at start, after whitespace and after `(` `[` `{` `"` `'`; not inside `a@b.com`; accepts `owner/team`; closes on space and caret moves; insertion replaces only the token.
- **Mention order:** thread people first (commenters newest first, then author, assignees, reviewers); each once; viewer, ghost and bots out (`Bot` typename and `[bot]` logins); teams only when loaded; at most 8; prefix matching.
- **Permissions:** `issues: write` for issues, `pull_requests: write` for PRs, decided by route for a PR in no list; the comment note's wording; no field when unavailable.
- **Notifications:** the viewer's posted comment raises no "New comment" on PRs or issues.
- **Caches:** cached details without comment IDs or author types decode.

Manual check against real GitHub, on a test repo in an org with a team:

- comment on an open issue, a closed issue, an open PR, a merged PR, and a PR opened from a notification;
- a locked conversation (the failure line's reason);
- `@person` and `@org/team` notify them;
- a refresh right after doesn't flicker the comment or the count;
- the draft after a popover close, Back, reopen and an account switch;
- a post with the network cut mid-request: no duplicate on resend after the check;
- an installation without the permission;
- your own comment doesn't notify you.

## Calls made in writing this

The user asked for comments with @mentions, and noted the app is open source. The rest are the writer's calls:

- The field lives on the detail page only, in the bottom row before the item's buttons; rows don't take comments. The row's buttons never change; with no Comment button, ⌘↩ shows inside the field while it has focus, and "Sending…" takes its place while a post is in flight.
- ⌥⌘M focuses it; ⌘↩ posts while it has focus and opens on GitHub otherwise; Return is a new line; Esc leaves the field and a second Esc closes the detail.
- While the field has focus it owns the keyboard, except ⌘↩, Esc, ⌘W, ⌘, and ⌘/.
- An `NSTextView` with plain text and substitutions off.
- Drafts in memory only, per account and item; kept across account switches; lost on quit and sign-out.
- No undo, edit or delete; GitHub does those.
- REST issue-comments endpoint for issues and PRs alike; a post whose outcome is unknown is checked against a refetch before the user is told to resend.
- Posted comments show at once, refetch the detail, and update the rows' count and last commenter, so `is:unanswered` updates. They are cleared on account change.
- Mention order: thread people (commenters newest first, then author, assignees, reviewers), mentionable people, people PullBull's lists know, teams; bots left out. `mentionableUsers` rather than assignable users.
- No field where the account can't write to the owner at all; the permission note where an owner hasn't accepted yet. PR comments gate on the Pull requests permission.
- Two PRs: commenting, then mentions.
