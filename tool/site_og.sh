#!/usr/bin/env bash
# Preview images for links to busclear.de (og:image, 1200×630) from the
# draft pages site/content/og*.md (layout site/layouts/og.html): start Hugo
# with drafts, capture with headless Chrome at double resolution,
# scale down to 1200×630. Then deploy the site (tool/release.sh site knx --live).
#   tool/site_og.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/site/static/images
PORT=1418
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
hugo server -D --source "$ROOT/site" --port $PORT --bind 127.0.0.1 \
  --baseURL "http://localhost:$PORT/" --renderToMemory --disableFastRender >"$TMP/hugo.log" 2>&1 &
HUGO=$!
trap 'kill $HUGO 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 60); do curl -sf "http://localhost:$PORT/og/" >/dev/null && break; sleep 0.5; done
mkdir -p "$OUT"
for page in og:og-de og-box:og-box-de en/og:og-en en/og-box:og-box-en; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1200,630 --virtual-time-budget=4000 \
    --screenshot="$TMP/${page#*:}.png" "http://localhost:$PORT/${page%%:*}/" >/dev/null 2>&1
  sips -z 630 1200 "$TMP/${page#*:}.png" --out "$OUT/${page#*:}.png" >/dev/null
done
sips -g pixelWidth -g pixelHeight "$OUT"/og-*.png | paste - - -
