#!/usr/bin/env bash
# Publishes the teaser of knx-monitor.de (teaser/, Hugo) on the gh-pages
# branch of the public repository regetskcob/KNX-Monitor, which GitHub Pages
# serves under the custom domain. Only the built pages go there, never source;
# main of that repository stays the add-on repository (tool/sync_public.sh
# replaces everything in it, so the CNAME must not live there).
#
#   tool/deploy_teaser.sh [--push]
#
# Without --push the commit stays local in the checkout for review.
# Checkout: $PAGES_DIR (default ~/dev/knx-monitor/KNX-Monitor-pages), cloned if missing.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLIC_REPO=regetskcob/KNX-Monitor
DOMAIN=knx-monitor.de
DIR=${PAGES_DIR:-$HOME/dev/knx-monitor/KNX-Monitor-pages}

push=0
[ $# -le 1 ] || { echo "usage: $0 [--push]" >&2; exit 1; }
case "${1:-}" in
  "") ;;
  --push) push=1 ;;
  *) echo "usage: $0 [--push]" >&2; exit 1 ;;
esac

if [ ! -d "$DIR/.git" ]; then
  git clone -q "https://github.com/$PUBLIC_REPO.git" "$DIR"
  if git -C "$DIR" ls-remote --exit-code --heads origin gh-pages >/dev/null; then
    git -C "$DIR" checkout -q gh-pages
  else
    git -C "$DIR" checkout -q --orphan gh-pages
    git -C "$DIR" rm -rqf .
  fi
fi
[ "$(git -C "$DIR" branch --show-current)" = gh-pages ] || { echo "$DIR is not on gh-pages" >&2; exit 1; }
git -C "$DIR" pull -q --ff-only origin gh-pages 2>/dev/null || true

# Replace everything except .git, so removed pages disappear there too.
find "$DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
hugo --source teaser --quiet --destination "$DIR"
echo "$DOMAIN" >"$DIR/CNAME"
# No Jekyll: it would drop .well-known/ (passkeys).
touch "$DIR/.nojekyll"

git -C "$DIR" add -A
if git -C "$DIR" diff --cached --quiet; then
  echo "teaser already up to date"
  exit 0
fi
git -C "$DIR" commit -q -m "Teaser $DOMAIN ($(git rev-parse --short HEAD))"
if [ $push = 1 ]; then
  git -C "$DIR" push -q -u origin gh-pages
  echo "pushed the teaser to $PUBLIC_REPO (gh-pages)"
else
  echo "committed the teaser in $DIR – review, then push (or rerun with --push)"
fi
