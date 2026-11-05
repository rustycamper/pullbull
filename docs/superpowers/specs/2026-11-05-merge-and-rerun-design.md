# Merge a pull request and re-run its failed checks

Status: design, for the owner's review. Nothing here is built.

PullBull lets you merge a pull request, set it to merge when its requirements pass, add it to a merge queue, and re-run failed GitHub Actions jobs, all from the PR's detail. With reviews (`2026-11-05-submit-review-design.md`) this finishes the loop: a PR can go from "needs you" to merged without opening the browser.

This design builds on the reviews work: its mode, pinned head, overlay and lag handling. It assumes that branch has landed.

## Why

- Merging is the last step still in the browser. Today PullBull tells you a PR is ready and then sends you to GitHub to press one button.
- A failed check is the most common reason a ready PR stalls, and a flaky job needs only a re-run. That also means a trip to the browser.
- PullBull is open source and its users work in very different setups, so the feature must do the right thing in each without configuration.

## Who uses this

| User | Their setup | What they need |
|---|---|---|
| Solo maintainer | No branch protection, often no required checks, auto-merge off | Merge directly. Nothing stops a red merge but PullBull's warning |
| Team member | Protected branch, required reviews and checks, auto-merge maybe on | Merge when allowed, Merge when ready when not yet. A clear reason when neither is possible |
| Org on a merge queue | Queue required on the branch | Add to queue. A direct merge doesn't apply |
| Admin | Can bypass protection on the web | The same as a team member. PullBull never bypasses |
| Contributor without write access | Reads and reviews | Nothing new shown |
| Signed in before this release | App install still on the old permissions | Everything keeps working. Merge explains what's missing and where to accept it |

## Goals

- Merge from the detail in two deliberate key presses, with what's being merged in view.
- Merge exactly the commit the viewer saw, or nothing.
- Follow the repository's own rules: its merge methods, protection, queue and branch deletion setting.
- Set a PR to merge by itself once its requirements pass, even with PullBull closed.
- Re-run failed GitHub Actions jobs with one action.

## Non-goals

- Editing the merge commit's title or message. GitHub's default for the repository is used. Anyone who wants to write one uses the web.
- Deleting the head branch from PullBull. The repository's "Automatically delete head branches" setting applies, as it does on the web.
- Updating a branch that's behind, resolving conflicts, or closing a PR.
- Merging from a row without opening the PR, and merging several PRs at once.
- Re-running checks that aren't GitHub Actions (see Re-running). That would need Checks write, and most external systems re-run from their own screens.
- Re-running passed jobs, or a whole run, from PullBull.

## Anti-goals

This would be a failure even if it technically worked:

- **A merge nobody meant.** Merging can start a deploy within seconds and can't be taken back with a key press. No single key press may merge, and no key that's ordinary in the rest of the app may complete one.
- **Merging something the viewer didn't see.** A push between looking and confirming must stop the merge.
- **Going around the repository's rules.** PullBull never uses admin bypass, and never offers a way to.
- **A silent red merge.** Failing or running checks must be in view, in the warning colour, at the moment of confirming.
- **Merging twice, or not knowing whether it merged.** After a lost connection PullBull finds out what happened, and never sends again by itself.
- **Reporting a merge that didn't happen, or the reverse.** The screen follows GitHub's answer.
- **A watcher in the app.** Merge when ready is GitHub's own auto-merge. PullBull never holds a pending merge of its own, since it may be closed, asleep or signed out when the checks pass.

## What can be done

The detail reads the PR's merge state on opening, and again on entering merge mode. One action is offered, the first that applies:

| Situation | Action | Bottom row button |
|---|---|---|
| In the queue (`isInMergeQueue`) | None here: leaving the queue is on the web | none, and the detail says "In the merge queue" |
| Auto-merge already set (`autoMergeRequest`) | Cancel auto-merge | **Merging when ready** |
| Merge queue on the base branch (`isMergeQueueEnabled`), requirements met | Add to queue | **Merge** |
| No queue, requirements met | Merge | **Merge** |
| Requirements not met, `viewerCanEnableAutoMerge` true | Merge when ready | **Merge** |
| Anything else | None | none, with the reason in the detail (below) |

"Requirements met" means `mergeStateStatus` is `CLEAN`, `UNSTABLE` or `HAS_HOOKS`.

A PR that's open, not a draft, and on which the viewer has write access (`viewerPermission` of WRITE, MAINTAIN or ADMIN) gets a Merge section. Without those, nothing is shown at all: no button, no reason.

For a viewer with write access who can't act, one line in the detail says why, with **Open on GitHub**:

| State | Line |
|---|---|
| `DIRTY` or `CONFLICTING` | "Merge conflicts. Resolve them on GitHub." |
| `BEHIND` | "Behind the base branch. Update it on GitHub." |
| `BLOCKED` | "Merging is blocked: required reviews or checks aren't met." |
| `UNKNOWN` | Nothing yet: GitHub is still working it out, and the next read decides |

`BLOCKED` covers more than GitHub says through this field, so the line names no specific rule. `viewerCanMergeAsAdmin` is never read.

