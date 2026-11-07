#!/bin/bash
# Sets the box clock as requested by the server (knx-box-time.service).
#
# The server writes {"epochMs": <milliseconds>} to time-request.json when
# the clock is uncertain and an iPad supplies the time (see plan, section 2).
# It runs without CAP_SYS_TIME; the clock is set only here, with a plausibility check.
# The request lies in the server's directory: read as the server user, never
# followed as a link (data_read in box-common.sh).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091 # liegt daneben, siehe setup.sh
. "$here/box-common.sh"

request=$1
if [ -L "$request" ]; then
  rm -f "$request"
  echo "knx-box-time: Anfrage ist ein Link, verworfen"
  exit 0
fi
[ -f "$request" ] || exit 0
content=$(data_read "$request") || content=""
rm -f "$request"
ms=$(printf '%s\n' "$content" | sed -n 's/.*"epochMs"[[:space:]]*:[[:space:]]*\([0-9]\{13\}\).*/\1/p' | head -n 1)
[ -n "$ms" ] || { echo "knx-box-time: ungültige Anfrage"; exit 0; }
seconds=$((ms / 1000))
# 2025-01-01 to 2100-01-01: anything else is a broken device.
if [ "$seconds" -lt 1735689600 ] || [ "$seconds" -gt 4102444800 ]; then
  echo "knx-box-time: Zeit außerhalb des Bereichs ($seconds)"
  exit 0
fi
before=$(date '+%F %T')
# English month names: chrony does not understand "Okt" (the image runs on de_DE).
chronyc -m "settime $(LC_ALL=C date -d "@$seconds" '+%b %d, %Y %H:%M:%S')" >/dev/null
if [ -e /dev/rtc0 ]; then hwclock -w || true; fi
# Remember it for the next start without an RTC (as knx-box-clock-save.service).
if mkdir -p /var/lib/systemd/timesync 2>/dev/null; then
  touch /var/lib/systemd/timesync/clock 2>/dev/null || true
fi
echo "knx-box-time: Uhr gestellt ($before -> $(date '+%F %T'))"
