# Edit a pull request's reviewers, assignees and labels

PullBull lets you change a pull request's reviewers, assignees and labels from the popover, with the same picker issues use for assignees and labels. Today pull requests are read-only. In a daily, someone says "I'll take that one". Adding them as a reviewer means opening the browser, finding the PR and using GitHub's sidebar. With this, you select the row, press ⌥⌘R, type a few letters, Return.

This builds on `2026-10-31-edit-status-assignees-labels-design.md` (the edit spec): its picker, diff mutations, overrides, undo, failure line and permission handling. This document states only what is new or different for pull requests. Where it is silent, the edit spec's behaviour applies unchanged.

## Why

- Reviewers change in the moment: someone volunteers in a daily, or the author decides mid-task. The browser round trip breaks the flow it interrupts.
- Removing a reviewer (someone else picked it up) and asking for another look after new commits ("re-request") are the other common reviewer edits.
- Labels on PRs are set now and then for later categorisation and search.
- PullBull is open source. Teams other than the author's request teams as reviewers and assign PRs, so both are covered, though the author's own use is people and labels.

## Goals

- Request reviews from people and teams, remove review requests, and ask a past reviewer to review again, on pull requests.
- Add and remove assignees on pull requests.
- Add and remove labels on pull requests.
- From the same places as issue edits: keys on the highlighted PR row (every PR tab and PR search results) and in the PR detail; the right-click menu; the PR detail's fields.
- The change shows at once wherever the PR appears, survives refreshes that haven't caught up, and can be undone right after, as the edit spec describes for issues.

## Non-goals

- Submitting, approving or dismissing reviews, or anything else that writes a review. PullBull only asks people to review.
- Status on pull requests (board cards for PRs stay out of scope, as in the edit spec).
- Draft or ready-for-review, merge, close, comment, titles, bodies, milestones, linked issues.
- Editing CODEOWNERS or branch protection. Owners GitHub requested automatically show as requested like anyone else and can be removed like anyone else.
- Bulk edits.

## Anti-goals

The edit spec's anti-goals hold. In addition, the feature fails if:

- a stray keystroke asks a colleague for a review. GitHub notifies the person the moment the request lands, and an undo can't take the email back. The picker applies only when it closes, after deliberate ticks, as for issues, and nothing is sent until then;
- removing a reviewer looks as if it deletes their review or approval;
- the viewer is notified about a review request they just made themselves.

## What PullBull writes

PullBull writes exactly these to GitHub, each only when the user picks a value:

- an issue's board Status, assignees and labels;
- a pull request's review requests, assignees and labels.

Nothing else, ever. This replaces the edit spec's sentence wherever the product promises it (see Docs and copy).

## Interaction

### Keys

| Key | Does | Where |
|---|---|---|
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>R</kbd> | Reviewers picker | PR row, PR search result or PR detail |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> | Assignees picker | Issue or PR: row, search result or detail |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> | Labels picker | Issue or PR: row, search result or detail |

- ⌥⌘R is free today. ⌘R (refresh) is a different combination and stays as it is.
- ⌥⌘S stays issues-only.
- The selected PR is found the way ⇧⌘↩ and ⌃⌘C already find it (`selectedPRKey`), and the PR detail route (`.detail(key)`) takes the keys as the issue detail does.
- The open-picker rules extend to the new picker: opening one picker closes another, and while one is open the other pickers' keys do nothing. Its own key again applies and closes it.
- Non-Latin keyboard layouts already map R by key position (`SearchKeyMonitor.letterR`, used for ⌘R), so ⌥⌘R needs no new fallback.
- ⌥⌘R always belongs to the reviewers picker: with no PR selected, on an issue, or on a PR PullBull doesn't hold, it does nothing, and never refreshes or reloads.
- All three edits are offered on open, closed and merged PRs. A review after the merge ("have a look at what I merged") is a real use, and labelling for later search often happens after a merge. When GitHub refuses a request there, the failure line carries GitHub's reason. Whether GitHub ever accepts review requests on closed and merged PRs has not been checked against real GitHub yet; if it always refuses, ⌥⌘R and **Reviewers…** are to be hidden there.
- The Keyboard Shortcuts window's Editing section adds Reviewers <kbd>⌥⌘R</kbd>, noted "Pull requests". Its description covers issue and pull request rows, search results and both details. Set Status keeps its note.

### Mouse

