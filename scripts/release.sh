#!/usr/bin/env bash
# Builds a PullBull release from main: archives Release as VERSION with the commit count of main as the
# build number, exports it signed with Developer ID, notarises and staples it, zips it, signs the zip for
# Sparkle, zips the dSYM and writes appcast.xml. Only once all of that succeeds does it tag v<VERSION> locally (an
# annotated tag) and print the push and `gh release create` commands. It never commits, pushes or publishes.
# The release notes are written by hand beforehand, in build/release/notes-VERSION.md (see docs/releasing.md); they
# become the GitHub release's description and, as Markdown in appcast.xml, the notes Sparkle's update dialog shows.
#
#   scripts/release.sh VERSION           e.g. scripts/release.sh 1.0.0
#   scripts/release.sh --check VERSION   preflight only: reports every problem and changes nothing
#
# Environment: PULLBULL_NOTARY_PROFILE names the notarytool keychain profile (default: pullbull).
# Outputs go to build/release/ (git-ignored).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TEAM_ID=98ZBCX6D7T
NOTARY_PROFILE=${PULLBULL_NOTARY_PROFILE:-pullbull}
REPO_URL=https://github.com/rustycamper/pullbull
FEED_URL=$REPO_URL/releases/latest/download/appcast.xml
OUT=build/release
DERIVED=$OUT/DerivedData
SPARKLE_BIN=$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin

check_only=false
version=
for arg in "$@"; do
  case $arg in
    --check) check_only=true ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) version=$arg ;;
  esac
done
if [[ -z $version ]]; then
  echo "Usage: scripts/release.sh [--check] VERSION   (e.g. 1.0.0)" >&2
  exit 2
fi
NOTES=$OUT/notes-$version.md

problems=0
# In --check mode a failure is listed and the checks go on; otherwise the first one stops the release.
fail() {
  echo "✗ $*" >&2
  if $check_only; then problems=$((problems + 1)); else exit 1; fi
}
step() { echo "==> $*"; }

# The value a build would see: the last assignment across Release.xcconfig, Shared.xcconfig and
# Local.xcconfig, in their include order. Trailing `//` comments are dropped, as xcconfig does.
xcconfig_value() {
  local key=$1 value= file line
  for file in Config/Release.xcconfig Config/Shared.xcconfig Config/Local.xcconfig; do
    [[ -f $file ]] || continue
    while IFS= read -r line; do
      line=${line%%//*}
      if [[ $line =~ ^[[:space:]]*$key[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        value=${BASH_REMATCH[1]}
        value=${value%"${value##*[![:space:]]}"}
      fi
    done < "$file"
  done
  printf '%s' "$value"
}

# The build number only ever goes up on main, and the release commits nothing to raise it.
build=$(git rev-list --count HEAD)
tag=v$version

step "Preflight for PullBull $version ($build)"

[[ $(git rev-parse --abbrev-ref HEAD) == main ]] \
  || fail "Releases are made from main; this is $(git rev-parse --abbrev-ref HEAD)."

[[ -z $(git status --porcelain) ]] \
  || fail "The git tree has uncommitted changes. Commit or remove them first (git status)."

if git fetch -q origin main; then
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] \
    || fail "HEAD isn't origin/main. Pull or push main first, so the tag lands on the published commit."
else
  fail "Couldn't fetch origin main."
fi

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "Version '$version' is not of the form 1.2.3."

if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
  fail "Tag $tag already exists locally. Pick a new version."
fi
if remote_tags=$(git ls-remote --tags origin "refs/tags/$tag"); then
  [[ -z $remote_tags ]] || fail "Tag $tag already exists on origin. Pick a new version."
else
  fail "Couldn't list origin's tags."
fi

# The published feed, if any (read only). Sparkle offers an update only for a higher sparkle:version.
# Only a 404 means "no release yet"; any other failure would drop the feed's history and skip the check.
feed_file=$(mktemp)
feed_status=$(curl -sL -o "$feed_file" -w '%{http_code}' "$FEED_URL" 2>/dev/null || true)
previous_feed=
case $feed_status in
  200) previous_feed=$(<"$feed_file") ;;
  404) ;;
  *) fail "Couldn't fetch the published feed (HTTP ${feed_status:-none}). Try again when GitHub is reachable." ;;
