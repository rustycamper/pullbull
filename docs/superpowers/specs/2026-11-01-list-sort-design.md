# Sorting the lists

Each list tab gets a Sort choice: what's new, what's stuck, or what's old. The default stays "Recently updated", so nothing changes for anyone who never opens the menu.

## Why

- Today every list is in one fixed order: the most recently updated first. Review alone has an alternative, "Oldest review request first", and it's hidden in Settings → General.
- The questions people bring to a PR list differ by moment. "What changed?" is answered by recent activity. "What's been sitting?" is answered by the review wait (PR #33), which the rows now show but no list can be ordered by. "What's old?" is answered by when it was opened.
- PullBull is open source and needs no setup. A sort should be one click, visible where the list is, and the same on every tab. It shouldn't be a preference people have to find.

## Goals

- Every list tab (Review, Mine, Team, Assigned, Created, Board) has its own sort, remembered across launches.
- PR tabs can be ordered by the review wait.
- A changed sort is always visible, so a list that "looks wrong" explains itself.
- Search results follow the sort of the tab they're laid out like.

## Non-goals

- Sorting by size, CI state, approvals, title, comment count or labels.
- Sorting by more than one key, or an ascending/descending toggle. Each choice has one fixed direction.
- Dragging rows into a custom order.
- A different sort per repo, per group or per board lane.
- A keyboard shortcut for the sort menu. It can come later if people ask.

## Anti-goals

- A sort that hides itself. Someone who changed Review to "Oldest first" a month ago mustn't be left wondering why new requests sit at the bottom.
- Settings sprawl. The feature removes a Settings toggle and adds none.
- Reordering under the pointer. A refresh may move rows, as it does today, but changing the sort mustn't lose the selected row.

## The choices

| Tabs | Choices, default first |
|---|---|
| Review, Mine, Team | Recently updated · Waiting longest · Oldest first |
| Assigned, Created, Board | Recently updated · Newest first · Oldest first |

- **Recently updated:** by last update, newest first. This is today's order.
- **Waiting longest:** by the review wait `ReviewWait` computes for the row (PR #33), longest first. It uses the wait the row actually shows: Review's short form on a Review row counted for you or your team, and the full form everywhere else, including a Review row that isn't waiting on you and a search result laid out with another tab's chips.
  - It orders by when the wait started, oldest first. That is the same order as by length and needs no `now`.
  - A PR whose row shows no age follows in Recently updated order. That covers drafts, PRs reviewed or approved with nothing pending, and a wait whose start isn't known for every pending reviewer (the row then shows names with no age).
  - The row and the sort read the start from one shared `ReviewWait` accessor, so they can't disagree.
- **Oldest first:** by when it was opened (`createdAt`), oldest first, on every tab and for drafts too. This is today's "Oldest review request first", now on every tab.
- **Newest first** (issue tabs): by when it was opened, newest first.
- An issue missing the date its sort uses (`updatedAt`, or `createdAt` for Newest/Oldest first) goes after the dated ones.
- Ties break by repo, then number, as today.

## The control

- A sort button on the right end of the filter bar, after the spacer: `↑↓` (SF Symbol `arrow.up.arrow.down`). It opens a menu of that tab's three choices, with a checkmark on the current one.
- When the tab isn't on its default, the button shows the choice's short name beside the icon ("Waiting longest") in the accent colour. When it is on the default, it shows only the icon, in the filter bar's usual secondary style. That's the "never hidden" rule.
- The same three choices appear as **Sort By ▸** in the list's right-click menu, next to **Show Only Updated**.
- Help and VoiceOver: "Sort: Recently updated".

## What the sort applies to

- **Rows** in every group of the tab.
- **Repo groups** are ordered by their first row under the chosen sort. Today they go by their newest update, which is the same thing for Recently updated.
- **Author groups** (Team by author) stay alphabetical under every sort, as today. A person is looked up by name. Moving authors around would also change the default order, which the anti-goals rule out. *(Builder-check call.)*
- **Board lanes** keep the board's own column order. The sort applies inside each lane.
- **These are left alone:** Done, Mine's Recently closed, and search's "Closed and merged" / "Closed". They stay ordered by when the item ended, because that's what those sections are for.
- **Search** uses the sort of the tab the results are laid out for: the search's reference tab when it has one, otherwise the current tab.
- **Keyboard navigation** (↑/↓, ⌥↑/⌥↓, the detail's ⌥↓ next-item order) already follows the on-screen order. That order is captured when the first detail opens, and changing the sort doesn't reshuffle an open detail's sequence, as a refresh doesn't.
- **Selection:** changing the sort keeps the selected row selected and scrolls it into view. A row in a folded group or lane stays folded away, and nothing scrolls.

## Settings and migration

- The sort is stored globally per tab in `SettingsStore` (`[tab: ListSort]`), not per account, org or board.
- "Oldest review request first" is removed from Settings → General. The old `reviewOldestFirst` key is read only when the stored settings have no sort key yet. `true` then becomes Review's sort = Oldest first. Once the sort key exists it wins, and the old key is no longer written.
- The manual's Review row ("Oldest first: Settings → General") and the Settings table entry change to describe the Sort menu.

## Where it lives

- A `ListSort` enum in PullBullKit with four cases (`recentlyUpdated`, `waitingLongest`, `oldestFirst`, `newestFirst`); Oldest first is shared by PR and issue tabs. Each tab has its allowed choices and default.
- `TabBuilder.contents` and `IssueTabBuilder`'s sort take a `ListSort` in place of `oldestFirst`. `SearchLayout` passes the tab's sort.
- "Waiting longest" needs `ReviewWait`'s wait as a sortable duration. The sort and the row must use the same rule for a tab: Review's short form on Review, the full form elsewhere.
- Kit tests cover each order, the no-wait tail, ties, groups ordered by their first row, the untouched ended sections, and the settings migration.
