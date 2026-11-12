#!/usr/bin/env bash
# Smoke test of the add-on and Docker image: starts the finished image and checks
# what no unit test sees – settings and history in the data folder across a
# restart, the box mode's access rules, and Docker as the guide documents it
# (tool/public-repo/docker: compose.yaml and the "docker run" example, settings
# changed in .env applying on the next start).
#
#   tool/smoke_docker.sh <image>
#
# The same script runs in .github/workflows/addon.yml (docker) and locally through
# tool/release.sh smoke (podman, which builds the image first). ENGINE=docker|podman
# picks the engine (default: docker if there, else podman), COMPOSE the compose
# command (default: "<engine> compose"). Every request to a container on the host
# network goes through a small curl container on that network, so the checks also
# work where the host network lives in a VM (podman on macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

image=${1:?usage: tool/smoke_docker.sh <image>}
engine=${ENGINE:-$(command -v docker >/dev/null 2>&1 && echo docker || echo podman)}
read -r -a compose <<<"${COMPOSE:-$engine compose}"
# Pinned by digest (multi-arch index of 8.11.1): it runs on the host network.
curl_image=docker.io/curlimages/curl:8.11.1@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69
guide="$PWD/tool/public-repo/docker"
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/knx-smoke.XXXXXX")
# Container names of this run only: removing them never touches a container of
# the user's (e.g. a real "knx-monitor") or of a second run.
pfx=$(basename "$work" | tr -c 'a-zA-Z0-9\n' '-' | tr '[:upper:]' '[:lower:]')
c_smoke=$pfx-smoke c_box=$pfx-box c_closed=$pfx-closed c_doc=$pfx-doc
compose+=(-p "$pfx")
# Containers write the data folder as root (docker) or as the mapped user (rootless
# podman); reading it back needs sudo only in the first case.
as_owner() { if [ "$engine" = docker ] && [ "$(id -u)" != 0 ]; then sudo "$@"; else "$@"; fi; }
step() { printf '\n==> %s\n' "$*"; }
cleanup() {
  for c in "$c_smoke" "$c_box" "$c_closed" "$c_doc"; do "$engine" rm -f "$c" >/dev/null 2>&1 || true; done
  if [ -f "$work/compose/compose.yaml" ]; then (cd "$work/compose" && "${compose[@]}" -f compose.yaml -f compose.override.yaml down >/dev/null 2>&1) || true; fi
  as_owner rm -rf "$work" 2>/dev/null || true
}
fail() {
  for c in "$c_smoke" "$c_box" "$c_closed" "$c_doc"; do
    "$engine" logs "$c" >/dev/null 2>&1 && { echo "--- logs $c"; "$engine" logs "$c" 2>&1 | tail -30; }
  done
  cleanup
}
trap fail ERR
trap cleanup EXIT
cleanup_start() { for c in "$c_smoke" "$c_box" "$c_closed" "$c_doc"; do "$engine" rm -f "$c" >/dev/null 2>&1 || true; done; }
cleanup_start
code() { curl -s -o /dev/null -m 5 -w '%{http_code}' "$@" || true; }
mode() { as_owner stat -c %a "$1" 2>/dev/null || as_owner stat -f %Lp "$1"; }
# Logs captured first: "logs | grep -q" ends in SIGPIPE under pipefail.
logs_have() { local out; out=$("$engine" logs "$1" 2>&1); grep -q "$2" <<<"$out"; }
# Response of a request, likewise captured before grep.
has() { local out; out=$(curl -sf "${@:2}"); grep -q "$1" <<<"$out"; }
# The same on the host network, from a container there.
net() { "$engine" run --rm --network host "$curl_image" "$@"; }
net_code() { net -s -o /dev/null -m 5 -w '%{http_code}' "$@" || true; }

