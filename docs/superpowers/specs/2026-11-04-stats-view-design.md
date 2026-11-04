# Stats view

A Stats view, opened from the gear menu with ⌘3, shows how your reviewing and your pull requests have gone over the last 7, 30 or 90 days. It covers how many reviews you did and how fast, how many of your PRs merged and how long they waited for a first review, who reviews you most, and what is waiting right now. Every number comes from GitHub for the account and scope on screen.

Mockup: https://claude.ai/artifact/RjYzu4Ddd4dqmonwWUcjkz (artboard Main, light and dark).

## Why

- Many apps have a stats screen. Most count clicks inside the app and turn them into "time saved". PullBull's users are engineers, and a minutes figure built on a made-up seconds-per-action number is the first thing they'd distrust.
- What engineers do want to know about their own review habits isn't on GitHub's profile page: how long people wait for them, how long they wait for others, who carries their reviews. GitHub has the data, so the view is full on its first open, with no history kept on the Mac.
- PullBull is open source and used by solo maintainers and large teams. The view has to read right for an org account and for a personal one.

## Goals

- One view with four cards (Your reviews, Your pull requests, Right now, Issues) and a provenance footer.
- Periods of 7, 30 and 90 days, each compared with the period before it.
- The account and scope on screen (an org, or the personal scope), the ones the lists use.
- Every number traceable to a GitHub query; anything that can't be known is left out rather than estimated.
- A bounded cost: a fixed number of queries per load, capped pages, a 15-minute cache.

## Non-goals

- Counters of what you did inside PullBull (comments sent from the popover, jumps, Ask queries).
- A "time saved" figure, in any form.
- Several accounts added together.
- Other people's stats, team leaderboards, per-repo breakdowns.
- History stored on the Mac, charts beyond the one bar chart, exporting.
- Board Status moves (see Decisions).
- A weekly digest notification. A possible follow-up; not built here.

## Anti-goals

The feature fails if:

- a number is wrong: a median over data a cap cut without saying so, a count that silently misses part of the period, a bar drawn as zero for a day that wasn't loaded. Missing beats wrong;
- it reads as a gamified dashboard: streaks, scores, colours that judge (red for slow). Values are the primary text colour, comparisons secondary, and the accent only marks today's bar;
- one load costs more than about 20 points of the 5,000/hour GraphQL budget, or it refetches every time it opens.

## Behaviour

### Opening and closing

