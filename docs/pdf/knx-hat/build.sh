#!/usr/bin/env bash
# Baut die Bastler-Anleitung zum KNX-HAT (Weinzierl kBerry) aus index.html:
# Horizont-Schriften aus dem Pub-Cache kopieren, dann mit headless Chrome
# drucken. Ergebnis liegt bei der Box-Seite (teaser/static/box/), damit
# knx-monitor.de/box/ darauf verlinken kann.
#   docs/pdf/knx-hat/build.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
config="$root/.dart_tool/package_config.json"
# In einem Worktree ohne pub get die Pakete des Hauptcheckouts nehmen.
[ -f "$config" ] || config="$(cd "$root" && cd "$(git rev-parse --git-common-dir)/.." && pwd)/.dart_tool/package_config.json"
horizont="$(python3 -c "import json,sys; c=json.load(open(sys.argv[1])); print(next(p['rootUri'] for p in c['packages'] if p['name']=='horizont').removeprefix('file://'))" "$config")"
mkdir -p "$here/fonts" "$root/teaser/static/box"
cp "$horizont"/fonts/*.ttf "$horizont"/fonts/*.otf "$here/fonts/"
out="$root/teaser/static/box/knx-box-kberry.pdf"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=5000 \
  --print-to-pdf="$out" "file://$here/index.html"
echo "$out"
