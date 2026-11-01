# Review wait on pull request rows

A pull request row that is waiting for a review says who it's waiting on and for how long: "🕒 @georgi 3d". A PR nobody was asked to review says how long it has gone without one: "🕒 No reviewer 5d".

## Why

- On a busy repo, the question people bring to the list is "what's been sitting, waiting for a review?". The row shows approvals, checks, conflicts and when the PR last changed, but not how long a review has been outstanding or whom to nudge.
- PRs nobody was asked to review rot quietly. Today they read "No reviews" on Mine and nothing on Team, with no sense of age. With ⌥⌘R (reviewers picker) one keystroke fixes them, once they're visible.
- PullBull is open source. Everything here comes from data GitHub already exposes, with no setup, team rules or per-repo configuration, so it reads the same for a solo maintainer and a 70-PR team.

## Goals

- Every open, non-draft PR row with a pending review request shows the oldest pending request's reviewer and how long it has waited.
- Every open, non-draft PR row with no pending request and no review shows how long it has been ready for review.
- Same rule on every PR tab and in PR search results, so a PR reads the same everywhere.

## Non-goals

- A "ball in court" state for every PR (waiting on author, CI, conflicts, merge). This was considered and dropped: it's the review wait people want, not the whole state machine.
- A "waiting on me" filter. The Review tab is that list.
- Sorting or grouping by wait, an `is:` search token for it, notifications or thresholds when a wait gets long.
- Branch protection, required reviewer counts, CODEOWNERS rules.

## Anti-goals

The feature fails if:

- a row shows a wait that is wrong, such as a date made up when the real one isn't known. Missing beats wrong;
- the meta line gets noisy. The wait is one glyph-and-text item, gray like other info, and healthy rows (reviewed, nobody pending) gain nothing;
- it costs an extra request per refresh or per PR.

## Behaviour

### When a row shows a wait

Only open, non-draft PRs. Closed, merged and draft PRs show none.

| PR state | Row shows | Clock starts |
|---|---|---|
| One or more pending review requests (people or teams) | `🕒 <oldest> <age>`, plus `+N` when more are pending | When that request was made. A re-request is a new request and resets the clock |
| No pending requests, and no submitted review | `🕒 No reviewer <age>` | When the PR was last marked ready for review; if it never was a draft, when it was opened |
| No pending requests, and at least one submitted review | nothing | – |

- "Pending request" means an entry in `reviewRequests`. When a reviewer submits, GitHub drops their request, so their clock stops and the row moves to the oldest of those still pending.
- A request GitHub returns with no reviewer (a team the viewer can't see, a bot such as Copilot) isn't a pending request here: `reviewRequests` already drops it, so it neither names nor ages the row.
- Two requests made at the same moment: the first in GitHub's order counts as the oldest.
- "Submitted review" means a `latestReviews` entry by a person that isn't pending and has a submission date, any state (approved, changes requested, commented, dismissed). A bot's review (Copilot code review, a review app) doesn't count: those land on nearly every PR within minutes, so counting them would hide every "No reviewer" wait on repos that use one. The fragment fetches each review author's `__typename` to tell.
- After "changes requested", the ball stays with the author until they re-request the review. Pushes don't move it. Since the reviewer's request is gone until then, the row shows nothing for them; the existing Changes-requested capsule and counts already say where it stands.
- Failing or running CI doesn't hide the wait. The row already shows CI; the clock is about the request.
- Other row items (approval count, Changes-requested and Ready-to-merge capsules, Conflicts, the Review tab's reason) stay as they are. A PR can show an approval and a wait for another pending reviewer at once.

### Wording

- **Oldest pending reviewer:** a person reads `@login`; a team reads `@org/slug`, the way the Review tab's "via @org/slug" does (bare slug when the repo has no owner). When the oldest pending request is the viewer's own, it reads `You`; a team of the viewer's reads as the team.
- **More pending:** `+N` after the name, N being the number of other pending requests.
- **Age:** the short relative age the row already uses (`RelativeAge.short`), measured from the clock's start to now.
- **Review tab:** rows there wait on the viewer, so the wait is just `🕒 <age>`, measured from the viewer's own pending request, else the oldest pending request to a team of the viewer's, whatever the row's reason (requested, re-requested, via team, new commits). A Review row with no pending request to the viewer or their teams (there for "new commits since your review" alone) shows no wait.
- **Short form follows the data, not just the tab.** A search opened on the Review tab draws its results with Review-tab chips, including PRs that don't wait on the viewer. The short form applies only when the row is laid out as Review, the row is counted there with a reason (it needs the viewer's review), *and* there is a pending request to the viewer or their teams. Any other row on a Review layout, including a dimmed "You approved · not counted" row whose team is still pending, gets the full form (`@org/ios 3d`, `No reviewer 5d`) by the general rules, since a bare age there would read as "waiting on you".
- **Mine tab:** the wait replaces today's "No reviews" item. `🕒 No reviewer <age>` covers "no reviews, nobody asked"; a PR with pending requests but no reviews shows the wait instead of "No reviews". Two changes follow from the rules above and are intended: a PR whose only reviews are comments or dismissed reviews shows no wait (someone has reviewed it), and drafts lose "No reviews" (a draft isn't asking for review).
- **Team tab and search results:** gain the wait; they had no "No reviews" item.

