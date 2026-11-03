# One issue list, in sections

Issues mode gets the layout Pull Requests mode got in #44–#49: scope chips in the second row instead of the Assigned / Created / Board tab bar, and an **All** scope that shows my issues in sections. Issue #50.

Builds on `2026-11-03-sectioned-pr-list-design.md`. Where this document is silent, the PR rules apply as written there (chip behaviour, selection, folding, search narrowing, the open-on lifecycle).

## Why

- The two modes now draw the same row differently. Pull Requests shows capsule chips; Issues shows a segmented tab bar in the same place, so switching mode changes the control's look and meaning.
- The Issues tabs have the problem the PR tabs had: they look like separate lists but act like filters, and an issue I opened and assigned to myself is in both Assigned and Created.
- PullBull is open source, and people use Issues differently:
  - A solo maintainer is often both author and assignee, so Assigned and Created overlap heavily.
  - A team member lives in Assigned, grouped by board Status.
  - A lead or PM lives in the Board.
  - A drive-by contributor mostly tracks issues they opened and waits on others.

  A sectioned All puts each person's own work on one screen; a chip gets each of them to their slice in one click.

## Goals

- The two modes share one header: mode switch + search, then chips, then the filter bar.
- Opening Issues shows what is assigned to me, then what I opened, with no click.
- Assigned, Created and Board each stay one click away, with their counts and stale warnings.
- An issue appears once in All.
- The Board keeps its lanes, its 14-day Done group, its lane folds and its board menu.

## Non-goals

- Changing what is fetched (`RefreshCoordinator`) or the issue row rules (`IssueRowRules`).
- Changing the Board's lanes, Done window, Status editing or the board picker.
- New notifications, or a change to `countAssignedIssues`.
- Section reordering or presets. They wait for the first-run walkthrough, as on the PR side.

## Anti-goals

- Losing the Board as a destination. Board users must still reach the lanes in one click, and be able to land there.
- Nested headers: a section header with lane headers under it.
- Hiding the place where a board is chosen or its missing access is explained.
- Moving rows under the pointer when chips change or sections fold.

## The popover in Issues mode

```
┌────────────────────────────────────────┐
│ [⎇│◎•] 🔍 Search issues            ⌘F  │  unchanged
│ (All) (Assigned 7) (Created 3) (Board 15)│ scope chips, replacing the tab bar
│ ▤ All repos ▾                ⇅ Updated │  filter bar (board menu on Board only)
│────────────────────────────────────────│
│ ◎ Assigned to you                    7 │
│ ✎ You opened                         2 │  minus issues assigned to me
│ › Rest of the board                  9 │  folded; only when a board is readable
└────────────────────────────────────────┘
```

### Scope chips (Issues mode)

