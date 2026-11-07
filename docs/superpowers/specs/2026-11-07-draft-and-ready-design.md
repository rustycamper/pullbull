# Mark a pull request ready for review, or convert it to draft

PullBull lets you mark a draft PR ready for review, and turn an open PR back into a draft, from the PR's detail. You can switch either way as often as you like, just as on GitHub.

## Why

- A draft is the one PR state that PullBull shows but can't change. After review (#62), merging (#64) and re-running (#65), moving out of draft is often the step just before merging, and it's the last one still done in the browser.
- Today a draft's detail has no Merge section, and nothing says why. The space where Merge would be is empty.

## Who uses this

| User | What they get |
|---|---|
| Author of a draft | **Ready for review** where Merge would be |
| Author of an open PR | **Convert to draft** in the Reviewers section, as GitHub has it under Reviewers |
| Maintainer with write access, on someone else's PR | The same, as GitHub allows it |
| Reader without write access, not the author | Nothing new shown |
| Install without Pull requests write | A note where **Ready for review** would be, with the link to accept |

## Goals

- One click each way, from the detail.
- What's on screen (the state pill, the rows, the Merge section) follows at once once GitHub answers, and doesn't flicker back while GitHub's reads catch up.
- A refusal or an unclear answer says so clearly.

## Non-goals

- Changing it from a row, a context menu, or for several PRs at once.
- A keyboard shortcut. Re-running has none either. One can come later if it's missed.
- Opening a PR as a draft. PullBull doesn't open PRs.
- Working out in advance whether the repository supports drafts. GitHub's refusal reason is shown instead.

## Anti-goals

The feature fails, even if it works, if:

- **The state shown is wrong.** The detail shows "Ready" while GitHub still has a draft, or the reverse. Nothing changes on screen before GitHub has answered yes.
- **A PR flips twice on one click.** The button can't be pressed again while a change is on its way.
- **It runs into a merge.** Neither control works while the merge panel is open or a merge is on its way. PullBull never calls the auto-merge mutations here. Whatever GitHub does to auto-merge on a flip, the screen shows that and nothing else.

## What's offered

`isAuthor` means the viewer is the PR's author (logins compared without case). `canWrite` is `MergeInfo.canWrite`, from `viewerPermission`: write, maintain or admin. Unknown (`nil`) counts as allowed, as it does for Merge, and GitHub's refusal settles it.

| PR | Viewer | Shown |
|---|---|---|
| Open, draft | `isAuthor` or `canWrite` | Merge section: "Draft. It can't be merged until it's ready for review." **Ready for review** · Open on GitHub |
| Open, not draft | `isAuthor` or `canWrite` | **Convert to draft** link in the Reviewers section's header |
| Open, either | neither | Nothing |
| Merged or closed | anyone | Nothing |

- Both controls come only from a held detail with `merge` and `author` present, the same data Merge uses. While the detail loads, or for a detail cached before those fields were stored, neither shows. The click uses the held `MergeInfo.nodeID` and doesn't fetch anything first.
- **Auto-merge set:** **Convert to draft** is still offered. GitHub's docs don't say what a convert does to auto-merge. One PR timeline suggests it turns it off, and the real-GitHub test settles it. No copy claims either way. The detail read after the answer shows whatever GitHub did. If a draft still has auto-merge set, its Merge section line reads "Draft, with auto-merge set. It can't merge until it's ready for review."
- The Merge section on a draft has always been hidden. It now shows the line above. The merge rules (`MergeGate`) are unchanged: a draft still offers no Merge.
- **Without the permission** (an app install lacking Pull requests write): on a draft, the Merge section shows the permission note in place of **Ready for review**, with its link, as Merge does. **Convert to draft** is just hidden: a header has no room for a sentence. Production already has Pull requests write, so this only matters for an install that hasn't accepted the current permissions yet.
- With a `gh` login it's always ready. A classic token's `repo` covers it. A fine-grained token without Pull requests write gets GitHub's refusal line.
- Who GitHub lets call the two mutations (the author, or write access) is taken from how the web offers them. The docs don't spell it out. A fork contributor without write access relies on `isAuthor`, from `PRDetail.author`.
- Both controls stay visible but disabled while the merge panel is open on this PR, or while any post or merge is on its way for it (`isPostInFlight`). They don't disappear.
- **Convert to draft** has the tooltip "Marks it as still in progress. It can't be merged until it's ready again."

## Interaction

