#!/usr/bin/env bash
# Updates the public code repository regetskcob/KNX-Monitor-Code from HEAD.
# It holds the source under GPLv3 without the private parts (see
# tool/export_public_source.sh). Every sync is one commit there, named after
# the commit here; the private history never leaves this repository.
#
#   tool/sync_public_source.sh [--push] [--no-build]
#
# Without --push the commit stays local in the checkout for review.
# Checkout: $PUBLIC_CODE_DIR (default ~/dev/knx-monitor/KNX-Monitor-Code),
# cloned if missing.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLIC_CODE=regetskcob/KNX-Monitor-Code
DIR=${PUBLIC_CODE_DIR:-$HOME/dev/knx-monitor/KNX-Monitor-Code}
push=0 build=''
for arg in "$@"; do
  case "$arg" in
    --push) push=1 ;;
    --no-build) build=--no-build ;;
    *) echo "usage: $0 [--push] [--no-build]" >&2; exit 1 ;;
  esac
done
[ -z "$(git status --porcelain)" ] || { echo "commit first: the snapshot is built from HEAD" >&2; exit 1; }

if [ ! -d "$DIR/.git" ]; then
  git clone -q "git@github.com:$PUBLIC_CODE.git" "$DIR"
fi
git -C "$DIR" pull -q --ff-only 2>/dev/null || true

snapshot=$(mktemp -d)
trap 'rm -rf "$snapshot"' EXIT
# shellcheck disable=SC2086 # empty or one flag
tool/export_public_source.sh "$snapshot/tree" $build

# Replace everything except .git, so files removed here also disappear there.
find "$DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
(cd "$snapshot/tree" && tar --exclude=./.git -cf - .) | tar -x -C "$DIR"

head=$(git rev-parse --short HEAD)
git -C "$DIR" add -A
if git -C "$DIR" diff --cached --quiet; then
  echo "nothing changed since the last sync"
  exit 0
fi
git -C "$DIR" commit -q -m "Stand $head" -m "Source of KNX Monitor as of $head, without the private parts (backend, its operations, release workflows)."
echo "committed in $DIR: $(git -C "$DIR" log --oneline -1)"
if [ "$push" = 1 ]; then
  git -C "$DIR" push -q origin HEAD:main
  echo "pushed to $PUBLIC_CODE"
fi
