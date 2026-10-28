#!/usr/bin/env bash
# Fails when a tracked file holds what looks like a GitHub token anywhere in the tree, or names
# client_secret in code or config (the docs discuss it on purpose). Untracked files, such as
# Config/Local.xcconfig, are not read.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
self=':!scripts/check-no-secrets.sh'
status=0
if matches=$(git grep -lE 'gh[uropst]_[A-Za-z0-9]{20,}' -- . "$self"); then
  echo "Possible GitHub tokens in:" >&2
  echo "$matches" >&2
  status=1
fi
if matches=$(git grep -l 'client_secret' -- PullBull Packages Config project.yml "$self"); then
  echo "client_secret in:" >&2
  echo "$matches" >&2
  status=1
fi
exit $status
