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
- **Auto-merge set:** **Convert to draft** is still offered. GitHub turns auto-merge off when it converts a PR: about a second after the convert, the timeline gets an `AutoMergeDisabledEvent` with reason code `converted_to_draft`. PullBull doesn't call anything for it, and no copy mentions it. The detail read after the answer shows auto-merge gone and the plain draft line. The line "Draft, with auto-merge set. It can't merge until it's ready for review." stays for a draft GitHub ever reports with auto-merge set. A convert doesn't produce one.
- The Merge section on a draft has always been hidden. It now shows the line above. The merge rules (`MergeGate`) are unchanged: a draft still offers no Merge.
- **Without the permission** (an app install lacking Pull requests write): on a draft, the Merge section shows the permission note in place of **Ready for review**, with its link, as Merge does. **Convert to draft** is just hidden: a header has no room for a sentence. Production already has Pull requests write, so this only matters for an install that hasn't accepted the current permissions yet.
- With a `gh` login it's always ready. A classic token's `repo` covers it. A fine-grained token without Pull requests write gets GitHub's refusal line.
- Who GitHub lets call the two mutations (the author, or write access) is taken from how the web offers them. The docs don't spell it out. A fork contributor without write access relies on `isAuthor`, from `PRDetail.author`.
- Both controls stay visible but disabled while the merge panel is open on this PR, or while any post or merge is on its way for it (`isPostInFlight`). They don't disappear.
- **Convert to draft** has the tooltip "Marks it as still in progress. It can't be merged until it's ready again."

## Interaction

- One click, no confirmation, in both directions. On GitHub, **Ready for review** is a single click too. Either change is undone by the other. Marking ready can notify requested reviewers and CODEOWNERS. That notification is the reason to mark a PR ready, so nobody is surprised by it.
- While the change is on its way, the control reads "Marking ready…" or "Converting…", disabled. It's counted as a post in flight for that PR, so Review's send and Merge wait for it too. The comment field goes read-only for the same reason but doesn't read "Sending…", as that word is for a comment.
- **GitHub said yes:** the overlay changes `isDraft` on the PR's rows and its detail at once. Then the detail is read again. The Merge section becomes whatever `MergeGate` offers now: a Merge button, a reason, or nothing. The Reviewers link appears or disappears. The Reviewers section is shown for **Convert to draft** even when the PR has no reviewers, as the link lives in its header. VoiceOver announces "#88 is ready for review" or "#88 is a draft".
- **While it's on its way,** the control changes, the comment field is read-only, and Review and Merge are hidden, as during a merge. The state pill and the rows don't dim, as nothing has changed yet. On a yes, the rows refresh and follow the edited row (`refreshShown`, `followEditedRow`), as for other edits.
- **Refused:** one more read comes first. If it shows the state that was asked for (a stale detail sent "ready" for a PR already ready, or someone else flipped it meanwhile), that counts as yes. Otherwise a line above the comment field gives GitHub's reason and **Open on GitHub**: "Couldn't mark #88 ready for review: …" or "Couldn't convert #88 to draft: …". Nothing on screen changes. The line stays until it's dismissed or the next edit, as a sent merge's line does (`staysOnLeaving: true`). The answer often lands with the popover closed, and a refusal nobody saw leaves someone thinking their PR is out for review when it isn't.
- **Already in the asked state:** GitHub refuses neither flip. "Ready" on a PR that's already ready answers `isDraft: false` with no error and adds no timeline event, so it's done at once. "Convert" on a PR that's already a draft answers a null payload with no error. That counts as not sure, and the first confirming read shows the draft, so it's done after that read. Either way no line shows.
- **Not sure** (a timeout, a dropped connection, a server-side error): fresh reads of the detail decide: up to three, 2 seconds apart, as a merge confirms, because GitHub's reads trail its writes by about 1.5 seconds. If one shows the new state, that counts as yes. Otherwise the line, which stays in the same way, reads "Couldn't confirm #88 is ready for review. Check it on GitHub." or "Couldn't confirm #88 is a draft. Check it on GitHub." Nothing is sent again. The refusal read is a single one: a refusal means GitHub ran nothing, so it needs no waiting. The not-sure reads are `MergeFlow.confirmLanded`'s.
- **Account changed while it ran:** the in-flight slot is released for the account that sent it, not the running one. Its line is held for that account, as merge lines are (`heldMergeLines`), and shows on switching back. Nothing changes on screen under the other account. When the answer comes after a switch, a done flip records no overlay entry and no `readiedHere` key for the account that left: the switch already cleared both, so what is there belongs to the account now running, and touching it would leave a stale "Marking ready…" label or miss a silencing after switching back.
- **Shared with merging:** the flip is a `PendingMerge`, settled by `settleMerge` and failed through `mergeFailed`, so its in-flight slot, held lines and dismissal behave as a merge's do. The refusal line is one string for the overlay's failure text and for the flow, so the two can't drift apart.

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
  - `draftsAhead` is the `.draft` case of `mergesAhead`: it holds the entry while the held detail's `MergeInfo.isDraft` doesn't show it yet, and `reconcile` takes that set as it takes `holdingMerges`. A flip's hold is kept apart from an auto-merge's hold on the same PR, so one settling doesn't release the other. A detail that is merged or closed holds nothing, as there is no draft state left to wait for.
  - The 5-minute lifetime still applies.
