#!/usr/bin/env bash
# Builds the landing page (site/) for www.regetskcob.de/knx/ and puts it into the
# website repo (Hugo, GitHub Pages) under static/knx/. There it is served
# unchanged on the next build of the website.
#
#   tool/deploy_site.sh            # build + copy (without commit)
#   tool/deploy_site.sh --push     # also commit and push
#
# The social page /knx/socials/ (tool/social/preview.py) is kept on a deploy.
#
# The start pages /knx/ and /knx/en/ redirect to knx-monitor.de (where the
# teaser lives, teaser/), as does /knx/box/. Support, privacy policy and
# account deletion exist only on knx-monitor.de now. Only the
# buy page (with business registration) and the preview stay here.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=werkbank/lib/common.sh
. "$(dirname "$0")/werkbank/lib/common.sh"
wb_enter_repo
wb_load_conf
[ $# -le 1 ] || { echo "usage: $0 [--push]" >&2; exit 1; }
case "${1:-}" in
  ""|--push) ;;
  *) echo "usage: $0 [--push]" >&2; exit 1 ;;
esac
WEB=${WEBSITE_REPO:-$HOME/dev/website/regetskcob.github.io}
DIR=knx
OUT=$(wb_site_build site "https://www.regetskcob.de/$DIR/")
# Public site without buy page and offers (prices) as long as no
# business is registered.
if [ "${HUGO_PARAMS_COMMERCE:-}" != true ]; then
  rm -rf "$OUT/kaufen" "$OUT/en/buy"
fi
# Support, privacy policy and account deletion live on knx-monitor.de (teaser/).
rm -rf "$OUT/support" "$OUT/datenschutz" "$OUT/konto-loeschen" "$OUT/en/support" "$OUT/en/privacy" "$OUT/en/delete-account"
# Replace what exists there – the public site keeps the socials/ folder, otherwise
# the social page would be gone. The commit happens only after the redirects.
WEBSITE_REPO=$WEB wb_site_blog "$OUT" "$DIR" --keep /socials/
# GitHub Pages has no server-side redirects; a small page
# redirects immediately and names the new address as canonical.
if [ "$DIR" = knx ]; then
  redirect() {
    cat >"$1" <<HTML
<!doctype html>
<html lang="$2">
<meta charset="utf-8">
<title>KNX Monitor</title>
<meta name="robots" content="noindex">
<link rel="canonical" href="$3">
<meta http-equiv="refresh" content="0; url=$3">
<script>location.replace('$3' + location.hash)</script>
<p><a href="$3">$3</a></p>
</html>
HTML
  }
  redirect "$WEB/static/knx/index.html" de https://knx-monitor.de/
  redirect "$WEB/static/knx/en/index.html" en https://knx-monitor.de/en/
  # The KNX Box page moved as well (teaser/content/box.*.md).
  mkdir -p "$WEB/static/knx/box" "$WEB/static/knx/en/box" "$WEB/static/knx/preview/socials"
  redirect "$WEB/static/knx/box/index.html" de https://knx-monitor.de/box/
  # Old address of the social page.
  redirect "$WEB/static/knx/preview/socials/index.html" de https://www.regetskcob.de/knx/socials/
  redirect "$WEB/static/knx/en/box/index.html" en https://knx-monitor.de/en/box/
fi
if [ "${1:-}" = "--push" ]; then
  git -C "$WEB" add "static/$DIR"
  git -C "$WEB" commit -m "KNX Monitor: Landingpage aktualisieren"
  git -C "$WEB" push
fi
