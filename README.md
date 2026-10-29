<div align="center">

<img src="docs/icon/AppIcon.svg" width="128" alt="PullBull icon">

# PullBull

**GitHub pull requests, issues and Projects boards in the macOS menu bar.**

Keyboard-first · Native SwiftUI · Read-only

[![Release](https://img.shields.io/github/v/release/rustycamper/pullbull?style=flat-square&color=36d399&label=release)](https://github.com/rustycamper/pullbull/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/rustycamper/pullbull/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/rustycamper/pullbull/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-141518?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Homebrew](https://img.shields.io/badge/brew-rustycamper%2Ftap-141518?style=flat-square&logo=homebrew&logoColor=white)](#install)
[![License: MIT](https://img.shields.io/badge/license-MIT-141518?style=flat-square)](LICENSE)

[Install](#install) · [Tabs](#tabs) · [Search](#search) · [Keys](#keys) · [Privacy](#privacy) · [Manual](docs/manual.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/popover-dark.png">
  <img src="docs/media/popover-light.png" width="360" alt="PullBull Review tab in the menu bar popover">
</picture>

</div>

## Problem → solution

| &emsp;&emsp; | Problem | PullBull |
|:-:|---|---|
| <img src="docs/media/icons/bell-badge.png" width="22" height="22" alt=""> | Review requests get lost among CI, mentions and bot comments | **Review** tab with only PRs waiting on you or your team. Count in the menu bar |
| <img src="docs/media/icons/sparkles.png" width="22" height="22" alt=""> | Agents open PRs faster than you can track them | **Mine** tab: review state, checks, *Ready to merge* when approved and green |
| <img src="docs/media/icons/arrow-triangle-2-circlepath.png" width="22" height="22" alt=""> | Re-requests and new commits after your review go unnoticed | Both land back in **Review**, marked with why |
| <img src="docs/media/icons/rectangle-split-3x1.png" width="22" height="22" alt=""> | The Projects board is slow for a quick look | **Assigned** and **Board** tabs, grouped by board Status |
| <img src="docs/media/icons/link.png" width="22" height="22" alt=""> | Finding the PR that closes an issue takes clicks | Issue detail lists its linked PRs. Open one, <kbd>Esc</kbd> returns |
| <img src="docs/media/icons/bolt.png" width="22" height="22" alt=""> | "Where is #123?" means opening a browser | <kbd>⌃</kbd><kbd>⌥</kbd><kbd>P</kbd>, type `#123` or paste the link, <kbd>Return</kbd> |
| <img src="docs/media/icons/text-magnifyingglass.png" width="22" height="22" alt=""> | A chat mentions a PR or issue loosely: no link, no number | **Ask**: describe it in your own words (<kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd>), answered by Anthropic with your own API key. Off by default |
| <img src="docs/media/icons/slider-horizontal-3.png" width="22" height="22" alt=""> | Notifications are all or nothing | Toggle each event separately |
| <img src="docs/media/icons/keyboard.png" width="22" height="22" alt=""> | Web UIs make you reach for the mouse | Keyboard-first. Every action has a key; start typing anywhere to search |
| <img src="docs/media/icons/macwindow.png" width="22" height="22" alt=""> | Most dev tools are web apps in a window | Native SwiftUI and AppKit, no web views. System materials, light and dark, VoiceOver, Reduce Motion |

## Screens

| Pull request detail | Issue detail |
|:-:|:-:|
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/media/pr-detail-dark.png"><img src="docs/media/pr-detail-light.png" width="360" alt="Pull request detail, Ready to merge"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/media/issue-detail-dark.png"><img src="docs/media/issue-detail-light.png" width="360" alt="Issue detail with board card and linked PRs"></picture> |
| **Board** | **Search** |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/media/board-dark.png"><img src="docs/media/board-light.png" width="360" alt="Board tab grouped by Status"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/media/search-dark.png"><img src="docs/media/search-light.png" width="360" alt="Search with people completion"></picture> |

## Tabs

| &emsp;&emsp;&emsp; | Mode | Tab | Shows |
|:-:|---|---|---|
| <kbd>⌘</kbd><kbd>1</kbd> | **Pull Requests** | Review | PRs requesting your or your team's review, re-requests, new commits since your review |
| | | Mine | Your open PRs, review pills, checks, *Ready to merge* |
| | | Team | Other open PRs in the org |
| <kbd>⌘</kbd><kbd>2</kbd> | **Issues** | Assigned | Your issues, grouped by board Status (by repo without a board) |
| | | Created | Issues you opened |
| | | Board | All open issues on the board |

## Search

| Type | Finds |
|---|---|
| `@alice` | PRs alice authored or reviews, issues they opened or are assigned |
| `~bug` | Items with that label |
| `is:open` `is:closed` `is:merged` `is:draft` | Items in that state |
| `#123` | That number, in every repo |
| a GitHub link | Exactly that PR or issue |

Combine `@`, `~`, `is:` and words. Save the searches you repeat.

Can't remember the words? [Ask AI](docs/manual.md#ask-ai) finds the item from a description. Off by default.

## Keys

| Key | Does |
|---|---|
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>P</kbd> | Open or close, from any app |
| <kbd>↑</kbd> <kbd>↓</kbd> | Select |
| <kbd>Return</kbd> · <kbd>⌘</kbd><kbd>Return</kbd> | Open detail · open on GitHub |
| <kbd>⌘</kbd><kbd>1</kbd> · <kbd>⌘</kbd><kbd>2</kbd> | Pull Requests · Issues |
| <kbd>/</kbd> or just type | Search |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>Return</kbd> | Ask (once turned on) |
| <kbd>Esc</kbd> | Back, clear, close |

Full list in the [manual](docs/manual.md#keyboard).

## Notifications

Each is a separate toggle: review requested · approved · changes requested · CI failed · new comment · merged · issue assigned.

## Requirements

- macOS 14+
- A GitHub account, via either:
  - **Sign in with GitHub** (the *PullBull for macOS* app)
  - **[GitHub CLI](https://cli.github.com)** login with `repo` and `read:org`

> [!NOTE]
> **Orgs:** an owner has to install the GitHub App before Sign in with GitHub shows the org. PullBull detects this and gives you the link to send.
>
> **Boards with `gh`:** add the `read:project` scope with `gh auth refresh -s read:project`.

## Install

```bash
brew install --cask rustycamper/tap/pullbull
```

Or download the zip from [Releases](https://github.com/rustycamper/pullbull/releases/latest) and move PullBull.app to /Applications.

- Signed with Developer ID, notarised
- Updates itself via [Sparkle](https://sparkle-project.org)

## Privacy

| &emsp;&emsp; | | |
|:-:|---|---|
| <img src="docs/media/icons/eye.png" width="22" height="22" alt=""> | Read-only | Never writes to GitHub |
| <img src="docs/media/icons/key-horizontal.png" width="22" height="22" alt=""> | Tokens | App sign-in and Anthropic API key (Ask): Keychain, this Mac only. `gh`: memory only |
| <img src="docs/media/icons/chart-bar-xaxis-ascending.png" width="22" height="22" alt=""> | Telemetry | None. No server |
| <img src="docs/media/icons/network.png" width="22" height="22" alt=""> | Network | GitHub API, GitHub avatars, GitHub release feed. Anthropic API, only if you turn Ask on. Nothing else |

No data leaves the Mac except to GitHub, and to Anthropic when you use Ask.

## Docs

- [Manual](docs/manual.md): every tab, key and setting
- [Build from source](docs/manual.md#build-from-source)
- [Own GitHub App for forks](docs/github-app-setup.md)

## Contributing

Bug reports and fixes welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