## Interaction

### Merge mode

Merge mode follows review mode, without the text. It's a panel above the bottom row, in the layout, not over it.

- ⌥⌘G, or the **Merge** button, opens the panel and pins the head on screen. Nothing moves the pin from then on.
- A fresh read of the PR runs on entering. The confirm key does nothing until it's back, and the panel says "Checking…". If that read shows a different head from the pin, the panel closes, the detail is read again, and the failure line says "New commits on #88 since you opened this. Look again, then merge." The viewer then sees the new commits on the page before opening the panel again, which pins them.
- The panel shows:
  - the action as a sentence: "Squash and merge #88 into main", "Add #88 to the merge queue", "Merge #88 into main when ready";
  - the method, when the repository allows more than one (below);
  - a summary line: commits, approvals and checks, for example "3 commits · 2 approvals · 1 of 12 checks failing". The checks part takes the warning colour when any check is failing or running;
  - in the same colour, on a repository with no required checks: "Nothing here requires these checks."
- ⌘↩ confirms, only with the panel open and the read back. Esc closes the panel. So does leaving the detail, closing the popover, or changing account.
- ⌥← and ⌥→ change the method. Arrow keys alone do nothing.
- While the panel is open, ⌘↩ never reaches the comment field, and the panel has keyboard focus. The comment draft is left alone.
- A repeat of ⌘↩ from a held key never confirms.
- Merge when ready shows "Merges by itself once its requirements pass. This keeps working with PullBull closed."

The panel takes focus rather than following the comment field, so review mode's click-away ruling doesn't apply: a click anywhere outside the panel closes it. That's stricter than reviews on purpose. A merge is more consequential than a review, and there's no text to lose.

Merge mode and review mode exclude each other. Opening the panel ends review mode, keeping its text, as any loss of focus does. With the panel open, ⌥⌘V does nothing. A merge on its way counts as a post in flight for that PR, in the same tracking reviews and comments use, so none of the three can start while another is under way.

### Cancelling auto-merge

**Merging when ready** cancels with one click and no panel. It's safe to do by accident, since it sends nothing to the branch and setting it again takes two key presses, and a slow second step here could lose the race with the checks passing. It has no head to pin. It shows at once through the override layer; a refusal, such as the PR having merged already, shows on the failure line and the detail is read again.

### Failing and running checks

When the action is a direct merge and a check is failing or running, the first ⌘↩ doesn't merge. The confirm label changes to "Merge anyway" and a second, separate ⌘↩ merges. This applies to solo repositories above all, where nothing else stands between a red build and `main`. A repository that requires its checks never gets here, since `BLOCKED` offers Merge when ready instead.

### Merge method

The methods offered are the ones the repository allows (`mergeCommitAllowed`, `squashMergeAllowed`, `rebaseMergeAllowed`). The panel opens on `viewerDefaultMergeMethod`, GitHub's own record of the last one used. With a single method there's no choice to show, and the sentence names it. A queue's method is the queue's, so none is shown there.

### Keys

| Key | Does | Where |
|---|---|---|
| ⌥⌘G | Open the merge panel | PR detail |
| ⌥← ⌥→ | Change the method | Merge panel |
| ⌘↩ | Confirm | Merge panel |
| Esc | Close the panel | Merge panel |

Re-run has no key, as it's a single low-risk button beside the failing checks.

## Merging

- **Direct merge:** the `mergePullRequest` mutation with `expectedHeadOid` set to the pin and `mergeMethod`. GitHub refuses a moved head itself, so unlike reviews no separate head check is needed, and there's no gap between check and write.
- **Merge when ready:** `enablePullRequestAutoMerge` with `expectedHeadOid` and `mergeMethod`. Cancelling is `disablePullRequestAutoMerge`.
- **Queue:** `enqueuePullRequest` with `expectedHeadOid`.
- **Sending:** the panel locks and reads "Merging…". It can't be called back. The PR shows as merged at once, dimmed, through the override layer. Queue and auto-merge show their own state the same way.
- **Refused:** the panel closes, the overlay goes, and the failure line gives GitHub's reason with **Open on GitHub**. A moved head reads "New commits on #88 since you opened this. Look again, then merge."
- **Outcome unknown:** a fresh read decides. Merged, or queued, or auto-merge set, counts as success; otherwise the line says "Couldn't confirm the merge of #88. Check it before trying again." Nothing is ever sent twice by PullBull.
- **After merging:** the detail stays open showing the merged state. The row moves as it would after any refresh.
- **No undo.** GitHub has no undo for a merge. Cancel auto-merge is the only take-back, and only before it happens.
- **Lag:** GitHub's reads trail its writes, by up to about 1.5 s measured on reviews. The overlay stays until both the list and the held detail show the new state, as reviews do.
- **Notifications:** merging your own PR raises nothing, as `ChangeDetector.mergedEvents` skips a merge by the viewer. A PR auto-merge merges while you're away should notify. GitHub may report the person who set auto-merge as `mergedBy`, which the existing check would skip: confirm that on real GitHub and, if so, tell the two cases apart using the auto-merge state of the previous fetch.

