#!/bin/bash
# Restarts the server when it runs but no longer answers (knx-box-health.timer).
# systemd's Restart=always only sees a process that ended; a hung one would keep
# the box silent and the recording stopped until someone pulls the plug.
#
# Asks /healthz the way setup.sh does. Any HTTP answer below 500 counts as alive
# (an older server answers 401 there); no answer or a 5xx, three times in a row,
# restarts the service. A refused connection (port not open yet) counts as still starting
# during the first 30 minutes of the service. The counter lives in /run, so a reboot starts at zero.
set -euo pipefail

ROOT=${KNX_BOX_ROOT:-}
state=$ROOT/run/knx-box-health
limit=3

# Stopped on purpose or still starting: not this script's business.
if ! systemctl is-active --quiet knx-box.service; then
  rm -f "$state"
  exit 0
fi
rc=0
code=$(curl -s -o /dev/null --connect-timeout 3 -m 10 -w '%{http_code}' http://127.0.0.1/healthz 2>/dev/null) || rc=$?
# Connection refused: the port is not open yet. The server opens it only after it tidied up
# its history, which can take minutes on a large day; restarting would start that over, for
# good. A process that ended is systemd's business (Restart=always).
# Only for the first 30 minutes of the service; refused after that means it hangs before
# listening, and then a restart is the way out.
if [ "$rc" -eq 7 ]; then
  since=$(systemctl show -p ActiveEnterTimestampMonotonic --value knx-box.service 2>/dev/null || true)
  now=$(awk '{printf "%d", $1 * 1000000}' "${ROOT}/proc/uptime" 2>/dev/null || echo 0)
  # Unknown start time: still starting, as before.
  if ! [[ "$since" =~ ^[1-9][0-9]*$ ]] || [ "$((now - since))" -lt 1800000000 ]; then
    rm -f "$state"
    exit 0
  fi
fi
if [[ "$code" =~ ^[1-4][0-9][0-9]$ ]]; then
  rm -f "$state"
  exit 0
fi
count=$(cat "$state" 2>/dev/null || echo 0)
[[ "$count" =~ ^[0-9]+$ ]] || count=0
count=$((count + 1))
if [ "$count" -lt "$limit" ]; then
  echo "$count" >"$state"
  echo "knx-box-health: Server antwortet nicht (${code:-keine Antwort}), Versuch $count von $limit"
  exit 0
fi
rm -f "$state"
echo "knx-box-health: Server antwortet seit $limit Prüfungen nicht (${code:-keine Antwort}) – Neustart" >&2
systemctl restart knx-box.service