- **Review wait:** marking ready sets `readyForReviewAt` to the time GitHub answered. That only changes the "🕒 No reviewer" wait, which counts from it. With requested reviewers the wait reads their request times, which a flip doesn't change, so it's unaffected. The `readyForReviewAt` part of the entry stays until a fetched copy carries a ready event at or after the click. Otherwise, if GitHub's timeline lags, the age would jump from 0 back to the PR's full age. "At or after the click" allows 60 seconds of clock skew between this Mac and GitHub, so a ready event stamped slightly early by GitHub's clock still counts. A PR that was already ready when Ready was clicked keeps GitHub's ready time, and its entry settles on `isDraft` alone. A stale or cached detail can offer Ready on a PR readied long ago, and GitHub's answer then counts as done, but no new ready event comes. Stamping it would show a wait of about 0, and move the row in sort-by-wait, for 5 minutes. The flip carries the PR as shown when it was sent (`pullRequest(for:)`, through the overlay), so a convert made just before still counts as a draft and marking it ready stamps. A PR with no copy anywhere is stamped.
- **Where the overlay shows:** the PR's rows in every list, the detail, `MergeInfo`, and the linked-PR chip on an issue's detail (`LinkedPR.isDraft`). The local `is:draft` filter reads it. Search result rows are overlaid too (`apply(to: SearchResults)`); only which PRs a GitHub search returns catches up on its next read. The Ask index and Stats aren't overlaid and catch up on their next read.
- **Rows move** as for any refresh. A PR of yours that's no longer a draft can move from Your PRs to Waiting on others, and back. Converting someone else's PR takes it out of Review, which leaves drafts out (`ReviewRules`, `hideDrafts`), and out of a detail walk through Review. Marking someone else's draft ready adds it to Review only when GitHub's search returns it: the overlay changes rows that are there, it doesn't add any.

## Notifications

- **Review requested** stays silent for a PR the viewer marked ready from PullBull in this session (`readiedHere`, like `mergedHere`). GitHub requests code owners when a draft turns ready, so a maintainer who owns the code, or is on an owning team, and marks a contributor's draft ready would otherwise get a banner for their own click. A reviewer requested while it was still a draft is already silent, since the request was there before. The key stays in `readiedHere` for 15 minutes after GitHub's answer (the 5-minute overlay lifetime plus the 10 minutes a search may lag a request). Every Review requested on that PR is silent for the whole window, a re-request from someone else included. A re-request after the window notifies. The key is set before the request is sent, as the answer can land after the next poll has already run. A refusal clears it, as does a convert, since the PR is no longer one the viewer made ready. "Not sure" keeps it, as the flip may have landed. The window starts at GitHub's yes, or at the send when the result is not sure. A key is pruned on the next refresh that isn't mid-flight, once 15 minutes (`EditOverrides.lifetime + reviewRequestLag`) have passed. A failed refresh prunes too, so a failed poll can end the window at most one poll early. That is accepted.
- An own PR that becomes ready to merge after being marked ready can raise **Ready to merge** on the next poll. That's kept: it depends on reviews and checks the viewer may not have looked at, and the banner comes later, not on the click.

## Permissions

- `EditField` gains `draft`, gated by `canWritePullRequests`. `EditPermission.note(for: .draft)` says "Marking ready needs …", in the same form as the other notes. With no installation (`.unavailable`) it says "Marking ready needs PullBull installed here.", as Merge does.
- No GitHub App permission change.

## Docs

- `docs/manual.md`: a **Drafts** section between Reviewing and Merging, with the bullets Who can, Where, One click, Done, Refused, Not sure, Auto-merge, Not here and Permissions. The Merging section's "Who can" says a draft shows **Ready for review** instead, linking to Drafts. Reviewing's "Who can" already read right about drafts and is unchanged. The notifications section says Review requested stays silent for a while after you mark a PR ready yourself.
- `README.md`: the merging row adds "**Ready for review** and **Convert to draft**, one click", and the privacy row lists the draft state among the writes.
- `SECURITY.md`: the one-click writes now include marking a pull request ready for review or converting it to draft.
- `docs/github-app-setup.md`: the Pull requests write reasons add "marking a pull request ready for review or a draft", and the list of writes names the draft state.
- `2026-11-05-merge-and-rerun-design.md`: "A PR gets the Merge section only if it's open, not a draft…" points here for drafts.
- No shortcuts window change: there's no key.

## Testing

- **Kit tests:** the offer table (author, write access, neither, unknown permission, closed, merged); the permission gate and note; decoding the two mutations' answers (yes, refused, `errors` only, mismatched `isDraft`, unknown); the overlay applied to rows, the detail and `MergeInfo`, and settling; `readyForReviewAt` on marking ready, and kept on a PR already ready. The controls disabled while in flight and with the merge panel open (`canFlipDraft`, in the app) are checked in the app by hand.
- More Kit tests: one `.draft` entry per PR, a stale read not dropping a newer entry, `.draft` dropping `.autoMerge` entries, `draftsAhead` holding the entry while the detail lags, a PR in no list agreeing, `readyForReviewAt` held until a ready event at or after the click, a refusal whose read shows the asked state counting as yes, the line held per account, and `readiedHere` silencing Review requested.
- **Real GitHub, by click, on the owner's Mac,** in the public throwaway repo `rustycamper/draft-lab`, which the owner deletes afterwards:
  - both directions, several times in a row on one PR;
  - the Merge section changing to Merge after marking ready;
  - converting a PR with auto-merge set: GitHub turns auto-merge off, and the detail shows the plain draft line;
  - flipping a PR already in the asked state, from a stale detail: GitHub doesn't refuse, and no line shows;
  - a refusal, on a PR the viewer can't change.

## Left to the builder

- Layout of the Reviewers header link at 360 pt. If the title and link don't fit on one row, the link wraps under the title, as Checks does.
- How "Marking ready…" and "Converting…" are styled, as long as they're visibly disabled.
