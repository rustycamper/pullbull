# One pull request list, in sections

The Review, Mine and Team tabs become one list in sections, with scope chips above it. The Pull Requests / Issues switch moves into the search row, which removes the header row the tabs used to share. Review reasons get short labels.

Mockups: https://claude.ai/artifact/EpgpsFBW6hyLMHocJFmdBC (2a is the chosen header, 2 the chosen list).

## Why

- Answering "what needs me right now?" takes two to four clicks today. The popover reopens on the last tab, Review and Mine are separate tabs, and a failing PR of mine is invisible from Review: Mine's count doesn't say whether something is wrong.
- The tabs look like separate lists but act like filters. Each one is its own GitHub search, but per tab they only hold a count, a sort and a remembered selection. Notifications and the badge are configured elsewhere.
- The layers overlap:
  - A teammate's PR that requests my review is in both Review and Team.
  - The time focus resets when the tab changes, but the repo focus doesn't.
  - During a search the tab bar becomes a scope picker, so one control means two things.
- PullBull is open source, and its users work differently:
  - A solo maintainer lives in their own PRs.
  - A reviewer on a big team lives in Review.
  - An org lead watches Team.
  - Some users live in the Board.
  
  One fixed landing tab serves one of these. A list in sections puts each person's work near the top, and a chip gets them to their slice in one click.

## Goals

- Opening the popover shows what needs me, then my own PRs, with no click.
- Every slice the tabs gave (Review, Mine, Team) stays one click away, with its count visible.
- A PR appears once in the list.
- Each control has one meaning. The chips scope the list, and during a search the same chips scope the search.
- The Issues mode keeps working as it does today.
- The header row the tabs used to share is gone; that height goes to the list.

## Non-goals

- Changing what is fetched. `RefreshCoordinator` runs the same searches, and `TabBuilder`'s membership rules (`ReviewRules`, the Review filters, Team without my PRs) are unchanged.
- Changing the Issues tabs (Assigned, Created, Board) or the Board lanes.
- Reordering sections by drag, or presets such as Reviewer, Maintainer and Lead. These belong with the first-run walkthrough, which comes next as a separate task.
- New notifications, or changes to `BadgeSource`'s meaning.
- A user-defined section or query. Saved searches already cover that.

## Anti-goals

- A list that hides urgent things below the fold. "Needs your review" and the PRs I have to act on always come before anything I'm only waiting on.
- Losing a slice someone relied on. A Team-only or Mine-only view must stay one click away for anyone who used that tab.
- Settings sprawl. This adds one setting and no more.
- Moving rows under the pointer. Selection and keyboard navigation keep the selected row when sections fold or chips change, as sorting does today.

## The popover, top to bottom

```
┌────────────────────────────────────────┐
│ [⎇│◎•] 🔍 Search pull requests     ⌘F  │  mode switch + search field (one row)
│ (All) (Needs you 4) (Mine 4) (Team 12) │  scope chips (Issues mode: its tabs)
│ ▤ All repos ▾                ⇅ Updated │  filter bar, unchanged
│────────────────────────────────────────│
│ 🔔 Needs your review                 4 │
│ ⎇  Your PRs                          2 │
│ ◷  Waiting on others                 2 │
│ ›  Recently closed                   3 │  folded
│ ›  Team                             12 │  folded; org accounts only
└────────────────────────────────────────┘
```

### Header: the mode switch moves into the search row

- The title row goes. `ModeToggle` sits at the left of the search field in one row (mockup 2a).
- The toggle becomes a two-segment control on one shared track, as tall as the search field (24pt today), and the hairline divider goes. The free-standing chips and divider were there so it wouldn't read as part of the tab bar. With no tab bar beside it, a track groups the two icons and sets them apart from the field.
- These stay as they are:
  - the accent colour on the selected segment, and its Increase Contrast edge;
  - the news dot on the other mode (`ModeNews`);
  - the help text and VoiceOver labels ("Pull requests ⌘1", "Issues ⌘2", plus the news note);
  - ⌘1 / ⌘2.
