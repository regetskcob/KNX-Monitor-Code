#!/bin/bash
# Upgrade probe of the add-on server on this machine: the server version of a
# tag creates data, the current state takes it over, then it goes back to
# the old version. Runs with ALLOW_ALL on a free port in a test directory
# and touches neither Home Assistant nor a box. The test on a real
# Home Assistant is described in docs/resilience-tests.md.
#
#   tool/addon_upgrade_test.sh [tag]     # default: the newest addon-v*
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tag=${1:-$(git -C "$repo" tag --list 'addon-v*' --sort=-v:refname | head -1)}
[ -n "$tag" ] || { echo "kein addon-v*-Tag gefunden" >&2; exit 2; }
git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "Tag $tag unbekannt" >&2; exit 2; }

tmp=$(mktemp -d)
pid=
cleanup() {
  [ -z "$pid" ] || kill -9 "$pid" 2>/dev/null || true
  [ -n "${KEEP:-}" ] || rm -rf "$tmp"
}
trap cleanup EXIT
fail() { echo "FEHLER: $*" >&2; [ ! -f "$tmp/log" ] || tail -20 "$tmp/log" >&2; exit 1; }

echo "Baue Server aus $tag und aus dem Arbeitsstand …"
mkdir -p "$tmp/old"
git -C "$repo" archive "$tag" ha-addon/knx_monitor/server | tar -x -C "$tmp/old"
(cd "$tmp/old/ha-addon/knx_monitor/server" && dart pub get --enforce-lockfile >/dev/null && dart compile exe bin/server.dart -o "$tmp/server-old" >/dev/null)
(cd "$repo/ha-addon/knx_monitor/server" && dart pub get --enforce-lockfile >/dev/null && dart compile exe bin/server.dart -o "$tmp/server-new" >/dev/null)

port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
data=$tmp/data
mkdir -p "$data" "$tmp/web"
echo '<base href="/">' >"$tmp/web/index.html"
api=http://127.0.0.1:$port
# Today, otherwise retention rightly removes the day.
today=$(date +%F)
day=$data/installations/default/history/$today.ndjson

start() {
  PORT=$port DATA_DIR=$data WEB_DIR=$tmp/web ALLOW_ALL=1 "$1" >>"$tmp/log" 2>&1 &
  pid=$!
  for _ in $(seq 1 50); do
    curl -sf -m 2 "$api/api/bus" >/dev/null && return 0
    sleep 0.2
  done
  fail "$1 antwortet nicht"
}
stop() {
  kill -TERM "$pid"
  wait "$pid" 2>/dev/null || true
  pid=
}
get() { curl -sf -m 5 "$api/$1"; }
has() { # has <path> <text>
  get "$1" | grep -q "$2" || fail "$1 enthält nicht: $2"
}
same_data() {
  [ "$(get api/files/catalog.json)" = '{"groups":[],"style":"threeLevel"}' ] || fail "Katalog verändert"
  has api/bus '"retentionDays":30'
  has api/bus '"host":"192.0.2.1"'
  [ -f "$day" ] || fail "Verlauf fehlt"
  [ "$(wc -l <"$day" | tr -d ' ')" = 1 ] || fail "Verlauf verändert"
}

# 1. The old version creates what a user has. Host without connection (TEST-NET).
echo "1. Alte Version ($tag): Daten anlegen"
start "$tmp/server-old"
curl -sf -m 5 -X PUT -H 'Content-Type: application/json' \
  -d '{"retentionDays":30,"host":"192.0.2.1","enabled":false}' "$api/api/bus" >/dev/null || fail "Einstellungen"
curl -sf -m 5 -X PUT -d '{"groups":[],"style":"threeLevel"}' "$api/api/files/catalog.json" >/dev/null || fail "Katalog"
mkdir -p "$data/installations/default/history"
echo "{\"t\":$(date +%s)000000,\"s\":4357,\"d\":2563,\"y\":2,\"x\":\"01\",\"m\":true}" >"$day"
same_data
stop

# 2. The new version takes over everything and enables nothing on its own.
echo "2. Aktueller Stand: übernehmen"
start "$tmp/server-new"
same_data
has api/report '"enabled":false'
has api/report '"notifyKind":"off"'
[ ! -d "$data/installations/default/reports" ] || fail "Bericht ohne Einschalten"
if command -v jq >/dev/null; then
  [ "$(get api/bus | jq -r '.restarts.count // 0')" = 0 ] || fail "Upgrade als Absturz gezählt"
fi
curl -sf -m 5 "$api/healthz" >/dev/null || fail "Lebenszeichen fehlt"
stop

# 3. Back to the old version: it copes with the new files.
echo "3. Zurück auf $tag"
start "$tmp/server-old"
same_data
stop

# 4. And forward again, without a false crash.
echo "4. Erneut aktueller Stand"
start "$tmp/server-new"
same_data
if command -v jq >/dev/null; then
  [ "$(get api/bus | jq -r '.restarts.count // 0')" = 0 ] || fail "Rückweg als Absturz gezählt"
fi
stop
echo "Upgrade-Probe von $tag bestanden"