- The chips are **All · Assigned · Created · Board**, drawn with `ScopeChip`, as the PR chips are. One is selected at a time.
- **Assigned is renamed.** Today's tab reads "Mine"; the chip, Back buttons, tooltips and the footer say "Assigned". It matches the Assigned to you section and no longer clashes with the PR side's Mine (PRs I opened).
- **Board is always shown**, also with no board chosen or no access. It is where a board is chosen and missing access is explained (today's Board tab states), so hiding it would hide setup.
- **Counts** are today's tab counts (`IssueTabCount`): Assigned and Board leave out their uncounted Done groups; Created counts its open issues. All shows no count.
- **Created can count more than You opened.** Created keeps issues also assigned to me; You opened doesn't. The Created chip's tooltip and VoiceOver text say "Includes issues also assigned to you", so the difference doesn't read as a bug.
- **Stale counts keep their warning.** Unlike PR counts, an issue count can be stale (`.stale`), and an unreadable Board reads "–" (`.unavailable`). The chip shows the count with the warning triangle and the same tooltip and VoiceOver text the tab gives today. `ScopeChip` gains that state.
- Clicking the selected chip (other than All) goes back to All. ←/→ moves between the chips.
- No chip is drawn in the accent colour: unlike Needs you, nothing here is a request waiting on me.

### What each scope shows

| Scope | Shows |
|---|---|
| All | Assigned to you, You opened, Rest of the board (folded) — flat sections |
| Assigned | Today's Assigned tab: Status lanes, Not on board, folded Done ("still open"), or repo groups when the board has no Status |
| Created | Today's Created tab: grouped by `grouping` |
| Board | Today's Board tab: lanes, lane folds, 14-day Done, board menu in the filter bar |

- The three single scopes are today's tabs unchanged, including their empty and not-loaded states. Only All is new.

### Sections in All

| Section | Rows | Shown when |
|---|---|---|
| Assigned to you | Assigned's open issues, leaving out those done on the board | Assigned is loaded |
| You opened | Created's open issues, leaving out those done on the board, minus any assigned to me | Created is loaded |
| Rest of the board | The board's open, not-done items, minus any in the two sections above | The board is available (`BoardStatus.available`) |

- **Flat sections, no lanes.** All never groups by Status or by repository; the sections are the grouping. Each row names its repo, and a row on the board shows its Status as a row chip (new; today the lane says it). The chip is gray glyph and text, never colour alone, and VoiceOver reads it as "Status: In Progress". This is the PR rule for All (no repo grouping) applied to lanes, and it avoids nested headers.
- **De-duplication runs top to bottom**, so each issue sits in the first section that holds it.
- **Done stays out of All.** An open issue in the board's Done column is housekeeping, so no All section shows it, whichever list it came from. It stays reachable on its chips: Assigned's folded "still open" Done group, the Board's 14-day Done, and Created, which lists it as today. The "done on the board" test (`IssueTabBuilder.isDone` on the issue's board copy) runs before de-duplication, so an issue removed from Assigned to you for being done never falls through to You opened.
- **Folding:** headers fold on click, kept in `sectionFolds` as the PR sections are, under their own keys. Defaults: Assigned to you and You opened open, Rest of the board folded. Nothing folds while searching.
- **Empty is said only of a loaded list.** An empty loaded section hides itself. If Assigned has loaded and Assigned to you is empty, a one-line "Nothing assigned to you" sits at the top and the other sections follow. If every list All reads has loaded and all three sections are empty, the empty state reads "No open issues assigned to you or opened by you".
- **Not loaded is never shown as empty.** A list still loading shows its section header with the skeleton rows lists use today. A list that failed with nothing kept shows its header with one line, "Couldn't load assigned issues" (or created), and the error in its tooltip; it never falls back to the empty copy.
- **Stale:** a section whose list failed shows its last good rows with the warning glyph on its header and the chip's tooltip. Because a stale section can be folded or scrolled away and All has no count, the All chip also shows the warning glyph while any list it reads is stale, with a tooltip naming which.
- **An unreadable board changes All's shape, as it changes Assigned's today.** Done is known only from the board copy, so while the board can't be read nothing is left out as done and Rest of the board is absent; when the board comes back they return. An issue on a project other than the chosen board is never treated as done.
- **Footer link:** All links to the Assigned issues page on GitHub, as today's Assigned tab does.

### Sorting

- Each scope has one sort. Assigned, Created and Board keep their `settings.sorts` keys. All is new and needs its own key; `"all"` is taken by `PRScope.all`, so it is `"issuesAll"`, starting at Recently updated.
- In All the sort orders rows within each section; sections keep their fixed order.
- All adds one sort choice, **Board status**: rows in board column order, then by Recently updated, with issues not on the board last. It gives a team member their workflow order in All without lane headers. It is offered only while the board is available; otherwise All sorts by Recently updated.

### Search

- While the field holds a query, the chips become **Everywhere · Assigned · Created · Board**, as on the PR side: each shows its match count, Everywhere is the default, and narrowing stays local (`SearchScope.issues`).
- Everywhere results take All's sections: a result the list holds goes in its section; an issue I authored or am assigned that the list doesn't hold goes in You opened or Assigned to you; any other open result goes in **Other results** after Rest of the board. An open result that is done on the board goes in the **Done · still open** group that issue search shows today, after Other results, wherever it came from: search finds it, but it doesn't sit with live work. Closed results follow last, as now.
- A search narrowed to a chip takes that chip's layout (lanes for Assigned and Board, Created's grouping), as narrowed searches do today.

### Settings (Settings → General)

