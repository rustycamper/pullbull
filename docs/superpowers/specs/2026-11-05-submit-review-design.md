# Approve or request changes on a pull request

PullBull lets you submit a review, Approve or Request changes, from a pull request's detail page. Today the Review list tells you what needs you and the detail shows you the description, checks, conversation and changed files, and then the verdict means a trip to the browser. With this, you open the PR, press ⌥⌘V, optionally write a line, and press ⌘↩.

This is the first of two projects that finish the PR loop. The second, merging and re-running checks, needs new GitHub App permissions and has its own design.

It builds on `2026-11-02-comments-and-mentions-design.md` (the comments spec) and `2026-10-31-edit-status-assignees-labels-design.md` (the edit spec): their comment field, drafts, posting states, failure line, overrides and permission handling. This document states what is new. Where it is silent, those specs apply.

## Why

- The verdict is the last step of a review and the only one still in the browser. PullBull already gets you to the PR, and now lets you comment, change reviewers and open a file's diff.
- It serves team reviewers working through their Review list, maintainers reviewing outside contributions, and anyone reviewing agent PRs, which arrive faster than a browser round trip suits. Board-heavy users and org leads who rarely review see one more button, and nothing else changes for them.
- The comments spec ruled out submitting a review because PullBull has no diff view. That still holds for line comments. A verdict needs only a way to read the diff, and the detail reaches each file's diff on GitHub.

## Goals

- Approve or request changes on an open pull request by someone else, from its detail page.
- See what you are approving before it goes: the commit, the size of the change and the state of the checks.
- Never approve code you weren't shown: a push after you enter review mode stops the review.
- Your review shows at once in the Reviewers section and in the lists, and the PR leaves Needs your review.
- Review text shows in the Conversation, yours and other people's.
- What you typed is never lost, as for comments.

## Non-goals

- Line comments, replying in a review thread, suggested changes, batching a pending review. These need a diff view.
- A review with the verdict Comment. An ordinary comment already does this job.
- Reviewing from a row without opening the PR: a verdict needs the PR in view.
- Dismissing a review, your own or anyone's.
- Merging, re-running checks, closing, reopening, marking ready for review.

## Anti-goals

The comments spec's anti-goals hold. In addition, the feature fails if:

- a review goes out by accident, or twice. An approval can count towards merging the moment it lands, and GitHub emails it. No key press in the ordinary flow may send one: it takes ⌥⌘V (or the Review button), then ⌘↩;
- an approval lands on a commit the reviewer never saw;
- a user who never reviews, or who can't, sees broken or nagging controls;
- the copy claims more or less than PullBull writes.

## What PullBull writes

PullBull writes exactly these to GitHub, each only when the user picks or sends it:

- an issue's board Status, assignees and labels;
- a pull request's review requests, assignees and labels;
- a comment on an issue or pull request;
- a review of a pull request: Approve or Request changes, with optional text (required for Request changes).

Nothing else, ever. This replaces the comments spec's sentence wherever the product promises it (see Docs and copy).

## Who can review

The Review button and ⌥⌘V are offered only when all of these hold:

- the PR is open;
- the viewer is not its author (GitHub refuses both verdicts on your own PR);
- the account may review (see Permissions).

A draft PR is offered like any other: GitHub decides, and a refusal shows its reason. On any other PR, ⌥⌘V does nothing and the button isn't there.

A PR PullBull holds in no list (opened from a notification, Ask, a pasted link or a linked PR) can be reviewed too, as it can be commented on. Those are common ways to reach a PR you were asked to look at. The detail itself supplies the author and state (see Data); until it has them, the PR isn't offered.

The viewer's existing review doesn't change this: you can approve after requesting changes, and the other way round, as on GitHub.

## Interaction

### Review mode

The review reuses the comment field, because a review is a comment with a verdict. Text, `@` mentions, the draft, Esc and focus all behave as the comments spec says, with one draft per item shared between commenting and reviewing.

- ⌥⌘V, or the **Review** button, puts the field in review mode and focuses it. ⌥⌘V also works with the field already focused, so text you've started becomes the review's text. The field owns the keyboard except for this addition.
- In review mode a panel sits directly above the bottom row, part of the layout rather than floating over the page, so the failure line stays visible above it and the `@` list opens above it. It holds, top to bottom:
  - the verdict: **Approve** and **Request changes**, a two-way choice. Approve is chosen on entering, except that a PR the viewer last reviewed with Request changes opens on Request changes;
  - one summary line: the short head commit, `5 files +120 −3`, and the checks (`checks passed`, `2 checks failing`, `checks running`, or nothing when there are none). The checks part takes the warning colour when failing or running. It warns and doesn't block: reviewers may approve code while an unrelated check is red.