- **Right-click a PR row** (open and closed rows, and PR search results): **Reviewers…** (`person.2`), **Assignees…** and **Labels…**, above the copy items after a separator, as issue rows have **Assignees…** and **Labels…**.
- **PR detail:**
  - The Reviewers card is clickable and opens the reviewers picker anchored to it, with the help tag "Change reviewers (⌥⌘R)". "No reviewers" stays as the empty line and is clickable too. On a PR PullBull doesn't hold, the card is plain.
  - The card's requests come from the detail while the detail is current for the PR (`PRDetail.isCurrent(for:)`), else from the list copy, with the edit overrides applied either way. A PR with no list copy shows the detail's requests.
  - A new card titled "Details" holds Assignees and Labels rows. It sits right under the summary, as the issue detail's card does, so it comes before Checks, and before the description on closed and merged PRs, and it doesn't move when the detail loads. Its rows are the issue detail's own, shared between the two: "No one" and "None" when empty, clickable, with help tags "Change assignees (⌥⌘A)" and "Change labels (⌥⌘L)". The labels move out of the summary into this card, so they show once, and there is a place to click when a PR has none.

### The reviewers picker

The same multi-select picker as assignees: the same placement, filter, keys and apply-on-close. The header names the PR (`acme/widgets#88`). What differs:

- **Rows, in order:**
  1. Requested now: people and teams with a pending request. These are ticked.
  2. Past reviewers who aren't requested now. These are unticked.
  3. The viewer, unless they are the author or already listed.
  4. The people GitHub suggests for the PR (`suggestedReviewers`).
  5. Everyone else who can be requested in the repo, by login, then teams.
  The cached people show at once and the PR's own data (requests, reviews, suggestions) arrives with the fetch, so the order is rebuilt on each load until the user first ticks or unticks a row. From then on it stays put and later loads append, as for assignees.