- **Issues open on:** All (default) · Last used · Assigned · Created · Board. It works as "Pull requests open on" does: the chosen scope applies on every open, and Last used restores the chip at close. A board-first user picks Board.
- **There is no chips on/off setting.** The PR side's Scope chips toggle (#49) is removed before it is released, in its own PR ahead of this one (owner). Chips are always shown in both modes. All already gives the no-chips experience to anyone who never clicks a chip, and in Issues the Board chip is the only way to the lanes and the board menu, so hiding the chips would hide the board.
- The badge's "Count assigned issues" is unchanged.

### Settings migration

- `lastIssueTab` becomes `lastIssueScope`, an `IssueScope` (`all`, `assigned`, `created`, `board`). The old value seeds it, so Last used works at once for anyone who picks it.
- The new `issueOpenOn` is All for a new install. An existing user (a settings file without `issueOpenOn`) gets Last used, seeded from `lastIssueTab`, so they land where they did before. This differs from the PR side on purpose: All flattens Assigned's Status lanes, which team and board users rely on, so landing everyone there would take something away rather than add a view (owner).
- Old sort keys carry over; `sorts["issuesAll"]` starts at Recently updated.

## What stays the same

- Fetching, the `Snapshot`, notifications and the badge.
- `IssueTabBuilder`'s groups for Assigned, Created and Board, `LaneFolds`, the Done windows, Status editing and the board picker.
- The filter bar: repo focus, time focus, sort, and the board menu on Board.
- Pull Requests mode.

## Left to the builder

- **Type names.** `IssueTab` stays as the name of the three fetched lists. New: `IssueScope` for the chip, an `IssueSection` for the All sections, and whatever replaces `BuiltIssueTabs` reads for All (derived, as `teamSection` is on the PR side).
- **Sharing with the PR chips.** Whether `ScopeChips` becomes generic over the scope or Issues gets its own view.
- **The Status row chip's look**, within `RowChips`' gray glyph-and-text style.
- **Keyboard order** across sections, skipping folded ones, as `ListNavigation` does for PRs.

## Delivery

One PR: chips, All sections, search layout, the open-on setting, the migration and the README/manual. It is the size of PR step 3 + 4 together, but the Issues header row already exists (#45), so most of the work is the All builder and its view.

## Testing

- **Builder:** section membership and the top-to-bottom de-duplication (an issue assigned and created; on the board and assigned; on the board and created); done-on-board issues left out of All; Rest of the board absent without a board; stale and never-loaded lists.
- **Chip counts:** match today's tab counts, ignore focus, keep `.stale` and `.unavailable`.
- **Search layout:** an Everywhere result in each section, Other results, narrowing to each chip.
- **Settings decoding:** an old file with `lastIssueTab` seeds `lastIssueScope` and opens on Last used; a new install opens on All; the new sort key doesn't collide with PR `all`.
- **In the app**, with a board and without one, with an org account and a personal one: landing on All; each chip; folding; Board's menu and lanes; search scoping; light and dark, Increase Contrast, and VoiceOver on the chips.

## Calls made in writing this

These were my decisions, not the owner's. They are worth checking:

- **The Assigned tab's "Mine" title becomes "Assigned".**
- **Board chip always shown**, because it hosts board setup and access messages.
- **All is flat:** no Status lanes or repo groups; Status becomes a row chip.
- **Rest of the board is in All, folded**, de-duplicated against the two sections above it, like Team on the PR side. Named "Rest of the board" so it doesn't read as my issues on the board.
- **Not loaded and failed lists show a line, not the empty copy**, and the All chip carries a stale warning for any list it reads.
- **All gets a Board status sort.**
- **Created's tooltip explains its count** against You opened.
- **Board stays shown without a board**, as the Board tab is today: personal boards exist without an org, and the chip is where one is chosen and access is explained.
- **Clicking the selected chip returns to All**, as on the PR side.
- **No cap on Rest of the board**: it is folded by default and lazily drawn.
- **Done stays out of All**, from every section, checked before de-duplication; in an Everywhere search such results go in Done · still open.
- **Single chips are today's tabs unchanged**; only All de-duplicates. Created still lists an issue I also assigned to myself.
- **No accent colour** on any Issues chip.
- **No chips on/off setting**: removed from the PR side before release, so the Board is always reachable (owner).
- **Issues open on All for new installs; existing users keep Last used**, seeded from `lastIssueTab` (owner).
- **All's sort key is `issuesAll`.**
- **One PR.**
