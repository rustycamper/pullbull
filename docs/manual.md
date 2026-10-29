# PullBull manual

Every tab, key and setting. Overview: [README](../README.md).

[Install](#install) · [Sign in](#sign-in) · [Pull Requests](#pull-requests) · [Issues](#issues) · [Search](#search) · [Ask AI](#ask-ai) · [Keyboard](#keyboard) · [One repo](#one-repo) · [Settings](#settings) · [Data](#data) · [Build](#build-from-source)

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
| Token | Read-only, renews itself | Fetched from `gh` each launch |
| Stored | Keychain | Memory only |
| Orgs | Owner installs the app → **Request Approval** | Scopes `repo`, `read:org` |
| Org board | App's Projects permission | Scope `read:project` |
| Personal boards | No | `read:project` |

The first-run screen offers your `gh` logins first if there are any. PullBull never picks one by itself.

### GitHub CLI setup

**Set Up GitHub CLI** opens a checklist that ticks itself off. PullBull runs nothing.

```bash
brew install gh
gh auth login --web -s read:project     # new login
gh auth refresh -s read:project         # existing login
```

Without `read:project`: Board shows the command to add it, Assigned groups by repo.

### No organization

- Pick repos on GitHub (all or some). The window closes once GitHub confirms
- Your own repos only, no Team tab
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
| Right-click | Settings · Check for Updates · Quit |

## Pull Requests

<kbd>⌘</kbd><kbd>1</kbd>

| Tab | Shows |
|---|---|
| Review | PRs waiting on you or your team. Icon says why: requested, team, re-requested, new commits |
| Mine | Your PRs, review pills, checks, **Ready to merge**. Folded "Recently closed" |
| Team | Other open PRs in the org |

> [!NOTE]
> Ready to merge = approved, no changes requested, checks green or none, no conflicts, not a draft. It doesn't see branch protection (required review count).

- **Detail:** reviewers, checks, description, conversation, files. Markdown incl. `<details>`
- **Right-click a row:** copy branch, link or Markdown link · open on GitHub · show only this repo · search author
- **Footer:** account · refresh · open on GitHub · settings. Turns amber with **Retry** when a refresh fails

## Issues

<kbd>⌘</kbd><kbd>2</kbd>

| Tab | Shows | Grouped by |
|---|---|---|
| Assigned | Your issues | Board Status, then "Not on board" |
| Created | Issues you opened | Repo |
| Board | All open issues on the board | Board Status. Done folded, last 14 days |

- **Switch board:** click its name in the filter row, or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>B</kbd>
- **Detail:** board card · linked PRs (<kbd>Esc</kbd> returns) · description · last two comments

## Search

<kbd>/</kbd>, <kbd>⌘</kbd><kbd>F</kbd>, or just type. Searches the current mode, open and closed.

| Token | Matches |
|---|---|
| `@alice` `@me` | Author or reviewer. On issues: author or assignee |
| `~bug` `~"good first issue"` | Label |
| `is:open` `is:closed` `is:merged` `is:draft` | State |
| `#123` | That number, every repo |
| `owner/repo#123` or a link | Exactly that item |
| words | Title |

- `@`, `~`, `is:` and words combine; everything must match
- `#123` and links work only on their own
- Results span all tabs; click a tab to narrow
- Matches in the other mode show a hint: <kbd>⌘</kbd><kbd>1</kbd> / <kbd>⌘</kbd><kbd>2</kbd>
- Empty field shows saved searches and token hints. <kbd>↓</kbd> to walk them
- **Save:** bookmark icon in the field. Manage in Settings → Search

| Completion list | |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Choose |
| <kbd>Return</kbd> · <kbd>Tab</kbd> | Complete |
| <kbd>Esc</kbd> | Close |

## Ask AI

<kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> in the search field. Finds a PR or issue from a loose description ("the one that fixed the login redirect, last week") and answers a short question about it, using Anthropic's API with your own key. Off by default.

### Set up

Settings → Ask AI.

| Control | Default |
|---|---|
| Ask AI on/off | Off |
| Anthropic API key | Empty. Stored in the Keychain only |
| Model | The newest Sonnet your key can use. The newest Haiku is cheaper and less accurate. The list updates when you save the key; if Anthropic retires the chosen model, the next one takes over. Keys saved before this version keep the built-in list until saved again |
| Exclude from Ask AI | Empty. Pick from the repos of the current org or scope; excluded repos are never stored or sent |
| Index | Shown while Ask AI is on: items indexed, backfill progress ("N of ~M") or last sync, **Rebuild** |

- The key can be saved only while Ask AI is on. It is checked when you save it (`GET /v1/models`, free). A bad key never reaches a question. [Get a key](https://platform.claude.com/settings/keys)
- Without a key, <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> says "Add an Anthropic API key in Settings → Ask AI" and sends nothing

### What is sent

| When | To Anthropic |
|---|---|
| You save the key | The key, for the check |
| You press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> | Your question and up to 40 matching PR and issue descriptions (first 1,500 characters each, plus title, author, state, labels, dates) |
| Anything else | Nothing |

- Matching runs on this Mac. Only the best matches are sent
- Excluded repos are never sent
- Descriptions are untrusted text. Ask AI can't write to GitHub or act on anything; only items it was shown become links

### Asking

| | |
|---|---|
| Ask | Type the description, press <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd>. Normal results stay on screen; an "Asking…" row shows at the top |
| Cancel | <kbd>Esc</kbd>, or edit the field |
| Answer | Answer on top, then PRs and issues in one list, each with a line on why it matched |
| Open | <kbd>Return</kbd> opens the item in its own mode. <kbd>Esc</kbd> or <kbd>←</kbd> in the detail returns to Ask AI |
| GitHub · copy | <kbd>⌘</kbd><kbd>Return</kbd> opens on GitHub. Copy keys work as in the list |
| Edit and re-ask | <kbd>Esc</kbd> or <kbd>←</kbd> on Ask AI returns to the field with the question kept |
| Empty or edit the field | Back to normal search |

- Each question stands alone; there are no follow-up questions
- Questions about deployment ("is it on production?") are answered only from what descriptions and labels say. The answer says so when it can't confirm
- "Nothing matched" is a valid answer; try other words
- Errors show as one line in place of the answer: no network, key rejected, rate limited, no answer in 20 s, declined, answer cut off, no answer, model retired, HTTP error
- While the index is still syncing, Ask AI runs on what is indexed and says so

### Index

| | |
|---|---|
| Contents | PRs and issues updated in the last 90 days in the account's scope, with full descriptions. No comments |
| Where | This Mac, in the cache folder ([Data](#data)). Never sent as a whole |
| Built | Turning Ask AI on starts a paced backfill; regular refresh goes first. Then it updates on each refresh |
| Deleted | Ask AI off (every index file), sign-out, or a renamed login. **Rebuild** empties the index and refetches; the file stays |
| Excluded repos | Never stored. Rows are deleted when you add a repo to the list; removing it backfills the repo |

### Cost

- No spending cap in PullBull. Set limits in the Anthropic console
- Cost depends on how long your descriptions are

## Keyboard

| List | |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Select |
| <kbd>←</kbd> <kbd>→</kbd> | Previous / next tab |
| <kbd>Return</kbd> | Detail |
| <kbd>⌘</kbd><kbd>Return</kbd> | Open on GitHub |
| <kbd>⌘</kbd><kbd>C</kbd> | Copy link |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>C</kbd> | Copy `owner/repo#123` |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy Markdown link |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> | [Ask AI](#ask-ai), from the search field |
| <kbd>⌘</kbd><kbd>1</kbd> · <kbd>⌘</kbd><kbd>2</kbd> | Pull Requests · Issues |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>F</kbd> | Repo menu |
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>B</kbd> | Board menu |
| <kbd>⌘</kbd><kbd>R</kbd> | Refresh |
| <kbd>⌘</kbd><kbd>,</kbd> | Settings |
| <kbd>Esc</kbd> | Clear search → clear repo → close |
| <kbd>⌘</kbd><kbd>W</kbd> | Close |

| Detail | |
|---|---|
| <kbd>Esc</kbd> · <kbd>←</kbd> · <kbd>⌘</kbd><kbd>[</kbd> | Back |
| <kbd>⌘</kbd><kbd>Return</kbd> | Open on GitHub |
| <kbd>⌘</kbd><kbd>C</kbd> · <kbd>⌘</kbd><kbd>⇧</kbd><kbd>C</kbd> · <kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> | Same copies as the list |
| <kbd>⌘</kbd><kbd>R</kbd> | Refresh |

Reopen within a minute and the detail is still there.

## One repo

- Right-click a row → **Show Only *repo***, or <kbd>⌘</kbd><kbd>⇧</kbd><kbd>F</kbd>
- Applies to every tab; search stays inside it
- Counts and notifications still cover all repos
- Cleared on relaunch

## Settings

<kbd>⌘</kbd><kbd>,</kbd> or the footer gear.

| Tab | |
|---|---|
| General | Background, filters, menu bar count, refresh interval, shortcut, launch at login, updates |
| Account | Account, org, board, access notices |
| Notifications | One toggle per event |
| Search | Saved searches |
| Ask AI | [Ask AI](#ask-ai): on/off, key, model, exclude list, index |

| Notification | Default |
|---|---|
| Review requested | on |
| PR approved | on |
| Changes requested | on |
| CI failed | on |
| New comment | on |
| PR merged by someone else | on |
| Issue assigned by someone else | off |

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
