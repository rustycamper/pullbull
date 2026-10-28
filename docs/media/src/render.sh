#!/bin/zsh
# Renders the README stills at 2x with headless Chrome, each in dark and light, to ../<name>-{dark,light}.png:
#   review -> popover, board, pr-detail, issue-detail, search (the default set); mine on request.
# Usage: ./render.sh [scene ...]
set -euo pipefail
here=${0:A:h}
W=520 H=640
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# SF Symbols and the cursor are Apple's, so they're exported locally (git-ignored), never committed.
# Needs a built app for the custom pullbull.* symbols: xcodebuild build -scheme PullBull -derivedDataPath build
if [[ ! -f $here/symbols/manifest.js ]]; then
  app=${PULLBULL_APP:-$here/../../../build/Build/Products/Debug/PullBull.app}
  [[ -d $app ]] || { print -u2 "Build the app first, or set PULLBULL_APP: $app not found"; exit 1; }
  swift "$here/export-symbols.swift" "$app" "$here/symbols"
  swift "$here/export-cursor.swift" "$here/symbols/cursor-arrow.png"
fi
scenes=(${@:-review} ); (( $# )) || scenes=(review board pr-detail issue-detail search)
for data in $scenes; do
  name=$data; [[ $data == review ]] && name=popover
  for scheme in dark light; do
    "$chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
      --allow-file-access-from-files --window-size=$W,$H \
      --screenshot="$here/../$name-$scheme.png" \
      "file://$here/popover.html?scheme=$scheme&data=$data&width=$W&height=$H" 2>/dev/null
  done
done
