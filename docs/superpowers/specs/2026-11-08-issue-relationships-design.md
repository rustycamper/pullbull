# Relationships in the details

An issue's detail shows the issue's relationships: its parent, its sub-issues, the issues blocking it, and the issues it blocks. A PR's detail shows the issues the PR will close. All of this is read-only. Clicking a related item opens its detail in PullBull, and Back steps back through each detail you passed through on the way.

## Why

- GitHub's issue dependencies (blocked by, blocking) and sub-issues are how work gets sequenced. Today PullBull shows none of it, so an issue that looks ready to pick up may still be waiting on another one. For example, seai-tech/seai-server #1028 is blocked by #1026, and nothing in PullBull says so.
- A PR detail doesn't say which issue it closes. The issue detail already lists its linked PRs; the PR side has no counterpart.

## Who uses this

| User | What they get |
|---|---|
| Someone picking up an assigned issue | Sees at a glance whether it's still blocked, and by what |
| Someone working through an epic | The parent's sub-issues with progress, and one click into each |
| A reviewer on a PR | The issue the PR closes, one click away |
| An issue or PR with no relationships | Issue: no new section. PR: an empty "Linked issues" section, like the issue's empty "Linked pull requests" |

## Goals

- Relationships are part of the issue detail and PR detail fetch: no extra request, no extra wait.
- Each related item is a row that opens that item's detail in the app.
- Back always returns to the detail you came from, however many links you followed.

## Non-goals

- Adding, removing or reordering relationships. Read-only.
- Showing relationships, or a "blocked" marker, on list rows, in search results or in notifications.
- Tracked issues (`trackedIssues` / `trackedInIssues`, the older tasklist relation), and links mentioned in issue or comment text.
- Issues linked to a PR only by a mention. Only `closingIssuesReferences` counts.
- Relationships of a related item, shown inline. To see those, open that item's detail.

## Anti-goals

The feature fails, even if it works, if:

- **Back loses its way.** After following links, Back skips a detail, lands on the wrong one, or leaves the user stuck going round in circles.
- **The issue detail gets noisier for the common case.** Most issues have no relationships, and they look exactly as they do today.
- **A relationship's state is wrong.** A blocker shows as open when GitHub has it closed, after the detail has been read again.

## Data

All fields below are on github.com GraphQL. PullBull supports github.com only.

**Issue detail query** (`Queries.issueDetail`). These fields are added:

```graphql
parent { ...relatedIssue }
subIssuesSummary { total completed }
subIssues(first: 20) { totalCount nodes { ...relatedIssue } }
issueDependenciesSummary { blockedBy totalBlockedBy blocking totalBlocking }
blockedBy(first: 20) { totalCount nodes { ...relatedIssue } }
blocking(first: 20) { totalCount nodes { ...relatedIssue } }
```

**PR detail query** (`Queries.detail`). This field is added:

```graphql
closingIssuesReferences(first: 20) { totalCount nodes { ...relatedIssue } }
```

**The related-issue fields** are `number title url state stateReason repository { nameWithOwner }`. That is enough for the row and for the glyph that `IssueGlyph` (open, completed, not planned) already supplies.

- `issueDependenciesSummary.blockedBy` is the open blocker count. `totalBlockedBy` counts every blocker, closed ones included. `blocking` and `totalBlocking` work the same way. These counts were checked against #1026 and #1028.
- A null node, such as an issue the account can't read, is skipped.

## Issue detail

```
[Status / Assignees / Labels card]
RELATIONSHIPS
┌───────────────────────────────────────────┐
│ Parent                                    │
│ ◯ Relief planning epic                  › │
│   #1001 · open                            │
├───────────────────────────────────────────┤
│ Blocked by                         1 open │
│ ◯ Relief planning: relief cover per…    › │
│   #1026 · open                            │
├───────────────────────────────────────────┤
│ Blocking                                2 │
│ …                                         │
└───────────────────────────────────────────┘
SUB-ISSUES                        2 of 5 done
┌───────────────────────────────────────────┐
│ ✓ …                                     › │
└───────────────────────────────────────────┘
LINKED PULL REQUESTS
…
```

