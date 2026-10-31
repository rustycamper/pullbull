# Edit Status, assignees and labels

PullBull lets you change an issue's board Status, and the assignees and labels of an issue or pull request, from the popover. Today it is read-only: noticing that #412 sits in the wrong column means opening the browser, waiting for Projects to load and dragging the card. This turns that into: select the row, press a key, type a few letters, Return.

## Why

PullBull's pitch is that the browser is slow for a quick look. Triage is the natural next step after the quick look: the board shows something wrong, and the fix is one field. All three fields are "pick from a list", and PullBull already has that picker in search (`status:`, `~`, `@` completions). The menu bar suits small, single-field edits. It does not suit writing text or forms with several fields at once.

## Goals

- Set or clear the board Status of an issue on the board PullBull shows, and add an issue that isn't on that board to it with a Status.
- Add and remove assignees on issues and PRs.
- Add and remove labels on issues and PRs.
- From the keyboard first, from any list row (every tab and search results) and from the detail; also from the mouse (right-click menu, the detail's fields).
- The change shows at once everywhere the item appears, and survives refreshes that haven't caught up yet.
- Every edit can be undone right after.

## Non-goals

- Status on pull requests. The board query reads only issue cards, and `status:` is issues-only; PR cards stay out of scope.
- Other board fields (Priority, Iteration, Estimate), milestones, issue type.
- Bulk edits. The lists have no multi-select.
- Creating labels, editing label colours.
- Close, reopen, comment, approve, merge, edit titles or bodies. These stay out of scope.
- Draft items on the board.
- Ask AI gets no write path. "Ask AI can't write to GitHub or act on anything" stays true.

## Anti-goals

The feature fails, even if it works, if:

- a stray keystroke silently changes a board the whole team sees, with no quick way back;
- an edit appears, then flickers back on the next refresh, then reappears;
- a user who never edits sees nags, broken controls or permission prompts they can't act on;
- the copy claims more or less than PullBull actually writes.

## What PullBull writes

PullBull writes exactly three things to GitHub, each only when the user picks a value: a board item's Status (including adding the issue to the board), assignees, and labels. Nothing else, ever. This sentence, in this form, replaces "Read-only" wherever the product promises it (see Docs and copy).

## Which board, which account

- PullBull shows one board per account and scope: the snapshot's `boardProject` and `boardOwner`. Status edits always target that board. Its `projectId` and Status `fieldId` come from the board fetch, and the item's `itemId` comes from the `BoardIssue` the board fetch produced. Each item carries one `itemId`, for the shown board. Switching boards rebuilds the snapshot, so another board's item ID is never held.
- Status is offered on an issue when a board is shown and has a Status field. The issue may already be on the board, or not yet on it while its repo's owner is the board's owner (an org board takes that org's issues; a personal board takes the user's own). For any other issue, the Status key and submenu are absent.
- The board fetch stops at 20 pages (`GitHubAPI.maxPages`), so on a very large board "not on the board" can be wrong. The add path doesn't trust it. `addProjectV2ItemById` returns the existing item when the issue is already on the project. Status is then set on whatever item comes back. The builder confirms that behaviour against GitHub. If it doesn't hold, the add path first reads the issue's `projectItems` for this project.
- Edits use the account the popover is showing, with the same token and `GitHubAPI` as its reads. There is no choosing between accounts.

## Interaction

### Keys

Bare letters start a search ("just type"), so edits need a modifier. Builder's call: the bindings below. Check them against the existing key handling and change them if one clashes.

| Key | Does | Where |
|---|---|---|
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd> | Status picker | Issue row or issue detail, when a board is shown |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> | Assignees picker | Any issue or PR row, or detail |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> | Labels picker | Any issue or PR row, or detail |
| <kbd>⌘</kbd><kbd>Z</kbd> | Undo the last edit | For 10 seconds after it, unless the search field has text to undo |

These keys work in search results too, where the search field keeps focus while arrows walk the rows.

### Mouse

- **Right-click a row:** a **Status** submenu listing the board's options (current one checked, then **Clear Status**), **Assignees…** and **Labels…** (open the picker on the row). Placed above the copy items, after a separator.
- **Detail:** the board card's Status, the assignees and the label chips are clickable and open the same picker.

### The picker

The picker reuses the search completion list's look and keys: a small popup anchored to the row (or the detail field), with a filter field on top and a list below.

- **Status (single choice):** the board's Status options in board order, each with its colour dot and its open count (as `status:` shows them), then **Clear Status** when the item has one. The current Status is checked. <kbd>↑</kbd><kbd>↓</kbd> choose, <kbd>Return</kbd> applies and closes, <kbd>Esc</kbd> closes without change. Typing filters by part of the name, case ignored.
- **Assignees and labels (several):** the current ones checked and listed first, then the rest. <kbd>Return</kbd> (or a click) toggles the highlighted entry and keeps the picker open. Closing applies all the toggles as one edit: <kbd>Esc</kbd>, a click outside, or the picker's key again. Closing with nothing toggled sends nothing. This matches GitHub's own sidebar pickers, which apply when they close. The edit's undo covers a mistake. <kbd>⌘</kbd><kbd>Return</kbd> applies and closes too.
  - Assignees: the viewer first, then people assignable in the item's repo, with avatars. GitHub allows at most 10 assignees; at 10, unchecked entries are dimmed.
  - Labels: the repo's labels with their colour dots and descriptions.
- The issue or PR the picker edits is named in its header (`acme/widgets#412`), so an edit from a list never lands on the wrong row.

### After an edit

- The row updates at once in every list and in the detail. On Board and Assigned the row moves to its new Status lane. Unassigning yourself takes it off Assigned. Assigning yourself puts it on Assigned (built from the item PullBull already holds).
- No message on success. The updated row is the feedback.
- The selection follows the row. It stays selected in its new lane, and the list scrolls to keep it in view. When the edit takes the row off the list (unassigning yourself on Assigned), the selection moves to the next row. In the detail, the edited field shows the new value.
- **Undo:** ⌘Z within 10 seconds of an edit sends the inverse change: the previous Status or clearing it, the removed labels and assignees back, the added ones off. Only the last edit can be undone.
  - An edit that added the issue to the board is undone by removing the item from the board.
  - Undo sends the inverse without first checking whether someone else changed the field in between. The window is 10 seconds, and a check would cost a round trip.
  - Undo is not itself undoable. After an undo, the selection follows the row back.
  - When focus is in the search field and the field has text changes to undo, ⌘Z keeps its text meaning there.
  - Nothing on screen shows that undo exists; the manual's key tables document it.
- No confirmation dialogs.

### Failure

- When an edit's request partly succeeds (one aliased mutation applied, another refused), only the refused part is rolled back; the error message says what didn't apply. Undo then reverses only what applied.
- The change shown on screen is rolled back, and an error message appears at the bottom of the popover, above the footer, until dismissed or the next edit. It says what failed and why, in GitHub's terms, with **Open on GitHub**. The reason is GitHub's own message when it refused the write, otherwise the wording the refresh already uses (offline, rate limited, …). The messages:
  - "Couldn't set Status on #412: you need write access to the acme board"
  - "Couldn't clear Status on #412: …"
  - "Couldn't add #412 to the board: …"
  - "Couldn't remove #412 from the board: …" (undoing an add)
  - "Couldn't change labels on #412: …", "Couldn't change assignees on #412: …"
- A partial failure names both halves, labels by name and people by login, comma-joined: "Added bug to #412, but couldn't remove triage: …" or "Removed triage from #412, but couldn't add bug: …". When neither half applied, it reads as the plain failure above. When GitHub gives no reason, the reason reads "GitHub didn't apply it".
- Offline or rate-limited: the picker opens (from cached candidates where there are any), but applying fails at once with the existing offline or rate-limit wording. No queueing for later.

## Data and GitHub API

### IDs PullBull needs and doesn't fetch today

- Issue and PR node `id`: add `id` to `issueRowFields` and `prFields` (`Packages/PullBullKit/Sources/PullBullKit/GraphQL/Queries.swift`).
- Board: `projectV2 { id }`, the Status field's `id` (the `field(name:"Status")` selection already fetches option `id`s), and each item's node `id` beside `databaseId`.
- Cached snapshots lack these. Decode them with `decodeIfPresent`. When an edit needs an ID the cached item lacks, look it up first (one query by owner, repo and number, or the board's next refresh). Then apply. Old caches must not block an edit.

### Mutations

| Edit | Mutation |
|---|---|
| Set Status | `updateProjectV2ItemFieldValue(projectId, itemId, fieldId, value: {singleSelectOptionId})` |
| Clear Status | `clearProjectV2ItemFieldValue(projectId, itemId, fieldId)` |
| Issue not on the board | `addProjectV2ItemById(projectId, contentId)`, then set Status on the returned item |
| Undo an add to the board | `deleteProjectV2Item(projectId, itemId)` |
| Labels | `addLabelsToLabelable` / `removeLabelsFromLabelable`, label node IDs |
| Assignees | `addAssigneesToAssignable` / `removeAssigneesFromAssignable`, user node IDs |

Labels and assignees go as a diff (what the user added, what they removed), never as "replace with this set". So a label someone else added a minute ago, which PullBull hasn't seen yet, survives. When one edit both adds and removes, the two mutations go in one GraphQL request as aliased fields.

Mutations go through the existing `GitHubAPI` and transport, with the same error mapping (`APIError`). A GraphQL `FORBIDDEN` or a 403 on a mutation maps to a new case that says the write was refused, not to `boardForbidden`, which means "can't read".

### Picker candidates

- Status options: from the snapshot (`boardStatusOptions`), already loaded.
- Labels: `repository.labels`, all pages, with `id name color description`. Fetched when the picker first opens for a repo and cached in memory for the session. A refetch on open may run in the background and replace the list when it lands.
- Assignees: `repository.assignableUsers(first:100)`, with `id login avatarUrl`, cached the same way. When the repo has more than 100, typing in the filter queries `assignableUsers(query:)`.
- Candidates aren't written to disk.

### The local override until GitHub catches up

Search-backed lists (Assigned, Created, PR tabs, search) can return the old value for a while after a write: GitHub's search index lags. The board query reads the project directly and lags little, but a refresh can still be in flight from before the edit. So:

- Each applied edit records an override: the item's `PRKey` (repo and number, the key every list and the detail already share), the field, the intended value, and when it was made. It lives in PullBullKit, beside the snapshot, in memory only. Node IDs are not part of the key, so overrides work on cached items without them.
- An override is stored as a change, not as a whole item: the Status option ID (or none), and the labels and assignees added and removed. Applying it to any model of the item (a PR row, a `BoardIssue`, a detail) changes only those fields.
- Agreement means: the same Status option ID (not its name, so a renamed option still agrees), and every added label or assignee present and every removed one absent, compared case-insensitively, on the first copy of the item found (board, then Assigned, Created, Closed, then PR lists). A removal from the board agrees once the card is gone. If the board no longer has the overriding option (it was deleted), the override is dropped at once.
- Assigning or unassigning yourself on an open issue agrees only once Assigned agrees too (when Assigned was fetched). The board copy shows the new assignee at once, but Assigned comes from search and lags; dropping the override on the board copy alone would make the row flicker on Assigned.
- Self-assigning puts the open issue on Assigned from the `BoardIssue` PullBull holds, from the board or Created copy. Both carry `issueRowFields`, which is all an Assigned row shows. An issue found only through search shows on Assigned once search lists it. Assigning someone else inserts nothing. A PR has no Assigned list, so nothing is inserted for PRs; on a PR an override shows labels only.
- Tabs, search results and the detail read the snapshot through the overrides. The stored snapshot stays as GitHub returned it. Notification change detection compares raw snapshots, so an override never fakes an event.
- An override is dropped when a fetched snapshot agrees with it, or when 5 minutes pass, or when it is undone or fails. After 5 minutes GitHub's answer wins, even if it differs: someone else changed it, or the write didn't stick.
- Overrides apply oldest first, so several edits to one item before a refresh show their net result. When a fetch agrees with an edit, the older edits to the same item that it replaced are dropped with it: any older Status edit, or an older label or assignee edit that touched one of the same labels or people. Todo → Doing → Done followed by a fetch showing Done leaves nothing behind, and neither does adding to the board and undoing it. An older edit to a different label still waits for GitHub to show it. Each override is checked against fetches independently, so a fetch that agrees with an earlier edit doesn't drop a later one.
- The copies search results and the detail use keep the issue's node ID and its board item's node ID, so editing from them needs no lookup.
- Own edits don't notify: `ChangeDetector` already skips Status moves and assignments whose actor is the viewer (`Notify/ChangeDetector.swift`, `statusEvents` and `assignedEvents`). Label changes don't notify today. Keep it that way, and cover it with a test.

## Permissions

### GitHub App

- Change the app's permissions: **Issues: Read and write**, **Projects (organization): Read and write**. Everything else stays read-only.
- Pull requests stay **Read-only**. The app never gets a permission that could merge. Before the permissions change ships, the builder checks on a test app and a test org whether `addLabelsToLabelable` and `addAssigneesToAssignable` accept a PR with Issues write alone.
  - If they do, PR labels and assignees ship as described, gated on the installation's `issues` permission like issue edits.
  - If they don't, labels and assignees on PRs are left out of this release. Their keys and menu items don't appear on PR rows or the PR detail, and the copy says "issues" where it would have said "issues and PRs". Adding them later is a separate permission change.
- Installation permission keys: `issues: write` gates labels and assignees; `organization_projects: write` gates Status.
- Request all the write permissions in one change, before the Status release. Every new permission makes org owners re-approve, so they should approve once, not once per release.
- Existing installations keep their old, read-only permissions until an owner accepts the new ones. `AccessChecker` already reads each installation's `permissions`; the edit controls use them:
  - The installation grants write: the keys, menu items and clickable fields work.
  - It doesn't: the keys and the menu items still show. Choosing one shows a one-line note in place of the picker: "Editing needs PullBull's new permissions for acme. An org owner accepts them on GitHub." It links to the installation's permissions page (`AccessChecker` already builds `installations/new/permissions`). Lists and details look as today. No banners, no badges.
- A GitHub App user token can do only what the user can do. A user with read-only access to a repo gets refused. If GraphQL exposes it, use the item's `viewerCanUpdate` (and `viewerCanLabel`, if it exists) to show the same one-line note in place of the picker instead of failing after the fact. Otherwise rely on the failure path.
- Personal boards: GitHub Apps can't reach them at all. Nothing changes: those boards are read through a `gh` login, as today.
- Update `docs/github-app-setup.md`: the permission table and the app's description text.

### GitHub CLI logins

- Labels and assignees: the `repo` scope, already required.
- Status: the `project` scope; `read:project` isn't enough. `GhAccount` already parses scopes; add a `canWriteProjects` beside `canReadProjects`. Without it, the Status picker shows a one-line note in place of the list: the command to run, in the existing checklist style (`GhCommands.addProjectScope` gains a write variant: `gh auth refresh -s project`).

## Docs and copy

- README tagline: replace "Read-only" with a short claim that is true. Builder's call; for example "Keyboard-first · Native SwiftUI · Edits only what you pick".
- README Privacy row: "Writes to GitHub: board Status, assignees and labels, only when you pick them. Never merges, comments, approves or closes."
- CONTRIBUTING out-of-scope: "Writing to GitHub beyond Status, assignees and labels (merge, comment, approve, close)". Reason: "PullBull triages; GitHub is where work is written".
- Manual: a new **Editing** section (keys, picker, undo, overrides in one sentence, permissions); the Keyboard tables (list and detail); right-click lists in Pull Requests and Issues; Sign in table (token is no longer "Read-only"; `gh` scope `project` for Status).
- GitHub App description (`docs/github-app-setup.md`): the same sentence as Privacy.
- Release notes: say plainly that PullBull now writes these three fields, and that org owners will be asked to accept new permissions.

## Delivery

1. **Permissions and plumbing:** node IDs in queries and models (cache-compatible), mutation support in `GitHubAPI`, write-permission detection for the app and `gh`, override store with reconciliation, undo, the error message. App permission change requested here.
2. **Status:** picker, keys, right-click submenu, detail click, add-to-board, clear, undo.
3. **Assignees and labels:** the multi-select picker, candidate fetching, the diff mutations, for issues and PRs.

Each step ships as its own PR. The README and manual change with the step that makes them true.

## Testing

Per CONTRIBUTING, logic lives in PullBullKit with tests; views stay thin. Tests cover at least:

- Diff building: toggles to add and remove sets, and a toggle back and forth sends nothing.
- Mutation documents and variables for each edit, including add-to-board followed by set.
- Override reconciliation: applied to tabs and search, dropped on agreement, on timeout and on failure; not visible to change detection.
- Lane moves: Status change moves the row on Board and Assigned; self-unassign removes from Assigned; self-assign inserts.
- Permission gating: installation permissions, `gh` scopes, `viewerCanUpdate`.
- Undo: the inverse of each edit, including delete-from-board for an add; ⌘Z expires after 10 seconds and yields to the search field's text undo.
- Selection: follows the row to its new lane, and moves to the next row when the row leaves the list.
- No notification for the viewer's own Status, assignment or label changes.
- Old cached snapshots without node IDs decode and still allow an edit.

Manual check against real GitHub, on a test org with a board and a test repo, before each PR leaves draft. For each field, cover:

- setting and clearing it, and undo;
- adding an issue to the board;
- a refresh right after the edit doesn't flicker;
- the read-only install (old permissions);
- a read-only repo collaborator;
- a `gh` login with `read:project` only;
- offline.

## Left to the builder

- Exact key bindings, if the ones above clash with existing handling.
- The error message's look, and where it sits relative to the footer's refresh-error state.
- How the picker anchors to a row in a scrolled list, and in compact cards.
- Paging limits for labels on unusually large repos.
- Whether one combined request or sequential requests best fit add-to-board followed by set Status.
