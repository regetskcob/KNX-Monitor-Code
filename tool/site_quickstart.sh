#!/usr/bin/env bash
# The quick start as PDF (A4, three pages, German and English) from the draft
# pages site/content/schnellstart*.md (layout site/layouts/schnellstart.html):
# start Hugo with drafts, print with headless Chrome into
# site/static/schnellstart/. Then deploy the site (tool/release.sh site knx --live).
#   tool/site_quickstart.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/site/static/schnellstart
PORT=1419
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
hugo server -D --source "$ROOT/site" --port $PORT --bind 127.0.0.1 \
  --baseURL "http://localhost:$PORT/" --renderToMemory --disableFastRender >"$TMP/hugo.log" 2>&1 &
HUGO=$!
trap 'kill $HUGO 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 60); do curl -sf "http://localhost:$PORT/schnellstart/" >/dev/null && break; sleep 0.5; done
curl -sf "http://localhost:$PORT/schnellstart/" >/dev/null || { cat "$TMP/hugo.log" >&2; exit 1; }
mkdir -p "$OUT"
for page in schnellstart:busclear-schnellstart en/schnellstart:busclear-quick-start; do
  "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=4000 \
    --print-to-pdf="$OUT/${page#*:}.pdf" "http://localhost:$PORT/${page%%:*}/" >/dev/null 2>&1
done
ls -la "$OUT"/*.pdf
