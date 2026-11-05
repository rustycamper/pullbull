# Merge a pull request and re-run its failed checks

Status: merging is built and tested on real GitHub (PR 1). Re-running is designed and ships in the second PR.

PullBull lets you merge a pull request, or set it to merge by itself once its requirements pass, from the PR's detail, and re-run failed GitHub Actions jobs. With reviews (`2026-11-05-submit-review-design.md`, merged as #62) this finishes the loop for most PRs: from "needs you" to merged without opening the browser.

It ships as two PRs: merging first, then re-running. Both use the one permission change, so installs accept once.

## Why

- Merging is the last step still in the browser. Today PullBull tells you a PR is ready and then sends you to GitHub to press one button.
- A failed check is the most common reason a ready PR stalls, and a flaky job needs only a re-run. That also means a trip to the browser.
- PullBull is open source and its users work in very different setups, so the feature must do the right thing in each without configuration.

## Who uses this

| User | Their setup | What they get |
|---|---|---|
| Solo maintainer | No protection, often no required checks, auto-merge off | Merge, with a second step when anything looks wrong, since nothing else stands between a red build and `main` |
| Team member | Protected branch, required reviews and checks | Merge when allowed, Merge when ready when not yet, and a reason when neither applies |
| Org on a merge queue | Queue required on the branch | One line pointing to GitHub, in this version |
| Admin, or anyone who can bypass rules | Can bypass on the web | The same as a team member. PullBull never bypasses |
| Stacked PR author | PRs in a stack | One line pointing to GitHub: merging one merges those below it |
| Contributor without write access | Reads and reviews | Nothing new shown |
| Signed in before this release | Install on the old permissions | Everything keeps working. Merge says what's missing and where to accept it |

## Goals

- Merge from the detail with deliberate, separate steps, with what's being merged in view.
- A direct merge merges exactly the commit the viewer saw, or nothing.
- Follow the repository's own rules: its merge methods, branch rules and branch deletion setting.
- Set a PR to merge by itself once its requirements pass, even with PullBull closed.
- Re-run failed GitHub Actions jobs with one action.

## Non-goals

- Adding to a merge queue. Queues differ enough that this needs its own design, tested on a real one.
- Merging a stacked PR.
- Editing the merge commit's title or message. GitHub's default is used.
- Deleting the head branch. The repository's "Automatically delete head branches" setting applies.
- Updating a branch that's behind, resolving conflicts, or closing a PR.
- Merging from a row, and merging several PRs at once.
- Re-running checks that aren't GitHub Actions. That needs Checks write, and external systems re-run from their own screens.
- Re-running passed jobs, or a whole run.

## Anti-goals

This would be a failure even if it technically worked:

- **A merge nobody meant.** Merging can start a deploy within seconds and can't be taken back. No single key press may merge, and the confirm key must mean nothing else anywhere in the app. ⌘↩ can't be it: it opens GitHub, posts a comment and submits a review, and ⌥⌘V ⌘↩ is a two-key Approve, with G directly above V.
- **Merging something the viewer didn't see.** A push, a retargeted base or a changed state between looking and confirming stops the merge.
- **Going around the repository's rules.** PullBull always sends `bypass_rules: false`, and never offers a way round.
- **A silent red merge.** Anything that looks wrong needs a separate second step, with the reason in view.
- **Merging twice, or not knowing whether it merged.** PullBull finds out what happened and never sends again by itself.
- **Reporting a merge that didn't happen, or the reverse.**
- **A watcher in the app.** Merge when ready is GitHub's own auto-merge. PullBull never holds a pending merge of its own, since it may be closed, asleep or signed out.

## What can be done

A PR gets the Merge section only if it's open, not a draft, and the viewer has write access. Without those, nothing is shown: no button, no reason. The first row that applies decides:

| Situation | Offered | Line in the detail |
|---|---|---|
| Part of a stack (`stack` not null) | Nothing | "Part of a stack. Merge it on GitHub." |
| Merge queue on the base branch (`isMergeQueueEnabled`) | Nothing | "Uses a merge queue. Add it on GitHub." |
| Auto-merge set by the viewer | **Cancel auto-merge** | "Merging by itself when its requirements pass." |
| Auto-merge set by someone else | Nothing | "Auto-merge set by @name. Change it on GitHub." |
| `mergeStateStatus` `CLEAN`, `UNSTABLE` or `HAS_HOOKS` | **Merge** | |
| `BLOCKED` and `viewerCanEnableAutoMerge` | **Merge** (as Merge when ready) | |
| `mergeable` is `CONFLICTING`, or status `DIRTY` | Nothing | "Merge conflicts. Resolve them on GitHub." |
| `BEHIND` | Nothing | "Behind the base branch. Update it on GitHub." |
| `BLOCKED` | Nothing | "This branch's rules aren't met yet." |
| `UNKNOWN` | Nothing yet | None. GitHub is still working it out; read again a few times |

- Each line carries **Open on GitHub**.
- `viewerCanMergeAsAdmin` is never read. An admin who sees `BLOCKED` gets the same line as anyone else.
- `BLOCKED` covers more than reviews and checks (signatures, deployments, locked branches), so the line names no specific rule.
- `viewerPermission` is documented as null when "authenticated as a GitHub App", but it reads correctly on a user token (`ghu_`), so write access comes from it and no REST read backs it up. Null never reads as "no write access" with nothing shown. Unknown enum values decode leniently.

## Interaction

### Merge mode

A panel above the bottom row, in the layout.

- ⌥⌘G, or the **Merge** button, opens it. ⌥⌘G works with the comment field focused, by the same exception ⌥⌘V has. On a PR with nothing offered it does nothing.
- Opening it pins the head, the base and the action, and starts a fresh read. "Checking…" shows until it's back. If the head differs from the one on screen, the panel closes, the detail is read again, and the failure line says "New commits on #88 since you opened this. Look again, then merge."
- What the panel shows is frozen from that read. It doesn't change under the viewer.
- It shows:
  - the action as a sentence: "Squash and merge #88 into main", "Merge #88 into main when its requirements pass";
  - the method, when more than one is allowed;
  - a summary: "3 commits · 2 approvals · 1 of 12 checks failing";
  - the warnings below, in the warning colour;
  - for Merge when ready: "Merges by itself, even with PullBull closed. Commits pushed later by people with write access are included."
- **⌃⌘↩ confirms.** It means nothing else in the app, and the panel shows it on a **Merge** button that also takes a click.
- Confirming is disarmed for 500 ms after the sentence appears or changes, for the key and the click alike, so a reflex or a double click does nothing.
- Esc closes the panel, and so does the **Cancel** that the bottom row's **Merge** button becomes while it's open. So does a click outside it, leaving the detail, closing the popover, or changing account. A click on the panel itself, including **Merge** and the method, leaves it open.
- The panel takes keyboard focus, and it's built with no first responder: opening it releases the comment field, review mode ends keeping its text, and the comment draft is left alone. The key monitor takes every key while the panel is open: ⌃⌘↩, ⌥← ⌥→ and Esc do their work and everything else is swallowed, so ↩ and ⌘↩ do nothing, with no field to type into and no GitHub page opened. ⌘W, ⌘, and ⌘/ run first, so the popover, Settings and the shortcuts window still work. No view takes focus because SwiftUI's programmatic focus depends on the system's keyboard navigation setting, and a key that must never type or merge by accident can't rest on that.
- Esc or Cancel returns focus to the comment field if it had focus when the panel opened, as typing would otherwise go nowhere and ⌘↩ would open GitHub instead of posting. A click outside, or a send, doesn't: the click chose somewhere else, and a send has nothing to return to. Review's own Esc keeps focus as before.
- The panel lives in the bottom bar, above the bottom row, so it shares the detail's width and fits at 360 pt.
- ⌥← and ⌥→ change the method, which resets the second step.
- A held key's repeat never confirms.
- Merge mode and review mode exclude each other: with the panel open, ⌥⌘V does nothing. A merge on its way counts as a post in flight for that PR, in the tracking reviews and comments use. Closing the panel cancels anything before the send; the send is the only exception.
- VoiceOver: the panel announces its sentence and warnings on opening, the method is an adjustable control, and confirming is a named action on the panel.

### Warnings and the second step

For a direct merge, any of these needs a second step:

- a failing or running check;
- no checks at all, which also covers a commit whose checks haven't started;
- a review requesting changes that's still standing.

The first confirm changes the label to "Merge anyway" and disarms for 1 s. A second, separate ⌃⌘↩ merges. A fast double tap can't pass, as the first only arms the second.