- **Order:** board card, Relationships, Sub-issues, then Linked pull requests, Description and Conversation as today.
- **Relationships** is one `DetailSection` holding one `DetailCard`. The groups inside it come in a fixed order: Parent, Blocked by, Blocking. Each group has a small sub-heading and is separated from the next by a `CardDivider`.
  - A group with nothing in it is left out.
  - With all three groups empty, the section is left out.
  - Blocked by's and Blocking's summaries are both "N open" when any issue in the group is open, else "all closed". They come from `issueDependenciesSummary`.
- **Sub-issues** is its own `DetailSection`, with the summary "N of M done" from `subIssuesSummary`. It's left out when `total` is 0.
- **The row** has the shape of `LinkedPRLine`:
  - The issue's state glyph and colour, as list rows use them.
  - The title on one line.
  - A grey line reading `#N · state`. The state text is the word issue rows already use for that state. When the related issue is in a different repository from the issue on screen, the line reads `owner/repo#N · state`.
  - A chevron.
  - Closed and not-planned issues are listed too, with their own glyph. They aren't hidden or dimmed.
- **More than 20** in a group: a last line "+N more on GitHub" opens the issue on screen in the browser. N is `totalCount` minus the nodes GitHub returned, null ones included. The line shows only when N > 0. An unreadable item, a null node, is just left out and isn't counted as "more", since the link wouldn't show it either.
- The state shown for each row is GitHub's answer from the last read of the detail on screen. PullBull can't change an issue's state, and no edit override touches a related row.

## PR detail

- A **Linked issues** section listing `closingIssuesReferences`, with the same row as above.
- **Placement:** directly after the Details card, before the status sections (Reviewers, Checks, Merge) and Description. It keeps that place whatever the PR's state.
- The section's summary is the count.
- With no closing issues it shows the heading and `EmptyLine("No linked issues")` in a card, mirroring the issue detail's empty "Linked pull requests".
- Before a detail has loaded, or for a detail cached before this field was stored, the section isn't shown. Neither a placeholder nor the empty line appears.

## Navigation: the trail

Today a PR opened from an issue's Linked pull requests returns to that issue. Opening an issue detail from another issue detail sends Back to the list. Both are replaced by a **trail**: a list of `(kind, key)` entries, where kind is PR or issue. The first entry is the **base**. Every later entry is a **hop**, a detail opened from the entry before it through a relationship row, a Linked pull requests row or a Linked issues row.

- **The base** is the detail opened from outside a detail: a row, search, Ask, Stats or a notification. Where Back from the base goes is its **origin**: the list, search, Ask, Stats, with the back scope and Ask's return as today. The origin is saved once, when the base opens, and hops never change it.
- **Following a link** appends a hop and opens it. This holds in every direction: issue to issue, issue to PR, and PR to issue.
  - A hop doesn't go through the from-outside steps of `openDetail` and `openIssueDetail`. It doesn't touch `askReturn`, the return routes, the back scopes or the list or search selection.
  - The trail owns the whole back chain from the base onwards.
  - Today's Linked pull requests row, a PR opened from an issue returning via `detailReturnRoute = .issueDetail`, becomes a trail with two entries.
  - A PR opened from outside while an issue detail is on screen, such as a notification, keeps today's return to that issue. It's a new base whose origin is that issue detail, and Back to it makes the issue the base of a fresh trail. Any trail the issue had before is gone, as is everything else a notification replaces.