esac
rm -f "$feed_file"
if [[ $previous_feed == *'</channel>'* ]]; then
  published_build=$(sed -nE 's/.*<sparkle:version>([0-9]+)<\/sparkle:version>.*/\1/p' <<< "$previous_feed" | sort -n | tail -1)
  if [[ -n $published_build ]] && ((build <= published_build)); then
    fail "Build $build isn't above the published build $published_build, so Sparkle wouldn't offer it."
  fi
else
  previous_feed=
fi

if [[ -s $NOTES ]]; then
  # They go into appcast.xml inside CDATA, which this would end.
  ! grep -q ']]>' "$NOTES" || fail "$NOTES contains ']]>', which would break appcast.xml. Reword that line."
else
  fail "No release notes in $NOTES. Write them first: what's new for users, grouped by feature, then
  fixes, ending with the full changelog link (see docs/releasing.md)."
fi

for tool in xcodegen xcodebuild ditto curl; do
  command -v "$tool" > /dev/null || fail "$tool is not installed."
done

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($TEAM_ID)"; then
  fail "No \"Developer ID Application\" certificate for team $TEAM_ID in your keychain. Create it once in
  Xcode › Settings › Accounts › (your Apple ID) › $TEAM_ID › Manage Certificates… › + › Developer ID
  Application (only the team's Account Holder can), then run this again."
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1; then
  fail "The notarytool keychain profile '$NOTARY_PROFILE' is missing or can't sign in. Store it once with
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID
  (it asks for an app-specific password from account.apple.com), or set PULLBULL_NOTARY_PROFILE."
fi

[[ -n $(xcconfig_value PULLBULL_SPARKLE_PUBLIC_KEY) ]] \
  || fail "PULLBULL_SPARKLE_PUBLIC_KEY in Config/Shared.xcconfig is empty, so the release couldn't update
  itself. Run Sparkle's generate_keys once (see docs/releasing.md) and paste the public key there."

[[ $(xcconfig_value DEVELOPMENT_TEAM) == "$TEAM_ID" ]] \
  || fail "DEVELOPMENT_TEAM resolves to '$(xcconfig_value DEVELOPMENT_TEAM)', not $TEAM_ID (check Config/Local.xcconfig)."

if $check_only; then
  if ((problems > 0)); then
    echo "$problems problem(s) to fix before releasing." >&2
    exit 1
  fi
  echo "Ready to release PullBull $version ($build)."
  exit 0
fi

archive=$OUT/PullBull.xcarchive
export_dir=$OUT/export
app=$export_dir/PullBull.app
zip=$OUT/PullBull-$version.zip
# The same bytes under a second name, for the Homebrew cask only, so its download count is brew's alone.
brew_zip=$OUT/PullBull-$version-brew.zip
dsym_zip=$OUT/PullBull-$version.dSYM.zip
rm -rf "$archive" "$export_dir" "$zip" "$brew_zip" "$dsym_zip" "$OUT/notarize.zip" "$OUT/appcast.xml"
mkdir -p "$OUT"

step "Generating the project"
xcodegen generate -q

step "Archiving Release"
xcodebuild -scheme PullBull -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" -archivePath "$archive" -allowProvisioningUpdates \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  archive > "$OUT/archive.log" 2>&1 \
  || { tail -30 "$OUT/archive.log" >&2; fail "Archive failed; full log in $OUT/archive.log."; }

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
  -exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates > "$OUT/export.log" 2>&1 \
  || { tail -30 "$OUT/export.log" >&2; fail "Export failed; full log in $OUT/export.log."; }

step "Verifying the signature"
codesign --verify --deep --strict "$app" || fail "codesign --verify failed for $app."
codesign -d --entitlements - "$app" 2>/dev/null | grep -q keychain-access-groups \
  || fail "The exported app lacks keychain-access-groups, so Sign in with GitHub would fail. Check CODE_SIGN_ENTITLEMENTS."
signature=$(codesign -dvv "$app" 2>&1)
grep -q "^Authority=Developer ID Application: .*($TEAM_ID)" <<< "$signature" \
  || fail "The exported app isn't signed with this team's Developer ID Application certificate."
plist=$app/Contents/Info.plist
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist") == "$version" &&
   $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist") == "$build" ]] \
  || fail "The exported app's version isn't $version ($build)."
[[ -x $SPARKLE_BIN/sign_update ]] || fail "Sparkle's tools aren't in $SPARKLE_BIN."
app_key=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$plist")
keychain_key=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null) \
  || fail "Sparkle's private key isn't in your keychain (generate_keys -p found none)."