### Glyph and placement

- SF Symbol `clock`, the glyph "No reviews" uses today. No new icon.
- A text info item in the meta line (after the age, after `·`), gray like the other info items, not a warning.
- When the meta line is too narrow, the name shortens first; the age never truncates.
- Compact rows show no wait, on any tab. Their one age stays the updated age, the same number the full row and the PR show; a second bare age beside it (`🕒 4d … 1h`) reads as noise, and a wait in its place would show a number that changes on opening the PR. The Review reason glyph stays the reason.

### Hover and VoiceOver

The full wording lists every pending reviewer with their own wait, oldest first, for example "Waiting on review: @acme/ios 4 days, @dana 1 day" (the viewer reads "You"). When a time is unknown it lists the names alone, in GitHub's order: "Waiting on review: @georgi, @dana". "No reviewer" reads "No reviewer requested, ready for 5 days". The Review tab's reads "Requested from you 2 days ago" (or "from @org/slug"). Ages are spelled out: "under a minute", "1 minute", "3 hours", "4 days", "2 months", "1 year".

### Unknown times

- A request older than the timeline events fetched (below), or a snapshot cached before the times were stored: the request's time is unknown.
- If **any** pending request's time is unknown, "oldest" can't be known, so the row shows no age: the first pending request in GitHub's order, `+N`, no age. Showing the oldest *known* one could name the wrong person with the wrong age. On the Review tab, with nothing else to show, an unknown time shows nothing: the viewer's own request when there is one, else any of the viewer's team requests.
- A PR converted from draft, read from a snapshot cached before the ready time was stored, counts "No reviewer" from when it was opened until the first refresh brings the ready time. It is brief and self-correcting, so it isn't special-cased.
- The ready-for-review time has its own one-event query (below), so it is never crowded out. No `ReadyForReviewEvent` means the PR was never converted from draft, and the opened time is correct.

### Edits from PullBull