- **The author** is never listed: GitHub doesn't allow requesting the author.
- **Bots** (Copilot's reviewer and other apps) are never listed, even when they have reviewed: a review can't be requested from them by login. The candidate query reads the review author's `__typename` and keeps only `User`s; `prFields` and `Review` are unchanged. A bot's review still shows in the detail's Reviewers card as today.
- **Verdicts:** a person who has reviewed shows their latest verdict beside their name, in the same pills the detail's Reviewers card uses (approved, changes requested, commented). A person whose review is pending again after a re-request shows ticked with the verdict.
- **Ticking a past reviewer asks them again.** This is GitHub's re-request, sent as the same `POST …/requested_reviewers` as a first request. Ticking someone who has never reviewed requests them. Whether that POST re-notifies a past reviewer as GitHub's own re-request button does has not been checked against real GitHub yet; if it doesn't, past reviewers go through the re-request endpoint instead.
- **Unticking removes the request.** When someone who was requested as the picker opened and has reviewed is unticked, the row reads "Their review stays", so it is clear their approval isn't deleted. A past reviewer who wasn't requested and hasn't been touched shows no such line.
- **Teams:**
  - Listed by name, with the team glyph the detail uses (`person.2.fill` in a circle).
  - Offered only on repos owned by an organisation, and only when the team list could be read.
  - If it couldn't be read (permissions, or a `gh` login without `read:org`), the picker lists people only, with no note. Teams already requested on the PR still show ticked from the PR's own data, and can be unticked.
- **A requested reviewer with no candidate** (outside the first 100 people, or a team whose list couldn't be read) is shown ticked. Unlike a locked label, it can be unticked, because a review request is removed by login or team slug, so no ID is missing.
- **Copy:** loading says "Loading reviewers…". A filter with no match says "No one called “…”". An empty list says "No reviewers to ask".
- **No cap:** the picker dims nothing for reviewers. The assignee limit of 10 applies to assignees only. Whether GitHub caps review requests per PR has not been checked against real GitHub yet; a cap found later dims unticked entries at it, as assignees do at 10. Until then a request past one fails with GitHub's reason.
- **Accessibility:** the picker is labelled "Reviewers for …", and a ticked row reads "requested".

### Assignees and labels on pull requests

The issue pickers, unchanged, opened on a PR. Their "current" values come from the PR. A PR has no Mine list for assignees, so assigning yourself inserts nothing anywhere.

- Only a PR PullBull holds can be edited: one in a tab or search results, or opened from one. A PR opened from an issue's linked PRs, Ask or a notification, and in no list, has no Details card and the keys do nothing, as for issues.
- PRs in a cache from before assignees were read show none until the first refresh, so the card says "No one" and the picker shows real assignees unticked. Ticking one again changes nothing on GitHub.

### After an edit

- The PR row and the PR detail update at once. The detail must read through the overrides: today `AppModel.pullRequest(for:)` reads the raw snapshot and the opened PR unmodified, and that changes.
- **Review tab:**
  - Review lists open PRs only, so a closed PR never appears there, whatever its requests.
  - Requesting yourself, or one of your teams, on someone else's open PR puts it on Review (as "requested" or "re-requested"). The override carries a copy of the PR taken when the edit is made (from the Team tab, the Review candidates, or search), and that copy is inserted into Review when PullBull doesn't already list it there.
  - Removing your own direct request takes it off Review, unless another rule still keeps it there, such as a request for one of your teams.
  - The tab's existing rules (`ReviewRules.status`) decide this from the PR with the override applied.
- **Mine and Team** don't depend on reviewers or assignees, so nothing moves there.
- **Undo** (⌘Z within 10 seconds) sends the inverse:
  - Requests the user added are removed.
  - Requests the user removed are requested again. For a past reviewer that is a re-request, which is accepted: it puts back what was there.
  - Labels and assignees as for issues.
- **No message on success,** as for issues.

### Failure

As the edit spec, with these messages:

- "Couldn't change reviewers on #88: …"
- Partial: "Asked alice to review #88, but couldn't remove bob: …" and "Removed bob from #88, but couldn't ask alice: …". People are named by login and teams by name, comma-joined.
- GitHub refuses a request for someone without access to the repo. The failure line carries GitHub's reason.

## Data and GitHub API

### What the PR models need

- **Assignees:** `PullRequest` has none. Add `assignees(first:10){nodes{login avatarUrl}}` to `prFields`. Cached snapshots decode without it (`decodeIfPresent`, empty).
- **Review requests:** `reviewRequests` holds `Reviewer`s: `.user(login)` and `.team(slug:name:)`. `Reviewer.key` (lowercased login, or `team:` plus the lowercased slug) is the identity everywhere: picker rows, diffs, agreement. `Reviewer` has a hand-written `Codable`: a person keeps the cached shape, and a team written before names were read decodes with its slug as the name.
- **PR detail:** the detail query adds `reviewRequests(first:20)` as `PRDetail.requests`, nil when a detail doesn't carry them.

### Mutations

| Edit | Request |
|---|---|
| Request reviews, re-request | REST `POST /repos/{owner}/{repo}/pulls/{number}/requested_reviewers` with `reviewers` (logins) and `team_reviewers` (slugs) |
| Remove review requests | REST `DELETE /repos/{owner}/{repo}/pulls/{number}/requested_reviewers`, same body |
| Labels, assignees | The issue mutations (`addLabelsToLabelable` and friends), with the PR's node ID |

- Reviewers go as a diff, like labels and assignees. GraphQL's `requestReviews` without `union` replaces the whole set, which would drop a reviewer someone else just added.
- The REST endpoints take logins and slugs, so no user or team node IDs are needed, and a requested reviewer without a candidate can still be removed.
- An edit that both adds and removes sends two requests: add first, then remove. The edit spec's partial-result rules apply. Only what applied stays on screen and is undone.
- The REST calls use the same token and `APIError` mapping as the GraphQL writes. `GraphQLTransport` has a REST method (method, path, JSON body) with a default that throws `APIError.server(501)`, so test doubles that never write reviewers need nothing. The production request carries the Bearer token, `Accept: application/vnd.github+json` and `X-GitHub-Api-Version: 2022-11-28`; a test pins it.
- A 422, a 404 and a 403 that isn't a rate limit are refusals in GitHub's words (for example "Reviews may only be requested from collaborators"): the message is the failure line's reason.
- Once the POST has applied, any DELETE failure is a partial result, never a thrown error, so the added requests stay on screen and are undone alone.
- `reviewers` is the DELETE body's required field, so a team-only removal sends `reviewers: []`.

### Picker candidates

- **People:** `repository.assignableUsers(first:100)` (already used for assignees) plus the PR's `suggestedReviewers`. The filter queries `assignableUsers(query:)` and the teams past the first 100, as for assignees. The PR's author is left out of every list.
- **Cache:** only `assignableUsers` people, with their node IDs, are cached, under the key the assignees picker uses (`assignees|<repo>`), so the two pickers share them. Teams cache under `teams|<owner>`. Per-PR data (requests, verdicts, suggestions) is never cached, so it can't leak into the assignees picker.
- **Teams:** `organization.teams(first:100, query:)`, with `slug name`, for the repo's owner when it is an organisation. Paging works as for labels. Any error reading them leaves teams out without a note. Teams without access to the repo may be listed, and GitHub refuses them. The failure line says so.
- **The PR's own values:** the reviewer candidate query reads the PR's current review requests, latest reviews, author and suggested reviewers through `issueOrPullRequest(number:)`. A reviewer whose node ID isn't read keeps its key as its ID: REST takes logins, and per-PR candidates are never cached.
- Nothing is written to disk.

### Overrides

- `EditChange` gains `.reviewers(added: [Reviewer], removed: [Reviewer])`. The model's `Reviewer` is the reference; there is no separate type.
- Applying it to a `PullRequest` adds or removes entries in `reviewRequests`. `latestReviews` is untouched, so a removed reviewer's verdict stays visible.
- **Agreement:** every added reviewer is present in `reviewRequests` and every removed one is absent, case-insensitively, on the first copy of the PR found in the snapshot: Review candidates, Mine, Team, then closed Mine. A PR held only through search isn't in the snapshot, so its override waits out the 5 minutes; search results read through it meanwhile.
- **Adding or removing yourself or one of your teams** on an open PR agrees only once the Review candidates agree too, as self-assignment waits for Mine on issues. A search's node fields are live but its matching lags, so the Team copy can show the request a poll before `review-requested:@me` lists the PR. Dropping the override on the Team copy would make the row leave Review and come back. So adding the viewer or one of their teams agrees once the Review candidates list the PR with that request, and removing one agrees once the Review candidates' copy no longer carries it (or no longer lists the PR).
- On a closed or merged PR, a self-edit agrees on the PR copy alone: Review never lists closed PRs, so waiting for it would hold the override the full 5 minutes.
- **Assignees on PRs:** agreement looks in the PR lists too. Today `agrees` for `.assignees` searches only issues, so a PR assignee edit would wait out the 5 minutes.
- Lifetime, oldest-first application and dropping replaced edits work as in the edit spec. An older reviewers edit is replaced by a newer one that touches one of the same people or teams.

### Notifications

- `ChangeDetector` compares raw snapshots and doesn't know who made a request. So requesting yourself would raise "review requested" on the next poll, attributed to the PR's author.
- The viewer's own review request must not notify them. When the viewer adds themselves to a PR's reviewers, the "review requested" event for that PR is suppressed on every poll up to and including the first one whose Review candidates list the PR as needing the viewer's review. The suppression ends there, and in any case 6 minutes after the edit (the override's 5 minutes plus a poll's slack). So a request that never shows (someone removed the viewer a minute later) can't swallow a real request hours later.
- The suppression sits in `NotificationGate` (`ownReviewRequest(on:at:)`, `selfRequestWindow` = 360 s). It applies on every live fetch, including the CI follow-ups and the first fetch after launch. Tests pin it.
- Requesting a team the viewer belongs to counts as requesting themselves: the anti-goal "notified about a review request they just made themselves" covers it.
- Requesting someone else never notifies the viewer. That is already the case.

## Permissions

### GitHub App

- **New permission:** **Pull requests: Read and write**. It gates all three PR edits (`pull_requests: write` in the installation's permissions; add `canWritePullRequests` to `Installation`).
- Labels and assignees on PRs gate on `pull_requests: write` alone, as reviewers do: one rule for every PR edit. GitHub's permission tables accept it for PR labels and assignees, and the official app has it.
- Existing installations behave as in the edit spec: until an owner accepts, choosing a PR edit shows the one-line note with the link to the installation's permissions page, in place of the picker. Issue edits keep working on `issues: write` alone.
- **Members: Read** (already granted) covers reading the org's teams. Without it, the picker lists people only.
- Update `docs/github-app-setup.md`: the permission table and the description text.

### GitHub CLI logins

- `repo` covers all three edits.
- Teams need `read:org`. Without it the team list fails and the picker shows people only, as above. No nag: the scope is not required for anything else, so no note asks for it.

## Docs and copy

- **README Privacy row:** "An issue's board Status, assignees and labels, and a pull request's reviewers, assignees and labels, only when you pick them. Never merges, comments, approves or closes".
- **README keys table:** ⌥⌘R beside ⌥⌘A and ⌥⌘L. The right-click bullet adds the PR items.
- **Manual:**
  - The Editing section covers pull requests and the reviewers picker: re-request, "their review stays", and teams.
  - The key tables cover ⌥⌘R, and ⌥⌘A and ⌥⌘L on pull requests.
  - The right-click list for pull requests.
  - The PR detail's Details card.
- **CONTRIBUTING out-of-scope:** "Writing to GitHub beyond Status, assignees, labels and review requests (merge, comment, approve, close)".
- **GitHub App description:** the Privacy sentence.
- **The edit spec:** its lines saying pull requests stay read-only (Non-goals, the override section's "A PR … takes no edits", and the GitHub App section) are rewritten to point here and state the result as fact.
- **Code comments:** "The read-only detail of one PR" (`PRDetailView`) goes.

## Delivery

1. **Assignees and labels on pull requests,** plus the permission change:
   - `pull_requests: write` detection and the note;
   - PR assignees in the model and query;
   - the Details card;
   - the keys and menu items for ⌥⌘A and ⌥⌘L on PRs;
   - overrides through the PR detail;
   - PR assignee agreement.
   The official app's permission (Pull requests: Read and write) was changed on 2026-11-01, before step 1, and covers both steps. Step 1 updates `docs/github-app-setup.md` to match.
2. **Reviewers:**
   - the REST mutations;
   - candidates (people, suggested, teams);
   - the reviewers picker with verdicts, re-request and "their review stays";
   - ⌥⌘R, the menu item and the clickable Reviewers card;
   - overrides, Review-tab moves and the self-request notification rule.

Each step ships as its own PR. The README and manual change with the step that makes them true.

## Testing

Per CONTRIBUTING, logic lives in PullBullKit with tests. Beyond the edit spec's list:

- **Reviewer diffs:** ticking a past reviewer is an add (re-request); unticking a requested one is a remove; a toggle back sends nothing.
- **Request building:** the REST paths, methods and bodies for add, remove and both; logins and team slugs; the partial result when one call is refused; a 422's message as the reason.
- **Picker rows:** the order; the author and bots excluded; verdicts shown; a requested reviewer without a candidate shows ticked and can be unticked; teams only when loaded.
- **Gating:** all three edits offered on open, closed and merged PRs; a closed PR never enters Review.
- **Overrides:** reviewers applied to PR rows and the detail; agreement; `latestReviews` untouched; PR assignee agreement in PR lists; a self-add that the Team copy shows but the Review candidates don't yet keeps its override.
- **Review tab:** self-request inserts the copy carried by the override; self-removal removes unless a team request keeps it.
- **Notifications:** the viewer's own self-request raises no notification, including on the poll where the Review candidates first list it; the suppression ends after 6 minutes, so a later real request still notifies; a request by someone else still notifies.
- **Permissions:** `pull_requests: write` gating; the no-teams fallback.
- **Caches:** cached PRs without assignees or team names decode.

Manual check against real GitHub, on a test repo in an org with a team. For step 2 it has not been run yet; the re-request, closed and merged PR, and cap answers above depend on it:

- request, remove, re-request a past reviewer, a team, undo;
- a review request on a closed and on a merged PR;
- assignees and labels on a PR;
- a refresh right after doesn't flicker;
- an installation without the new permission;
- a `gh` login without `read:org`;
- requesting yourself doesn't notify you.

## Calls made in writing this

The user decided: reviewers first, then labels, assignees rarely; people as reviewers; removing and re-requesting both happen; the app is open source, so others' workflows count. The rest are the writer's calls:

- ⌥⌘R for reviewers; ⌥⌘A and ⌥⌘L reused on PRs.
- Teams included, listed after people, for other users' workflows. Silently people-only when the team list can't be read.
- Re-request is a tick on a past reviewer, not a separate button. Unticking a past reviewer says "Their review stays".
- Bots never listed in the reviewers picker.
- A Details card (Assignees, Labels) in the PR detail; labels move there from the summary.
- REST `requested_reviewers` for reviewer writes, for diff semantics without node IDs.
- Self-request agreement waits for the Review candidates, and the self-notification suppression ends at the first poll that lists the request, capped at 6 minutes.
- Delivery in two PRs: assignees and labels first (with the permission change), reviewers second.

## Settled in building

- The notification suppression sits in `NotificationGate`.
- No review-request cap in the picker, pending the manual check.