- One click, no confirmation, in both directions. On GitHub, **Ready for review** is a single click too. Either change is undone by the other. Marking ready can notify requested reviewers and CODEOWNERS. That notification is the reason to mark a PR ready, so nobody is surprised by it.
- While the change is on its way, the control reads "Marking ready…" or "Converting…", disabled. It's counted as a post in flight for that PR, so Review's send and Merge wait for it too.
- **GitHub said yes:** the overlay changes `isDraft` on the PR's rows and its detail at once. Then the detail is read again. The Merge section becomes whatever `MergeGate` offers now: a Merge button, a reason, or nothing. The Reviewers link appears or disappears. VoiceOver announces "#88 is ready for review" or "#88 is a draft".
- **While it's on its way,** only the control changes. The state pill and the rows don't dim, as nothing has changed yet. On a yes, the rows refresh and follow the edited row (`refreshShown`, `followEditedRow`), as for other edits.
- **Refused:** one more read comes first. If it shows the state that was asked for (a stale detail sent "ready" for a PR already ready, or someone else flipped it meanwhile), that counts as yes. Otherwise a line above the comment field gives GitHub's reason and **Open on GitHub**: "Couldn't mark #88 ready for review: …" or "Couldn't convert #88 to draft: …". Nothing on screen changes. The line stays until it's dismissed or the next edit, as a sent merge's line does (`staysOnLeaving: true`). The answer often lands with the popover closed, and a refusal nobody saw leaves someone thinking their PR is out for review when it isn't.
- **Not sure** (a timeout, a dropped connection, a server-side error): fresh reads of the detail decide: up to three, 2 seconds apart, as a merge confirms, because GitHub's reads trail its writes by about 1.5 seconds. If one shows the new state, that counts as yes. Otherwise the line, which stays in the same way, reads "Couldn't confirm #88 is ready for review. Check it on GitHub." or "Couldn't confirm #88 is a draft. Check it on GitHub." Nothing is sent again.
- **Account changed while it ran:** the in-flight slot is released for the account that sent it, not the running one. Its line is held for that account, as merge lines are (`heldMergeLines`), and shows on switching back. Nothing changes on screen under the other account.

## Data and GitHub API

- `markPullRequestReadyForReview(input:{pullRequestId})` and `convertPullRequestToDraft(input:{pullRequestId})`, both asking for `pullRequest{isDraft}`. The ID is `MergeInfo.nodeID`, which the detail already reads for drafts too.
- A refusal is a `data` object with a null payload and an error, or an `errors` body with no `data`: nothing ran. The answer's `isDraft` must match what was asked for. If it doesn't, or the answer is anything else, the outcome counts as not sure. The rules match `enablePullRequestAutoMerge`'s.
- No new fields in the detail query.

## Overlay and lists

- A new `EditChange.draft(isDraft: Bool, viewer: String)`, never undone or part-applied, like `.merged`. The overlay sets `isDraft` on the PR in the lists and on the detail, and `MergeInfo.isDraft` too, so `MergeGate` sees the new state before the read lands. `PullRequest.isDraft` and `MergeInfo.isDraft` become settable within the Kit, as `state` and `autoMerge` are.
- **One entry per PR.** Recording a `.draft` replaces any earlier `.draft` entry on that PR, so flipping twice leaves only the latest. A stale read that agrees with the older value can't drop it. The entry settles when a read shows its own value.
- **Auto-merge overlays:** recording a `.draft` drops any `.autoMerge` entry on that PR. Otherwise enabling auto-merge, converting to draft and marking ready within 5 minutes would replay a request GitHub has since turned off, and offer **Cancel auto-merge** on a PR without one. From then on `MergeInfo.autoMerge` comes from GitHub's reads alone.
- **Settling** works as for merges, as lists alone can agree while the held detail is still stale, and `MergeGate` would flip back:
  - `agrees` matches a fetched list copy whose `isDraft` equals the entry's. A PR with no copy in any list counts as agreeing, as `.merged` does. A detail opened from search or from an issue's linked PR has none.
  - `draftsAhead(of: details)`, like `mergesAhead`, holds the entry while the held detail's `MergeInfo.isDraft` doesn't show it yet. `reconcile` takes that set as it takes `holdingMerges`.
  - The 5-minute lifetime still applies.
