# Releasing

```bash
scripts/release.sh --check 1.0.0   # preflight only, changes nothing
scripts/release.sh 1.0.0           # build, sign, notarise, tag
```

Then run the two commands it prints: `git push origin v1.0.0` and `gh release create …`.
Then [bump the Homebrew cask](#homebrew-cask).

## What the script does

1. **Preflight:** on `main`, clean tree, HEAD = `origin/main`, tag is new (local and origin), build number above the published appcast's, certificate, notary profile, Sparkle key and team present
2. **Build:** archive Release as `VERSION`, build number = commit count of `main`
3. **Sign:** export with Developer ID (`scripts/ExportOptions.plist`), check signature, keychain entitlement, version and Sparkle key
4. **dSYM:** check its UUIDs against the app, zip it
5. **Notarise:** notarise and staple
6. **Package:** zip, sign the zip for Sparkle, write `appcast.xml`
7. **Tag:** annotated `v<version>`, local only

- Output: `build/release/`
- Commits, pushes and publishes nothing
- The printed `gh release create` attaches the zip, `appcast.xml` and the dSYM zip (for symbolicating crash reports)
- The feed is `releases/latest/download/appcast.xml`, so every release must be marked latest, not pre-release

## Ask model list

The app offers the newest Sonnet and Haiku that the user's key lists (`GET /v1/models` on key save), so a new or retired model needs no release. `AskModel.all` (in `PullBullKit`) is only the fallback before the first key check. Before each release, check it against [Anthropic's current model list](https://platform.claude.com/docs/en/models/overview):

- Each ID still exists and is not deprecated
- The default is still the intended Sonnet
- Nothing else holds model IDs

## Homebrew cask

After the release is published, in [rustycamper/homebrew-tap](https://github.com/rustycamper/homebrew-tap):

```bash
shasum -a 256 build/release/PullBull-1.0.0.zip   # in this repo
# Casks/pullbull.rb: set version and sha256
brew audit --cask --online --strict rustycamper/tap/pullbull
git commit -am "pullbull 1.0.0" && git push
```

- Installed copies update through Sparkle (`auto_updates true`); the cask only matters for new installs
- Don't test with `brew uninstall` on a Mac running PullBull: the cask's `uninstall quit:` quits it

## One-time setup

| | |
|---|---|
| Developer ID certificate | Xcode → Settings → Accounts → the team in `Config/Release.xcconfig` → Manage Certificates → + → Developer ID Application. Account Holder only |
| Notary profile | `xcrun notarytool store-credentials pullbull --apple-id <apple-id> --team-id <team-id>` with an app-specific password from [account.apple.com](https://account.apple.com). Other name: `PULLBULL_NOTARY_PROFILE` |
| Sparkle key | Already in `Config/Shared.xcconfig`. The private key lives in the releasing Mac's login keychain. To move or replace it, see below |

### Sparkle key

```bash
xcodegen generate
xcodebuild -resolvePackageDependencies -scheme PullBull -derivedDataPath build/release/DerivedData
SPARKLE=build/release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
$SPARKLE/generate_keys            # new key into the login keychain, prints the public key
$SPARKLE/generate_keys -x <file>  # back up the private key
$SPARKLE/generate_keys -f <file>  # import it on another Mac
```

- Public key → `PULLBULL_SPARKLE_PUBLIC_KEY` in `Config/Shared.xcconfig`, `//` written as `/$()/`
- A new key locks out existing installs from updating. Keep the backup
