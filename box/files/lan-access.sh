#!/bin/bash
# Allow or block new TCP connections via cable (web app, pairing, SSH,
# Prometheus). Decides by
# interface, not by source address: if the customer network itself uses
# 10.42.0.0/24, a check in the server would otherwise let it through.
#
# The server stores the choice as /var/lib/knx-box/lan-access ("yes"/"no";
# it may not configure the firewall itself), knx-box-lan.path calls this
# script on every change. If the file is missing, LAN_ACCESS from
# /etc/knx-box/env applies, otherwise blocked.
#
# The block itself is the static table in lan.nft, loaded before the network
# by knx-box-lan-lock.service. This script only adds the exception ("open")
# to the chain lan_open or empties it again. Fail closed: if nft fails while
# opening, the cable stays closed; if it fails while closing, the script loads
# the whole table again and exits with an error if even that fails.
set -euo pipefail

ROOT=${KNX_BOX_ROOT:-}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091 # liegt daneben, siehe setup.sh
. "$here/box-common.sh"

file=$ROOT/var/lib/knx-box/lan-access
choice=
# Read as the server user: the file lies in its directory (box-common.sh).
if [ ! -L "$file" ] && [ -f "$file" ]; then
  choice=$(data_read "$file" | tr -d '[:space:]') || choice=
elif [ -f "$ROOT/etc/knx-box/env" ]; then
  choice=$(sed -n 's/^LAN_ACCESS="\{0,1\}\([a-z]*\)"\{0,1\}$/\1/p' "$ROOT/etc/knx-box/env")
fi

# The table from lan.nft (closed), in case the lock unit did not run or an older
# version deleted it.
ensure_table() {
  nft list chain inet knx_box_lan lan_open >/dev/null 2>&1 || nft -f "$here/lan.nft"
}

if [ "$choice" = yes ]; then
  if ensure_table && printf 'flush chain inet knx_box_lan lan_open\nadd rule inet knx_box_lan lan_open accept\n' | nft -f -; then
    echo "KNX-Box: Zugriff über das Kabel frei"
  else
    echo "KNX-Box: Freigabe über das Kabel fehlgeschlagen (nft)" >&2
    exit 1
  fi
else
  if ! { ensure_table && nft flush chain inet knx_box_lan lan_open; }; then
    # Flushing failed: load the closed table as a whole.
    nft -f "$here/lan.nft" || {
      echo "KNX-Box: Sperre über das Kabel fehlgeschlagen" >&2
      exit 1
    }
  fi
  echo "KNX-Box: Zugriff nur im WLAN der Box"
fi