- **Review wait:** marking ready sets `readyForReviewAt` to the time GitHub answered. That only changes the "🕒 No reviewer" wait, which counts from it. With requested reviewers the wait reads their request times, which a flip doesn't change, so it's unaffected. The `readyForReviewAt` part of the entry stays until a fetched copy carries a ready event at or after the click. Otherwise, if GitHub's timeline lags, the age would jump from 0 back to the PR's full age.
- **Where the overlay shows:** the PR's rows in every list, the detail, `MergeInfo`, and the linked-PR chip on an issue's detail (`LinkedPR.isDraft`). The local `is:draft` filter reads it. Search results from GitHub, the Ask index and Stats aren't overlaid and catch up on their next read.
- **Rows move** as for any refresh. A PR of yours that's no longer a draft can move from Your PRs to Waiting on others, and back. Converting someone else's PR takes it out of Review, which leaves drafts out (`ReviewRules`, `hideDrafts`), and out of a detail walk through Review. Marking someone else's draft ready adds it to Review only when GitHub's search returns it: the overlay changes rows that are there, it doesn't add any.

## Notifications

- **Review requested** stays silent for a PR the viewer marked ready from PullBull in this session (`readiedHere`, like `mergedHere`). GitHub requests code owners when a draft turns ready, so a maintainer who owns the code, or is on an owning team, and marks a contributor's draft ready would otherwise get a banner for their own click. A reviewer requested while it was still a draft is already silent, since the request was there before. The key stays in `readiedHere` for 15 minutes after GitHub's answer (the 5-minute overlay lifetime plus the 10 minutes a search may lag a request). A later re-request from someone else still notifies.
- An own PR that becomes ready to merge after being marked ready can raise **Ready to merge** on the next poll. That's kept: it depends on reviews and checks the viewer may not have looked at, and the banner comes later, not on the click.

## Permissions

- `EditField` gains `draft`, gated by `canWritePullRequests`. `EditPermission.note(for: .draft)` says "Marking ready needs …", in the same form as the other notes. With no installation (`.unavailable`) it says "Marking ready needs PullBull installed here.", as Merge does.
- No GitHub App permission change.

## Docs

- `docs/manual.md`: a **Drafts** section between Reviewing and Merging, covering who can, where each control is, one click, refused, not sure and permissions. The Merging section's "Who can" (line 224) says a draft shows **Ready for review** instead, linking to Drafts. Reviewing's "Who can" (line 204), about drafts, is checked to still read right. The notifications section says Review requested stays silent for a PR you marked ready yourself. Lines 86, 91 and 153 (Your PRs and Stats on drafts) stay true and are left alone.
- `README.md`: the merging row (line 38) adds "**Ready for review** and **Convert to draft**, one click."
- `docs/github-app-setup.md`: the Pull requests write reasons add "marking a pull request ready for review or a draft".
- `SECURITY.md` and the README privacy row: wherever they list what PullBull writes, add the draft state.
- `2026-11-05-merge-and-rerun-design.md`: "A PR gets the Merge section only if it's open, not a draft…" now points here for drafts.
- No shortcuts window change: there's no key.

## Testing

- **Kit tests:** the offer table (author, write access, neither, unknown permission, closed, merged); the permission gate and note; decoding the two mutations' answers (yes, refused, `errors` only, mismatched `isDraft`, unknown); the overlay applied to rows, the detail and `MergeInfo`, and settling; `readyForReviewAt` on marking ready; the controls disabled while in flight and with the merge panel open.
- More Kit tests: one `.draft` entry per PR, a stale read not dropping a newer entry, `.draft` dropping `.autoMerge` entries, `draftsAhead` holding the entry while the detail lags, a PR in no list agreeing, `readyForReviewAt` held until a ready event at or after the click, a refusal whose read shows the asked state counting as yes, the line held per account, and `readiedHere` silencing Review requested.
- **Real GitHub, by click, on the owner's Mac,** in the public throwaway repo `rustycamper/draft-lab`, which the owner deletes afterwards:
  - both directions, several times in a row on one PR;
  - the Merge section changing to Merge after marking ready;
  - converting a PR with auto-merge set, recording what GitHub does, and setting the draft's line to match;
  - whether GitHub refuses "ready" on a PR that's already ready, or treats it as a no-op;
  - a refusal, on a PR the viewer can't change.

## Left to the builder

- Layout of the Reviewers header link at 360 pt. If the title and link don't fit on one row, the link wraps under the title, as Checks does.
- How "Marking ready…" and "Converting…" are styled, as long as they're visibly disabled.