When the viewer requests a reviewer with ⌥⌘R, the override that adds the request also gives it a request time of now (the edit's time); a reviewer who was already pending keeps GitHub's time, so the row shows "@dana 0m"-style ages at once and stays consistent until the refresh brings GitHub's own time. A request removed through the picker disappears from the wait like any other.

### The row's age and the PR page

- A row's own age (`#779 · 1h`) stays the last update: it's the list's sign of activity and what the lists sort by, while the wait says how long a PR has sat. Showing the opened age there instead would often repeat the wait (`4d · No reviewer 4d`).
- So the number on the row is also on the PR page, its byline names both: "rado opened 4d ago · updated 1h ago", leaving out "updated" when it would read the same as "opened". Beside a wide pill the byline wraps to a second line rather than cutting "updated" off.
- The row's age (full and compact) says "Updated 1h ago" on hover and to VoiceOver.
- Neutral pills on a fill (Open, Ready to merge, an issue's not-planned Closed, Ask's Open) use a stronger text colour, about 7.5:1 in both appearances; the secondary text colour on a fill was near 4:1 in dark mode at the pills' 10pt.

## Data

Two aliased fields on the shared PR fragment (`Queries.prFields`), in the same request as today. The pattern matches `Queries.assignedEvents`:

```graphql
reviewRequestEvents: timelineItems(itemTypes:[REVIEW_REQUESTED_EVENT], last:20){
  nodes{... on ReviewRequestedEvent{createdAt requestedReviewer{__typename ... on User{login} ... on Team{slug}}}}
}
readyEvent: timelineItems(itemTypes:[READY_FOR_REVIEW_EVENT], last:1){
  nodes{... on ReadyForReviewEvent{createdAt}}
}
```

- For each entry in `reviewRequests`, its request time is the newest `ReviewRequestedEvent` naming the same user (case-insensitive login) or team (slug). None found: unknown.
- The ready-for-review time is the `ReadyForReviewEvent`, else `createdAt`. Kept apart from the request events so a busy request history can't push it out.
- The caps (`last:20`, `last:1`) bound the cost: up to 21 more nodes per PR in GitHub's query cost, no extra round trip.
- The new values are optional on `PullRequest` and in the cached snapshot, nil in snapshots cached before them, like the other fields added since. Their shape is the builder's call; keeping `Reviewer`'s identity unchanged (it's a key in edit overrides and search) matters more than where the times live.

## Rule location

The wait is a pure function in PullBullKit, next to `ReviewRules` and `RowChips`, unit-tested on its own: given a `PullRequest`, the viewer, their teams, the tab and now, it returns what the row shows (the item and its full wording), or nothing. `RowChips` carries it as an info item. The views only draw it.

## Docs

- `docs/manual.md`, Pull Requests section: one line on the wait, its two forms, and the Review tab's short form.
- `docs/media/src`: the screenshot data and the `noReviews` component change to the wait, so the popover and search screenshots match. The mock gives way the way the app does: other info text ellipsizes and the wait stays whole.

## Decisions

- **Review wait only, not a full "ball in court".** The owner narrowed it: what people want is how long something has been sitting waiting for a review. The earlier rule order (draft → conflicts → failing CI → changes requested → pending requests → nobody → ready to merge, with failing CI putting the ball with the author because reviewers wait for green) is not built.
- **Back to the reviewer only on re-request.** Authors push fixups in several goes; a push doesn't hand the ball back.
- **"Since" matters, so the request time is fetched**, in the existing query.
- **Who + how long (`@georgi 3d`), not just how long.** The point is to see what's sitting and nudge someone; a name is actionable from the list without hovering.
- **Review tab shows the age alone.** Every row there waits on the viewer, so a name adds nothing.
- **"No reviewer" counts from ready for review.** A PR that was a draft for two weeks and went ready yesterday shouldn't read "2w".
- **Drafts show no wait.** A draft isn't asking for review.
- **Missing time → no age, never a guessed one.** One unknown pending time hides the age for the row, since "oldest" can't be known.
- **Ready-for-review time has its own one-event query**, so request history can't crowd it out and the opened-time fallback is only used when it's correct.
- **The Review tab's short form needs a pending request to the viewer or their teams**, not just the Review layout: search results on that tab include PRs that don't wait on the viewer.
- **Bot reviews don't count as reviewed.** Found in the final review: Copilot posts a COMMENTED review on nearly every PR in repos that use it, which would have hidden "No reviewer" there and dropped Mine's old "No reviews" signal.
- **The short form needs a counted Review row.** Found in the final review: a dimmed or uncounted row with the viewer's team still pending isn't waiting on the viewer.
- **Compact rows show no wait.** The owner saw the real list in compact mode, nearly every row with two bare ages, and found it confusing; replacing the updated age with the wait would make the number change when the PR is opened. The wait belongs to full rows.
- **The row keeps "updated"; the PR page adds it.** The owner saw a row's `1h` and the page's "opened 4d ago" disagree. Of showing "opened" on the row or "updated" on the page, the page won: the row keeps its activity signal and doesn't repeat the wait.
- **Neutral pills get their own text colour.** The owner found the Open pill too faint in dark mode; only pill text changes, so the app's other gray text stays as it is.
- **Unseen and bot requests don't count.** GitHub returns them with no reviewer; naming or ageing a row by something nobody can see or nudge would be noise.
- **Missing beats wrong, in the hover too.** With an unknown time the hover lists names only, not ages for the known ones, so it can't contradict the row.
- **The old-cache ready time isn't special-cased.** Showing "No reviewer" from the opened time until the first refresh is a short, self-healing exception to "missing beats wrong"; handling it would mean a cache version flag for one refresh.
- **Existing icons.** SF Symbol `clock` in the meta line, the app's own glyphs only where SF Symbols has none.
