#!/usr/bin/env bash
# Updates the public repository regetskcob/KNX-Monitor-HA (the Busclear
# integration for Home Assistant, installed through HACS) from ha-integration/
# at HEAD. Every sync is one commit there, named after the commit here.
#
#   tool/sync_ha_integration.sh [--push] [--release]
#
# --push      pushes the commit.
# --release   also tags v<version from manifest.json> and creates the GitHub
#             release HACS offers as the update (implies --push).
# Checkout: $HA_INTEGRATION_DIR (default ~/dev/knx-monitor/KNX-Monitor-HA).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=regetskcob/KNX-Monitor-HA
DIR=${HA_INTEGRATION_DIR:-$HOME/dev/knx-monitor/KNX-Monitor-HA}
push=0 release=0
for arg in "$@"; do
  case "$arg" in
    --push) push=1 ;;
    --release) push=1 release=1 ;;
    *) echo "usage: $0 [--push] [--release]" >&2; exit 1 ;;
  esac
done
[ -z "$(git status --porcelain -- ha-integration)" ] || { echo "commit ha-integration/ first" >&2; exit 1; }

if [ ! -d "$DIR/.git" ]; then
  git clone -q "git@github.com:$REPO.git" "$DIR"
fi
# The checkout is replaced below: only a clean one that is up to date.
[ -z "$(git -C "$DIR" status --porcelain)" ] || { echo "$DIR has local changes – look at them first" >&2; exit 1; }
# An empty repository (first sync) has nothing to pull yet; a failed probe stops.
heads=$(git -C "$DIR" ls-remote --heads origin) || { echo "cannot reach $REPO" >&2; exit 1; }
if [ -n "$heads" ]; then
  git -C "$DIR" pull -q --ff-only || { echo "$DIR cannot fast-forward to origin – look at it first" >&2; exit 1; }
fi

# Replace everything except .git with the committed state of ha-integration/.
find "$DIR" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git archive HEAD ha-integration | tar -x --strip-components=1 -C "$DIR"
# Same secret scan as the public source (tool/export_public_source.sh), before
# anything is committed there; publishing needs gitleaks.
command -v gitleaks >/dev/null || { echo "gitleaks not installed (brew install gitleaks); required for publishing" >&2; exit 1; }
gitleaks dir --no-banner --redact --config tool/public_source/gitleaks.toml "$DIR" || {
  echo "gitleaks found secrets in ha-integration/ – remove them (and rotate) first; nothing was committed in $DIR" >&2
  exit 1
}

head=$(git rev-parse --short=8 HEAD)
version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
  "$DIR/custom_components/knx_monitor/manifest.json")
git -C "$DIR" add -A
if git -C "$DIR" diff --cached --quiet; then
  echo "nothing changed since the last sync"
else
  git -C "$DIR" commit -q -m "Stand $head" -m "Busclear integration $version, generated from ha-integration/ as of $head."
  echo "committed in $DIR: $(git -C "$DIR" log -1 --format='%h %s')"
fi
[ "$push" = 1 ] || exit 0
git -C "$DIR" push -q origin HEAD
echo "pushed to $REPO"
[ "$release" = 1 ] || exit 0
tag="v$version"
if git -C "$DIR" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "$tag exists – raise the version in manifest.json for a new release" >&2
  exit 1
fi
git -C "$DIR" tag -a "$tag" -m "Busclear integration $version"
git -C "$DIR" push -q origin "$tag"
gh release create "$tag" -R "$REPO" --title "Busclear $version" --latest \
  --notes "Busclear integration $version. Needs the Busclear add-on 1.9.7 or newer; see README for what it adds."
echo "released $tag"
