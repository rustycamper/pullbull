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

- The gear menu (footer gear, and the menu bar item's right-click) gets a **Stats** item with ⌘3, after Keyboard Shortcuts. ⌘3 also opens Stats from the list and from search, by key position as well as character, as ⌘1 and ⌘2 do.
- Stats opens only from the list or the search. On any other screen (a detail, Ask, Stats itself) or with a picker open, the menu item is disabled and ⌘3 does nothing. It is disabled, and ⌘3 does nothing, while no account is signed in or the account's scope hasn't loaded.
- It is a pushed screen like a detail: it slides in from the trailing edge over the list (a fade with Reduce Motion), with a back chevron in the header. Esc, ⌘[ or the chevron return to where it was opened from: the list, or the search with its query kept. ← does not go back on Stats; it moves the period chips (below).
- ⌘1 and ⌘2 do nothing on Stats, as on a detail.
- The popover closed while Stats is on screen reopens on Stats under the rule a detail follows (`PopoverReopen`); otherwise on the list.
- When the account or org changes (Settings, or the menu bar's account menu), Stats reloads for the new one if it is on screen.

### Layout (top to bottom)

1. **Header:** back chevron, the title "Stats" centred, a refresh button on the right. ⌘R on Stats refreshes the stats, not the lists.
2. **Period chips:** This week · This month · 90 days, styled as the scope chips. ← and → move between them (no wrap). The choice is one app setting, kept across opens and relaunches. Default: This week.
3. **Error line**, only when there is an error (below).
4. **Your reviews** card.
5. **Your pull requests** card.
6. **Right now** card.
7. **Issues** card.
8. **Footer:** "From GitHub, for `<login>` in `<org>`" (personal scope: "in your repositories"), plus "· from latest 100" when any cap cut in (below). Hover on the footer: "Updated 4 minutes ago. Only repositories PullBull can see."

Header, chips and footer stay put; the cards scroll between them when they don't fit.

### Periods

- A period is whole local calendar days ending with today: This week = today and the 6 days before, This month = today and the 29 before, 90 days = today and the 89 before. It starts at local midnight of its first day and ends now.
- The comparison period is the same number of whole days just before it, ending at the period's start.
- Both are half-open: a moment exactly at the period's start belongs to the period, not the comparison. Queries ask GitHub for `[start, end − 1 s]`, since GitHub's ranges include both ends.
- Comparison wording, in secondary text after the value: "last week 5 h", "last month 31", "previous 90 days 2 d 4 h".
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
- Bars: today's in the accent colour, the others in the secondary colour; a day with none draws a 1-pt stub on the baseline. No axis. Hover on the chart: "12 reviews in the last 7 days, most on Tuesday (4)"; for 90 days the busiest day reads with its date ("most on 14 Oct (6)").
- When the cap cut in (below), days before the oldest loaded review are not drawn at all, not as stubs, and the hover adds "Days before 3 Oct not loaded".
- Turnaround, for each review R of yours in the period:
  - the request is the latest `ReviewRequestedEvent` on that PR made at or before R, naming you or one of your teams;
  - R is your response only if you submitted no other review on that PR between the request and R;
  - turnaround = R − the request.
  - A review with no such request (you reviewed unasked, or a follow-up) is not a sample. Neither is one whose request is older than the 20 request events loaded per PR.
- Turnaround hover: "Median of 9 reviews you were asked for"; none: "No reviews you were asked for in this period".

### Your pull requests

| Item | Value | Comparison |
|---|---|---|
| Merged | Your PRs merged in the period | yes |
| Time to merge | Median of merged − opened over those PRs | yes |
| First review | Median wait for a first review, over your PRs opened in the period (below) | yes |
| Top reviewers | Up to 3 people, avatar + login + count, who reviewed the most of your PRs opened in the period | no |

- First review, for each of your PRs opened in the period:
  - the clock starts when it was last marked ready for review (its latest `ReadyForReviewEvent`), else when it was opened; the same start `ReviewWait` uses;
  - the first review is the earliest submitted review by a person other than you (a bot's review doesn't count, as in `ReviewWait`);
  - wait = first review − start.
  - Not samples: a PR still a draft, one not yet reviewed, one first reviewed before its start (reviewed while a draft).
  - Hover: "Median of 6 PRs. 2 of your PRs opened in this period still wait for a first review." (the second sentence only when there are some).
- Top reviewers count PRs, not reviews: someone who reviewed one PR three times counts once. Ties sort by login. Bots and you are left out. None: "No reviews yet" in secondary text. Clicking a reviewer does nothing.

### Right now

Two rows, drawn as full list rows (`PRRow`), from the PR rows already loaded for the All list, without Show Only repo or Show Only Updated. This card costs no queries and updates when the lists refresh.

- **Waiting on you longest:** of the rows counted in Needs your review, the one whose wait started earliest, by `ReviewWait.make(for:on: .review, …)`. The row shows that wait as the list does. None: "Nothing waits on your review".
- **Your PR waiting longest:** of your open, non-draft PRs with no submitted review by a person other than you, the one whose wait (`ReviewWait.make(for:on: .mine, …)`, "@georgi 2d" or "No reviewer 5d") started earliest. The no-review filter is this card's own; `ReviewWait` alone would also return re-requested PRs. None: "None of your PRs waits for a first review".
- A row whose wait has no known start (`ReviewWait.since` nil) is not chosen.
- ↑/↓ select between the two rows; click or ↩ opens the PR's detail, and Back from it returns to Stats. ⌘↩ opens it on GitHub and ⌘C copies its link, as in the list.

### Issues

| Item | Value | Comparison |
|---|---|---|
| Closed | Issues assigned to you that closed in the period, completed or not planned | yes |
| Opened | Issues you opened in the period | yes |
| Comments | Comments you wrote in the conversation of issues and PRs in the period (not review comments on code) | no |

- "Assigned to you" is who is assigned now: an issue unassigned after it closed isn't counted. The manual says so.

### Caps

- Each capped source reads at most the newest 100 items in scope for the period (per source below). When more exist, the item's hover ends with "From the latest 100", and the footer shows "· from latest 100".
- A count that GitHub gives exactly (`issueCount`) is always exact; the cap only affects medians, bars, top reviewers and the counts that are tallied from loaded items (reviews, comments). A capped tally reads "100+".

### Loading, errors, cache

- First load of a period (nothing cached for this account, scope and period): the cards' layout with the skeleton shimmer where values go, as the list's first load. The Right now card shows at once.
- Each period's result is cached in memory, per account, scope and period, for 15 minutes. Opening Stats or switching to a period within that time shows the cached result with no request. After 15 minutes the cached result shows at once while a refresh runs, and values change in place.
- A result with any failed item is stale at once: the next open or period switch fetches again.
- Refresh (button or ⌘R) ignores the cache.
- Memory only: a relaunch starts empty. An account's entries are dropped when it signs out.
- An error (offline, rate limited, a query refused) keeps whatever is on screen and shows the app's error line under the chips, "Couldn't load stats: <reason>", with Retry. Values with nothing behind them show "–".
- A query that fails takes out only the items it feeds; the others show.
- Rate limited: the line says when it resets, as the lists do; no automatic retry before then.
- No polling: it loads on open (when stale), on period switch (when stale), on refresh, and on account or scope change.

### Accessibility

- Each card is a VoiceOver group: "Your reviews, this week: 12 reviews, last week 9. Median turnaround 3 hours 10 minutes, last week 5 hours."
- The bar chart is one element labelled with its hover wording.
- Values use monospaced digits so they don't jitter on refresh.

## Data

When a period loads, all its queries run in parallel, for the period and its comparison. The scope's search qualifier is `FetchScope.searchQualifier` (`org:acme` or `user:login`); searches add `archived:false`, as the lists do. In the personal scope limited to an installation's repositories, items outside them are dropped (`FetchScope.covers`). Dates go to GitHub as ISO 8601 UTC.

### Reviews: contributions

```graphql
query($from: DateTime!, $to: DateTime!, $org: ID, $login: String!, $after: String) {
  viewer {
    contributionsCollection(organizationID: $org, from: $from, to: $to) {
      pullRequestReviewContributions(first: 100, after: $after, orderBy: {direction: DESC}) {
        pageInfo { hasNextPage endCursor }
        nodes {
          pullRequest {
            author { login }
            repository { nameWithOwner }
            timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 20) {
              nodes { ... on ReviewRequestedEvent { createdAt
                requestedReviewer { __typename ... on User { login } ... on Team { slug } } } }
            }
            reviews(author: $login, last: 50) { nodes { submittedAt state } }
          }
        }
      }
    }
  }
}
```

- GitHub returns one contribution per PR reviewed (its latest review), so the nodes are PRs, newest first. The reviews themselves come from each PR's `reviews(author:)`, `last: 50` so the newest are there; those with `submittedAt` in the window and state not `PENDING` are the period's reviews. Nodes whose PR you authored are dropped.
- `$org` is the org's node ID, fetched once per org (`organization(login:) { id }`) and kept with the account's stats state; null in the personal scope.
- Cap: up to 100 in-scope PRs. In the personal scope, nodes outside the scope are dropped and the next page is read, up to 3 pages. The cap cut in when GitHub has more pages after the last one read.
- The count of reviews, the bars and the turnaround are tallied from these. The total fields (`totalPullRequestReviewContributions`) aren't used: they count PRs, and include your own.
- Repositories the token can't see come back as restricted contributions with no detail and aren't counted.
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
createdAt isDraft
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

Per load of one period: contributions ×2 (2 points a page), merged ×2 (1), opened ×2 (2), issues closed ×2 (1), issues opened ×2 (1), comments ×1 (1 a page). In an org, about 15 points and 11 requests; at most about 30 in the personal scope with every extra page. A cold look at all three periods stays under 100; with the cache, an hour of ordinary use under 150 of the 5,000.

The GitHub App's user token wasn't tried; every query here was run with a `gh` token. An App sign-in check belongs to the PR's verification. If GitHub refuses a query to the App, the items it feeds show "–" by the error rule.

### Not used

- `search` with `reviewed-by:@me`: it can't filter by when the review was made.
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
- **Reviews are counted from each PR's own reviews, not GitHub's contribution totals.** Found in spec review, checked on public accounts: `pullRequestReviewContributions` gives one contribution per PR (78 against 104 real reviews for one user), and it includes reviews on your own PRs. The contributions query is still the source of which PRs you reviewed in the window, with `organizationID` and dates; each PR's `reviews(author:, last: 50)` gives the reviews.
- **Turnaround only for reviews you were asked for, and only the first after each request.** A review nobody asked for, or a second review on the same request, isn't a response time; counting them would pull the median toward zero.
- **First review starts when the PR was last marked ready, as `ReviewWait` does, and a review during the draft isn't a sample.** Counting it as 0 would pull the median toward zero.
- **Searches sort by created date.** Without `sort:`, a capped page is in no useful order; GitHub can't sort by merge time, so a capped merged median is over the most recently opened.
- **Opened issues come from search, not contributions**: exact, scoped, 1 point, and the same in both scopes.
- **Top reviewers count PRs, not reviews**, so a long back-and-forth on one PR doesn't outrank someone who reviewed five.
- **Board Status moves dropped from the Issues card.** The mockup had them. GitHub records them only on each issue's timeline (`ProjectV2ItemStatusChangedEvent`), so a count needs every issue you might have moved; any query that finds them (issues involving you) misses moves on other people's cards. Missing beats wrong. **Opened** takes its place.
- **Comments are conversation comments, paged back through `viewer.issueComments`.** GitHub has no per-period count, and review comments on code belong to reviews, already counted. The newest 100 alone would undercount an org when the viewer comments elsewhere, so it pages until the period is covered, up to 5 pages.
- **Issues closed means issues assigned to you now that closed**, whoever closed them: search can't find who closed an issue.
- **Right now reuses the loaded lists and `ReviewWait`**, so the rows match the list and cost nothing; its rows open the detail like list rows.
- **No polling.** Stats changes slowly; it loads when opened (if stale) and on demand.