### Confirming

Confirming re-reads the PR, as reviews check before sending, and compares it with what the panel showed: head, base, action, check tally and review state. Any difference stops it: nothing is sent. The panel updates and disarms when there's still something to do, and otherwise closes with a line saying why, as closing means the merge went. A moved head and a closed PR close it with their lines. So a check that failed while the panel sat open is seen before anything merges. If GitHub hasn't worked out the merge state yet (`UNKNOWN`) on that read, nothing is sent, as PullBull never sends on a state GitHub hasn't settled. That costs, rarely, one more open.

The check tally maps `STALE`, `ACTION_REQUIRED` and `STARTUP_FAILURE` to failing, and any state it doesn't know to running. An unknown state must warn and never pass, at the price of a second step that wasn't strictly needed. The summary shows one check part, failing first, and never failing and running together: the warnings list both counts, so nothing is hidden when it matters.

### Merge method

The methods offered are what the repository allows (`mergeCommitAllowed`, `squashMergeAllowed`, `rebaseMergeAllowed`), narrowed by the base branch's rules: the `pull_request` rules' allowed methods, intersected when there are several; required linear history, when a ruleset sets it; and `canBeRebased` for rebase. An App can't read linear history set by classic protection: `baseRef{rules}` is empty there and `branchProtectionRule` is forbidden without Administration read, which isn't worth asking every install for. Merge commit stays offered on those branches, and GitHub refuses it with "Merge commits are not allowed on this repository." The panel opens on `viewerDefaultMergeMethod` if that's allowed, else the first that is. With one method, the sentence just names it.

### Cancelling auto-merge

**Cancel auto-merge** takes one click and no panel, as on the web, and only for the viewer's own request (`viewerCanDisableAutoMerge`). Setting it again takes the full steps, and a slow cancel could lose to the checks passing. Someone else's request can't be cancelled from PullBull, since it may carry a commit message PullBull can't restore. A refusal reads "Couldn't cancel auto-merge on #88: …" and an unclear answer "Couldn't confirm auto-merge was cancelled on #88. Check it on GitHub." Both have their own lines, since a cancel that failed unnoticed is an unwanted merge. An unclear answer gets one read: a stale "still set" only sends the viewer to check.

### Keys

| Key | Does | Where |
|---|---|---|
| ⌥⌘G | Open the merge panel | PR detail |
| ⌥← ⌥→ | Change the method | Merge panel |
| ⌃⌘↩ | Confirm | Merge panel |
| Esc | Close the panel | Merge panel |

## Merging

