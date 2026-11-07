#!/bin/sh
# ExecStopPost of knx-box.service: keeps systemd's reason for the end of the
# server for its next start (CrashWatch, public issue #4). Runs as the server
# user in its sandbox; the server reads and deletes the file.
# SERVICE_RESULT: success, exit-code, signal, core-dump, watchdog, oom-kill,
# timeout, ...; EXIT_CODE: exited, killed, dumped; EXIT_STATUS: number or
# signal name (systemd.exec(5)).
set -eu
dir=${STATE_DIRECTORY:-/var/lib/knx-box}
# Only plain words: the values come from systemd, but end up in JSON.
clean() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9_-' | cut -c1-32; }
tmp=$dir/last-exit.json.tmp
printf '{"result":"%s","code":"%s","status":"%s","t":%s000}\n' \
  "$(clean "${SERVICE_RESULT:-}")" "$(clean "${EXIT_CODE:-}")" "$(clean "${EXIT_STATUS:-}")" "$(date +%s)" >"$tmp"
mv -f "$tmp" "$dir/last-exit.json"