[[ $app_key == "$keychain_key" ]] \
  || fail "The app's SUPublicEDKey doesn't match the key in your keychain (a // in the key needs writing as /\$()/)."

step "Keeping the dSYM"
dsym=$archive/dSYMs/PullBull.app.dSYM
[[ -d $dsym ]] || fail "The archive has no PullBull.app.dSYM, so this release couldn't be symbolicated. Check that Release builds with DEBUG_INFORMATION_FORMAT = dwarf-with-dsym."
# UUID and architecture per slice, without the file path, so the app and its dSYM can be compared.
uuids() { dwarfdump --uuid "$1" | sed -E 's/^(UUID: [^ ]+ \([^)]+\)).*/\1/' | sort; }
app_uuids=$(uuids "$app/Contents/MacOS/PullBull")
[[ -n $app_uuids && $app_uuids == "$(uuids "$dsym")" ]] \
  || fail "The dSYM's UUIDs don't match the exported app's binary, so it couldn't symbolicate this release."
ditto -c -k --keepParent "$dsym" "$dsym_zip"

step "Notarising (this takes a few minutes)"
ditto -c -k --keepParent "$app" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
  --output-format json > "$OUT/notary.json" || true
status=$(plutil -extract status raw -o - "$OUT/notary.json" 2>/dev/null || echo unknown)
if [[ $status != Accepted ]]; then
  id=$(plutil -extract id raw -o - "$OUT/notary.json" 2>/dev/null || echo "<id>")
  fail "Notarisation ended with status '$status'. Details: xcrun notarytool log $id --keychain-profile $NOTARY_PROFILE"
fi
rm -f "$OUT/notarize.zip"

step "Stapling"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app" || fail "Gatekeeper rejects the stapled app (spctl --assess)."

step "Zipping and signing for Sparkle"
ditto -c -k --keepParent "$app" "$zip"
enclosure_signature=$("$SPARKLE_BIN/sign_update" "$zip") || fail "sign_update failed."
cp "$zip" "$brew_zip"

step "Writing appcast.xml"
pub_date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
item=$OUT/appcast-item.xml
cat > "$item" <<ITEM
    <item>
      <title>$version</title>
      <link>$REPO_URL/releases/tag/$tag</link>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
$(<"$NOTES")
]]></description>
      <enclosure url="$REPO_URL/releases/download/$tag/PullBull-$version.zip" type="application/octet-stream" $enclosure_signature/>
    </item>
ITEM
# Earlier releases stay listed: the new item goes above them in the published feed.
previous=$OUT/appcast-previous.xml
if [[ -n $previous_feed ]]; then
  printf '%s\n' "$previous_feed" > "$previous"
  awk -v item="$item" '
    !done && (/<item>/ || /<\/channel>/) { while ((getline line < item) > 0) print line; done = 1 }
    { print }' "$previous" > "$OUT/appcast.xml"
else
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
    echo '  <channel>'
    echo '    <title>PullBull</title>'
    echo "    <link>$FEED_URL</link>"
    cat "$item"
    echo '  </channel>'
    echo '</rss>'
  } > "$OUT/appcast.xml"
fi
rm -f "$item" "$previous"

step "Tagging $tag"
git tag -a "$tag" -m "PullBull $version ($build)"

cat <<DONE

PullBull $version ($build) is notarised, stapled and signed for Sparkle:
  $zip
  $OUT/appcast.xml

The Homebrew cask's copy of the zip (same bytes, its own download count):
  $brew_zip

Its dSYM, for symbolicating crash reports (keep it with the release):
  $dsym_zip

Publish it with:
  git push origin $tag
  gh release create $tag "$zip" "$brew_zip" "$dsym_zip" "$OUT/appcast.xml" --title "PullBull $version" --notes-file "$NOTES"
DONE
