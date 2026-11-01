# Contributing

Bug reports and fixes welcome. For anything bigger, open an issue first.

## Build and test

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -scheme PullBull -derivedDataPath build
swift test --package-path Packages/PullBullKit
```

- Details: [Build from source](docs/manual.md#build-from-source)
- No Apple team needed. Sign in with GitHub won't work in your build; `gh` logins do
- Rerun `xcodegen generate` after adding files or editing `project.yml`

## Pull requests

- [ ] `swift test` passes
- [ ] No compiler warnings (CI fails on them)
- [ ] Logic goes in `PullBullKit`, with tests. Views stay thin
- [ ] One change per PR

CI on PRs from forks waits for a maintainer's approval. A PR that changes only docs (Markdown, `docs/`, the issue and PR templates) skips the build and tests; the secrets scan always runs.

## Out of scope

| | Why |
|---|---|
| Writing to GitHub beyond Status, assignees and labels (merge, comment, approve, close) | PullBull triages; GitHub is where work is written |
| Telemetry, analytics, crash SDKs | No data leaves the Mac except to GitHub, and to Anthropic when you use Ask AI |
| New third-party dependencies | Sparkle is the only one |
| Web views | Native SwiftUI and AppKit only |

## Security

See [SECURITY.md](SECURITY.md). Don't open an issue.
