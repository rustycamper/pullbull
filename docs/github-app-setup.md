# GitHub App setup

Only for **Sign in with GitHub** in a fork shipped under its own name, or a private test app. `gh` logins need none of this.

- The device flow needs a GitHub App's client ID
- The official app is *PullBull for macOS*, owned by rustycamper. Its ID and slug are in `Config/Shared.xcconfig`

## 1. Create

[github.com/settings/apps/new](https://github.com/settings/apps/new), or `github.com/organizations/<org>/settings/apps/new` for an org.

| Field | Value |
|---|---|
| Name | Your app's name (the official one is `PullBull for macOS`; plain `PullBull` is taken) |
| Description | Below |
| Homepage URL | Your repo |
| Callback URL | Empty |
| Expire user authorization tokens | ✓ (default) |
| Request user authorization during installation | ✗ |
| **Enable Device Flow** | **✓** |
| Webhook → Active | **✗** |
| Installable on | **Any account** to share it, **Only on this account** for a private app |

Description (Markdown, shown on the install and sign-in pages):

```
A native macOS menu bar app for the pull requests and issues that need you: reviews requested, your open PRs, your team's work, and assigned issues, with a badge count and notifications.

PullBull writes to GitHub only the board Status, assignees and labels you pick. It never merges, comments, approves or closes, and your sign-in stays in your Mac's Keychain.
```

### Permissions

**Issues** and **Projects** are **Read and write**, for editing the board Status, assignees and labels. The rest are **Read-only**. Everything else: No access.

| Repository | Organization |
|---|---|
| Metadata (automatic) | Members |
| Pull requests | Projects: **Read and write** |
| Issues: **Read and write** | |
| Checks | |
| Commit statuses | |
| Contents (PR file list) | |

## 2. After creating

| | |
|---|---|
| Logo | Glyph from `docs/icon/AppIcon.svg` only, mint on transparent, 1024 px, cropped tight. A full icon tile shows as a box inside GitHub's round badge |
| Badge background | `#141518` |
| Client ID | Starts with `Iv23`. Public |
| Slug | Last part of `github.com/apps/<slug>` |
| Client secret, private key | **Don't generate.** PullBull uses neither; the repo must never hold a secret |

## 3. Install

1. `https://github.com/apps/<slug>/installations/new`
2. Pick the org → **All repositories** → Install
3. Also install on your personal account to see your own repos' PRs in Review and Mine

## 4. Configure the build

In `Config/Local.xcconfig` (git-ignored):

```
PULLBULL_GITHUB_CLIENT_ID = Iv23...
PULLBULL_GITHUB_APP_SLUG = <slug>
```
