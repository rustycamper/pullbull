# Security

## Reporting a vulnerability

Don't open a public issue. Use **Security → Report a vulnerability** on this repo, or [report one here](https://github.com/rustycamper/pullbull/security/advisories/new). You'll get a reply in the advisory.

Only the latest release is supported.

## What's in scope

- **Tokens:** the Sign in with GitHub token and the Anthropic API key are kept in the macOS Keychain, on this Mac only. A `gh` token is held in memory only.
- **Writes to GitHub:** PullBull writes only what you pick: an issue's board Status, assignees and labels, a pull request's review requests, assignees and labels, the comments you write, the reviews you submit, and the pull requests you merge or set to merge, each only after a separate confirm and never bypassing the repository's rules. Anything that writes more, or writes without you picking it, is a vulnerability.
- **Network:** PullBull talks to the GitHub API, GitHub avatars, the GitHub release feed, and the Anthropic API when Ask is on. A request anywhere else is a vulnerability.
- **Untrusted content:** PR and issue text, Markdown and links come from GitHub users. Opening anything other than a web link from them is a vulnerability.
- **Updates:** Sparkle updates are signed. A way to install an unsigned or tampered update is a vulnerability.