- The gear menu (footer gear, and the menu bar item's right-click) gets a **Stats** item with ⌘3, after Keyboard Shortcuts. From the menu bar item's right-click it shows the popover, on Stats. ⌘3 also opens Stats from the list and from search, by key position as well as character, as ⌘1 and ⌘2 do.
- Stats opens only from the list or the search. On any other screen (a detail, Ask, Stats itself) or with a picker open, the menu item is disabled and ⌘3 does nothing. It is disabled, and ⌘3 does nothing, while no account is signed in or the account's scope hasn't loaded.
- It is a pushed screen like a detail: it slides in from the trailing edge over the list (a fade with Reduce Motion), with a back chevron in the header. Esc, ⌘[ or the chevron return to where it was opened from: the list, or the search with its query kept. ← does not go back on Stats; it moves the period chips (below).
- ⌘1, ⌘2 and ⌘3 do nothing on Stats, as on a detail. ⌘Z does nothing either: Stats has no edit to undo, and the list's last edit stays put.
- Stats keys go only to Stats, never to the list hidden behind it: Esc, ⌘[, ← →, ↑ ↓, ↩, ⌘↩, ⌘C and ⌘R act on Stats, and no key edits the list's search, pickers or selection. ↑/↓ move the highlight between the two Right now rows; ↩ opens the highlighted row's detail, ⌘↩ opens it on GitHub, ⌘C copies its link. The highlight clears each time Stats opens.
- An issue notification clicked while Stats is on screen opens the issue's detail, and Back from it returns to the list. A PR detail opened from Stats (a Right now row, or a PR notification) returns to Stats.
- Back from a PR detail onto Stats fetches again if the period's result is stale.
- The popover closed while Stats is on screen reopens on Stats under the rule a detail follows (`PopoverReopen`); otherwise on the list.
- When the account or org changes (Settings, or the menu bar's account menu), Stats reloads for the new one if it is on screen, once the new account's lists are loaded. Signing out while Stats is on screen returns to the list.

### Layout (top to bottom)

1. **Header:** back chevron, labelled with where Back goes (the list's name, or "Search"), the title "Stats" centred, a refresh button on the right. While a fetch runs the button is a spinner. ⌘R on Stats refreshes the stats, not the lists; with a fetch already running it does nothing, and neither does Retry.
2. **Period chips:** This week · This month · 90 days, styled as the scope chips, each with a tooltip such as "Today and the 6 days before", and a faint "← →" hint at the trailing end. ← and → move between them (no wrap). The choice is one app setting, kept across opens and relaunches. Default: This week.
3. **Error line**, only when there is an error (below).
4. **Your reviews** card, with "Last 7 days" (30, 90) at the trailing end of its header.
5. **Your pull requests** card.
6. **Right now**: the section header and the two rows, with no card box around them. The rows draw their own hover and selection fill, and a box would put a fill inside a fill. Each row has a caption above it ("Waiting on you longest", "Your PR waiting longest").
7. **Issues** card.
8. **Footer:** "From GitHub, for `<login>` in `<org>`" (personal scope: "in your repositories"), plus "· from latest 100" when any cap cut in (below). Hover on the footer: "Updated 4 minutes ago. Only repositories PullBull can see."

Header, chips and footer stay put; the cards scroll between them when they don't fit. Your reviews, Your pull requests and Issues are drawn as the detail's cards under list-style section headers.

### Periods

- A period is whole local calendar days ending with today: This week = today and the 6 days before, This month = today and the 29 before, 90 days = today and the 89 before. It starts at local midnight of its first day and ends now.
- The comparison period is the same number of whole days just before it, ending at the period's start.
- Both are half-open: a moment exactly at the period's start belongs to the period, not the comparison. Queries ask GitHub for `[start, end − 1 s]`, since GitHub's ranges include both ends.
- Comparison wording, in secondary text after the value: "last week 5 h", "last month 31", "previous 90 days 2 d 4 h". In a column too narrow for one line (the Your pull requests card's three columns), it takes two: the period's name ("previous 90 days") on the first, the value on the second.
- A comparison is left out when either side has no value (a median with no samples, an item that failed).

### Durations

Medians are durations, short in the cards and spelled out for hover and VoiceOver:

| Duration | Card | Spoken |
|---|---|---|
| under 1 minute | `< 1 m` | "under a minute" |
| under 1 hour | `42 m` | "42 minutes" |
| under 1 day | `3 h 10 m` (`3 h` when minutes are 0) | "3 hours 10 minutes" (singular for 1) |
| 1 day or more | `2 d 4 h` (`2 d` when hours are 0) | "2 days 4 hours" |

Minutes and hours round down. The median of an even count is the mean of the two middle values. No samples: the value is "–".

### Your reviews

| Item | Value | Comparison |
|---|---|---|
| Reviews | Reviews you submitted in the period, on PRs you didn't author | yes |
| Turnaround | Median time from a review request to your response (below) | yes |
| Bar chart | Reviews per local day, one bar per day of the period (7, 30 or 90 bars) | no |

- A review is one you submitted (approved, changes requested, commented, dismissed), dated by its `submittedAt`. Pending (unsent) reviews and reviews on your own PRs (replies in a thread) don't count.
- Bars: today's in the accent colour, the others in the secondary colour; a day with none draws a 1-pt stub on the baseline in the tertiary colour, and a day with reviews is at least 2 pt tall, so an empty day never reads as a short bar. The chart's summary: "12 reviews in the last 7 days, most on Tuesday (4)"; for 90 days the busiest day reads with its date ("most on 14 Oct (6)"). It is the chart's VoiceOver label; the chart has no tooltip.
- Chart layout, top to bottom: the caption "Per day" (caption size, secondary colour, leading); the bars, 36 pt tall, with about 12 pt reserved above them for the busiest day's count; and an axis row in caption2. The bars fill the card's width, with gaps of 6 pt at 7 days, 2 at 30 and 1 at 90; a week reads as seven wide columns, like Screen Time's week view.
- The busiest day's count (the same day the summary names: the most recent of tied days) sits centred above its bar in caption2 with monospaced digits, secondary colour, or accent when that day is today. It is kept inside the chart's width, so an edge bar's count doesn't clip. No count is drawn when no loaded day has a review.
- Hovering a day shows it at once (a continuous hover, no tooltip delay). Its bar or stub draws in the primary colour, today's in a brighter accent, and the label row above the bars shows that day in place of the busiest day's count: "1 · Thu 29 Oct", "0 · Fri 30 Oct", or "Not loaded · Thu 29 Oct" for a day not loaded. The date is "EEE d MMM" from the same en_US_POSIX formatting as the axis, with the local calendar deciding the day and its time zone. The label is centred on that day's bar and kept inside the chart's width, in caption2 with monospaced digits, secondary colour, or accent when the day is today. When the pointer leaves, the busiest day's count returns.
- Each day's hover target is the chart's full height (count row, bars and axis), from the middle of the gap before its bar to the middle of the gap after it; the first day's starts at the chart's leading edge and the last day's ends at its trailing edge, and the middle of a gap belongs to the later day. A 1-pt stub, or a day not loaded, is as easy to hit as a tall bar.
- Axis: for 7 days, every day's weekday initial in English ("T F S S M T W"), from the same en_US_POSIX formatting as the dates and the summary, so the axis, the summary and the hovered day read in one language whatever the system locale; the local calendar still decides the days, centred under its bar, today's in the accent colour and the rest secondary. For 30 and 90 days, two dates as "d MMM" in the secondary colour: the first day's, leading-aligned with the first bar's left edge, and today's, trailing-aligned with the last bar's right edge ("6 Oct" … "4 Nov"). A day not loaded keeps its label.
- The caption, count, hovered day's label and axis are drawn into the chart's one accessibility element, whose label is the summary; VoiceOver doesn't hear the per-day label. While the first report loads, the chart shows its real "Per day" caption and a shimmer only where the bars go (36 pt), with the count and axis rows left empty; when the reviews didn't load, the space is blank. Both take the chart's full height, caption to axis, so nothing moves when the report lands.
- When the cap cut in (below), days that may be missing reviews are not drawn at all, not as stubs. The reviewed search returns PRs most recently updated first, and a review updates its PR, so a PR not loaded has every review at or before the oldest loaded PR's `updatedAt`: every review from then on is loaded. The first day starting at or after that time is drawn (that same day when `updatedAt` is exactly local midnight, else the next day), and every day before it is not. When the cap cut in and no PR was loaded, no day is drawn. A period with no reviews: "No reviews in the last 7 days".
- Capped, the summary's total reads "N+", as the Reviews figure does, and the days not loaded follow as a sentence of their own: "12+ reviews in the last 7 days, most on Tuesday (4). Days before 3 Oct not loaded". When the first loaded day would be after today (every loaded PR was updated today), no day is drawn and the sentence reads "No day fully loaded": "37+ reviews in the last 7 days. No day fully loaded". With nothing loaded: "0+ reviews in the last 7 days".
- Turnaround, for each review R of yours in the period:
  - the request is the latest `ReviewRequestedEvent` on that PR made at or before R, naming you or one of your teams;
  - R is your response only if you submitted no other review on that PR between the request and R;
  - turnaround = R − the request.
  - A review with no such request (you reviewed unasked, or a follow-up) is not a sample. Neither is one whose request is older than the 20 request events loaded per PR.
- Turnaround hover: "Median of 9 reviews you were asked for" ("1 review" for one); none: "No reviews you were asked for in this period". Capped, the cap sentence follows after ". ", as on every hover: "Median of 9 reviews you were asked for. From the latest 100 PRs".

### Your pull requests

| Item | Value | Comparison |
|---|---|---|
| Merged | Your PRs merged in the period | yes |
| Time to merge | Median of merged − opened over those PRs; hover "Median of 12 merged PRs" ("Median of 12 merged PRs. From the latest 100 PRs" when capped), and no hover when nothing merged | yes |
| First review | Median wait for a first review, over your PRs opened in the period (below) | yes |
| Top reviewers | Up to 3 people, avatar + login + count, who reviewed the most of your PRs opened in the period | no |

- First review, for each of your PRs opened in the period:
  - the clock starts when it was last marked ready for review (its latest `ReadyForReviewEvent`), else when it was opened; the same start `ReviewWait` uses;
  - the first review is the earliest submitted review by a person other than you (a bot's review doesn't count, as in `ReviewWait`);
  - wait = first review − start.
  - Not samples: a PR still a draft, one not yet reviewed, one first reviewed before its start (reviewed while a draft).
  - Hover: "Median of 6 PRs. 2 of your PRs opened in this period still wait for a first review." The second sentence counts open, non-draft PRs with no review yet, and shows only when there are some; a PR closed or merged without a review doesn't wait.
- Top reviewers count PRs, not reviews: someone who reviewed one PR three times counts once. Ties sort by login. Bots and you are left out. None: "No reviews yet" in secondary text. Clicking a reviewer does nothing.

### Right now

Two rows, drawn as full list rows (`PRRow`), from the PR rows already loaded for the lists (`BuiltTabs`: Review and Mine), so the list's Settings filters apply, but not Show Only repo or Show Only Updated. This card costs no queries and updates when the lists refresh.

- **Waiting on you longest:** of the rows counted in Needs your review, the one whose wait started earliest, by `ReviewWait.make(for:on: .review, …)`. The row shows that wait as the list does. None: "Nothing waits on your review".
- **Your PR waiting longest:** of your open, non-draft PRs with no submitted review by a person other than you, the one whose wait (`ReviewWait.make(for:on: .mine, …)`, "@georgi 2d" or "No reviewer 5d") started earliest. The no-review filter is this card's own; `ReviewWait` alone would also return re-requested PRs. None: "None of your PRs waits for a first review".
- A row whose wait has no known start (`ReviewWait.since` nil) is not chosen.
- ↑/↓ select between the two rows; click or ↩ opens the PR's detail, and Back from it returns to Stats. ⌘↩ opens it on GitHub and ⌘C copies its link, as in the list.
- A row's context menu has only the copy and open items: Copy Branch Name, Copy Checkout Command, Copy Link, Copy as Markdown Link, Open on GitHub, the files item and, on a PR whose checks failed, Open Failing Check. The list's repo focus, person search and Reviewers…/Assignees…/Labels… are left out, and the row anchors no edit picker: they act on the list hidden behind Stats.

### Issues

| Item | Value | Comparison |
|---|---|---|
| Closed | Issues assigned to you that closed in the period, completed or not planned | yes |
| Opened | Issues you opened in the period | yes |
| Comments | Comments you wrote in the conversation of issues and PRs in the period (not review comments on code) | no |

- "Assigned to you" is who is assigned now: an issue unassigned after it closed isn't counted. The manual says so.

### Caps

- Each capped source reads at most the newest 100 items in scope for the period (per source below; comments read up to 500). Reviews come from the 100 most recently updated PRs you reviewed since the period began; the comparison's search has no end, so it reaches into the current period and those PRs count toward its 100 too. When more exist, the item's hover ends with "From the latest 100 PRs" (comments: "From your latest 500 comments"), and the footer shows "· from latest 100" (only comments capped: "· from latest 500 comments"). When the PR sources and the comments are both capped, the footer shows only "· from latest 100", to keep it short; the comments item's own hover still says "From your latest 500 comments".
- A count that GitHub gives exactly (`issueCount`) is always exact; the cap only affects medians, bars, top reviewers and the counts that are tallied from loaded items (reviews, comments). A capped tally reads "N+", N being what was counted ("137+"), comparisons included ("last week 137+").

### Loading, errors, cache

- First load of a period (nothing cached for this account, scope and period): the cards' layout with the skeleton shimmer where values go, as the list's first load. The Right now card shows at once.
- Each period's result is cached in memory, per account, scope and period, for 15 minutes, and goes stale at local midnight however young it is. Opening Stats or switching to a period within that time shows the cached result with no request. After 15 minutes the cached result shows at once while a refresh runs, and values change in place. Switching to a period with nothing cached shows the skeleton.
- A result with any failed item is stale at once: the next open or period switch fetches again.
- Refresh (button or ⌘R) ignores the cache.
- A fetch that is stopped (Back, a period switch while it runs, a sign-out) caches nothing and leaves no spinner behind.
- Memory only: a relaunch starts empty. An account's entries are dropped when it signs out or its session is revoked.
- An error (offline, rate limited, a query refused) keeps whatever is on screen and shows a line under the chips in the style of the search's failure banner, "Couldn't load stats: <reason>" (the reason worded as the lists' error; with several failures, the first), with a Retry button that refreshes. Values with nothing behind them show "–".
- A query that fails takes out only the items it feeds; the others show.
- Rate limited: the line says when it resets, as the lists do; no automatic retry before then.
- No polling: it loads on open (when stale), on period switch (when stale), on refresh, and on account or scope change.

### Accessibility

- Each card is a VoiceOver group: "Your reviews, this week: 12 reviews, last week 9. Median turnaround 3 hours 10 minutes, last week 5 hours." The other cards read the same way: "Your pull requests, this week: 6 merged, last week 4. Median time to merge …. Median first review …. Top reviewers: dana 3, lee 2." and "Issues, this week: 3 closed …. 5 opened …. 12 comments." For 90 days the period reads "the last 90 days". A figure that is unknown reads "not available"; a card with no report reads "<title>, loading" or "<title>, not available".
- A card's figures that have a hover give VoiceOver the same text as the card's hint, the hovers' sentences joined by ". " (a sentence that ends with its own full stop is followed by a space only), and a sentence two hovers share, such as the cap note, said once; a card with none has no hint.
- The bar chart is one element labelled with its summary.
- Values use monospaced digits so they don't jitter on refresh.

## Data

When a period loads, all its queries run in parallel, for the period and its comparison. The scope's search qualifier is `FetchScope.searchQualifier` (`org:acme` or `user:login`); searches add `archived:false`, as the lists do. In the personal scope limited to an installation's repositories, items outside them are dropped (`FetchScope.covers`). Dates go to GitHub as ISO 8601 UTC.

### Reviews: search

Search for the PRs you reviewed, and read your reviews on each:

```graphql
query($q: String!, $login: String!, $after: String) {
  search(query: $q, type: ISSUE, first: 100, after: $after) {
    issueCount
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest {
      updatedAt
      author { login }
      repository { nameWithOwner }
      timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 20) {
        nodes { ... on ReviewRequestedEvent { createdAt
          requestedReviewer { __typename ... on User { login } ... on Team { slug } } } }
      }
      reviews(author: $login, last: 50) { nodes { submittedAt state } }
    } }
  }
}
```

`$q` is `StatsQueries.reviewedPRs(window:scope:)`:

```
is:pr reviewed-by:@me -author:@me updated:>=<from> archived:false sort:updated-desc <scope>
```

- Search can't filter by when a review was made, but a review updates its PR, so `updated:>=<from>` finds every PR with a review in the window, and some with reviews only before it. The reviews themselves come from each PR's `reviews(author:)`, `last: 50` so the newest are there; those with `submittedAt` in the window and state not `PENDING` are the period's reviews.
- The window's end has no bound: a later update doesn't hide an earlier review, so a PR reviewed last week and updated today is still found for last week.
- `updated:>=` takes the full timestamp (`2026-10-28T22:00:00Z`), checked live to the second.
- `-author:@me` leaves out your own PRs; a node whose PR you authored is still dropped when tallying.
- Nodes come most recently updated first; a null node (an item GitHub hides) is skipped. `updatedAt` is kept on each PR to date what was loaded when the cap cut in (Your reviews, above).
- Cap: up to 100 in-scope PRs. An org reads 1 page. In the personal scope, PRs outside the scope are dropped and the next page is read, up to 3 pages. The cap cut in when the search has more pages after the last one read.
- The count of reviews, the bars and the turnaround are tallied from these.
- Cost: 2 points per page (measured with `gh`).

### Your merged PRs

Search, `first: 100`, nodes `createdAt mergedAt`:

```
is:pr author:@me is:merged merged:<from>..<to> archived:false sort:created-desc <scope>
```

Merged = `issueCount`. Time to merge = median over the nodes. Over 100: the 100 most recently opened, with the cap note (search can't sort by merge time). 1 point.

### Your opened PRs

Search, `first: 100`, `is:pr author:@me created:<from>..<to> archived:false sort:created-desc <scope>`, nodes:

```graphql
createdAt isDraft state
readyEvent: timelineItems(itemTypes: [READY_FOR_REVIEW_EVENT], last: 1) { nodes { ... on ReadyForReviewEvent { createdAt } } }
reviews(first: 50) { nodes { submittedAt state author { __typename login avatarUrl } } }
```

First review and top reviewers read these; over 100, the newest 100 with the cap note. 2 points.

### Issues closed and opened

`issueCount` only (`first: 0`), 1 point each:

```
is:issue assignee:@me closed:<from>..<to> archived:false <scope>
is:issue author:@me created:<from>..<to> archived:false <scope>
```

### Comments

```graphql
viewer { issueComments(last: 100, before: $before) {
  pageInfo { hasPreviousPage startCursor }
  nodes { createdAt repository { nameWithOwner } } } }
```

Pages backwards (newest first) until a page reaches before the period's start, up to 5 pages; counts those in the period and in scope. Still more in the period after 5 pages: the count reads "N+" with the cap note. Fetched for the period only, as there is no comparison. 1 point per page.

### Totals

Per load of one period: reviewed ×2 (2 points a page), merged ×2 (1), opened ×2 (2), issues closed ×2 (1), issues opened ×2 (1), comments ×1 (1 a page). In an org, about 15 points and 11 requests; at most about 30 in the personal scope with every extra page. A cold look at all three periods stays under 100; with the cache, an hour of ordinary use under 150 of the 5,000.

The GitHub App's user token wasn't tried; every query here was run with a `gh` token. An App sign-in check belongs to the PR's verification. If GitHub refuses a query to the App, the items it feeds show "–" by the error rule.

### Not used

- `contributionsCollection.pullRequestReviewContributions`: see Decisions.
- `PROJECT_V2_ITEM_STATUS_CHANGED_EVENT`: see Decisions.

## Rule location

- PullBullKit `Stats/`, the pure parts, unit-tested on their own: the period windows and wording, durations, medians, review samples and turnaround, first-review waits, top reviewers, daily bars, the Right now pick, the per-period result with its per-item values, failures and cap flags, and the cache's freshness.
- `GitHubAPI` gains the stats fetch and its decoding, tested against fixtures shaped like the spike's answers.
- App: a `.stats` route shown as a pushed layer, the Stats view (the cards draw what the kit returns), the gear menu entry and ⌘3.

## Docs

- README Keys/lists: ⌘3 Stats.
- `docs/manual.md`: a short Stats section (what each number means, the periods, the cap note, assigned-now for Closed, where the data comes from), and ⌘3 in the Keyboard section.
- `ShortcutCatalog`: "Stats ⌘3" in the Lists section after Issues ⌘2; the Refresh row notes "On Stats, refreshes the stats".
- Screenshots: not part of this change.

## Decisions

- **Only GitHub's data, no counters of PullBull actions, no "time saved".** The owner picked the GitHub-derived stats; a minutes figure needs an invented multiplier.
- **Layout is the mockup's Main**, not the denser label/value variant: big numbers and a readable bar chart, opened now and then rather than hourly. The cards scroll when they don't fit.
- **"last week 5 h", not "was 5 h".** The owner's wording; each period names its own comparison ("last month", "previous 90 days").
- **Periods are trailing windows of whole local days**, not calendar weeks and months (the owner's choice, so early in a month the chart isn't nearly empty). Whole days, not 7×24 hours, so each bar is a full day and the bars add up to the count.
- **Daily bars for every period**, 90 thin bars for 90 days. Weekly buckets can't divide 90 days evenly, and a partial bucket reads as a slow week.
- **System accent colour.** The app follows the system accent; the mockup's first green was a wrong guess.
- **Gear menu item with ⌘3, from the list and search only.** ⌘1 and ⌘2 are the modes and ⌘3 was free; Stats isn't an hourly check, so it gets no footer button. Opening it over a detail or Ask would stack screens the routing doesn't have.
- **← moves the period chips on Stats, not Back**, as it moves the list's chips; Esc, ⌘[ and the chevron go back.
- **Current account and scope only.** Switching account switches the stats, as the lists do.
- **Latest 100, cached 15 minutes, with a visible cap note.** The owner's choice of cost cap; the cap is said, not silently trimmed. A result with a failed item isn't cached as fresh.
- **A capped tally reads "N+" with what was counted**, not a flat "100+": 100 PRs can hold 137 reviews, and "100+" would understate what is known.
- **"Still waiting" counts only open PRs.** Found in plan review: the opened-PRs search includes closed and merged ones, and a PR closed without a review isn't waiting.
- **Right now follows the list's Settings filters**, so a row hidden from the list (an old or draft PR) doesn't come back on Stats.
- **The PRs you reviewed come from search, and the reviews from each PR's own reviews.** `viewer.contributionsCollection.pullRequestReviewContributions` returned zero, with no error and no restricted contributions, for an account that had 107 reviews that week on 79 PRs in its org, with or without `organizationID` and from both its tokens, so it can't be trusted. Its totals were wrong besides: one contribution per PR (78 against 104 real reviews for one public user), reviews on your own PRs included. Search with `reviewed-by:@me` can't filter by when a review was made, but `updated:>=` the window's start gives a superset that `submittedAt` then filters; each PR's `reviews(author:, last: 50)` gives the reviews. Search needs no org node ID, so there is no `organizationID` lookup.
- **Turnaround only for reviews you were asked for, and only the first after each request.** A review nobody asked for, or a second review on the same request, isn't a response time; counting them would pull the median toward zero.
- **First review starts when the PR was last marked ready, as `ReviewWait` does, and a review during the draft isn't a sample.** Counting it as 0 would pull the median toward zero.
- **Your merged and opened PR searches sort by created date; the reviewed search sorts by updated date.** Without `sort:`, a capped page is in no useful order; GitHub can't sort by merge time, so a capped merged median is over the most recently opened. Updated order is what lets a capped reviewed result say which days are fully loaded.
- **Opened issues come from search, not contributions**: exact, scoped, 1 point, and the same in both scopes.
- **Top reviewers count PRs, not reviews**, so a long back-and-forth on one PR doesn't outrank someone who reviewed five.
- **Board Status moves dropped from the Issues card.** The mockup had them. GitHub records them only on each issue's timeline (`ProjectV2ItemStatusChangedEvent`), so a count needs every issue you might have moved; any query that finds them (issues involving you) misses moves on other people's cards. Missing beats wrong. **Opened** takes its place.
- **Comments are conversation comments, paged back through `viewer.issueComments`.** GitHub has no per-period count, and review comments on code belong to reviews, already counted. The newest 100 alone would undercount an org when the viewer comments elsewhere, so it pages until the period is covered, up to 5 pages.
- **Issues closed means issues assigned to you now that closed**, whoever closed them: search can't find who closed an issue.
- **Right now reuses the loaded lists and `ReviewWait`**, so the rows match the list and cost nothing; its rows open the detail like list rows.
- **No polling.** Stats changes slowly; it loads when opened (if stale) and on demand.
- **Stats keys go only to Stats.** The list stays mounted behind the screen; a key that reached it would edit a search, open a picker or undo an edit the user can't see. ⌘Z is swallowed for the same reason.
- **An issue notification opened over Stats returns to the list.** An issue detail has no Stats return path, and adding one would be new routing for a rare case. A PR detail opened from Stats returns to Stats.
- **A stopped fetch caches nothing.** Back, a period switch mid-fetch or a sign-out ends the fetch; storing its answer could show another account's or period's figures. ⌘R and Retry don't restart a fetch that is running.
- **The footer says "· from latest 100" when both kinds of cap cut in.** One note keeps the footer on one line; the comments item's hover keeps its own wording.
- **Zero-review days are tertiary-colour stubs, and a day with reviews is at least 2 pt.** An empty day must not read as a short bar.
- **Hovering the chart shows each day live, in the count's place, instead of a whole-chart tooltip.** A tooltip waits before it shows and says only the total and the busiest day; the live label answers "how many on Thursday?" as the pointer moves. It takes the busiest count's row, so the chart's height doesn't change.
- **Hover strips run gap-middle to gap-middle, full height.** Hitting only the bars would make a 1-pt stub, and a day not loaded, nearly impossible to point at.
- **VoiceOver keeps the summary.** It can't hover, and the chart stays one element, as before.
- **Right now has no card box.** Its rows draw their own hover and selection fill.
- **A capped chart summary reads "N+", and "Days before … not loaded" is its own sentence.** The total is what was counted, as on the Reviews figure; a bare "12 reviews" over a capped chart would read as exact.
- **Every hover joins the cap sentence with ". "**, as the First review hover does, so "From the latest 100 PRs" never runs on from the sentence before it.
- **No hover when there is nothing to take a median of.** "Median of 0 merged PRs" says nothing the "–" doesn't; the turnaround keeps its "No reviews you were asked for in this period", which says why.
- **Capped with nothing loaded draws no bars.** No loaded PR has a review in the period, so no day can be vouched for; drawing seven zero stubs would be a wrong zero.
- **The cache goes stale at local midnight.** The periods are whole local days, so a report from before midnight covers a different span; showing it for up to 15 more minutes would put yesterday's bars under today's.
- **A Right now row's menu only copies and opens.** The list's repo focus, person search and edit pickers would change the list hidden behind Stats, which Stats keys already never reach.
- **VoiceOver hears the hovers as the card's hint.** VoiceOver can't hover, and the hovers carry the sample sizes and cap notes; the hint keeps them out of the card's sentence, read after it.
- **A narrow comparison breaks after the period's name, not wherever it wraps.** "previous 90 days 0" wrapped as "previous 90 days" over a lone "0" in one column and differently in the next; the two-line form keeps the copy and makes the break deliberate.
