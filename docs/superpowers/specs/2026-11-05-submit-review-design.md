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
  - one summary line: the short head commit, `5 files +120 −3`, and the checks (`checks passed`, `2 checks failing`, `checks running`, or nothing when there are none or every check was skipped or cancelled). `ReviewSummary` exposes the checks part on its own, so the panel colours it alone: the warning colour when failing or running. A cancelled check counts as failing in the number. It warns and doesn't block: reviewers may approve code while an unrelated check is red.
- ⌥← and ⌥→ change the verdict (arrow keys alone move the caret). Clicking one works too. The verdict can change only while composing: from ⌘↩ on, the control is disabled and the model refuses the keys as well.
- The field's hint reads ⌘↩ as for comments, and the placeholder reads "Add a note (optional)…" on Approve and "Say what needs changing…" on Request changes. It shows while the field is focused and holds nothing but spaces and new lines, on the first line however far the field has grown. Text an input method hasn't finished yet counts as text, so the placeholder never sits over it.
- ⌘↩ submits. On Approve, empty text is allowed. On Request changes, empty or blank text sends nothing and the placeholder takes the warning colour, since GitHub requires text there; VoiceOver announces the placeholder then, as the colour tells it nothing. Typing, or changing the verdict, takes the warning off. The same rule reads both: whitespace is no text, so a space typed into an empty field clears the amber over a placeholder that is still showing, and ⌘↩ brings it back.
- A held ⌘↩ is one press. Its repeats are swallowed, since after a refusal or a moved head they would otherwise submit again, post the text as a comment or open GitHub.
- In review mode the field's text is the review's and goes nowhere else: posting a comment from the field does nothing, so the one key can't send the same text two ways.
- Esc leaves review mode first and keeps the text, with focus staying in the field. With the `@` list open, Esc closes that first. So from a mention to the list: list, review mode, field, detail. Once the review is submitted, Esc is Cancel or nothing, so no `@` list opens to take it.
- **The head is pinned on entering.** Review mode records the detail's head commit at that moment, and the panel shows that commit from then on. A background refresh can replace the detail while the panel is open; it never moves the pin, so a push during review mode is caught by the check below rather than slipping past. A refresh before entering counts as shown: the page already displays it.
- **Review mode needs the field focused.** It ends when the field loses focus, the route changes, the popover closes or the account changes. The draft stays; the verdict doesn't. So ⌘↩ submits only with the field focused in review mode. With the field unfocused, ⌘↩ opens on GitHub as it always has, and can never become an accidental approval.
- **A click on the page isn't a loss of focus.** Clicking text in the detail doesn't take focus from the field, so review mode and its panel stay until Esc, and ⌘↩ still submits there. This lets the reviewer read and scroll the PR while reviewing. The cost is known and accepted: ⌘↩ after clicking away submits instead of opening GitHub. Clicking something that takes focus (another field, a picker) ends the mode. The Review, Cancel and verdict buttons take no focus, so using them never ends it.
- **Reopening the popover** leaves the field unfocused: `popoverDidShow` resigns any text first responder on every open that isn't a search, so ⌘↩ opens GitHub. Closing ended the mode and the panel is gone, while the draft stays.
- VoiceOver: the verdict is an adjustable control labelled "Review verdict"; the field gains a "Submit review" action in review mode, and "Post comment" goes while it's there; entering says "Reviewing. Approve selected." and reads the summary line. Submitting a Request changes with no text announces the placeholder.

### The Review button

- A bordered button reading **Review**, in the bottom row, before Copy branch's icon button, at the row's 24 pt height and in the same outlined style, with 6 pt of padding at each side, since 10 pt truncated its label at the narrowest popover width (360 pt), and the tooltip "Review (⌥⌘V)". It shows only when the PR can be reviewed and nothing is in flight on it. The field gives up the width.
- In review mode it reads **Cancel** and leaves review mode, keeping the text. It is disabled once the write starts.

### Keys

| Key | Does | Where |
|---|---|---|
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>V</kbd> | Review: enter review mode | PR detail, comment field focused or not |
| <kbd>⌥</kbd><kbd>←</kbd> <kbd>⌥</kbd><kbd>→</kbd> | Change the verdict | Review mode |
| <kbd>⌘</kbd><kbd>↩</kbd> | Submit the review | Review mode |
| <kbd>Esc</kbd> | Leave review mode, keeping the text | Review mode |

