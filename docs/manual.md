# PullBull manual

Every tab, key and setting. Overview: [README](../README.md).

[Install](#install) · [Sign in](#sign-in) · [Pull Requests](#pull-requests) · [Issues](#issues) · [Relationships](#relationships) · [Stats](#stats) · [Search](#search) · [Ask AI](#ask-ai) · [Keyboard](#keyboard) · [One repo](#one-repo) · [Sorting](#sorting) · [Settings](#settings) · [Data](#data) · [Build](#build-from-source)

## Install

```bash
brew install --cask rustycamper/tap/pullbull
```

Or the zip from [Releases](https://github.com/rustycamper/pullbull/releases/latest).

- Move to /Applications **before** first launch
- macOS 14+. Developer ID signed, notarised
- Updates via [Sparkle](https://sparkle-project.org), daily once you allow it
- Check now: Settings → General, or right-click the menu bar item

## Sign in

| | Sign in with GitHub | GitHub CLI |
|---|---|---|
| How | Code on github.com | Uses an existing `gh` login |
| Token | Writes only what you pick, renews itself | Fetched from `gh` each launch |
| Stored | Keychain | Memory only |
| Orgs | Owner installs the app → **Request Approval** | Scopes `repo`, `read:org` |
| Org board | App's Projects permission | Scope `read:project`; `project` to set Status |
| Personal boards | No | `read:project`; `project` to set Status |

The first-run screen offers your `gh` logins first if there are any. PullBull never picks one by itself.

### GitHub CLI setup

**Set Up GitHub CLI** opens a checklist that ticks itself off. PullBull runs nothing.

```bash
brew install gh
gh auth login --web -s read:project     # new login
gh auth refresh -s read:project         # existing login
```

Without `read:project`: Board shows the command to add it, Assigned groups by repo, and All has no Rest of the board or Status chips.

### No organization

- Pick repos on GitHub (all or some). The window closes once GitHub confirms
- Your own repos only, no Team chip or section
- Board: your first personal board, needs a `gh` login with `read:project`
- Change repos: Settings → Account → **Change Repositories…**

### Signed out

| | |
|---|---|
| Token revoked or expired | "Signed out of GitHub" + Sign In. Icon dims |
| Settings → Sign Out… | Removes the account and its cache. `gh` stays logged in |
| Revoke the app | [GitHub → Settings → Applications](https://github.com/settings/apps/authorizations) |

## Menu bar item

| | |
|---|---|
| Click · <kbd>⌃</kbd><kbd>⌥</kbd><kbd>P</kbd> | Open or close (shortcut: Settings → General) |
| Right-click | Settings · Keyboard Shortcuts · Stats · About PullBull · Check for Updates (release builds) · Quit. The same menu as the footer gear |

## Pull Requests

<kbd>⌘</kbd><kbd>1</kbd>

One list in sections, scoped by chips above it. It opens on All, or on the choice in Settings → General → Pull requests open on: All · Last used · Needs you · Mine · Team. A chip you pick lasts until the popover closes. Last used reopens the last chip you left, also after a relaunch. A choice whose chip isn't shown (Team without an org) opens on All.

| Chip | Shows |
|---|---|
| All | Needs your review, Your PRs, Waiting on others, then Recently closed and Team, folded. No count |
| Needs you | PRs waiting on you or your team. Icon says why: requested, team, re-requested, new commits. Lines added and removed (`+120 −30`), not in compact cards. Oldest first: [Sort](#sorting) |
| Mine | Your PRs, Waiting on others, folded Recently closed: yours closed or merged in the last 7 days. Review pills, checks, **Ready to merge** (a green glyph) |
| Team | Other open PRs in the org, not the ones in Needs you. Group by author: Settings → General. No chip without an org |

- **Chips:** click one to scope the list, click it again for All, or press <kbd>←</kbd> <kbd>→</kbd>. Each shows its count (Needs you in the accent colour when above zero); the counts ignore the repo and time focus
- **Not grouped by repo:** All and Mine are grouped by their sections, and each row names its repo after the number (`#1305 widgets`). Needs you and Team group by repo, or by author for Team, as before

| Section | Rows | Header |
|---|---|---|
| Needs your review | The Needs you rows, including "You approved" rows when Hide approved is off | 🔔 in the accent colour |
| Your PRs | Your open PRs that need you: ready to merge, changes requested, failing checks, conflicts, or a draft | PR glyph |
| Waiting on others | Your other open PRs: waiting on review, or on checks still running | 🕒 |
| Recently closed | Yours closed or merged in the last 7 days | archive box |
| Team | Team's rows | two people |

- **The split:** a PR of yours is in Your PRs when it is ready to merge, a latest review requests changes, its checks failed, it has conflicts or it's a draft. Any other is in Waiting on others. A run that was only cancelled reads as failed in GitHub's rollup, so that PR is in Your PRs
- **Once only:** a PR in Needs your review isn't repeated in Team, a dimmed one included. With Hide approved on, an approved PR isn't in Needs your review, so it stays in Team
- **Empty sections** hide. A section of only dimmed rows still shows, with a count of 0. When nothing is waiting on your review and Your PRs is empty, All starts with "Nothing needs you" and the sections that have rows follow
- **Folds:** click a header on All or Mine. Needs your review, Your PRs and Waiting on others start open, Recently closed and Team folded. Kept across relaunches, the same for every account. Needs you and Team have no header and no fold. The selected row stays selected through folds and chip changes
- **All's footer link** goes to your PRs on GitHub

A PR with merge conflicts shows a **Conflicts** note in every section.

A PR waiting on review shows who it waits on and for how long (🕒 @dana 3d, "+1" when more are asked). One nobody was asked to review shows 🕒 No reviewer 5d, counted from when it was ready for review. In Needs your review it's just 🕒 2d. Hover for every reviewer's wait. Not in compact rows.

> [!NOTE]
> Ready to merge = approved, no changes requested, checks green or none, no conflicts, not a draft. It doesn't see branch protection (required review count).

- **Pending CI:** while checks run on your PRs, PullBull checks up to 5 of them (newest commits first) every 30 s, for up to 20 minutes each, so *CI failed* and *Ready to merge* arrive sooner. Not while offline or rate-limited. Settings → General → Check my pending CI more often
- **Detail:** who opened it and when it was last updated (the row's age), or when it was merged or closed · assignees, labels and reviewers (click to change) · the issues it closes ([Linked issues](#relationships)) · checks (a cancelled run reads cancelled, not failed, though GitHub still marks the PR failed) · description (long ones fold) · the newest comments, with earlier ones counted above, and the text of each person's latest review among them, tagged Approved, Changes requested or Reviewed · files (click one to open its diff on GitHub). A [comment field](#commenting), with a **Review** button when you can [review](#reviewing) the PR and a **Merge** button when you can [merge](#merging) it, is pinned at the bottom. The header has **Open on GitHub**, Copy Link and Refresh, and **Copy branch** sits at the end of the head branch's chip. Markdown incl. `<details>`. **Open Failing Check** beside failed checks, and [**Re-run failed jobs**](#re-running-failed-jobs) when you can
- **Labels:** up to two chips per row (none in compact cards), each led by a dot in the label's GitHub colour, then "+N". A `~label` search puts that label first. The detail's Details card lists them all
- **Right-click a row:** [Reviewers…](#editing) · [Assignees…](#editing) · [Labels…](#editing) · copy branch, link or Markdown link · open on GitHub · copy checkout command · open files changed (or changes since my review) · open failing check (when checks failed) · show only this repo · show only updated · search author
- **Right-click a group header** (repo, author): **Open All *N* on GitHub**, from two PRs up; above 8 it asks first. An author header's menu also offers **Search @*login*** and **Show Only Updated**. Headers in search results get their section's or tab's menus, without Show Only Updated
- **Footer:** account · refresh · open on GitHub · Stats · the gear, a menu with Settings, Keyboard Shortcuts, Stats, About PullBull, Check for Updates (release builds) and Quit. Turns amber with **Retry** when a refresh fails
- **Switch account:** click the account in the footer, or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>A</kbd>. Lists your signed-in accounts, then GitHub CLI logins, each with the org it opens in; then Add Account… and Account Settings…. Each account comes back with its last org, and each org with its last board

## Issues

<kbd>⌘</kbd><kbd>2</kbd>

One list scoped by chips, as on [Pull Requests](#pull-requests). It opens on All, or on the choice in Settings → General → Issues open on: All · Last used · Assigned · Created · Board. A chip you pick lasts until the popover closes. Last used reopens the last chip you left, also after a relaunch. The Board chip is always shown: it is where a board is chosen and missing access is explained. Click the selected chip, other than All, to go back to All.

| Chip | Shows | Grouped by |
|---|---|---|
| All | Assigned to you, You opened, Rest of the board | Flat sections; each row shows its repo and, on the board, its Status as a chip |
| Assigned | Issues assigned to you | Board Status, then "Not on board". Done folded: done on the board, still open. Repo without a board |
| Created | Issues you opened | Repo, or none (Settings → General) |
| Board | All open issues on the board | Board Status. Done folded, last 14 days |

- **Sections on All:** **Assigned to you**, **You opened** (Created without the issues assigned to you) and **Rest of the board** (open board items in neither section, folded, only while a board is readable). An issue sits in the first section that holds it. Issues done on the board are in none; they stay on Assigned's Done, Board's Done and Created. Without a readable board nothing is left out as done and Rest of the board is absent
- **Counts:** the chips count what the tabs did: Assigned and Board without their Done groups, Created its open issues. An empty list shows no count; a failed refresh keeps the count with a warning, and an unreadable board reads "–". All has no count. Created can count more than You opened, since it keeps issues also assigned to you; its tooltip says so
- **Loading and failures:** a list still loading shows its header with placeholder rows. One that failed with nothing kept shows "Couldn't load assigned issues" (or created) with the error in its tooltip. One that failed with rows kept shows them with a warning on its header, and All's chip carries the warning too ("Didn't update · Assigned, Created"). All reads "Nothing assigned to you" above the other sections when Assigned is loaded and empty, and "No open issues assigned to you or opened by you" when every section is
- **Status lanes:** the glyph takes the Status colour set on the board, on Board and Assigned
- **Fold a lane:** click its header. Status, "No status" and "Not on board" fold; repo groups don't. Needs a board
- **Folds:** kept per tab and per board, across relaunches. Folding on Board leaves Assigned as it is. All's section folds are kept apart from the lanes': You opened and Assigned to you start open, Rest of the board folded
- **Searching:** every lane shows open; folds come back when the search ends; open issues done on the board show under Done only when the results are laid out like Assigned or Board, not on Created; closed ones go under Closed
- **Done:** click its header to unfold. Never counted
- **Labels:** chips as on [pull requests](#pull-requests). The board card lists them all
- **Switch board:** on the Board chip, click its name in the filter row, or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>B</kbd>
- **Right-click a row:** [Status](#editing) (when a board is shown) · [Assignees…](#editing) · [Labels…](#editing) · copy link or Markdown link · open on GitHub · show only this repo · show only updated · search author
- **Right-click a group header** (a Status lane, No status, Not on board or a repo): **Open All *N* on GitHub**, from two issues up; above 8 it asks first. Done has none. Headers in search results get the chip's menus, without Show Only Updated
- **Detail:** who opened it and when it was last updated (the row's age), or when it was closed · board card (incl. labels) · [relationships](#relationships) and sub-issues · linked PRs · description (long ones fold) · the last two comments, with earlier ones counted above. Markdown incl. `<details>`. A [comment field](#commenting) is pinned at the bottom. The header has **Open on GitHub**, Copy Link and Refresh

## Relationships

The issue detail shows what an issue is tied to, and the pull request detail the issues it closes. They're read-only: change them on GitHub.

- **Relationships:** Parent, Blocked by and Blocking, in one card. Blocked by and Blocking say how many are open ("1 open") or "all closed". An issue with none shows nothing extra
- **Sub-issues:** with how many are done ("1 of 3 done")
- **Linked issues** on a pull request: the issues it closes, or "No linked issues"
- **Rows:** state glyph, title, `#N · open` (or `closed`, `not planned`), with `owner/repo#N` for another repo. Closed ones are listed too. Over 20 in a group, "+N more on GitHub" opens the item in the browser
- **Click a row** to open it in PullBull, as with linked PRs. Keep following links: Back (<kbd>Esc</kbd>) steps back through each item you opened, then to where you started, and is titled with the previous item's number. Opening an item you've already passed goes back to it, so you never loop. <kbd>⌥</kbd><kbd>↓</kbd> <kbd>⌥</kbd><kbd>↑</kbd> step only on the item you started from

## Stats

<kbd>⌘</kbd><kbd>3</kbd> or the gear → **Stats**, from the list or the search; the chart button is in the list's footer only. How your reviewing and your pull requests have gone over the last 7, 30 or 90 days, each compared with the period before. It slides in like a detail: <kbd>Esc</kbd>, <kbd>⌘</kbd><kbd>[</kbd> or the back button return to where you were, search query kept. Nothing is counted inside PullBull and no time is estimated: every figure is a GitHub query.

- **Periods:** This week, This month and 90 days are whole local days ending today (today and the 6, 29 or 89 days before), not calendar weeks or months. The comparison is the same number of days just before. <kbd>←</kbd> <kbd>→</kbd> move between the chips; the choice is kept
- **Account and scope:** the ones on screen: the account and org the lists show, or your repositories in the personal scope. Only repositories PullBull can see count. Other accounts aren't added in

| Card | Figure | Means |
|---|---|---|
| Your reviews | Reviews | Reviews you submitted on other people's PRs in the period: approved, changes requested, commented or dismissed. Unsent reviews and replies on your own PRs don't count |
| | Turnaround | Median time from a review request (to you or one of your teams) to your response. Reviews nobody asked for, and a second review on the same request, aren't samples |
| | Bars | Reviews per day, today's in the accent colour, with the busiest day's count above its bar. A day with none is a small grey stub. Underneath, the weekday initials for a week, or the first and last dates for 30 and 90 days. Hover a day for its count and date |
| Your pull requests | Merged | Your PRs merged in the period |
| | Time to merge | Median of merged minus opened, over those PRs |
| | First review | Median wait for the first review by someone other than you, over your PRs opened in the period. It runs from when the PR was last marked ready. Drafts, unreviewed PRs and reviews made while a draft aren't samples; the hover says how many PRs still wait |
| | Top reviewers | Up to three people who reviewed the most of your PRs opened in the period. A person counts once per PR, however many reviews. Bots and you are left out |
| Right now | Waiting on you longest | The PR in Needs your review that has waited longest. Two rows like the list's; <kbd>↑</kbd> <kbd>↓</kbd> choose, <kbd>Return</kbd> opens the detail (<kbd>Esc</kbd> comes back), <kbd>⌘</kbd><kbd>Return</kbd> opens it on GitHub, <kbd>⌘</kbd><kbd>C</kbd> copies its link. Right-click offers only the copy and open items. The Settings filters apply |
| | Your PR waiting longest | Your open PR with no review yet that has waited longest |
| Issues | Closed | Issues assigned to you now that closed in the period, completed or not planned. An issue unassigned after it closed isn't counted |
| | Opened | Issues you opened in the period |
| | Comments | Comments you wrote in the conversation of issues and PRs. Review comments on code aren't counted |

- **Medians:** shown as `42 m`, `3 h 10 m`, `2 d 4 h`. A dash means nothing to measure, or the query failed; the hover says why. A comparison is left out when either side has no value. Hover a figure for how many items it covers
- **Caps:** each source reads at most the newest 100 PRs in scope for the period (comments: your latest 500). Reviews come from the 100 most recently updated PRs you reviewed since the period began; for the comparison that search reaches into the current period, so a busy current period uses up some of its 100. When more exist, the hover says so and the footer adds "· from latest 100". Counts GitHub gives exactly stay exact; counts tallied from loaded items read "137+". Days the chart can't vouch for are left out, not drawn empty
- **Not shown:** Status moves on a board. GitHub records them only on each issue, so they can't be counted without missing some
- **Refreshing:** the result is kept for 15 minutes per account, scope and period, in memory only. The refresh button and <kbd>⌘</kbd><kbd>R</kbd> fetch again. Nothing polls. A failure shows a line with **Retry** and keeps what was on screen. Hover the footer for when it was updated

## Editing

Set an issue's board Status, a pull request's reviewers, and the assignees and labels of issues and pull requests, from PullBull, and [comment](#commenting) on both, and [review](#reviewing) pull requests. It writes nothing else.

- **Open the picker:** select an issue row or search result and press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd>, click Status on the issue detail's board card, or right-click a row → **Status** to pick one straight away
- **Assignees and labels:** select an issue or pull request row or search result, or open it, and press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> (assignees) or <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> (labels), click Assignees or Labels on the detail (on a pull request, in its Details card), or right-click a row → **Assignees…** or **Labels…**. Open, closed and merged pull requests alike
- **Reviewers:** select a pull request row or search result, or open it, and press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>R</kbd>, click the detail's Reviewers card, or right-click a row → **Reviewers…**. The picker lists who is requested now (ticked), past reviewers with their latest verdict, you, the people GitHub suggests, everyone else who can be requested, then the organisation's teams. The author and bots are never listed. Ticking a past reviewer asks them again. Unticking a requested reviewer who has already reviewed takes back the request, not the review: the row says "Their review stays". Teams show on organisation repos when PullBull can read the team list (a `gh` login needs `read:org`); otherwise the picker lists people only. Open, closed and merged pull requests alike
- **Multi-select picker:** ticked entries first, then you (assignees), then the rest, in an order that stays put while you tick. Labels show their colour and description, people their avatar. Type to filter, <kbd>↑</kbd> <kbd>↓</kbd> to choose, <kbd>Return</kbd> to tick or untick and keep it open. <kbd>Esc</kbd>, <kbd>⌘</kbd><kbd>Return</kbd>, a click outside, the picker's own key or the popover hiding closes it and applies the ticks as one edit; nothing ticked sends nothing. An issue or pull request has at most 10 assignees: at 10, the unticked people are dimmed
- **Picker:** the board's Status options in board order, each with its open count, and **Clear Status** when the issue has one; the current one is checked. Type to filter, <kbd>↑</kbd> <kbd>↓</kbd> to choose, <kbd>Return</kbd> to apply, <kbd>Esc</kbd> to close without change
- **Which issues:** those on the board, and those in a repo the board's owner owns (an org board takes that org's issues; a personal board, your own). Picking a Status for an issue not on the board adds it
- **After an edit:** the row moves to its new lane at once and stays selected; nothing else is shown. PullBull keeps showing your edit until GitHub's answers catch up, for at most 5 minutes. Asking yourself to review someone else's open pull request puts it on Review at once; taking your request back takes it off, unless a request for one of your teams keeps it there
- **Undo:** <kbd>⌘</kbd><kbd>Z</kbd> within 10 seconds puts the previous Status back, or takes an issue the edit added off the board again; for reviewers, assignees and labels, it takes the added ones off and puts the removed ones back (a removed reviewer is asked again), and when GitHub applied only part of an edit, only that part. Only the last edit. Typing in the search field after it hands <kbd>⌘</kbd><kbd>Z</kbd> back to the text
- **When it fails:** the change is taken back and a line above the footer says why, with **Open on GitHub**, until you dismiss it, edit again or leave the PR or issue it's about. When GitHub applied only half of a reviewer, assignee or label edit, the line says which: "Added docs to #412, but couldn't remove bug: …" or "Asked alice to review #412, but couldn't remove bob: …"
- **Permissions:** with Sign in with GitHub, an org owner accepts PullBull's new permissions on GitHub once; until then the picker says so and links there. Pull requests need PullBull's Pull requests permission, accepted the same way. With a `gh` login, setting Status needs the `project` scope: the picker shows the `gh auth refresh -s project` command to run

## Commenting

Write a comment on an open, closed or merged issue or pull request from its detail. It goes out only when you post it.

- **Where:** a comment field at the bottom of the detail, on one row with Review and Merge (a PR) or View on board (an issue on the board), so it stays in view while the page scrolls. It reads "Comment…", or shows a pencil and the first line of a waiting draft. Opening a detail or the popover never puts the caret in it: press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd>, or click it. While you write, the field grows upward to 8 lines and shows <kbd>⌘</kbd><kbd>Return</kbd> at its end. The buttons beside it stay as they are
- **Post:** <kbd>⌘</kbd><kbd>Return</kbd> in the field; the field shows it at its end while you type. VoiceOver users have a **Post comment** action on the field. Empty text sends nothing
- **Keys in the field:** <kbd>Return</kbd> writes a new line. Outside the field, <kbd>⌘</kbd><kbd>Return</kbd> still opens the item on GitHub
- **Tagging:** type `@` and a list opens above the field with people to tag, narrowing as you type the login. First the people in this thread (who commented, newest first, then the author, assignees, requested reviewers and reviewers), then everyone who can be mentioned in the repo, then the people PullBull's lists know, then the organisation's teams. You, `ghost` and bots aren't offered. <kbd>↑</kbd> <kbd>↓</kbd> choose, <kbd>Return</kbd> or <kbd>Tab</kbd> puts in `@login ` (or `@owner/team `), and a click on a row does the same. GitHub turns it into a mention and notifies them when the comment posts
- **Teams:** on an organisation's repo, the list offers its teams when PullBull can read the team list; type `@acme/` to see only those. A `gh` login without `read:org` gets people only
- **The list closes** on a space, when the caret leaves the `@` word, or on <kbd>Esc</kbd>, which keeps what you typed. "Loading people…" shows while the repo's people are still on their way and nothing yet matches. A name that matches no one is sent as you typed it
- **Esc twice:** the first <kbd>Esc</kbd> leaves the field, the second closes the detail. With the `@` list open, <kbd>Esc</kbd> closes it first. Nothing you typed is lost
- **Drafts:** kept in memory for each account and item, across closing the detail, moving to another item, and closing the popover. They go on quit or sign-out
- **While posting:** the field is read-only and your comment shows at the end of the Conversation, dimmed, marked "Sending…". When GitHub accepts it, it becomes the real comment, the field empties, the row's comment count goes up, and the item leaves `is:unanswered`. PullBull shows it until GitHub's own reads catch up, for at most 5 minutes
- **Refused:** a line above the field says "Couldn't comment on #88: …" with GitHub's reason (a locked conversation, an archived repo, issues turned off) and **Open on GitHub**. The text stays in the field
- **Not sure:** after a timeout or a dropped connection PullBull checks the Conversation before saying anything. If your comment is there it counts as posted. If not, the line says "Couldn't confirm your comment on #88. Check the Conversation before sending again." and the text stays in the field. Check on GitHub first: the comment may have been made
- **No undo:** a posted comment emails everyone tagged and subscribed. PullBull can't edit or delete it; GitHub can. <kbd>⌘</kbd><kbd>Z</kbd> in the field undoes typing only
- **Your own comment** raises no "New comment" notification
- **Permissions:** with Sign in with GitHub, an issue needs PullBull's Issues permission and a pull request its Pull requests permission; until an org owner accepts them, a note takes the field's place in the row (hover it for the whole note); click it to accept them on GitHub. With a `gh` login, `repo` covers it

## Reviewing

Approve a pull request or request changes on it from its detail. It goes out only when you submit it.

- **Who can:** on an open pull request by someone else, once the detail has loaded, with Sign in with GitHub's Pull requests permission or a `gh` login. A draft is offered like any other; GitHub decides, and a refusal shows its reason. On your own PR, a closed or merged one, or an issue, <kbd>⌥</kbd><kbd>⌘</kbd><kbd>V</kbd> does nothing and there is no button
- **Start:** <kbd>⌥</kbd><kbd>⌘</kbd><kbd>V</kbd>, or the **Review** button in the bottom row, puts the comment field in review mode and focuses it. Text you had started becomes the review's. The commit you see is pinned: a background refresh never moves it
- **The panel:** above the bottom row, **Approve** and **Request changes**, with one line under them: the short commit, `5 files +120 −3`, and the checks (`checks passed`, `2 checks failing`, `checks running`, or nothing). Failing or running checks show in amber. They warn and don't block. A PR you last reviewed with Request changes opens on Request changes
- **Verdict:** <kbd>⌥</kbd><kbd>←</kbd> <kbd>⌥</kbd><kbd>→</kbd>, or a click. VoiceOver reads it as an adjustable control, "Review verdict"
- **Text:** optional on Approve ("Add a note (optional)…"). Request changes needs it ("Say what needs changing…"): submitted empty or blank, nothing is sent and the placeholder turns amber until you type or change the verdict. `@` tagging works as in [Commenting](#commenting)
- **Submit:** <kbd>⌘</kbd><kbd>Return</kbd> with the field focused. Holding it submits once. Review mode ends when the field loses focus, you leave the detail, the popover closes or the account changes, and then <kbd>⌘</kbd><kbd>Return</kbd> opens the PR on GitHub as ever, so it never sends a review by accident. A click on the page text doesn't take focus from the field: the mode stays, and <kbd>⌘</kbd><kbd>Return</kbd> still submits
- **Leave:** <kbd>Esc</kbd> or **Cancel** leaves review mode and keeps the text, with focus in the field. With the `@` list open, <kbd>Esc</kbd> closes it first
- **Checked first:** the field reads "Checking…" while PullBull reads the PR's head. If new commits arrived since you started, nothing is sent and the line says "New commits on #88 since you started reviewing. Look again, then review."; <kbd>⌥</kbd><kbd>⌘</kbd><kbd>V</kbd> pins the new head. If the PR has been merged or closed, nothing is sent and the line says so. If the read fails, nothing is sent. The review is sent on the commit you saw
- **While sending:** "Sending…". Cancel is disabled, <kbd>Esc</kbd> does nothing and the verdict is locked. Your review shows in Reviewers, dimmed. Cancel and <kbd>Esc</kbd> stop the check before that; leaving the detail or closing the popover doesn't
- **Done:** the field empties and gives up focus, the review shows in Reviewers and the PR leaves Needs your review (a PR you reviewed with Request changes leaves Review too; an approved one leaves it when "Hide pull requests I’ve approved" is on, the default, and otherwise stays there, dimmed). PullBull keeps showing it until GitHub's own reads catch up, for at most 5 minutes. Your own review raises no notification
- **Refused:** a line above the field says "Couldn't review #88: …" with GitHub's reason (an existing pending review on GitHub, a draft, a repo rule) and **Open on GitHub**. The text stays and review mode stays with it
- **Not sure:** after a timeout or a dropped connection PullBull reads the PR. If your review is there it counts as sent. If not, the line says "Couldn't confirm your review of #88. Check the Reviewers section before sending again." and the text stays in the field. Check on GitHub first
- **No undo:** GitHub can't delete a submitted review, and approving can count towards merging and sends an email. <kbd>⌘</kbd><kbd>Z</kbd> in the field undoes typing only. Changing your mind is another review
- **Not here:** line comments, suggested changes, a Comment verdict, dismissing a review. Merging is [its own step](#merging)
- **Permissions:** the same Pull requests permission as reviewers and comments, so nothing new to accept. With a `gh` login, `repo` covers it

## Drafts

Mark a draft pull request ready for review, or turn an open one back into a draft, from its detail. Either way is one click, and the other undoes it.

- **Who can:** the author of the pull request, or anyone with write access, once the detail has loaded. Anyone else sees nothing. Needs Sign in with GitHub's Pull requests permission or a `gh` login
- **Where:** **Ready for review** is in the Merge section of a draft, which reads "Draft. It can't be merged until it's ready for review." (with auto-merge set: "Draft, with auto-merge set. It can't merge until it's ready for review."). **Convert to draft** is a link in the header of Reviewers on an open pull request, even when it has no reviewers. Hover it for what it does: it can't be merged until it's ready again
- **One click:** no panel, no confirmation and no key. The label reads "Marking ready…" or "Converting…" and is disabled while it's on its way. Until GitHub says yes the state doesn't change; the comment field is read-only and Review and Merge are hidden, as during a merge. Both wait while the merge panel is open or a comment, review or merge is on its way
- **Done:** the state, the rows in the lists and the Merge section follow at once, without flickering back while GitHub's reads catch up. A PR of yours can move between Your PRs and Waiting on others. Someone else's PR you convert leaves Review. Marking ready can notify the requested reviewers and code owners, which is the point. Your own click raises no **Review requested** notification
- **Refused:** a line above the field says "Couldn't mark #88 ready for review: …" or "Couldn't convert #88 to draft: …" with GitHub's reason and **Open on GitHub**. Nothing on screen changes. The line stays until you dismiss it or make the next edit, even if you leave the PR
- **Not sure:** after a timeout or a dropped connection PullBull reads the PR a few times. If it shows the new state, that counts. If not, the line says "Couldn't confirm #88 is ready for review. Check it on GitHub." or "Couldn't confirm #88 is a draft. Check it on GitHub." and stays until you dismiss it or make the next edit. Nothing is sent twice. Check on GitHub first
- **Auto-merge:** converting a PR that has auto-merge set is allowed. GitHub turns its auto-merge off, so set it again after marking the PR ready
- **Not here:** changing it from a row or for several PRs at once, opening a PR as a draft
- **Permissions:** the same Pull requests permission as reviewers, comments and reviews, so nothing new to accept. If PullBull isn't installed here, or the install lacks Pull requests write, a draft shows a note in place of **Ready for review** ("Marking ready needs PullBull installed here." when not installed), and **Convert to draft** is hidden. With a `gh` login, `repo` covers it

## Merging

Merge a pull request, or set it to merge by itself once its requirements pass, from its detail. Nothing merges without a deliberate second action, and it can't be taken back.

- **Who can:** on an open pull request that isn't a draft (a draft shows **Ready for review** instead, see [Drafts](#drafts)), once the detail has loaded, with write access and Sign in with GitHub's Contents permission or a `gh` login. Without write access nothing is shown; without the Contents permission a note takes the button's place. Otherwise the detail says why not, with **Open on GitHub**: part of a stack, a merge queue, merge conflicts, behind the base branch, the branch's rules not met yet, or auto-merge set by someone else. Stacks and merge queues are merged on GitHub
- **Start:** <kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd>, or the **Merge** button in the bottom row, opens the merge panel above it. It works with the comment field focused, and does nothing on a PR with nothing to offer. The commit you see is pinned
- **The panel:** what will happen as a sentence ("Squash and merge #88 into main"), the method when the repository allows more than one, and a summary: `3 commits · 2 approvals · 1 of 12 checks failing`. Warnings show in amber. What it shows is read when you open it and doesn't change while you look
- **Method:** <kbd>⌥</kbd><kbd>←</kbd> <kbd>⌥</kbd><kbd>→</kbd>, or a click. Only the methods the repository and the branch's rules allow are offered, opening on your GitHub default. Where a branch's linear history comes from classic protection PullBull can't see it, so Merge commit stays offered and GitHub refuses it with its own reason
- **Confirm:** <kbd>⌃</kbd><kbd>⌘</kbd><kbd>↩</kbd>, or a click on **Merge** in the panel, which is filled with your accent colour (black or white text, whichever reads on it). Both are disarmed for half a second after the sentence appears or changes, so a double click does nothing. Nothing else merges: <kbd>↩</kbd> and <kbd>⌘</kbd><kbd>↩</kbd> do nothing while the panel is open, and a held key never confirms
- **A second step:** a failing or running check, no checks at all, or a review still requesting changes. The first confirm changes the button to **Merge anyway**, now filled amber, and disarms for a moment; a second, separate confirm merges. Changing the method resets it
- **Checked first:** confirming reads the PR again and compares it with the panel. If the commit, the base, the checks or the reviews differ, or GitHub hasn't worked out the state yet, nothing is sent: the panel updates when there's still something to do, and otherwise closes with a line saying why. A moved head and a closed PR close it with their lines. A push, a changed base or a closed PR can't be merged by accident. PullBull never bypasses the repository's rules, even for an admin
- **Merge when ready:** on a PR whose requirements aren't met yet, the panel's action is "Merge #88 into main when its requirements pass", and it sets GitHub's own auto-merge. It merges by itself, even with PullBull closed, and commits pushed later by people with write access are included. **Cancel auto-merge** takes one click and no panel, for a request you set, and a failed cancel leaves its line until you dismiss it; one set by someone else is cancelled on GitHub
- **Leave:** <kbd>Esc</kbd> or **Cancel** closes the panel, and gives the focus back to the comment field if it had it. So does a click outside it, leaving the detail, closing the popover or changing account. A click on the panel itself doesn't. While it's open the panel takes every key, apart from <kbd>⌘</kbd><kbd>W</kbd>, <kbd>⌘</kbd><kbd>,</kbd> and <kbd>⌘</kbd><kbd>/</kbd>, and review mode ends, keeping its text
- **Sending:** the panel closes at once and the PR shows as merged, dimmed, in Review, Mine and Team, not counted in the badge, until GitHub confirms, which takes a few seconds. It then turns solid. Your own merge raises no notification
- **Refused:** a line above the field says "Couldn't merge #88: …" with GitHub's reason and **Open on GitHub**, and the PR comes back. A moved head reads "New commits on #88 since you opened this. Look again, then merge." and a state that changed reads "#88 changed before it could merge. Look again, then merge." A line about a merge that was sent stays until you dismiss it or make the next edit; a line from before anything was sent goes when you leave the PR
- **Not sure:** after a timeout or a dropped connection PullBull reads the PR. If it merged, that counts. If not, the line says "Couldn't confirm the merge of #88. Check it before trying again." Nothing is ever sent twice. Check on GitHub first
- **No undo:** a merge can start a deploy within seconds. Cancelling auto-merge is the only take-back
- **Not here:** adding to a merge queue, merging a stack, editing the merge message, deleting the branch (the repository's setting applies), updating a branch, resolving conflicts, closing, merging from a row
- **Permissions:** Sign in with GitHub needs the Contents permission, which is new. Until an org owner accepts it, a note takes the button's place (click it to accept on GitHub); everything else keeps working. With a `gh` login, `repo` covers it

| Key | Does | Where |
|---|---|---|
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> | Open the merge panel | Pull request detail |
| <kbd>⌥</kbd><kbd>←</kbd> <kbd>⌥</kbd><kbd>→</kbd> | Change the method | Merge panel |
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>↩</kbd> | Confirm | Merge panel |
| <kbd>Esc</kbd> | Close the panel | Merge panel |

## Re-running failed jobs

Re-run the failed jobs of a pull request's GitHub Actions runs from its detail, in one click.

- **Who can:** on an open pull request with a failed check, with write access and Sign in with GitHub's Actions permission or a `gh` login. Without write access nothing is shown; without the Actions permission a note takes the button's place. Only runs that have finished count, so a run with another job still going is left until it ends. External checks can't be re-run here, nor can a run waiting for approval or one that failed to start
- **Start:** **Re-run failed jobs** in the Checks section, beside **Open Failing Check**. There is no panel and no key. Its tooltip says it re-runs the failed jobs and the jobs that depend on them, since a dependent job can deploy
- **Sending:** the button reads "Re-running…" and stays so while the detail is read up to three times, 2 s apart, until the runs show as restarted. If GitHub is slower, the button comes back, and pressing it again is safe. A run restarted since the detail loaded isn't sent again
- **Refused:** if some runs are refused the rest carry on, and a line says "Couldn't re-run 1 of 3 workflow runs on #88." If all are, it gives GitHub's reason, with **Open on GitHub**
- **Not here:** re-running every job of a run, one job, or a run waiting for approval
- **Permissions:** Sign in with GitHub needs the Actions permission, which is new. Until an org owner accepts it, a note takes the button's place (click **Open on GitHub** to accept); everything else keeps working. With a `gh` login, `repo` covers it

## Search

<kbd>/</kbd>, <kbd>⌘</kbd><kbd>F</kbd>, or just type. Searches the current mode, open and closed.

| Token | Matches |
|---|---|
| `@alice` `@me` | Author or reviewer. On issues: author or assignee |
| `~bug` `~"good first issue"` `label:bug` | Label |
| `is:open` `is:closed` `is:merged` `is:draft` | State |
| `is:ready` `is:conflict` `is:failing` `is:approved` | Ready to merge · merge conflicts · checks failed · has an approval. PRs only |
| `review:changes` `review:none` | Changes requested · no reviews yet. PRs only |
| `size:s` `size:m` `size:l` | Lines changed: up to 50, up to 300, more. PRs only |
| `repo:widgets` `repo:acme/widgets` | That repo. The name alone matches every owner's; several `repo:` match any of them. An exact `owner/name` goes to GitHub even for a repo PullBull hasn't seen; a name alone goes as the one known repo it names, and filters your lists only when no known repo or several have it. Saved searches keep it |
| `is:unanswered` | Your open PRs and the issues on your Assigned or Created chip whose last comment is someone else's, not a bot's. Searches your lists only |
| `status:prog` `status:"In progress"` | Status column on the board. Issues only |
| `#123` | That number, every repo. With other terms, that number if it matches them: `is:open #123`. A bare `123` is a title word |
| `owner/repo#123` or a link | Exactly that item |
| `updated:today` `3d` `1w` `1m` | Items active since 00:00 today, or 2, 6 or 29 days before. GitHub's date forms (`updated:>2026-10-01`, `updated:2026-10-01..2026-10-07`) go to GitHub as written and also filter locally; any other value goes to GitHub as written |
| words | Title |
| `-@bot` `-~wontfix` `-is:draft` `-status:done` `-updated:1w` | Not that. Works on every qualifier; a bare `-word` is a word. `-is:draft` and the other states still go to GitHub. These filter locally only and send nothing to GitHub: `-status:`, `-updated:`, `-is:ready`, `-is:conflict`, `-is:failing`, `-is:approved`, `-is:unanswered`, `-review:`, `size:` and `-size:`, and positive `is:ready`, `is:conflict`, `is:approved` and `review:changes`. A `repo:` or `-repo:` name alone that matches no known repo, or several, filters locally only too; an exact `-repo:owner/name` is sent. The rest of the search still goes to GitHub, except with `is:unanswered` or `-is:unanswered`, which keep the whole search in your lists |

- `@`, `~`, `is:`, `status:`, `updated:`, `review:`, `repo:`, `size:` and words combine; everything must match; a leading `-` excludes
- `status:` uses the board shown on the Board chip. Unquoted matches part of a Status name, quoted the whole name; case is ignored. Names with spaces need quotes to match exactly
- With `status:`, PRs and issues not on the board don't match
- `-status:` keeps PRs and issues not on the board
- Links and `owner/repo#123` work only on their own
- Pull request results start in Everywhere, laid out in the list's sections: a PR the list holds sits in its section, one of yours it doesn't hold in Your PRs or Waiting on others, any other open one in **Other results**, after Team. Nothing is folded while you search. Merged and closed PRs follow in **Closed and merged** (issues: **Closed**), open until you fold it for this search. Click a chip, or press <kbd>←</kbd> / <kbd>→</kbd> at the field's start / end, to narrow to Needs you, Mine or Team; <kbd>←</kbd> from Needs you goes back to Everywhere, and <kbd>→</kbd> from Team does nothing. Click the narrowed chip again, or **Search everywhere** in the narrowed empty state, for Everywhere. Mine narrowed is laid out in its sections, Needs you and Team in their lists; Team leaves out what is in Needs you. Everywhere shows the results' count, a narrowed search none. Issue results take All's sections the same way: Assigned to you, You opened, Rest of the board, then **Other results**; an open result done on the board goes under **Done · still open**, dimmed, after Other results. Narrowing to Assigned, Created or Board lays results out as that chip does
- The footer says what is searched and how many match, with a spinner while GitHub answers. <kbd>⌥</kbd><kbd>⌘</kbd><kbd>↩</kbd> Ask AI shows there when it fits
- <kbd>Return</kbd> opens the result you picked with <kbd>↓</kbd> <kbd>↑</kbd> or the mouse. No result is picked until you pick one, and typing drops the pick, so <kbd>Return</kbd> after typing doesn't open anything; it asks GitHub at once instead of after the typing pause. A `#123`, `owner/repo#123` or link with exactly one result picks it
- **Right-click a result:** [Status](#editing) (issues, when a board is shown) · [Reviewers…](#editing) (PRs) · [Assignees…](#editing) · [Labels…](#editing) · copy branch (PRs), link or Markdown link · open on GitHub · copy checkout command · open files changed (or changes since my review) · open failing check (when checks failed) · show only this repo · search author. The checkout, files and failing check items are on PRs. Search author replaces the query; show only this repo keeps it and searches that repo
- Each result looks as it does in its section or tab: avatars in Needs your review and Team, the review notes and counts the tab shows, assignees on issues. A soft yellow highlight marks the words that matched, and `· author` (or reviewer, assignee) after the age says why an `@` matched. Merged and closed PRs and closed issues carry their pill (an issue's: purple when completed, gray when not planned). Compact cards drop the pill and show only how long ago it ended (`2d`); the glyph says merged or closed, and hovering spells it out
- Compact cards (Settings → General) apply to results too, as in the lists
- Matches in the other mode show a hint: <kbd>⌘</kbd><kbd>1</kbd> / <kbd>⌘</kbd><kbd>2</kbd>
- Empty field shows saved searches, the first nine with their ⌃ key, and two lines of token hints: `#` `@` `~` `is:` `status:`, then `updated:` `review:` `repo:` `size:` `-`. <kbd>↓</kbd> to walk them; picking a token types it, and all but `#` and `-` open their list. After `-`, the next token joins it (`-@`, `-size:`), with the mouse or the keyboard
- Typing `@`, `~`, `label:`, `is:`, `status:`, `updated:`, `review:`, `repo:` or `size:` opens a completion list. `status:` lists the board's Status columns with their open counts; picking one writes the full name in quotes. `updated:` lists the four steps; `review:` lists `changes` and `none`; `size:` lists `s`, `m` and `l` with their line limits; `repo:` lists the repos in your lists. Also after `-`
- Typing the start of `status:`, `label:` or `updated:` (`st`, `la`, `up`) at the end of the field shows the rest in grey. Not `is:`, a common word; `status:` only when the board has Status columns; `updated:` only up to `upda`, so a title word like "update" is left alone. Also after `-`
- **Save:** bookmark icon in the field. Manage in Settings → Search

| Completion list | |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Choose |
| <kbd>Return</kbd> · <kbd>Tab</kbd> | Complete |
| <kbd>Esc</kbd> | Close |

| Grey suggestion (`st` → `status:`) | |
|---|---|
| <kbd>Tab</kbd> | Write it and open its list |
| <kbd>Return</kbd>, typing | Ignore it |

## Ask AI

<kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> in the search field. Finds a PR or issue from a loose description ("the one that fixed the login redirect, last week") and answers a short question about it, using Anthropic's API with your own key. Off by default.

### Set up

Settings → Ask AI.

| Control | Default |
|---|---|
| Ask AI on/off | Off |
| Anthropic API key | Empty. Stored in the Keychain only. **Remove** deletes it |
| Model | The newest Sonnet your key can use. The newest Haiku is cheaper and less accurate. The list updates when you save the key; if Anthropic retires the chosen model, the next one takes over. Keys saved before this version keep the built-in list until saved again |
| Exclude from Ask AI | Empty. Pick from the repos of the current org or scope; excluded repos are never stored or sent |
| Index | Shown while Ask AI is on: items indexed, backfill progress ("N of ~M") or last sync, **Rebuild** |

- The key can be saved only while Ask AI is on. It is checked when you save it (`GET /v1/models`, free). A bad key never reaches a question. [Get a key](https://platform.claude.com/settings/keys)
- Without a key, <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> says "Add an Anthropic API key in Settings → Ask AI" and sends nothing. Before the index opens, it says "Ask AI index isn't ready yet."

### What is sent

| When | To Anthropic |
|---|---|
| You save the key | The key, for the check |
| You press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> | Your question, the org or account name, today's date, and up to 40 matching PR and issue descriptions (first 1,500 characters each, plus title, author, state, labels, dates, and the base branch of merged PRs) |
| Anything else | Nothing |

- Matching runs on this Mac. Only the best matches are sent
- Excluded repos are never sent
- Descriptions are untrusted text. Ask AI can't write to GitHub or act on anything; only items it was shown become links

### Asking

| | |
|---|---|
| Ask | Type the description, press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd>. Normal results stay on screen; an "Asking…" row shows at the top |
| Cancel | <kbd>Esc</kbd>, or edit the field |
| Answer | Answer on top, then PRs and issues in one list, each with a line on why it matched. Under the answer: model, time, candidates sent |
| Open | <kbd>Return</kbd> opens the item in its own mode. <kbd>Esc</kbd> or <kbd>←</kbd> in the detail returns to Ask AI |
| GitHub · copy | <kbd>⌘</kbd><kbd>Return</kbd> opens on GitHub. Copy keys work as in the list |
| Edit and re-ask | <kbd>Esc</kbd> or <kbd>←</kbd> on Ask AI returns to the field with the question kept |
| Empty or edit the field | Back to normal search |

- Each question stands alone; there are no follow-up questions
- With [one repo](#one-repo) shown, Ask AI searches only that repo
- Questions about deployment ("is it on production?") are answered only from what descriptions and labels say. The answer says so when it can't confirm
- "Nothing matched" is a valid answer; try other words
- Errors show as one line in place of the answer: no network, key rejected, rate limited, no answer in 20 s, declined, answer cut off, no answer, model retired, HTTP error
- While the index is still syncing, Ask AI runs on what is indexed and says so

### Index

| | |
|---|---|
| Contents | PRs and issues updated in the last 90 days in the account's scope, with full descriptions. No comments |
| Where | This Mac, in the cache folder ([Data](#data)). Never sent as a whole |
| Built | Turning Ask AI on starts a paced backfill; regular refresh goes first. Then it updates on each refresh, with a full re-sync once a week |
| Deleted | Ask AI off (every index file), sign-out, or a renamed login. **Rebuild** empties the index and refetches; the file stays |
| Excluded repos | Never stored. Rows are deleted when you add a repo to the list; removing it backfills the repo |

### Cost

- No spending cap in PullBull. Set limits in the Anthropic console
- Cost depends on how long your descriptions are

## Keyboard

| List | |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Select |
| <kbd>⌥</kbd><kbd>↑</kbd> <kbd>⌥</kbd><kbd>↓</kbd> | Previous / next group (section, repo, author, lane, Done, Closed). Folded lanes are skipped; nothing without groups. Search results too |
| <kbd>⌘</kbd><kbd>↑</kbd> <kbd>⌘</kbd><kbd>↓</kbd> | First / last row, in search results too |
| <kbd>←</kbd> <kbd>→</kbd> | Previous / next chip. In search: narrow to the chip beside the one the results are laid out for (nothing from Everywhere with <kbd>←</kbd>, or from the last chip with <kbd>→</kbd>), with the caret at the start (<kbd>←</kbd>) or end (<kbd>→</kbd>) of the field |
| <kbd>Return</kbd> | Detail. In search, of the result picked with <kbd>↑</kbd> <kbd>↓</kbd> (or a `#123` with one result) |
| <kbd>⌘</kbd><kbd>Return</kbd> | Open on GitHub (in a detail's comment field it posts, or submits in review mode, see [Commenting](#commenting) and [Reviewing](#reviewing)) |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy link |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>C</kbd> | Copy `owner/repo#123` |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy Markdown link |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>Return</kbd> | Files changed; on a PR with new commits since your review, just those changes |
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy Checkout Command: `gh pr checkout 412 -R owner/repo` |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> | [Ask AI](#ask-ai), from the search field |
| <kbd>⌘</kbd><kbd>1</kbd> · <kbd>⌘</kbd><kbd>2</kbd> · <kbd>⌘</kbd><kbd>3</kbd> | Pull Requests · Issues · [Stats](#stats) |
| <kbd>⌃</kbd><kbd>1</kbd>…<kbd>⌃</kbd><kbd>9</kbd> | Saved search 1–9, in Settings order. Off while macOS uses ⌃1… to switch desktops (System Settings → Keyboard → Shortcuts → Mission Control) |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>F</kbd> | Repo menu ([one repo](#one-repo)) |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>B</kbd> | Board menu, on the Board chip |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>A</kbd> | Account menu |
| <kbd>⌘</kbd><kbd>R</kbd> | Refresh. On [Stats](#stats), refreshes the stats |
| <kbd>⌘</kbd><kbd>,</kbd> | Settings |
| <kbd>⌘</kbd><kbd>/</kbd> | Keyboard Shortcuts window: every shortcut by section, with a filter. <kbd>Esc</kbd> clears the filter, then closes; <kbd>⌘</kbd><kbd>W</kbd> or <kbd>⌘</kbd><kbd>/</kbd> closes. Also the footer gear, and Settings → General → Keyboard shortcuts |
| <kbd>Esc</kbd> | Clear search → clear repo → close |
| <kbd>⌘</kbd><kbd>W</kbd> | Close |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd> | [Status picker](#editing) on the selected issue, when a board is shown. In search results too |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>R</kbd> | [Reviewers picker](#editing) on the selected pull request. In search results too |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> · <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> | [Assignees or labels picker](#editing) on the selected issue or pull request. In search results too |
| <kbd>⌘</kbd><kbd>Z</kbd> | Undo the last edit, for 10 seconds after it |

| Detail | |
|---|---|
| <kbd>Esc</kbd> · <kbd>←</kbd> · <kbd>⌘</kbd><kbd>[</kbd> | Back |
| <kbd>⌥</kbd><kbd>↓</kbd> <kbd>⌥</kbd><kbd>↑</kbd> | Next / previous item of the list or search you came from. The back button shows where you are (2 of 6). Stops at the ends. Not for a detail opened from a notification or a linked PR |
| <kbd>⌘</kbd><kbd>Return</kbd> | Open on GitHub; in the comment field, posts the comment, or submits the review in review mode |
| <kbd>⌘</kbd><kbd>C</kbd> · <kbd>⌘</kbd><kbd>⇧</kbd><kbd>C</kbd> · <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> | Same copies as the list |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>Return</kbd> | Files changed; on a PR with new commits since your review, just those changes |
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy Checkout Command: `gh pr checkout 412 -R owner/repo` |
| <kbd>⌘</kbd><kbd>R</kbd> | Refresh |
| <kbd>⌘</kbd><kbd>/</kbd> | Keyboard Shortcuts window |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd> | [Status picker](#editing), on an issue |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>R</kbd> | [Reviewers picker](#editing), on a pull request |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> · <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> | [Assignees or labels picker](#editing), on an issue or pull request |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd> | [Comment field](#commenting), on an issue or pull request. <kbd>⌘</kbd><kbd>Return</kbd> posts; <kbd>@</kbd> opens the list of people to tag (<kbd>↑</kbd> <kbd>↓</kbd>, <kbd>Return</kbd> or <kbd>Tab</kbd> inserts, <kbd>Esc</kbd> closes it); <kbd>Esc</kbd> leaves the field, a second <kbd>Esc</kbd> goes back |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>G</kbd> | [Merge panel](#merging), on a pull request, with the comment field focused or not. <kbd>⌥</kbd><kbd>←</kbd> <kbd>⌥</kbd><kbd>→</kbd> change the method; <kbd>⌃</kbd><kbd>⌘</kbd><kbd>↩</kbd> confirms; <kbd>Esc</kbd> closes it |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>V</kbd> | [Review mode](#reviewing), on a pull request, with the comment field focused or not. <kbd>⌥</kbd><kbd>←</kbd> <kbd>⌥</kbd><kbd>→</kbd> change the verdict; <kbd>⌘</kbd><kbd>Return</kbd> submits; <kbd>Esc</kbd> leaves review mode, keeping the text |
| <kbd>⌘</kbd><kbd>Z</kbd> | Undo the last edit, for 10 seconds after it. In the comment field, undoes typing |

The order is the one on screen when you opened the first item; a refresh doesn't reshuffle it. An item that has left the lists since is skipped, unless its detail was already loaded.

Reopen within a minute and the detail is still there.

## One repo

- Right-click a row or a repo header → **Show Only *repo***
- Or the repo menu: <kbd>⌘</kbd><kbd>⇧</kbd><kbd>F</kbd>, or the repo name in the filter row. Each repo shows its counts
- Back to all: ✕ in the filter row, **Show all**, **Show All Repositories**, or <kbd>Esc</kbd>
- Applies to every chip and tab; search stays inside it
- To keep a repo in a saved search, use `repo:` instead
- Counts and notifications still cover all repos
- Cleared on relaunch

## Recent activity

- Right-click a row, a repo header, an author header or the list → **Show Only Updated** → Today, In the Last 3 Days, In the Last Week or In the Last Month
- A strip above the list names the step: *Today*, *Last 3 days*, *Last week*, *Last month*; hover for the full line and start date
- On All and Mine, the Recently closed header names the step too; under the month it stays *Last 7 days*
- Back to all: ✕ in the strip, **Show All**, or <kbd>Esc</kbd>. <kbd>Esc</kbd> clears this and Show Only *repo* together
- Kept across chip changes. Cleared when the popover closes, the mode changes or the Issues chip changes
- Judged by last activity: when an open item last changed, or when a closed one ended
- Counts and notifications still cover everything
- Combines with Show Only *repo*
- In search, type `updated:today`, `3d`, `1w` or `1m` instead

## Sorting

- Click ⇅ at the right of the strip above the list, or right-click a row, a header or the list → **Sort By**
- Pull request chips: **Recently updated** (default) · **Waiting longest** (the 🕒 review wait, longest first; PRs not waiting follow) · **Oldest first** (by when opened)
- Issue chips: **Recently updated** (default) · **Newest first** · **Oldest first** (by when opened). All adds **Board status**: rows in board column order, then by recently updated, issues not on the board last; offered only while a board is readable, else All sorts by recently updated
- Each chip keeps its own, across relaunches. In All the sort orders the rows within each section; the sections keep their order. Off the default, the strip names it in the accent colour
- Repo groups follow their first row; author groups stay by name; Board lanes keep the board's order and sort inside
- Done, Recently closed and search's Closed keep their own order (most recently ended first)
- Search results follow the sort of the chip they're laid out for; Everywhere uses All's
- The selected row stays selected and in view

## Settings

<kbd>⌘</kbd><kbd>,</kbd>, or the footer gear → Settings….

| Tab | |
|---|---|
| General | Grouping, Team by author, compact cards, where pull requests and issues open (Issues open on: All · Last used · Assigned · Created · Board), background, filters (Needs you and Team), menu bar count, refresh interval, pending CI checks, shortcut, Keyboard Shortcuts window, launch at login, updates |
| Account | Account, org, board, access notices |
| Notifications | One toggle per event, grouped: my pull requests · pull requests I review · issues assigned to me · issues I created |
| Search | Saved searches: rename, edit the query, drag to reorder, **+** and **−**. Apply one from the empty search field; the first nine have ⌃1–⌃9 |
| Ask AI | [Ask AI](#ask-ai): on/off, key, model, exclude list, index |

| Group | Notification | Default |
|---|---|---|
| My pull requests | Approved | on |
| | Changes requested | on |
| | CI failed | on |
| | New comment | on |
| | Ready to merge: approved, checks green, no conflicts | off |
| | Merged outside PullBull: by someone else, by you on GitHub, or by Merge when ready | on |
| Pull requests I review | Review requested, re-requested, or new commits since your review | on |
| | Your review dismissed: your approval or requested changes, by someone else | on |
| | New comment on a PR you reviewed | off |
| Issues assigned to me | Newly assigned by someone else | off |
| | New comment | on |
| | Status changed on the board | on |
| | Closed or reopened | on |
| Issues I created | New comment | off |
| | Status changed on the board | off |
| | Closed or reopened | on |

With Settings → General → Check my pending CI more often, CI failed and Ready to merge arrive within about 30 s while your checks run: for up to 5 of your PRs, for 20 minutes each, and not at a 1-minute refresh interval. Your own comments, moves, closes and merges made in PullBull never notify, nor does asking yourself or one of your teams to review. Review requested stays silent for about 15 minutes after you mark a pull request ready for review yourself, as GitHub may ask the code owners then. A re-request after that still notifies. Several comments on one issue between refreshes make one notification ("3 new comments"). A dismissed review that also puts the PR back in Review notifies once, as the dismissal. Status changes count on the board the Board chip shows, as "In Progress → In Review"; moves the board's automation makes after a close or a merge don't notify, the close does.

Click a notification to open the detail.

## Data

| What | Where |
|---|---|
| Cache | `~/Library/Application Support/io.github.rustycamper.pullbull/` |
| Avatars | `~/Library/Caches/io.github.rustycamper.pullbull/` |
| Settings | defaults domain `io.github.rustycamper.pullbull` |
| Ask index | Same cache folder, one file per account and scope. Only while Ask AI is on |
| Sign-in tokens | Keychain, this Mac only, not synced |
| Anthropic API key | Keychain, this Mac only, not synced |
| `gh` tokens | Not stored |

## Build from source

Needs macOS 14+, Xcode 27+, `brew install xcodegen`.

```bash
xcodegen generate
xcodebuild build -scheme PullBull -derivedDataPath build
open build/Build/Products/Debug/PullBull.app
swift test --package-path Packages/PullBullKit
```

- Without an Apple team only `gh` logins work
- **Sign in with GitHub:** copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig`, set `DEVELOPMENT_TEAM` and `CODE_SIGN_ENTITLEMENTS = PullBull/PullBull.entitlements`, build with `-allowProvisioningUpdates`
- **Own app name:** register your own GitHub App ([github-app-setup.md](github-app-setup.md))
- **Releasing:** [releasing.md](releasing.md)
