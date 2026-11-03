#!/usr/bin/env bash
# Header image of the website (og.png, banner.png) from the page site/content/header.de.md
# (layout site/layouts/header.html, Horizont CSS): start Hugo with drafts,
# capture with headless Chrome at double resolution.
#   tool/site_header.sh
# Generate the website images first: tool/store_shots.sh, then
# python3 tool/launch_graphics.py --site
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/site/static/images
PORT=1415
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
hugo server -D --source "$ROOT/site" --port $PORT --bind 127.0.0.1 \
  --baseURL "http://localhost:$PORT/knx/" --renderToMemory >"$TMP/hugo.log" 2>&1 &
HUGO=$!
trap 'kill $HUGO 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 60); do curl -sf "http://localhost:$PORT/knx/header/" >/dev/null && break; sleep 0.5; done
"$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1200,630 --virtual-time-budget=4000 \
  --screenshot="$TMP/header.png" "http://localhost:$PORT/knx/header/" >/dev/null 2>&1
cp "$TMP/header.png" "$OUT/banner.png"
sips -z 630 1200 "$TMP/header.png" --out "$OUT/og.png" >/dev/null
sips -g pixelWidth -g pixelHeight "$OUT/banner.png" "$OUT/og.png" | grep -v '^/' | paste - -