## Re-running

- A **Re-run failed jobs** button sits in the Checks section's accessory, beside **Open Failing Check**, on an open PR with a failed GitHub Actions run and a viewer with write access.
- It's a single click, with no confirmation: re-running can't lose anything.
- Checks are grouped by their workflow run through `checkSuite{workflowRun{databaseId}}` on each `CheckRun` in the detail query. Each failed run gets `POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun-failed-jobs`.
- A failed run is one with a check run concluding `FAILURE`, `TIMED_OUT` or `CANCELLED`. `ACTION_REQUIRED` isn't: that needs a person to approve the run on GitHub, not a re-run.
- With several runs, each gets its own request. When only some are refused, the ones that started carry on and the failure line says "Couldn't re-run 1 of 3 workflow runs." with **Open on GitHub**.
- Failed checks that aren't from Actions stay as they are, with their link. If all failures are external, the button isn't there.
- While it runs, the button reads "Re-running…". Then the detail is read again, and the existing CI follow takes it from there.
- Refusals show on the failure line as usual. A run too old to re-run is one GitHub refuses by itself.

## Data and GitHub API

- The PR detail query gains: `mergeStateStatus`, `isMergeQueueEnabled`, `isInMergeQueue`, `autoMergeRequest{enabledAt mergeMethod enabledBy{login}}`, `viewerCanEnableAutoMerge`, `viewerCanDisableAutoMerge`, and on the repository `viewerPermission`, `mergeCommitAllowed`, `squashMergeAllowed`, `rebaseMergeAllowed`, `autoMergeAllowed`, `viewerDefaultMergeMethod`. All are confirmed on GitHub's live schema.
- List queries change only as far as the row's merged and auto-merge state needs.
- `mergeStateStatus` can read `UNKNOWN` for a moment after a change, because GitHub computes it on demand. The entering read handles that by reading again a small number of times before saying nothing is available.

## Permissions

This permission list is a working assumption until it's proved on real GitHub. GitHub documents REST permissions, not GraphQL mutations, and every install has to accept a change, so it must be right the first time. See Testing.

- **Contents write** to merge (GitHub lists `PUT .../pulls/{n}/merge` under Contents, with nothing further). `enablePullRequestAutoMerge` and `enqueuePullRequest` may also rely on Pull requests write, which the App already has.
- **Actions write** to re-run (`rerun-failed-jobs` is listed under Actions, with nothing further).
- `AccessChecker` gains `canWriteContents` and `canWriteActions`. `EditField` gains `merge` and `rerun`.
- An install that hasn't accepted the new permissions: Merge and Re-run show a line saying so, with the existing `permissionsReviewURL` link. Everything else carries on.
- A `gh` login uses the token's `repo` scope. Its user's rights decide the rest.
- **Workflow files, unresolved.** GitHub's docs don't settle whether a GitHub App needs the Workflows permission to merge a PR changing `.github/workflows`. A push without it is refused, so a merge may be too. This is the first thing to test on real GitHub. If it's refused, the refusal must read clearly, and the owner decides whether to ask for Workflows write as well.
- The owner changes the App's permissions and description by hand, at release and not before: saving asks every install to accept.

## Docs and copy

- The App's description, `docs/github-app-setup.md`, the README privacy row and `SECURITY.md` currently say PullBull never merges. All change at release, with the exact text given to the owner then.
- `docs/manual.md`: a Merging section after Reviewing, and the key tables.
- The Keyboard Shortcuts window: a Merging section after Reviewing.

## Testing

- Kit tests against a fake GitHub: which action is offered for every state in the table; the summary; two-step confirming on failing and running checks; each outcome; the override and lag rules.
- **The production App can't be used for this:** it lacks both permissions, and changing it asks every install to accept. So real testing uses a separate private test App, owned by the maintainer, with Contents write and Actions write, installed only on the test repo. A build reaches it through `PULLBULL_GITHUB_CLIENT_ID` and `PULLBULL_GITHUB_APP_SLUG` in the git-ignored `Config/Local.xcconfig`.
- **The first thing built is a throwaway test of the permission list,** before the feature: direct merge, auto-merge, enqueue, a PR changing a workflow file, and a re-run, all with that App's token. The production permission list is final only after that.
- Real GitHub, before the PR, needs a Developer ID build, as Sign in with GitHub does. The private `rustycamper/pullbar` repo has a second account for opening PRs. It must exercise: each merge method; a moved head; a required check (auto-merge, which needs enabling on that repo); a PR changing a workflow file; re-running a failed job; and an install on the old permissions. A merge queue needs an org repo; if none is available, that row ships tested against the fake only, and the PR says so.

## Left to the builder

- The panel's exact layout, within the reviews panel's style.
- How many entering reads to try on `UNKNOWN`.
- Whether `ReviewMode` and merge mode share code. Don't refactor reviews to get there.
- Confirm ⌥⌘G is free in every key handler before using it.
- Where **Merge** sits in the bottom row, which must still fit at 360 pt beside Review and Copy branch.
- Leaving `mergeMethod` out of auto-merge on a queue-enabled repository, if GitHub requires that.