- **Direct merge:** `PUT /repos/{owner}/{repo}/pulls/{n}/merge-async` with `sha` set to the pin, `merge_method`, `merge_action: direct_merge` and `bypass_rules: false`. GitHub recommends this API, and `mergePullRequest` has no bypass field, so it can't honour the anti-goal. `sha` makes GitHub refuse a moved head.
- **Its answers:** each has a `status` and a `details` object. `202` with `details.uuid`: poll `GET .../merge-async/{uuid}`, with no body, until it's no longer `pending`. `200`: already merged. `409`: a request is already pending, and `details.uuid` names it, so poll that one. `400`: refused, with the reason in `details.message`, as with a moved head ("Pull request head branch was modified.") or a closed PR. Rules fail at poll time, not at send, so a poll's `failed` is a refusal. GitHub's reasons can span lines, so whitespace runs collapse to one space.
- **Merge when ready:** `enablePullRequestAutoMerge` with `expectedHeadOid` and `mergeMethod`. A panel opened on `BLOCKED` can turn `CLEAN`, and GitHub then answers "Pull request Pull request is in clean status", matched on "clean status": that becomes a fresh read and the `mergeChanged` line ("#88 changed before it could merge. Look again, then merge."), as the send has already closed the panel, not raw text. A refusal is a `data` object with a null payload and an error typed `UNPROCESSABLE` or `FORBIDDEN`. A body of `errors` with no `data` object is also a refusal, as nothing executed. Any other answer, including a server-side type such as `INTERNAL`, leaves the outcome unknown and a fresh read decides, as the mutation may have landed: telling someone nothing happened when it may have is the worst failure here. That costs, at worst, one extra read.
- **Sending:** once the confirming read checks out, the panel closes and the PR shows as merged at once, dimmed, through the override layer, turning solid when GitHub confirms. The comment field stays read-only until the answer, with its normal hint rather than "Sending…", as no draft is posting. The panel has no "Sending" or "Merging" state of its own. The row and the pill were already optimistic, so a locked panel only made the viewer wait about 4.5 s, measured, for GitHub's answer; the dimming says it isn't final. A refusal comes back as the failure line, which can show a brief "Merged" before it, when a rule fails at poll time. A send can't be called back, and Merge stays hidden until the answer, so it can't be sent twice.
- **Polling:** GitHub marks the poll's GET `max-age=60`, so through the URL cache the first `pending` stood in for every later poll and the merge never seemed to finish (12 of 12 pending, against merged on the third poll when the cache was skipped). Merge polls and the reads that decide an outcome skip the URL cache and go to GitHub each time. Only REST requests need this (`restRequest`); GraphQL reads are POSTs, which aren't cached.
- **In the lists:** while a direct merge's overlay is live, its row stays where it was, dimmed and not counted, as Review's dimmed rows are, so the badge drops at the send and a refusal restores it. It stays in Review, Mine and Team. A Review row keeps its reason chip; "You approved · not counted" shows only on a dimmed row with no reason, as a PR the viewer merged without approving was never approved. Without this the row would vanish, or jump to Team, and then back on a refusal. Recently closed leaves out a key only while a Review, Mine or Team row actually keeps it, so one PR is never listed twice and never in none: a stale detail can hold the overlay after a refresh moved the PR into Recently closed.
- **Refused:** one more read comes first. If it shows the PR merged or closed, that's the outcome, ahead of everything else, as someone else's merge can land while ours waits. If it shows a moved head, that's the cause, whatever GitHub's wording, so a change in GitHub's text can't hide it. The overlay goes, and the failure line gives GitHub's reason with **Open on GitHub**, and a 400's reason comes from `details.message`. A moved head reads the `mergeHeadMoved` text, "New commits on #88 since you opened this. Look again, then merge." A state that changed reads the `mergeChanged` text, "#88 changed before it could merge. Look again, then merge." `.changed` with no panel is only reached after a send, as closing the panel cancels before it, and nothing merged, so the line says so.
- **Merged or closed meanwhile:** when the read after a refusal shows the PR closed, the overlay is dropped, as left in place it would claim a merge for up to 5 minutes. When it shows it merged, the overlay stays, as the PR is merged, and its key leaves the set of merges made here: our merge didn't land, and someone else's should notify. That can cost one extra banner. Failure lines clear when the viewer leaves the item they're about, as "New commits on #29" read wrongly on #32. A line about a merge or a cancel that was really sent stays until dismissed or the next edit, because the app can't tell a seen line from an unseen one: the answer takes about 4.5 s, so it often lands with the popover closed, and reopening counts as leaving. Losing that line is a silent reopen, or a cancel that failed unnoticed, which is an unwanted merge. Comment and review lines still clear, as their text stays in the field. Confirming another merge doesn't clear a sent line about another PR. There's one failure slot, so a later line replaces an earlier one. Only merge lines are held per account, so a merge line for one account isn't shown under another; a comment's or review's line is dropped when another account runs. Successes are not held, since nobody is left not knowing.
- **Outcome unknown,** including a poll that doesn't finish in reasonable time: fresh reads decide, matched to the action sent: up to three, 2 s apart, a failed read counting as one. GitHub's reads trail its writes by about 1.5 s, so one read can miss a merge that landed. Otherwise the line says "Couldn't confirm the merge of #88. Check it before trying again." Nothing is ever sent twice.
- **After merging:** the detail stays open showing the merged state. The row moves as after any refresh.
- **No undo.** Cancelling auto-merge is the only take-back.
- **Lag:** GitHub's reads trail its writes, by about 1.5 s measured on reviews. The overlay stays until the held detail shows the merge, up to the 5-minute lifetime. A merged PR leaving the lists counts as the lists agreeing. An auto-merge change, set or cancelled, settles once the detail shows the PR merged or closed, as nothing is left to compare. A read just after approving can also show a stale `BLOCKED`, so that's retried like `UNKNOWN`, but only after a review sent from PullBull, three reads 2 s apart; `UNKNOWN` alone is read the same way.
- **Notifications:** `mergedBy` is whoever set auto-merge, so it can't tell a viewer's own merge from someone else's. `ChangeDetector.mergedEvents` therefore stays silent only for a merge made from PullBull in this session (`mergedHere`), and notifies for every other merge of the viewer's own PR: a teammate's, one the viewer made on GitHub, and a **Merge when ready** that merged by itself, which notifies like any merge that happened while the viewer was away. The Merged toggle's note therefore reads "When it's merged outside PullBull", not "When someone else merges it". An own PR merged by auto-merge while away reads "by <you>", which is accurate and stays. A teammate's PR the viewer set to auto-merge raises nothing in this version, as merged notifications come for the viewer's own PRs.