- ⌥← and ⌥→ change the verdict (arrow keys alone move the caret). Clicking one works too.
- The field's hint reads ⌘↩ as for comments, and the placeholder reads "Add a note (optional)…" on Approve and "Say what needs changing…" on Request changes.
- ⌘↩ submits. On Approve, empty text is allowed. On Request changes, empty text sends nothing and the placeholder takes the warning colour, since GitHub requires text there.
- Esc leaves review mode first and keeps the text, with focus staying in the field. With the `@` list open, Esc closes that first. So from a mention to the list: list, review mode, field, detail.
- **The head is pinned on entering.** Review mode records the detail's head commit at that moment, and the panel shows that commit from then on. A background refresh can replace the detail while the panel is open; it never moves the pin, so a push during review mode is caught by the check below rather than slipping past. A refresh before entering counts as shown: the page already displays it.
- **Review mode needs the field focused.** It ends when the field loses focus, the route changes, the popover closes or the account changes. The draft stays; the verdict doesn't. So ⌘↩ submits only with the field focused in review mode. With the field unfocused, ⌘↩ opens on GitHub as it always has, and can never become an accidental approval.
- VoiceOver: the verdict is an adjustable control labelled "Review verdict"; the field gains a "Submit review" action in review mode, and "Post comment" goes while it's there; entering says "Reviewing. Approve selected." and reads the summary line.

### The Review button

- A bordered button reading **Review**, in the bottom row, before Copy branch's icon button, at the row's 24 pt height and in the same outlined style, with the tooltip "Review (⌥⌘V)". It shows only when the PR can be reviewed. The field gives up the width.
- In review mode it reads **Cancel** and leaves review mode, keeping the text.

### Keys

| Key | Does | Where |
|---|---|---|
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>V</kbd> | Review: enter review mode | PR detail, comment field focused or not |
| <kbd>⌥</kbd><kbd>←</kbd> <kbd>⌥</kbd><kbd>→</kbd> | Change the verdict | Review mode |
| <kbd>⌘</kbd><kbd>↩</kbd> | Submit the review | Review mode |
| <kbd>Esc</kbd> | Leave review mode, keeping the text | Review mode |

- ⌥⌘V is free today. `SearchKeyMonitor.letterV` exists; `commandKey` gains it, so non-Latin layouts reach it by key position. It goes by the typed letter in the field as well as outside it. On a row or search result it does nothing.
- The Keyboard Shortcuts window adds a Reviewing section after Commenting: Review ⌥⌘V, noted "Pull request detail", and Submit ⌘↩, noted "In review mode". It's a section of its own because a section lists each key once. The manual's key tables say the same.

### Submitting

Follows the comments spec's Posting section, with these differences.

- **Before sending**, PullBull reads the PR's head commit and state in one small query (`headRefOid`, `state`). While it does, the field is read-only and reads "Checking…". Then:
  - the head differs from the pinned one: nothing is sent, review mode ends, the text stays, the detail is fetched again, and the failure line says "New commits on #88 since you started reviewing. Look again, then review." Reviewing the new head takes ⌥⌘V again, which pins it;
  - the PR is no longer open: nothing is sent and the line says "#88 was merged." or "#88 was closed.";
  - the read fails: nothing is sent and the line gives the reason. A review is never sent unchecked.
- **Cancelling during the check:** Cancel and Esc stop it, and nothing is sent. Leaving the detail or closing the popover doesn't: pressing ⌘↩ meant send, so the check and the write carry on and any failure line is there on return.
- **The write** sends the pinned head as `commit_id`, so a push between the check and the write can't move the review onto code nobody saw.
- **While sending**, the write can't be called back: Cancel is disabled, Esc does nothing, and the verdict is locked. The field reads "Sending…". The review shows at once in the Reviewers section, dimmed, as a comment does in the Conversation. VoiceOver announces "Sending review".
- **On success:**
  - review mode ends, the field empties, the draft and its undo stack are cleared, and focus leaves the field, because the next key is usually a move to the next item;
  - the review is laid over what was fetched (see Overrides), and the detail is fetched again once;
  - VoiceOver announces "Approved #88" or "Requested changes on #88"; nothing else is shown.
- **Refused:** the dimmed review goes, and review mode stays with the text when the field can keep focus, under the comments spec's rule for returning focus; otherwise review mode ends and the draft waits. The failure line says "Couldn't review #88: …" with GitHub's reason and **Open on GitHub**. This covers an existing pending review started on GitHub ("can only have one pending review"), a draft PR and a repo rule.
- **Outcome unknown:** as for comments. The fresh detail decides: a review by the viewer with the same state, submitted no earlier than 60 s before the send started, counts as success. Otherwise review mode ends with the text kept, so one ⌘↩ can't send it twice, and the line says "Couldn't confirm your review of #88. Check the Reviewers section before sending again."
- **No undo.** GitHub has no way to delete a submitted review. ⌘Z in the field undoes typing only, and the edit undo never touches a review. Changing your mind is another review.
- A submit in flight blocks a comment on that item and the other way round, through the same in-flight tracking.

