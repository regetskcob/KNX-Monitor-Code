#!/usr/bin/env bash
# Updates the public repository regetskcob/KNX-Monitor, which Home Assistant
# reads as add-on repository. It holds no source code: only the add-on
# metadata of a released version, the public README, LICENSE (GPLv3),
# SECURITY.md and the issue templates (tool/public-repo/).
#
#   tool/sync_public.sh [addon-v<version>] [--push]
#
# The add-on files come from the given tag (default: the latest addon-v* tag),
# never from the working tree – Home Assistant offers whatever version
# config.yaml names, so it must only ever see versions whose images exist.
# Without --push the commit stays local in the checkout for review.
# Checkout: $PUBLIC_REPO_DIR (default ~/dev/knx-monitor/KNX-Monitor), cloned if missing.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLIC_REPO=regetskcob/KNX-Monitor
DIR=${PUBLIC_REPO_DIR:-$HOME/dev/knx-monitor/KNX-Monitor}
ADDON_FILES=(config.yaml DOCS.md CHANGELOG.md README.md icon.png logo.png translations)

tag='' push=0
for arg in "$@"; do
  case "$arg" in
    --push) push=1 ;;
    addon-v*) tag=$arg ;;
    *) echo "usage: $0 [addon-v<version>] [--push]" >&2; exit 1 ;;
  esac
done
[ -n "$tag" ] || tag=$(git tag --list 'addon-v*' --sort=-v:refname | head -1)
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "tag $tag not found" >&2; exit 1; }

if [ ! -d "$DIR/.git" ]; then
  git clone -q "https://github.com/$PUBLIC_REPO.git" "$DIR"
fi
git -C "$DIR" pull -q --ff-only 2>/dev/null || true

# Replace everything except .git, so files removed here also disappear there.
find "$DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git archive HEAD:tool/public-repo | tar -x -C "$DIR"
# Docker: the template always names the published version, never "latest".
compose=$DIR/docker/compose.yaml
sed "s/KNX_MONITOR_VERSION:-[0-9][0-9.]*/KNX_MONITOR_VERSION:-${tag#addon-v}/" "$compose" >"$compose.new"
mv "$compose.new" "$compose"
git show "$tag:repository.yaml" >"$DIR/repository.yaml"
mkdir -p "$DIR/ha-addon/knx_monitor"
git archive "$tag" "${ADDON_FILES[@]/#/ha-addon/knx_monitor/}" | tar -x -C "$DIR"

git -C "$DIR" add -A
if git -C "$DIR" diff --cached --quiet; then
  # Nothing new, but a commit of an earlier run without --push may be waiting.
  if [ $push = 1 ] && [ "$(git -C "$DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)" -gt 0 ]; then
    git -C "$DIR" push -q origin HEAD
    echo "pushed the waiting commit to $PUBLIC_REPO ($tag)"
  else
    echo "public repository already up to date ($tag)"
  fi
  exit 0
fi
git -C "$DIR" commit -q -m "Home Assistant add-on ${tag#addon-v}"
if [ $push = 1 ]; then
  git -C "$DIR" push -q origin HEAD
  echo "pushed $tag to $PUBLIC_REPO"
else
  echo "committed $tag in $DIR – review, then push (or rerun with --push)"
fi