- `SearchKeyMonitor.letterV` and `commandKey` carry ⌥⌘V, so non-Latin layouts reach it by key position. It goes by the typed letter in the field as well as outside it. On a row or search result it does nothing.
- The Keyboard Shortcuts window adds a Reviewing section after Commenting: Review ⌥⌘V, noted "Pull request detail", and Submit ⌘↩, noted "In review mode". It's a section of its own because a section lists each key once. The manual's key tables say the same.

### Submitting

Follows the comments spec's Posting section, with these differences.

- **Before sending**, PullBull reads the PR's head commit and state in one small query (`headRefOid`, `state`). While it does, the field is read-only and reads "Checking…". Then:
  - the head differs from the pinned one: nothing is sent, review mode ends, the text stays, the field gives up focus so that a following ⌘↩ opens GitHub rather than posting the text, the detail is fetched again, and the failure line says "New commits on #88 since you started reviewing. Look again, then review." Reviewing the new head takes ⌥⌘V again, which pins it. A ⌘↩ pressed in the one frame before the field lets go would post the text as a comment; that is accepted. It needs a new key press inside that frame, it can only post text the reviewer can see and never a review, and a hold in the model would have to clear on blur, which never fires if the field is already unfocused, so it could block comments silently;
  - the PR is no longer open: nothing is sent and the line says "#88 was merged." or "#88 was closed."; the detail is fetched again, so the page shows the new state, and the panel stays until Esc or blur;
  - the read fails: nothing is sent and the line gives the reason. A review is never sent unchecked.
- **Cancelling during the check:** Cancel and Esc stop it, and nothing is sent. They are the only things that do: an explicit flag set there marks the attempt cancelled, because blur, closing the popover, leaving the detail and an account change also end review mode while pressing ⌘↩ meant send. So the check and the write carry on and any failure line is there on return. The verdict and the pinned head are captured at ⌘↩, and the time the unknown-outcome check measures from is taken just before the write.
- **The write** sends the pinned head as `commit_id`, so a push between the check and the write can't move the review onto code nobody saw.
- **While sending**, the write can't be called back: Cancel is disabled, Esc does nothing, and the verdict is locked. The field reads "Sending…". The review shows at once in the Reviewers section, dimmed, as a comment does in the Conversation. VoiceOver announces "Sending review". The account is checked first: if another account runs by the time the head check answers, the write still goes out for the account that pressed ⌘↩, but nothing is shown or changed for the one on screen. The dimming follows the item, not the account, so a late outcome from another account's review of the same PR can end it early; that is cosmetic and takes two accounts mid-send.
- **On success:**
  - review mode ends, the field empties, the draft and its undo stack are cleared, and focus leaves the field, because the next key is usually a move to the next item;
  - the review is laid over what was fetched (see Overrides), and the detail is fetched again;
  - VoiceOver announces "Approved #88" or "Requested changes on #88"; nothing else is shown.
- **Refused:** the dimmed review goes, and review mode stays with the text and the field keeps focus; if the field has lost focus by then, blur has already ended review mode and the draft waits. The failure line says "Couldn't review #88: …" with GitHub's reason and **Open on GitHub**. This covers an existing pending review started on GitHub ("can only have one pending review"), a draft PR and a repo rule.
- **Outcome unknown:** as for comments. The fresh detail decides: a review by the viewer with the same state, submitted no earlier than 60 s before the send started, counts as success. Otherwise review mode ends with the text kept and the field gives up focus, so one ⌘↩ can't send it twice, and the line says "Couldn't confirm your review of #88. Check the Reviewers section before sending again." The fresh read is kept either way, so the Reviewers section that line points at shows what GitHub has.
- **No undo.** GitHub has no way to delete a submitted review. ⌘Z in the field undoes typing only, and the edit undo never touches a review. Changing your mind is another review.
- A submit in flight blocks a comment on that item and the other way round, through the same in-flight tracking.

### Overrides