## Re-running

- A **Re-run failed jobs** button in the Checks section's accessory, beside **Open Failing Check**, on an open PR with a viewer who has write access. Its tooltip says "Re-runs the failed jobs and the jobs that depend on them", since a dependent job can deploy.
- One click, with no panel.
- Offered only for runs that have finished (`checkSuite.status` `COMPLETED`), as a run with a failed job can still have others running.
- A failed run has a check run concluding `FAILURE`, `TIMED_OUT` or `CANCELLED`. `ACTION_REQUIRED` needs a person to approve the run, and `STARTUP_FAILURE` can't be re-run, so neither counts.
- The run ID comes from the check's `detailsUrl`, which holds it. A failed check with no run ID there is left out. Each failed run gets `POST .../actions/runs/{run_id}/rerun-failed-jobs`.
- All of a PR's checks are paged in for this. The detail's `contexts(first:50)` can miss failures on a big PR: `grafana#134874` has 2 failures in 127 contexts, none in the first 50.
- If only external checks failed, the button isn't there.
- It reads "Re-running…", then the detail is read again and the existing CI follow takes over.
- When some runs are refused, the rest carry on and the line says "Couldn't re-run 1 of 3 workflow runs."

## Data and GitHub API

- The PR detail query gains: `mergeable`, `mergeStateStatus`, `isMergeQueueEnabled`, `stack{size}`, `autoMergeRequest{enabledBy{login}}`, `viewerCanEnableAutoMerge`, `viewerCanDisableAutoMerge`, `canBeRebased`, `commits{totalCount}`, a check tally from `checkRunCountsByState`, and on the repository `viewerPermission`, the three `*Allowed` fields and `viewerDefaultMergeMethod`, and `baseRef{rules}`.
- The summary's check tally comes from those counts, not from `detail.checks`, which stops at 50.
- `mergeStateStatus` needs no preview header.

## Permissions

Measured on real GitHub with `ghu_` tokens from a test App, as GitHub documents REST permissions, not GraphQL mutations, and every install has to accept a change.

- **Contents write** to merge, and to enable and cancel auto-merge. With Pull requests set to read-only, both auto-merge calls still worked and `merge-async` was still accepted.
- **Actions write** to re-run. On a run still going, GitHub answers `403` "This workflow is already running".
- **Workflow files need nothing more.** The App merged a PR adding a file under `.github/workflows` without Workflows write, and so did a `gh` token without the `workflow` scope.
- **`bypass_rules: false` stops a bypass.** An account able to bypass was refused at poll time on a failing required check, under a ruleset and under classic protection. The same call with `true` merged, so the bypass was real.
- **The detail query needs no new permission.** It answers without errors on an install on the old permissions. `checkSuite{status}` is readable there, but `workflowRun` is refused without Actions permission, so it's never fetched.
- `viewerPermission` reads correctly on a `ghu_` token, so no REST read backs it up.
- `AccessChecker` gains `canWriteContents` and `canWriteActions`. `EditField` gains `merge` and `rerun`.
- **An install on the old permissions:** Merge and Re-run show a line saying so, with the existing `permissionsReviewURL` link. Everything else carries on.
- **No install on the owner, or a repository left out of a selected-repositories install:** a line, not silence. The second reports ready and is refused, and that refusal must read clearly.
- The owner changes the App's permissions and description by hand, at release and not before: saving asks every install to accept.
- **Release:** the release that carries both PRs asks for Contents write and Actions write in one acceptance. Merging alone needs only Contents write; if the first PR were released alone, that is all it would ask, and Actions write would join with re-running.

