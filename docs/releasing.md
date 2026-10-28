# Releasing

```bash
scripts/release.sh --check 1.0.0   # preflight only, changes nothing
scripts/release.sh 1.0.0           # build, sign, notarise, tag
```

Then run the two commands it prints: `git push origin v1.0.0` and `gh release create …`.

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