- `EditChange` has a review case: state, head commit, viewer and the text sent. `EditOverrides.apply` lays it over `latestReviews`, replacing the viewer's entry, and takes the viewer's own user entry off `reviewRequests`, so `ReviewRules.status` gives `approvedByMe` or `reviewedByMe` at once and the PR leaves Needs your review without waiting for search.
- For a PR in no list there is no row to change, so the overlay applies to the detail's `reviews` and `requests` only. The overlay's `Review` carries the text sent, and the Conversation and the default verdict read through it, so a sent review's text shows at once, in place of an earlier review's.
- A newer review by the viewer replaces an older self-request in the overlay: GitHub drops the viewer's own request on a review, so the request would never agree and would re-request the viewer once the review retired.
- It agrees with a fetch when the fetched `latestReviews` has the viewer's review at that commit with that state. It lives for `EditOverrides.lifetime` like other edits.
- GitHub answers a review before its reads catch up. On a real repo the lag measured up to about 1.5 s, in 2 of 3 rounds: `reviewRequests` still listed the viewer and `latestReviews` lacked the review. So a detail read right after the send can lack the review while the list agrees, and showing it once the overlay retired would drop the review from the page. Therefore a review's overlay stays while the held detail lacks it, even when the list agrees, and each refresh that finished without an error reads that detail again until it shows the review, once at a time per PR when it is off screen; the lifetime still ends it. That holds for a PR in no list too, which no list could ever confirm. There are no timers: the next refresh decides, which usually costs one extra detail read per affected review, and a detail that never shows the review is read on each clean refresh and holds the overlay for 5 minutes at most.
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

- REST rather than GraphQL because `postComment` already has this path: `restAnswer` with `keepingTransportFailures: true` and `CommentFailure.classify`, which a review reuses as it is. The body is trimmed and left out when empty. A refusal's reason is read from an `errors` list of objects or of plain strings, as this endpoint answers either way.
- The detail query reads `headRefOid`, `state` and `author{login}` at the pull request level, and `PRDetail` keeps them; a deleted author is kept as "ghost". `PRDetail` is `Codable` and cached: new fields are optional, and a cached detail without them can't start a review until it's fetched again.
- The review panel reads its summary from the detail on screen, the same data the page shows. A review can start from a held detail that is refreshing, since the head check covers it; it can't start before a detail with these fields is held.

## Permissions

- `EditField` has a `review` case, gated like reviewers: `installation.canWritePullRequests` for a GitHub App account, `.ready` for `gh`.
- A missing permission shows as it does for comments: the note takes the field's place and links to accepting it. The live App already has Pull requests write, so nobody should see this.
- Pull requests write is enough to submit a review: the owner approved and requested changes on a private test repo (rustycamper/pullbar#78) through the App's token, so the feature needs no new App permissions and no one has to accept any.
- Sign in with GitHub needs a team-signed build, so testing the feature against the App's token needs a Developer ID build; a Debug build is ad-hoc signed and can't sign in.

## Docs and copy

- README's privacy table: "… and comments you write, only when you pick or send them. Never merges, approves or closes" reads "… comments you write and reviews you submit, only when you pick or send them. Never merges or closes".
- README's feature table has a row in the style of the Comment row, and its keys table lists ⌥⌘V and ⌘↩.
- `docs/github-app-setup.md`: "It never merges or closes", and the Issues/Pull requests write sentence names reviews. The App's description on GitHub carries the same sentence; the owner changes that one by hand at release.
- `SECURITY.md`'s list of what PullBull writes names the comments you write and the reviews you submit.
- `docs/manual.md`: a Reviewing section after Commenting, and the key tables.
- `ShortcutCatalog` as above. Release notes mention it.

## Testing

- **Kit (Swift Testing):** who can review; the head check's three outcomes; a background detail refresh leaves the pin alone; failure classification; unknown-outcome matching; overrides apply, agree and expire, and the PR leaves Needs your review; `ChangeDetector` stays silent; Conversation merge order; a cached detail without new fields decodes.
- **Real GitHub, on rustycamper/pullbar#78 with a Developer ID build, signed in through the App:** Approve; Request changes with text; the empty and blank Request changes refused; ⌥⌘V opening on the viewer's last verdict; Esc keeping the text, after which ⌘↩ posts a comment; the field released after a send, after which ⌘↩ opens GitHub; the bottom row and panel at 360 pt. The lag in Overrides was found here. A PR reviewed with Request changes leaves the Review list, and an approved one leaves it while "Hide pull requests I’ve approved" is on (the default) and stays dimmed otherwise: that is the list's existing rule (`TabBuilder`).
- **Not run on real GitHub:** a slowed connection, a push while in review mode, VoiceOver, a pending review started on the web, a draft PR, a closed PR, and a `gh` login.

## Left to the builder

- The panel's exact spacing and styling, within the app's existing materials.
- Whether review mode lives in `CommentField` or wraps it.
- How the dimmed review appears in `ReviewerEntry`.