### Overrides

- `EditChange` gains a review case: state, head commit and viewer. `EditOverrides.apply` lays it over `latestReviews`, replacing the viewer's entry, and takes the viewer's own user entry off `reviewRequests`, so `ReviewRules.status` gives `approvedByMe` or `reviewedByMe` at once and the PR leaves Needs your review without waiting for search.
- For a PR in no list there is no row to change, so the overlay applies to the detail's `reviews` and `requests` only.
- It agrees with a fetch when the fetched `latestReviews` has the viewer's review at that commit with that state. It lives for `EditOverrides.lifetime` like other edits.
- It never enters `EditUndo`. It never reaches `ChangeDetector`, which compares raw snapshots and already skips the viewer's own reviews, so your review raises no Approved or Changes requested notification. A test pins this.
- The Stats reviews figure comes from search and catches up with its 15-minute cache, unchanged.

### Review text in the Conversation

The detail fetches no review text today, so a Request changes note would vanish as soon as it was sent, and authors can't read why changes were requested.

- `latestReviews` in the detail query adds `body` and `commit{oid}`.
- The Conversation shows each latest review with non-empty text, in time order among the comments, by the reviewer, with a small tag: **Approved**, **Changes requested** or **Reviewed** (GitHub's Commented state). Reviews with no text stay in the Reviewers section only.
- Pending reviews never show: their text was never sent. Dismissed reviews don't show either, since the review no longer stands.
- Bot reviews show like bot comments do today, with no filtering and the same rendering. A long Copilot review is long here as it is on GitHub.
- This covers the latest review per person, not earlier ones; those stay on GitHub.
- The Conversation's count and `is:unanswered` still count comments only.

## Data and GitHub API

| Step | Request |
|---|---|
| Head check | GraphQL `repository.pullRequest(number){headRefOid state}` |
| Submit | REST `POST /repos/{owner}/{repo}/pulls/{n}/reviews` with `event` (`APPROVE`, `REQUEST_CHANGES`), `body`, `commit_id` |

- REST rather than GraphQL because `postComment` already has this path: `restAnswer` with `keepingTransportFailures: true` and `CommentFailure.classify`. The classifier's names generalise, or a review reuses them as they are; the builder picks whichever reads better.
- The detail query adds `headRefOid`, `state` and `author{login}` at the pull request level, and `PRDetail` keeps them. `PRDetail` is `Codable` and cached: new fields are optional, and a cached detail without them can't start a review until it's fetched again.
- The review panel reads its summary from the detail on screen, the same data the page shows. A review can start from a held detail that is refreshing, since the head check covers it; it can't start before a detail with these fields is held.

## Permissions

- `EditField` gains `review`, gated like reviewers: `installation.canWritePullRequests` for a GitHub App account, `.ready` for `gh`.
- A missing permission shows as it does for comments: the note takes the field's place and links to accepting it. The live App already has Pull requests write, so nobody should see this.
- GitHub's docs were only partly checked here: the row for creating a review wasn't read word for word. **The first runnable build proves it, before the PR opens.** The token lives in the app's Keychain, so the owner runs this: signed in through the App, on an account that isn't the PR's author, approve and request changes on a test PR. Building up to that point is safe, because nothing here changes if the answer is no. If GitHub refuses, the feature waits for the permission and ships with the second project.

## Docs and copy

- README's privacy table: "… and comments you write, only when you pick or send them. Never merges, approves or closes" becomes "… comments you write and reviews you submit, only when you pick or send them. Never merges or closes".
- README's feature table gains a row in the style of the Comment row.
- `docs/github-app-setup.md` and the App's description on GitHub (the owner changes that one by hand): "It never merges or closes".
- `docs/manual.md`: a Reviewing section after Commenting, and the key tables.
- `ShortcutCatalog` as above. Release notes mention it.

## Testing

- **Kit (Swift Testing):** who can review; the head check's three outcomes; a background detail refresh leaves the pin alone; failure classification; unknown-outcome matching; overrides apply, agree and expire, and the PR leaves Needs your review; `ChangeDetector` stays silent; Conversation merge order; a cached detail without new fields decodes.
- **Real GitHub, two accounts, on a test repo:** Approve with and without text; Request changes; approve after requesting changes; a push while in review mode, and one just before entering it; a pending review started on the web; a draft PR; a closed PR; both a `gh` login and a Sign in with GitHub login.
- **In the app:** keys in and out of review mode with the `@` list open; ⌘↩ with the field unfocused opens GitHub and sends nothing; Cancel during the check; closing the popover during the check; a PR opened from a notification; VoiceOver; the bottom row at the narrowest popover width.

## Left to the builder

- The panel's exact spacing and styling, within the app's existing materials.
- Whether review mode lives in `CommentField` or wraps it.
- How the dimmed review appears in `ReviewerEntry`.
