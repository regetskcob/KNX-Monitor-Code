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
# Only what is reviewed and merged becomes public: a branch or an unpushed
# commit on main would publish code that never went through a pull request.
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
  { echo "HEAD differs from origin/main – publish only the merged main" >&2; exit 1; }

if [ ! -d "$DIR/.git" ]; then
  git clone -q "git@github.com:$PUBLIC_CODE.git" "$DIR"
fi
# The checkout is replaced below: only a clean one that is up to date.
[ -z "$(git -C "$DIR" status --porcelain)" ] || { echo "$DIR has local changes – look at them first" >&2; exit 1; }
git -C "$DIR" pull -q --ff-only || { echo "$DIR cannot fast-forward to origin – look at it first" >&2; exit 1; }

snapshot=$(mktemp -d)
trap 'rm -rf "$snapshot"' EXIT
# shellcheck disable=SC2086 # empty or one flag
# Publishing needs gitleaks; the pattern check alone is not enough.
KNX_REQUIRE_GITLEAKS=1 tool/export_public_source.sh "$snapshot/tree" $build

# Replace everything except .git, so files removed here also disappear there.
find "$DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
(cd "$snapshot/tree" && tar --exclude=./.git -cf - .) | tar -x -C "$DIR"

head=$(git rev-parse --short HEAD)
git -C "$DIR" add -A
if git -C "$DIR" diff --cached --quiet; then
  echo "nothing changed since the last sync"
else
  git -C "$DIR" commit -q -m "Stand $head" \
    -m "Source of KNX Monitor as of $head, without the private parts (tool/public_source/private.txt)."
  echo "committed in $DIR: $(git -C "$DIR" log --oneline -1)"
fi

# The wiki is generated from docs/ of the same snapshot (build_wiki.py). Its
# repository only exists once the first page was created on GitHub.
WIKI=${PUBLIC_WIKI_DIR:-$DIR.wiki}
if [ ! -d "$WIKI/.git" ]; then
  url="git@github.com:$PUBLIC_CODE.wiki.git"
  if probe=$(git ls-remote "$url" 2>&1); then
    git clone -q "$url" "$WIKI"
  elif grep -q "not found" <<<"$probe"; then
    echo "wiki skipped: create its first page on GitHub, then run again"
  else
    echo "$probe" >&2
    exit 1
  fi
fi
if [ -d "$WIKI/.git" ]; then
  [ -z "$(git -C "$WIKI" status --porcelain)" ] || { echo "$WIKI has local changes – look at them first" >&2; exit 1; }
  git -C "$WIKI" pull -q --ff-only || { echo "$WIKI cannot fast-forward to origin – look at it first" >&2; exit 1; }
  python3 -I tool/public_source/build_wiki.py "$snapshot/tree" "$WIKI"
  git -C "$WIKI" add -A
  if ! git -C "$WIKI" diff --cached --quiet; then
    git -C "$WIKI" commit -q -m "Stand $head" -m "Generated from docs/ as of $head."
    echo "committed in $WIKI: $(git -C "$WIKI" log --oneline -1)"
  fi
fi

# A commit from an earlier run without --push is pushed now as well.
if [ "$push" = 1 ]; then
  git -C "$DIR" push -q origin HEAD:main
  echo "pushed to $PUBLIC_CODE"
  if [ -d "$WIKI/.git" ]; then
    git -C "$WIKI" push -q origin HEAD
    echo "pushed the wiki"
  fi
fi