- **Back** from a hop returns to the entry before it. That detail shows its cached copy at once and is fetched again, as the issue detail is now when coming back from a linked PR. Back from the base goes to its origin, exactly as today, and clears the trail.
- **The back button's title** is `#N` of the entry before while on a hop, and the origin's title on the base, as today.
- **No loops:** opening an item already on the trail, the base included, goes back to that entry and drops everything after it, exactly as that many Backs would: cached copy at once, then fetched again. For example, base #1028 → Blocked by #1026 → Blocking #1028 lands back on the base #1028, and Back from there goes to its origin. The trail never holds the same item twice.
- **The walk** (⌥↓ / ⌥↑ through the list) belongs to the base. On a hop, the "2 of 6" isn't shown and stepping does nothing. This holds even when the hop's item is in the walk, such as a blocker that is also on the list. It's decided by being on a hop, not by the walk's kind. Hops leave the list and search selection alone, so Back to the base finds the walk, its position and the selection as they were.
- **Everything that today asks "which detail is this, and where does it return to"** reads the trail's base: the popover-close handling of the back scopes (`showsPRDetail`, `showsIssueDetail`), `detailReturnsToSearch`, and the back button's position. A hop of either kind over a base of the other kind counts as being in the base's detail. Closing and reopening the popover on a hop, then Backing to the base and then to its origin, lands on the base's origin chip, or its search with the query kept.
- **Starting fresh:** opening a detail from outside a detail (a row, a notification, Ask, search) starts a new trail with that detail as the base.
- **Kept and cleared:** the trail lives exactly as long as being in a detail does. Closing and reopening the popover keeps it, as the open detail and its walk are kept today. Anything that today takes the route out of a detail clears it: an account switch, a reset to the list, Back from the base.
- **Header before load:** a hop whose item is in no list and has no cached detail shows the row's title until it loads, in place of today's `owner/repo #N`. No stub `BoardIssue` or `PullRequest` is built from the row. It would show an empty Details card, "no assignees" and no labels, which isn't known yet. So the state pill, byline and Details card wait for the load, as they do today for a linked PR in no list. `linkedPR(for:)` gives that title today for a linked PR. It generalises to looking the key up among the related items of the details on the trail.
- **Unreadable items:** a hop to an item the account can't read, in another org or with no access, still goes on the trail. Its detail shows the existing load error with Retry, and Back works as for any hop. Rows aren't checked before opening.

## Caching

- `IssueDetail` gains `parent`, `subIssues`, `blockedBy` and `blocking`. `PRDetail` gains `linkedIssues`. Each comes with its counts.
- Details cached before this change still decode.
  - **Issue detail:** a cached copy shows no relationships until the next read. The detail is always read again on open, so this lasts only for the moment the cached copy is on screen.
  - **PR detail:** the missing field is `nil`. That's "not known", not "none": the Linked issues section stays hidden until a read succeeds, even when that read fails or happens offline. Showing "No linked issues" would be wrong for a PR that has some. A detail read by this version always stores the field, with an empty list when there are none.
- `isCurrent(for:)` is unchanged. A blocker closing elsewhere doesn't change this issue's `updatedAt`, so a prefetched detail can show a stale blocker state until the issue is opened. Prefetch also won't refresh a legacy cached detail whose `updatedAt` still matches. Opening the issue always reads it again.
- Back to an earlier entry shows its cached copy first, so for that moment a related row can show the state from before. For example, B closed on GitHub while you were on its detail. The read that follows corrects it, and that's accepted. Rows aren't patched from other details' copies.

## Testing

- **Kit tests:**
  - Decoding of every new field.
  - Null nodes skipped.
  - The "+N more" count.
  - A legacy cache decoding.
  - The query text containing the new fields, as `DecodingTests` does for the list query.
- **Trail logic:** tests over the trail's push, Back, dedupe and clearing rules. This means the trail is a small type that can be tested on its own, not state spread across `AppModel`.
- **In the app** (there's no app test target), checked by hand:
  - Close and reopen the popover on a hop, then Back to the base and then to its origin. It lands on the origin chip, or the search with its query.
  - A hop to an issue that's also in the walk shows no "2 of 6", and ⌥↓ does nothing there.
  - An account switch mid-trail lands on the list with the trail gone.
  - A notification PR over an issue detail returns to that issue.
- **Real GitHub:**
  - seai-tech/seai-server #1026 (Blocking #1028) and #1028 (Blocked by #1026), read with the peter-seai account. Only reads happen there.
  - A parent with sub-issues, and a PR with a closing issue, set up in the test repo rustycamper/pullbar.
- **Browser verification:** not applicable. This is a native app with no save path.