## Docs and copy

- `docs/manual.md` has a Merging section after Reviewing, with the key tables. Its Reviewing section lists merging as something reviews don't do, which stays true: a review doesn't merge.
- The Keyboard Shortcuts window has a Merging section after Reviewing.
- The Merged notification toggle's note, and the manual's notification table, say a merge outside PullBull notifies, including the viewer's own.
- The App's description, `docs/github-app-setup.md`, the README privacy row and `SECURITY.md` no longer say PullBull never merges. They say it merges only what the viewer confirms, never bypassing the repository's rules; neither names Contents write, which `docs/github-app-setup.md` and the App's own permissions carry. The owner changes the App's own description and permissions by hand at release, with the exact text given then. Actions write and the wording about re-running join the same files with the second PR.

## Testing

**The test setup:**

- The public repository `rustycamper/merge-lab`, with auto-merge on, a second account on Write, a ruleset on `main` requiring `test`, and a `classic` branch under classic protection. `rustycamper/pullbar` can't do this: on a free plan a private repo has no branch protection, rulesets or auto-merge, so it can't produce `BLOCKED` or Merge when ready.
- A separate test GitHub App, installed only there, with the production permissions plus Contents write and Actions write. The production App can't be used: it lacks them, and changing it asks every install to accept.
- A build reaches it through `PULLBULL_GITHUB_CLIENT_ID` and `PULLBULL_GITHUB_APP_SLUG` in the git-ignored `Config/Local.xcconfig`. It needs a Developer ID build, as Sign in with GitHub does.
- Sign in with the second account: a test build shares the Keychain item and would otherwise overwrite the production sign-in.

**The permission test** ran first, on that App's tokens and on a token from the production App. Its results are under Permissions.

**Kit tests** against a fake GitHub: every row of the action table; the method narrowing; the second step and arming; the confirm comparison; each `merge-async` answer and poll result; the override, list and lag rules; the key routing.

**Run on real GitHub, by click, on the owner's Mac** (merge-lab, Developer ID builds):

- Each merge method: merge commit, squash and rebase.
- The panel closing at the send, and Esc closing it at once.
- A moved head stopping the merge with the line, and a check changing with the panel open stopping it.
- The second step on a failing check and on no checks, and Esc resetting it.
- **Merge when ready**: set, cancelled, set again, and merged by itself after a re-run, with the app showing Merged and notifying.
- ⌘↩ and ↩ doing nothing in the panel; a click outside closing it, Cancel staying closed, a click on **Merge** or the method keeping it open, a click on the comment field closing it and taking focus; ⌥⌘G from the field then Esc keeping the text and the focus.
- The layout at the default width.

Two merges happened that weren't test steps (#40 and #43): each was the owner's click on **Merge**, two deliberate actions as on GitHub, not a fault.

**Not run on real GitHub or a Mac:**

- ⌃⌘↩. Another app takes it on the owner's Mac, so it never reached PullBull, and the panel's **Merge** button did the confirming in every test. This is a known limit: the chord is a default that may be taken on other Macs. The button always works, so a taken chord can't lock anyone out, and no global hotkey can make a merge happen, as one only stops the key arriving. Also unrun by hand: keypad Enter as a confirm, the next panel opening after the popover closes, VoiceOver, the hairlines and the panel's height with every warning, a 360 pt popover, IME input, and ⌘, and ⌘/ with the panel open.
- An install on the old permissions, and a repository left out of a selected-repositories install.
- A merge queue and a stacked PR, which only show a line.

**Re-running** is tested with PR 2.

## As built

Choices the design left open:

- The panel is laid out in the reviews panel's style, in the bottom bar, and fits at 360 pt. **Cancel auto-merge** is a button on the line that says auto-merge is set.
- `UNKNOWN` and a stale `BLOCKED` after a review sent here are read up to three times, 2 s apart, in the detail's refresh.
- Review mode and merge mode share the comment field's release and focus code, not their state. Reviews were not refactored.
- ⌃⌘↩ was audited in every key handler. A text view doesn't type it, the status picker applies only on plain Return, and no menu item or `NSStandardKeyBindingResponding` entry takes it. The one way it reaches another handler is outside the key handlers: a user can record it as PullBull's own show-or-hide shortcut, which makes the popover hide and the panel close, and fails safe.