step "Start, configure, restart, check persistence"
mkdir -p "$work/data"
run() { "$engine" run -d --name "$c_smoke" -e ALLOW_ALL=1 -e ALLOW_ALL_EXPOSED=1 -e BIND=0.0.0.0 -e TZ=Europe/Berlin -p 8765:8765 -v "$work/data:/data" "$image" >/dev/null; }
wait_up() { for _ in $(seq 1 30); do curl -sf http://localhost:8765/api/bus >/dev/null && return 0; sleep 1; done; return 1; }
run; wait_up
has '"retentionDays":30' -X PUT -H 'Content-Type: application/json' -d '{"retentionDays": 30}' http://localhost:8765/api/bus
has '<base href' http://localhost:8765/
"$engine" stop -t 10 "$c_smoke" >/dev/null && "$engine" rm "$c_smoke" >/dev/null
as_owner test -f "$work/data/app/installations/default/server.json"
run; wait_up
has '"retentionDays":30' http://localhost:8765/api/bus
"$engine" rm -f "$c_smoke" >/dev/null

# Busclear Box without Home Assistant: nothing without login, with password or device
# access from /pair everything except the raw relay; survives the restart.
step "Box mode (BOX=1) access"
mkdir -p "$work/box" "$work/box-closed"
# The test connects through the engine's port forwarding, so for the box this is
# "via cable": blocked as long as LAN_ACCESS does not allow it.
run() { "$engine" run -d --name "$c_box" -e BOX=1 -e BOX_PASSWORD=ci-box-pass -e BOX_NAME=KNX-Box-CI -e LAN_ACCESS=yes -e TZ=Europe/Berlin -p 8766:8765 -v "$work/box:/data" "$image" >/dev/null; }
# Without LAN_ACCESS the container listens on its own loopback only, so the
# published port answers nothing, not even with the correct password.
"$engine" run -d --name "$c_closed" -e BOX=1 -e BOX_PASSWORD=ci-box-pass -e TZ=Europe/Berlin -p 8767:8765 -v "$work/box-closed:/data" "$image" >/dev/null
# "Port 8765" is logged after the bind, so the server is listening by then.
for _ in $(seq 1 30); do logs_have "$c_closed" 'Busclear: Port 8765' && break; sleep 1; done
logs_have "$c_closed" 'Busclear: Port 8765'
logs_have "$c_closed" 'nur am Rechner selbst erreichbar'
test "$(code http://localhost:8767/)" = 000
test "$(code -u x:ci-box-pass http://localhost:8767/api/bus)" = 000
as_owner grep -qx no "$work/box-closed/app/lan-access"
"$engine" rm -f "$c_closed" >/dev/null
wait_up() { for _ in $(seq 1 30); do [ "$(code http://localhost:8766/)" = 401 ] && return 0; sleep 1; done; return 1; }
ws=(-H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==')
run; wait_up
pw=ci-box-pass
as_owner test ! -e "$work/box/app/box-password.txt"
# Box mode keeps its data folder to itself (keyring, passwords).
test "$(mode "$work/box/app")" = 700
test "$(code http://localhost:8766/api/bus)" = 401
test "$(code "${ws[@]}" http://localhost:8766/ws/bus)" = 401
test "$(code -u "x:$pw" http://localhost:8766/api/bus)" = 200
test "$(code -u "x:wrong" http://localhost:8766/api/bus)" = 401
# /pair hands out a one-time code, not the device key; the app exchanges it without login, once.
page=$(curl -sf -u "x:$pw" -d 'name=CI' http://localhost:8766/pair)
if printf '%s' "$page" | grep -q 'key='; then echo "/pair zeigt den Schlüssel im Link" >&2; exit 1; fi
paircode=$(printf '%s' "$page" | grep -o 'code=[A-Za-z0-9_-]*' | head -1 | cut -d= -f2)
test ${#paircode} = 43
key=$(curl -sf -d "{\"code\":\"$paircode\",\"name\":\"CI\"}" http://localhost:8766/api/box/claim | grep -o '"key":"[A-Za-z0-9_-]*"' | cut -d'"' -f4)
test ${#key} = 43
test "$(code -d "{\"code\":\"$paircode\"}" http://localhost:8766/api/box/claim)" = 403
test "$(code -H "Authorization: Bearer $key" http://localhost:8766/api/bus)" = 200
test "$(code -H "Authorization: Bearer $key" "${ws[@]}" http://localhost:8766/ws/bus)" = 101
test "$(code -H "Authorization: Bearer $key" http://localhost:8766/ws)" = 403
# Health endpoint without login, but without data.
test "$(curl -sf -m 5 http://localhost:8766/healthz)" = ok
# Device from /pair: reading yes, bus connection and keyring no.
test "$(code -H "Authorization: Bearer $key" -X PUT -d '{"host":"192.0.2.1"}' http://localhost:8766/api/bus)" = 403
test "$(code -H "Authorization: Bearer $key" http://localhost:8766/api/files/secure_keys.json)" = 403
# Pairing from the app: with the password an admin access, a /pair device does not manage.
admin=$(curl -sf -u "x:$pw" -d '{"name":"CI-App"}' http://localhost:8766/api/box/pair | grep -o '"key":"[A-Za-z0-9_-]*"' | cut -d'"' -f4)
test ${#admin} = 43
test "$(code -H "Authorization: Bearer $admin" http://localhost:8766/api/box/devices)" = 200
test "$(code -H "Authorization: Bearer $key" http://localhost:8766/api/box/devices)" = 403
# Clock: Docker keeps the host's time (#214). No box clock in /api/box and no
# /api/box/time, so no paired device can move the history's time stamps.
if has '"clock"' -H "Authorization: Bearer $key" http://localhost:8766/api/box; then exit 1; fi
res=$(code -H "Authorization: Bearer $admin" -H 'Content-Type: application/json' \
  -d "{\"epochMs\": $(date +%s)000}" http://localhost:8766/api/box/time)
[[ $res = 404 || $res = 405 ]]
as_owner test ! -e "$work/box/app/time-request.json"
# /api/files/ hands out the server's own files to nobody.
for f in access.json server.json box-password.txt lan-access; do
  test "$(code -H "Authorization: Bearer $key" "http://localhost:8766/api/files/$f")" = 403
  test "$(code -u "x:$pw" "http://localhost:8766/api/files/$f")" = 403
done
test "$(code -u "x:$pw" -H 'Origin: http://evil.example' -X PUT http://localhost:8766/api/bus)" = 403
if as_owner grep -q "$key" "$work/box/app/access.json"; then exit 1; fi
"$engine" stop -t 10 "$c_box" >/dev/null && "$engine" rm "$c_box" >/dev/null
run; wait_up
test "$(code -H "Authorization: Bearer $key" http://localhost:8766/api/bus)" = 200
"$engine" rm -f "$c_box" >/dev/null

# Docker as the guide says: the published compose.yaml and the "docker run"
# example, only the image swapped for this build. Settings changed in .env after
# the first start must apply on the next "up -d"; until 1.9.9, LAN_ACCESS did not
# (forum report). server/test/docker_docs_test.dart keeps the documented
# variables and the server in step.
step "Docker as documented (compose.yaml, docker run, changed settings)"
dir="$work/compose"
mkdir -p "$dir"
cp "$guide/compose.yaml" "$dir/"
printf 'services:\n  knx-monitor:\n    image: %s\n    pull_policy: never\n    container_name: %s\n' "$image" "$c_doc" >"$dir/compose.override.yaml"
"$engine" pull -q "$curl_image" >/dev/null
# An address of the host network other than loopback is "from the network".
ip=$("$engine" run --rm --network host --entrypoint sh "$curl_image" -c 'ip -4 route get 1.1.1.1' | sed -n 's/.* src \([0-9.]*\).*/\1/p')
[ -n "$ip" ]
wait_up() { for _ in $(seq 1 30); do [ "$(net_code http://localhost:8765/)" = 401 ] && return 0; sleep 1; done; return 1; }
up() { (cd "$dir" && "${compose[@]}" -f compose.yaml -f compose.override.yaml up -d >/dev/null 2>&1); wait_up; }
pw=ci-compose-pass
# First start as in the guide: only the password in .env.
echo "BOX_PASSWORD=$pw" >"$dir/.env"
up
logs_have "$c_doc" 'Nur-Lesen'
test "$(net_code -u "x:$pw" http://localhost:8765/api/bus)" = 200
test "$(net_code -u "x:$pw" "http://$ip:8765/api/bus")" = 000
# Later LAN_ACCESS=yes and READ_ONLY=0 in .env, then "up -d": both apply.
printf 'BOX_PASSWORD=%s\nLAN_ACCESS=yes\nREAD_ONLY=0\n' "$pw" >"$dir/.env"
up
test "$(net_code -u "x:$pw" "http://$ip:8765/api/bus")" = 200
if logs_have "$c_doc" 'Nur-Lesen'; then exit 1; fi
# And back to the defaults.
echo "BOX_PASSWORD=$pw" >"$dir/.env"
up
test "$(net_code -u "x:$pw" "http://$ip:8765/api/bus")" = 000
logs_have "$c_doc" 'Nur-Lesen'
(cd "$dir" && "${compose[@]}" -f compose.yaml -f compose.override.yaml down >/dev/null 2>&1)
# The "docker run" example from "## Without Compose", with its LAN_ACCESS=yes and
# READ_ONLY=1, on a fresh data folder.
example=$(awk '/^## Without Compose/{f=1} f&&/^```sh/{g=1;next} g&&/^```/{exit} g' "$guide/README.md")
grep -q 'ghcr.io/regetskcob/knx-monitor:<version>' <<<"$example"
example=${example//ghcr.io\/regetskcob\/knx-monitor:<version>/$image}
example=${example//your-own-password/ci-run-pass}
example=${example//docker run/$engine run}
grep -q -- '--name knx-monitor ' <<<"$example"
example=${example//--name knx-monitor /--name $c_doc }
# podman does not create a missing bind mount folder (docker does).
mkdir -p "$work/run/data"
(cd "$work/run" && bash -ec "$example" >/dev/null)
wait_up
test "$(net_code -u x:ci-run-pass "http://$ip:8765/api/bus")" = 200
logs_have "$c_doc" 'Nur-Lesen'
"$engine" rm -f "$c_doc" >/dev/null

step "Smoke test passed ($engine)"