- An unselected segment's hover takes `Palette.strongFill`. The track itself is `Palette.fill`, so the usual hover fill wouldn't show on it.
- The search field fills the rest of the row. Its placeholder still follows the mode.
- The save-search row (opened by the field's bookmark) opens directly under the search row and above the tabs, so it sits next to the bookmark that opened it.
- The empty-field hints and search results still open below the tabs, which stay visible and narrow a search.
- **Issues mode:** Assigned / Created / Board take the second row, where the PR chips sit, styled as today's tab bar. Their counts, stale-warning glyph and ←/→ behaviour don't change.

### Scope chips (Pull Requests mode)

- The chips are **All · Needs you · Mine · Team**, one selected at a time. Team shows only when Team is fetched, so not for an account with no org (today's `PRTab.shown` rule).
- Each count ignores the repo and time focus, as tab counts do today, and the VoiceOver label still says so.
  - **Needs you** counts the Review rows that count (`TabContents.count` for Review). Its number is in the accent colour when it's above zero.
  - **Mine** counts the rows of Your PRs plus Waiting on others.
  - **Team** counts Team rows after the de-duplication below.
  - **All** shows no count.
- Clicking the selected chip (other than All) goes back to All.
- ←/→ moves between the chips, as it moved between tabs.
- The popover opens on the scope Settings chooses (All by default). A chip picked while it's open lasts until the popover closes, and the reset to that scope happens as it closes, so the next open never shows the old chip for a frame. A reopen that was already on its opening scope keeps its scroll offset, as a reopen keeps its selection; only a reset from another chip scrolls the list to the top. A detail left open keeps its walk through the reset.
- When a settings change hides the Team chip (the account loses its org) while it is selected, the scope goes back to All.
- The opening rules (`AppSettings.scopeOnOpen`, over `OpenOn` and `prChips`):
  - A scope whose chip isn't shown opens on All. A saved Team choice or Last used + Team therefore opens on All without an org, and on Team again when the org comes back.
  - `lastScope` is recorded at every close and at a quit with the popover shown, whatever the open-on choice, so switching to Last used finds the chip last used. It records the chip actually used (All, Needs you or Mine), also on a personal account, because that is what "last used" means.
  - A change to the open-on choice while the popover is closed applies at once. The settings `didSet` reapplies the opening chip whenever `scopeOnOpen` changes, which also covers an org switched back. While the popover is shown the chip on screen stays.
  - Back from a detail, and the Esc hint, never name a chip that is no longer shown. Back goes to the chip the detail was opened from when that chip is still shown, else to All. The Esc hint is cleared unless it names the chip the list reopens on.
- One selection is shared by every chip. It stays selected through chip changes and folds; a fold that hides the selected row moves it to the next row shown, and a selection in another chip's row is left alone. A chip change with no selection shown opens the new chip at its top.
- A detail opened from the list names the chip it was opened on in its Back button ("All", "Needs you").
- What each scope shows:

| Scope | Sections shown |
|---|---|
| All | Needs your review, Your PRs, Waiting on others, Recently closed (folded), Team (folded) |
| Needs you | Needs your review |
| Mine | Your PRs, Waiting on others, Recently closed (folded) |
| Team | Team |

- In a single-section scope (Needs you, Team) the section header is hidden, the section never folds, and the list looks like today's tab.
- The chips show their counts as they stand; a pull request count is never stale outside a search, so the chips draw no stale-warning glyph.

### Sections

| Section | Rows | Row chips | Header glyph |
|---|---|---|---|
| Needs your review | Today's Review rows, including dimmed "You approved · not counted" rows when Hide approved is off | Review's (`RowChips` `.review`), Review's short wait | `bell`, accent colour |
| Your PRs | My open PRs that need me: ready to merge, changes requested, a failed check, conflicts, or a draft | Mine's | the pull request glyph |
| Waiting on others | My other open PRs: waiting on review or on checks still running | Mine's | `clock` |
| Recently closed | Today's Mine "Recently closed" | as today | fold chevron |
| Team | Today's Team rows minus any PR in Needs your review | Team's | fold chevron |

- **Your PRs and Waiting on others split Mine with no overlap.** A PR goes in Your PRs when any of these hold:
  - `ReviewRules.isReadyToMerge`;
  - a latest review requests changes;
  - its CI rollup (`PullRequest.ci`) is `.failure`;
  - `hasConflicts`;
  - it's a draft.

  Everything else goes in Waiting on others.
- **A cancelled run counts as a failure here.** GitHub's rollup reads a cancelled run as a failure (`CIState`, Models.swift:33-35), and the list has no per-check data, so a PR whose only problem is a cancelled run lands in Your PRs. Fetching per-check data for the list is out of scope. The row's CI glyph is unchanged.
- **De-duplication:** a PR in Needs your review is not repeated in Team, dimmed rows included. The badge already de-duplicates by `PRKey` (`BuiltTabs.badgeCount`); the list now does too. With Hide approved on, an approved PR isn't in Needs your review, so it stays in Team.
- **Empty sections hide themselves.** A section with only dimmed rows is not empty: it shows, with a count of zero. If Needs your review has no counted rows and Your PRs is empty in All, a one-line "Nothing needs you" sits at the top, and the sections that have rows follow, including any dimmed rows. If the whole list is empty, today's empty state applies (#42): on All it reads as Needs you's does ("Nothing needs your review"). On Mine with no open rows, the empty state sits above Recently closed.
- **Folding:** every header folds on click. Fold state is kept per section in a new settings map (for example `sectionFolds`), the same for every account. It is not per account: the sections are the same for everyone. The defaults:
  - open: Needs your review, Your PRs, Waiting on others;
  - folded: Recently closed and Team.
- **Recently closed's fold is part of the same map**, so it is kept across relaunches. It was session state on Mine before.
- **Single-section scopes** (Needs you, Team) show no header and never fold. Nothing shows folded while searching; the stored state returns when the search ends.
- **Hairlines:** an edge-to-edge hairline parts each section from the one above it, and Mine's Recently closed from the empty state above it. The first section has none.
- **Footer link:** All links to Mine's page on GitHub ("PRs on GitHub"), since the footer's pages are per fetched list.
- **Grouping:**
  - In All and Mine, rows aren't grouped by repository. Sections are the grouping, and each row names its repo (`repo #num`). This was the owner's ruling for Mine.
  - On Needs you and Team, today's grouping applies: by repository unless turned off or merged by a repo focus. Team groups by author when `groupTeamByAuthor` is on.

### Sorting

- Each scope has one sort, kept in `settings.sorts` under its key: `all` is new, while `review`, `mine` and `team` are today's keys and carry over unchanged.
- In All, the sort orders rows within each section, and the sections keep their fixed order.
- Search follows the sort of the chip its results are laid out for; Everywhere uses All's.
- The choices are today's PR choices: Recently updated · Waiting longest · Oldest first.

### Review reasons on rows

| Reason (`ReviewReason`) | Today | Now | Glyph | Full label (VoiceOver, tooltip) |
|---|---|---|---|---|
| `.requested` | no chip | **Req** | `bell` | "Review requested from you" |
| `.reRequested` | Re-requested | **Re-req** | `arrow.uturn.left` | "Review re-requested from you" |
| `.newCommitsSinceReview` | New commits | unchanged | `arrow.triangle.2.circlepath` | unchanged |
| `.teamRequested` | via @org/team | unchanged | `person.2` | unchanged |

- `RowChips.Info` gets a `requested` case. Like the other review reasons, it is gray glyph-and-text information, not a capsule. Only the section header's bell is in the accent colour, so a list of requests stays calm.

### Search

- While the field holds a query, the chip row becomes the scope picker: **Everywhere · Needs you · Mine · Team**. Each chip shows its match count, and Everywhere is the default. Everywhere shows the count of the results on screen; while the search is narrowed it shows none, because a narrowed search never asks GitHub, so there is no Everywhere count to give.
  - The narrowing is today's `SearchScope`, moved from the tab bar to the chips.
  - The Everywhere chip is new. Today `.everything` is the state where no tab is selected. Clicking a selected chip goes back to Everywhere, as clicking a selected tab clears the scope today.
- Results narrowed to a scope are matched locally, as now (`SearchNarrowing`).
- Results in Everywhere come from the snapshot and from GitHub, so many fit no section. They are laid out like this:
  - A result the list holds goes in its section.
  - A result I authored that the list doesn't hold goes in Your PRs or Waiting on others, by the same split rule.
  - Every other open result goes in a new **Other results** section, after Team. Its rows take Team's chips.
  - "Closed and merged" follows last, as now.
  - Folded sections open while a search is on, as `LaneFolds.shownFolded` opens lanes today, and fold back when the field clears.
- A search narrowed to a chip is laid out for that chip:
  - **Needs you** and **Team** take that list's layout, grouped as the list is, with Closed and merged after it.
  - **Mine** takes the sections: Your PRs and Waiting on others, then Closed and merged. Recently closed PRs that match are closed results, so they sit in Closed and merged.
  - Narrowing to **Team** searches the de-duplicated Team, so it leaves out what is in Needs you, as the chip's count does.
  - Each layout follows its own chip's sort, and Everywhere follows All's.
- A search kept open when the popover closes stays narrowed; the list under it resets to the opening scope. Its Esc hint stops naming a chip it started on ("Started typing on …") unless that is the chip the list reopens on, because returning there is no longer what Esc does.
- In Issues mode, search scoping stays on the Issues tabs, as today.

### Settings (Settings → General)

- **Pull requests open on:** All (the default) · Last used · Needs you · Mine · Team. Team is offered only for an account with an org, or while it is the saved choice.
  - The chosen scope applies every time the popover opens, not only at launch. A chip picked while it's open lasts until it closes. The goal is that each open lands on what needs me with no click.
  - With Last used, the scope at close is restored on the next open and across launches.
  - Someone who wants an inbox-first popover picks Needs you and can fold Your PRs.
- **There is no setting to turn the chips off.** One shipped in #49 (mockup variant 4: the list always All, no chip row) and was removed before release (owner). With chips on, All already gives the no-chips experience to anyone who never clicks a chip; the toggle bought one row of height for a disabled picker, its own Last used, search and Back rules, and in Issues mode it would have hidden the Board, the only way to the lanes.
- **Badge** (`BadgeSource`): the values and their meaning don't change. `.mine` still counts all my open PRs (Your PRs plus Waiting on others), so it's labelled after the Mine chip, not the narrower Your PRs section. The picker's note says the badge uses the same filters as the lists it counts, and the status tooltip's text is unchanged:
  - Needs your review
  - Mine
  - Needs your review + mine
  - All

### Settings migration

- `AppSettings.lastTab`, its coding and `reconcileTab()` are gone. An old `lastTab` key is ignored, so every existing user opens on All and the change is visible at first launch.
- The new keys are `openOn` and `lastScope`. `AppSettings` decodes each field on its own, so an unreadable value takes its default and leaves the others alone. `lastScope` is stored state, not a setting, and has no row.
- `sorts["review"/"mine"/"team"]` keep working as scope sorts, and `sorts["all"]` starts at Recently updated.
- `groupTeamByAuthor`, the hide filters, the badge and notification settings don't change.

## What stays the same

- Fetching, polling and CI follow (`RefreshCoordinator`, `CIFollow`), and the `Snapshot`.
- `ReviewRules`, `ReviewFilters`, `ReviewWait`, and notifications.
- The filter bar: repo focus, time focus and the sort button. The time focus now persists across chip changes, like the repo focus does; it used to reset on every tab switch, and there are no tab switches left.
- The Issues mode, apart from its tabs moving into the second row.
- The footer and the gear menu (#41).

## Left to the builder

These were settled while building:

- **Type names.** `PRTab` (review, mine, team) stays as the internal name for the three fetched lists and their row rules (`RowChips`, `ReviewWait`, `TabBuilder.row`, `SearchScope.pullRequests`, `RowContext`). New types:
  - `PRScope` (`all`, `review`, `mine`, `team`) is the chip. Its raw values are the `settings.sorts` keys.
  - `PRSection` names a section, and `ListSection` holds a section's rows.
  - `PRList` is the sections a scope shows, and `ScopedPRList` the same narrowed to the focus.
  - `SectionFolds` is the fold map, `settings.sectionFolds`.
  - `SearchSectionLayout` lays out sectioned search results.
  - `OpenOn` is the open-on choice (`openOn`), `prChips` the chips shown, `prSearchTabs` the tabs a search can narrow to, and `scopeOnOpen` the scope the list opens on.
- **`BuiltTabs.review`, `.mine` and `.team` don't change.** The badge, `ModeNews`, notifications, the repo menu and `reviewCleared` keep reading them. The de-duplication and the Mine split are derived (`teamSection`, `yourPRs`, `waitingOnOthers`), and only the list, the chip counts and search narrowing read them.
- **Sizes.** Chips are 22pt tall and sit in the row the tabs used to; Issues mode keeps `TabBar` there. A section header is 28pt, like every list header.
- **Reasoning on the open calls above.**
  - Mine has no repo grouping by the owner's ruling: its sections are the grouping, as in All, and rows name their repo. This replaces the draft's "a single-scope chip keeps today's grouping".
  - A narrowed search never asks GitHub, which is why Everywhere's count has nothing to show.
  - The reset to the opening scope happens when the popover closes, not when it opens, so the old chip is never on screen.
  - A scope reset scrolls to the top because a reopen mid-list would hide Needs your review; a reopen already on the opening scope keeps its offset, matching the rule that reopening restores selection and scroll.
  - `searchStartedOnTab` is cleared, not set to All, because "Started typing on All" would be false.
  - A cancelled-only run lands in Your PRs because the list sees only GitHub's rollup.

## Delivery

Four PRs, each shippable alone:

1. **Review-reason labels:** Req and Re-req, and the new `RowChips.Info.requested`.
2. **The mode switch in the search row**, with the Issues tabs moving to the second row. The PR tabs move with them, still as tabs, until step 3.
3. **The sectioned list and scope chips:** sections, de-duplication, chips, search scoping, ←/→, sorts and fold state.
4. **The open-on setting and the badge labels.**

The README (Tabs section, table rows and screenshots in `docs/media`) and `docs/manual.md` change with step 3. The list-sort and PR/issue parity specs name tabs; update them where they describe tabs, in the step 3 PR.

## Testing

- **`TabBuilder` (or what replaces it):**
  - Section membership, including the Your PRs / Waiting on others split for each state: ready to merge, changes requested, CI failure, conflicts, draft, waiting on review, checks running.
  - The Review/Team de-duplication, including dimmed rows.
  - Empty sections, a section with only dimmed rows, and the "Nothing needs you" case.
- **Search layout:** an Everywhere result in each section, my own PR from GitHub split by the rule, Other results, and folded sections opening during a search.
- **Chip counts:** focus doesn't change them, and Mine is the sum of its two sections.
- **`RowChips`:** Req and Re-req text and labels, and that no chip shows for a dimmed row.
- **Settings decoding:** an old file with `lastTab` loads and opens on All; old sort keys carry over; the open-on setting and `lastScope` round-trip; a saved `scopeChips` is ignored and not written back.
- **`ListNavigation`:** keyboard order across sections, and skipping folded ones.
- **`SearchScope`:** scope picking with chips, and Team hidden without an org.
- **In the app**, with an org account and with a personal one:
  - landing state;
  - each chip;
  - folding;
  - search scoping;
  - the mode switch and ⌘1 / ⌘2, including the news dot;
  - Issues mode;
  - light and dark, Increase Contrast, and VoiceOver on the chips and the mode switch.

## Calls made in writing this

These were my decisions, not the owner's. They are worth checking:

- **Mine splits** into Your PRs and Waiting on others, with no overlap, on the rule above.
- **Rows aren't grouped by repository in All or Mine**; the repo name moves onto the row.
- **One sort per scope**, applied within sections in All.
- **Req stays gray**, like the other reasons. Only the header bell uses the accent colour.
- **The mode switch gets a shared track**, replacing the free-standing chips and divider.
- **The Issues tabs move to the chip row**, so both modes have the same two-row header.
- **Every existing user opens on All**, not on their last tab, so the change is visible.
- **One setting ships** (open-on). Section reordering and presets wait for the walkthrough task.
- **The time focus persists** across chip changes.
- **Delivery is in four PRs.**
- **A cancelled-only PR lands in Your PRs**, because the list sees only GitHub's rollup.
- **Dimmed approved rows stay in Needs your review** and leave Team. A section of only dimmed rows still shows.
- **Fold state is one map for all accounts.**
- **Everywhere search adds an Other results section**, and folded sections open during a search.
- **The badge's `.mine` option is labelled Mine**, not Your PRs.
- **Last used records the chip actually used**, also on a personal account.
- **No chips on/off setting**: added in #49, removed before release (owner).
- **The tooltip's text is unchanged**, and the badge picker's note says "lists" (owner).
- **The mode switch matches the field's 24pt height**; the mockup's 28pt was a guess.
