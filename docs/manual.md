# PullBull manual

Every tab, key and setting. Overview: [README](../README.md).

[Install](#install) · [Sign in](#sign-in) · [Pull Requests](#pull-requests) · [Issues](#issues) · [Search](#search) · [Ask AI](#ask-ai) · [Keyboard](#keyboard) · [One repo](#one-repo) · [Sorting](#sorting) · [Settings](#settings) · [Data](#data) · [Build](#build-from-source)

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

Without `read:project`: Board shows the command to add it, Mine groups by repo.

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
| Right-click | Settings · Keyboard Shortcuts · About PullBull · Check for Updates (release builds) · Quit. The same menu as the footer gear |

## Pull Requests

<kbd>⌘</kbd><kbd>1</kbd>

One list in sections, scoped by chips above it. It opens on All, or on the choice in Settings → General → Pull requests open on: All · Last used · Needs you · Mine · Team. A chip you pick lasts until the popover closes. Last used reopens the chip showing at the last close, also after a relaunch. A choice whose chip isn't shown (Team without an org) opens on All.

| Chip | Shows |
|---|---|
| All | Needs your review, Your PRs, Waiting on others, then Recently closed and Team, folded. No count |
| Needs you | PRs waiting on you or your team. Icon says why: requested, team, re-requested, new commits. Lines added and removed (`+120 −30`), not in compact cards. Oldest first: [Sort](#sorting) |
| Mine | Your PRs, Waiting on others, folded Recently closed: yours closed or merged in the last 7 days. Review pills, checks, **Ready to merge** |
| Team | Other open PRs in the org, not the ones in Needs you. Group by author: Settings → General. No chip without an org |

- **Chips:** click one to scope the list, click it again for All, or press <kbd>←</kbd> <kbd>→</kbd>. Each shows its count (Needs you in the accent colour when above zero); the counts ignore the repo and time focus. Turn them off in Settings → General → Scope chips. The list then stays on All, the sections are the only navigation, and search looks everywhere
- **Not grouped by repo:** All and Mine are grouped by their sections, and each row names its repo (`widgets #1305`). Needs you and Team group by repo, or by author for Team, as before

| Section | Rows | Header |
|---|---|---|
| Needs your review | The Needs you rows, including "You approved" rows when Hide approved is off | 🔔 in the accent colour |
| Your PRs | Your open PRs that need you: ready to merge, changes requested, failing checks, conflicts, or a draft | PR glyph |
| Waiting on others | Your other open PRs: waiting on review, or on checks still running | 🕒 |
| Recently closed | Yours closed or merged in the last 7 days | chevron |
| Team | Team's rows | chevron |

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
- **Detail:** who opened it and when it was last updated (the row's age), or when it was merged or closed · assignees, labels and reviewers (click to change) · checks (a cancelled run reads cancelled, not failed, though GitHub still marks the PR failed) · description (long ones fold) · the newest comments, with earlier ones counted above · files. A [comment field](#commenting) is pinned at the bottom. Markdown incl. `<details>`. **Open Failing Check** beside failed checks
- **Labels:** up to two chips per row (none in compact cards), each led by a dot in the label's GitHub colour, then "+N". A `~label` search puts that label first. The detail's Details card lists them all
- **Right-click a row:** [Reviewers…](#editing) · [Assignees…](#editing) · [Labels…](#editing) · copy branch, link or Markdown link · open on GitHub · copy checkout command · open files changed (or changes since my review) · open failing check (when checks failed) · show only this repo · show only updated · search author
- **Right-click a group header** (repo, author): **Open All *N* on GitHub**, from two PRs up; above 8 it asks first. An author header's menu also offers **Search @*login*** and **Show Only Updated**. Headers in search results get their section's or tab's menus, without Show Only Updated
- **Footer:** account · refresh · open on GitHub · the gear, a menu with Settings, Keyboard Shortcuts, About PullBull, Check for Updates (release builds) and Quit. Turns amber with **Retry** when a refresh fails
- **Switch account:** click the account in the footer, or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>A</kbd>. Lists your signed-in accounts, then GitHub CLI logins, each with the org it opens in; then Add Account… and Account Settings…. Each account comes back with its last org, and each org with its last board

## Issues

<kbd>⌘</kbd><kbd>2</kbd>

| Tab | Shows | Grouped by |
|---|---|---|
| Mine | Issues assigned to you | Board Status, then "Not on board". Done folded: done on the board, still open. Repo without a board |
| Created | Issues you opened | Repo, or none (Settings → General) |
| Board | All open issues on the board | Board Status. Done folded, last 14 days |

- **Status lanes:** the glyph takes the Status colour set on the board, on Board and Mine
- **Fold a lane:** click its header. Status, "No status" and "Not on board" fold; repo groups don't. Needs a board
- **Folds:** kept per tab and per board, across relaunches. Folding on Board leaves Mine as it is
- **Searching:** every lane shows open; folds come back when the search ends; open issues done on the board show under Done only when the results are laid out like Mine or Board, not on Created; closed ones go under Closed
- **Done:** click its header to unfold. Never counted
- **Labels:** chips as on [pull requests](#pull-requests). The board card lists them all
- **Switch board:** on the Board tab, click its name in the filter row, or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>B</kbd>
- **Right-click a row:** [Status](#editing) (when a board is shown) · [Assignees…](#editing) · [Labels…](#editing) · copy link or Markdown link · open on GitHub · show only this repo · show only updated · search author
- **Right-click a group header** (a Status lane, No status, Not on board or a repo): **Open All *N* on GitHub**, from two issues up; above 8 it asks first. Done has none. Headers in search results get the tab's menus, without Show Only Updated
- **Detail:** who opened it and when it was last updated (the row's age), or when it was closed · board card (incl. labels) · linked PRs (<kbd>Esc</kbd> returns) · description (long ones fold) · the last two comments, with earlier ones counted above. Markdown incl. `<details>`. A [comment field](#commenting) is pinned at the bottom

## Editing

Set an issue's board Status, a pull request's reviewers, and the assignees and labels of issues and pull requests, from PullBull, and [comment](#commenting) on both. It writes nothing else.

- **Open the picker:** select an issue row or search result and press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd>, click Status on the issue detail's board card, or right-click a row → **Status** to pick one straight away
- **Assignees and labels:** select an issue or pull request row or search result, or open it, and press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> (assignees) or <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> (labels), click Assignees or Labels on the detail (on a pull request, in its Details card), or right-click a row → **Assignees…** or **Labels…**. Open, closed and merged pull requests alike
- **Reviewers:** select a pull request row or search result, or open it, and press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>R</kbd>, click the detail's Reviewers card, or right-click a row → **Reviewers…**. The picker lists who is requested now (ticked), past reviewers with their latest verdict, you, the people GitHub suggests, everyone else who can be requested, then the organisation's teams. The author and bots are never listed. Ticking a past reviewer asks them again. Unticking a requested reviewer who has already reviewed takes back the request, not the review: the row says "Their review stays". Teams show on organisation repos when PullBull can read the team list (a `gh` login needs `read:org`); otherwise the picker lists people only. Open, closed and merged pull requests alike
- **Multi-select picker:** ticked entries first, then you (assignees), then the rest, in an order that stays put while you tick. Labels show their colour and description, people their avatar. Type to filter, <kbd>↑</kbd> <kbd>↓</kbd> to choose, <kbd>Return</kbd> to tick or untick and keep it open. <kbd>Esc</kbd>, <kbd>⌘</kbd><kbd>Return</kbd>, a click outside, the picker's own key or the popover hiding closes it and applies the ticks as one edit; nothing ticked sends nothing. An issue or pull request has at most 10 assignees: at 10, the unticked people are dimmed
- **Picker:** the board's Status options in board order, each with its open count, and **Clear Status** when the issue has one; the current one is checked. Type to filter, <kbd>↑</kbd> <kbd>↓</kbd> to choose, <kbd>Return</kbd> to apply, <kbd>Esc</kbd> to close without change
- **Which issues:** those on the board, and those in a repo the board's owner owns (an org board takes that org's issues; a personal board, your own). Picking a Status for an issue not on the board adds it
- **After an edit:** the row moves to its new lane at once and stays selected; nothing else is shown. PullBull keeps showing your edit until GitHub's answers catch up, for at most 5 minutes. Asking yourself to review someone else's open pull request puts it on Review at once; taking your request back takes it off, unless a request for one of your teams keeps it there
- **Undo:** <kbd>⌘</kbd><kbd>Z</kbd> within 10 seconds puts the previous Status back, or takes an issue the edit added off the board again; for reviewers, assignees and labels, it takes the added ones off and puts the removed ones back (a removed reviewer is asked again), and when GitHub applied only part of an edit, only that part. Only the last edit. Typing in the search field after it hands <kbd>⌘</kbd><kbd>Z</kbd> back to the text
- **When it fails:** the change is taken back and a line above the footer says why, with **Open on GitHub**, until you dismiss it or edit again. When GitHub applied only half of a reviewer, assignee or label edit, the line says which: "Added docs to #412, but couldn't remove bug: …" or "Asked alice to review #412, but couldn't remove bob: …"
- **Permissions:** with Sign in with GitHub, an org owner accepts PullBull's new permissions on GitHub once; until then the picker says so and links there. Pull requests need PullBull's Pull requests permission, accepted the same way. With a `gh` login, setting Status needs the `project` scope: the picker shows the `gh auth refresh -s project` command to run

## Commenting

Write a comment on an open, closed or merged issue or pull request from its detail. It goes out only when you post it.

- **Where:** a comment field at the bottom of the detail, on one row with the buttons, so it stays in view while the page scrolls. It reads "Comment…", or shows a pencil and the first line of a waiting draft. Opening a detail or the popover never puts the caret in it: press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd>, or click it. While you write, the field grows upward to 8 lines and shows <kbd>⌘</kbd><kbd>Return</kbd> at its end. The buttons beside it stay as they are
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
| `is:unanswered` | Your open PRs and the issues on your Mine or Created tab whose last comment is someone else's, not a bot's. Searches your lists only |
| `status:prog` `status:"In progress"` | Status column on the board. Issues only |
| `#123` | That number, every repo. With other terms, that number if it matches them: `is:open #123`. A bare `123` is a title word |
| `owner/repo#123` or a link | Exactly that item |
| `updated:today` `3d` `1w` `1m` | Items active since 00:00 today, or 2, 6 or 29 days before. GitHub's date forms (`updated:>2026-10-01`, `updated:2026-10-01..2026-10-07`) go to GitHub as written and also filter locally; any other value goes to GitHub as written |
| words | Title |
| `-@bot` `-~wontfix` `-is:draft` `-status:done` `-updated:1w` | Not that. Works on every qualifier; a bare `-word` is a word. `-is:draft` and the other states still go to GitHub. These filter locally only and send nothing to GitHub: `-status:`, `-updated:`, `-is:ready`, `-is:conflict`, `-is:failing`, `-is:approved`, `-is:unanswered`, `-review:`, `size:` and `-size:`, and positive `is:ready`, `is:conflict`, `is:approved` and `review:changes`. A `repo:` or `-repo:` name alone that matches no known repo, or several, filters locally only too; an exact `-repo:owner/name` is sent. The rest of the search still goes to GitHub, except with `is:unanswered` or `-is:unanswered`, which keep the whole search in your lists |

- `@`, `~`, `is:`, `status:`, `updated:`, `review:`, `repo:`, `size:` and words combine; everything must match; a leading `-` excludes
- `status:` uses the board shown in the Board tab. Unquoted matches part of a Status name, quoted the whole name; case is ignored. Names with spaces need quotes to match exactly
- With `status:`, PRs and issues not on the board don't match
- `-status:` keeps PRs and issues not on the board
- Links and `owner/repo#123` work only on their own
- Pull request results start in Everywhere, laid out in the list's sections: a PR the list holds sits in its section, one of yours it doesn't hold in Your PRs or Waiting on others, any other open one in **Other results**, after Team. Nothing is folded while you search. Merged and closed PRs follow in **Closed and merged** (issues: **Closed**), open until you fold it for this search. Click a chip, or press <kbd>←</kbd> / <kbd>→</kbd> at the field's start / end, to narrow to Needs you, Mine or Team; <kbd>←</kbd> from Needs you goes back to Everywhere, and <kbd>→</kbd> from Team does nothing. Click the narrowed chip again, or **Search everywhere** in the narrowed empty state, for Everywhere. Mine narrowed is laid out in its sections, Needs you and Team in their lists; Team leaves out what is in Needs you. Everywhere shows the results' count, a narrowed search none. Issues keep their tabs: click one to narrow
- The footer says what is searched and how many match, with a spinner while GitHub answers. <kbd>⌥</kbd><kbd>⌘</kbd><kbd>↩</kbd> Ask AI shows there when it fits
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
| <kbd>⌥</kbd><kbd>↑</kbd> <kbd>⌥</kbd><kbd>↓</kbd> | Previous / next group (repo, author, lane, Done, Closed). Folded lanes are skipped; nothing without groups. Search results too |
| <kbd>⌘</kbd><kbd>↑</kbd> <kbd>⌘</kbd><kbd>↓</kbd> | First / last row, in search results too |
| <kbd>←</kbd> <kbd>→</kbd> | Previous / next chip (tab in Issues). In search: narrow to the chip beside the one the results are laid out for (nothing from Everywhere with <kbd>←</kbd>, or from the last chip with <kbd>→</kbd>), with the caret at the start (<kbd>←</kbd>) or end (<kbd>→</kbd>) of the field |
| <kbd>Return</kbd> | Detail |
| <kbd>⌘</kbd><kbd>Return</kbd> | Open on GitHub (in a detail's comment field it posts, see [Commenting](#commenting)) |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy link |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>C</kbd> | Copy `owner/repo#123` |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy Markdown link |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>Return</kbd> | Files changed; on a PR with new commits since your review, just those changes |
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy Checkout Command: `gh pr checkout 412 -R owner/repo` |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> | [Ask AI](#ask-ai), from the search field |
| <kbd>⌘</kbd><kbd>1</kbd> · <kbd>⌘</kbd><kbd>2</kbd> | Pull Requests · Issues |
| <kbd>⌃</kbd><kbd>1</kbd>…<kbd>⌃</kbd><kbd>9</kbd> | Saved search 1–9, in Settings order. Off while macOS uses ⌃1… to switch desktops (System Settings → Keyboard → Shortcuts → Mission Control) |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>F</kbd> | Repo menu ([one repo](#one-repo)) |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>B</kbd> | Board menu, on the Board tab |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>A</kbd> | Account menu |
| <kbd>⌘</kbd><kbd>R</kbd> | Refresh |
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
| <kbd>⌘</kbd><kbd>Return</kbd> | Open on GitHub; in the comment field, posts the comment |
| <kbd>⌘</kbd><kbd>C</kbd> · <kbd>⌘</kbd><kbd>⇧</kbd><kbd>C</kbd> · <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> | Same copies as the list |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>Return</kbd> | Files changed; on a PR with new commits since your review, just those changes |
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy Checkout Command: `gh pr checkout 412 -R owner/repo` |
| <kbd>⌘</kbd><kbd>R</kbd> | Refresh |
| <kbd>⌘</kbd><kbd>/</kbd> | Keyboard Shortcuts window |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd> | [Status picker](#editing), on an issue |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>R</kbd> | [Reviewers picker](#editing), on a pull request |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>A</kbd> · <kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> | [Assignees or labels picker](#editing), on an issue or pull request |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>M</kbd> | [Comment field](#commenting), on an issue or pull request. <kbd>⌘</kbd><kbd>Return</kbd> posts; <kbd>@</kbd> opens the list of people to tag (<kbd>↑</kbd> <kbd>↓</kbd>, <kbd>Return</kbd> or <kbd>Tab</kbd> inserts, <kbd>Esc</kbd> closes it); <kbd>Esc</kbd> leaves the field, a second <kbd>Esc</kbd> goes back |
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
- Kept across chip changes. Cleared when the popover closes, the mode changes or the Issues tab changes
- Judged by last activity: when an open item last changed, or when a closed one ended
- Counts and notifications still cover everything
- Combines with Show Only *repo*
- In search, type `updated:today`, `3d`, `1w` or `1m` instead

## Sorting

- Click ⇅ at the right of the strip above the list, or right-click a row, a header or the list → **Sort By**
- Pull request chips: **Recently updated** (default) · **Waiting longest** (the 🕒 review wait, longest first; PRs not waiting follow) · **Oldest first** (by when opened)
- Issue tabs: **Recently updated** (default) · **Newest first** · **Oldest first** (by when opened)
- Each chip and Issues tab keeps its own, across relaunches. In All the sort orders the rows within each section; the sections keep their order. Off the default, the strip names it in the accent colour
- Repo groups follow their first row; author groups stay by name; Board lanes keep the board's order and sort inside
- Done, Recently closed and search's Closed keep their own order (most recently ended first)
- Search results follow the sort of the chip or tab they're laid out for; Everywhere uses All's
- The selected row stays selected and in view

## Settings

<kbd>⌘</kbd><kbd>,</kbd>, or the footer gear → Settings….

| Tab | |
|---|---|
| General | Grouping, Team by author, compact cards, where pull requests open, scope chips, background, filters (Needs you and Team), menu bar count, refresh interval, pending CI checks, shortcut, Keyboard Shortcuts window, launch at login, updates |
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
| | Merged by someone else | on |
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

With Settings → General → Check my pending CI more often, CI failed and Ready to merge arrive within about 30 s while your checks run: for up to 5 of your PRs, for 20 minutes each, and not at a 1-minute refresh interval. Your own comments, moves and closes never notify, nor does asking yourself or one of your teams to review. Several comments on one issue between refreshes make one notification ("3 new comments"). A dismissed review that also puts the PR back in Review notifies once, as the dismissal. Status changes count on the board the Board tab shows, as "In Progress → In Review"; moves the board's automation makes after a close or a merge don't notify, the close does.

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
