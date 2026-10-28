# PullBull manual

Every tab, key and setting. Overview: [README](../README.md).

[Install](#install) · [Sign in](#sign-in) · [Pull Requests](#pull-requests) · [Issues](#issues) · [Search](#search) · [Keyboard](#keyboard) · [One repo](#one-repo) · [Settings](#settings) · [Data](#data) · [Build](#build-from-source)

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
| Sign-in tokens | Keychain, this Mac only, not synced |
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
