#!/bin/bash
# Allow or block access via cable to ports 80 and 443. Decides by
# interface, not by source address: if the customer network itself uses
# 10.42.0.0/24, a check in the server would otherwise let it through.
#
# The server stores the choice as /var/lib/knx-box/lan-access ("yes"/"no";
# it may not configure the firewall itself), knx-box-lan.path calls this
# script on every change. If the file is missing, LAN_ACCESS from
# /etc/knx-box/env applies, otherwise blocked.
set -euo pipefail

ROOT=${KNX_BOX_ROOT:-}
choice=
if [ -f "$ROOT/var/lib/knx-box/lan-access" ]; then
  choice=$(tr -d '[:space:]' <"$ROOT/var/lib/knx-box/lan-access")
elif [ -f "$ROOT/etc/knx-box/env" ]; then
  choice=$(sed -n 's/^LAN_ACCESS="\{0,1\}\([a-z]*\)"\{0,1\}$/\1/p' "$ROOT/etc/knx-box/env")
fi

if [ "$choice" = yes ]; then
  nft delete table inet knx_box_lan 2>/dev/null || true
  echo "KNX-Box: Zugriff über das Kabel frei"
else
  # Only HTTP and HTTPS (web app, app, pairing); KNXnet/IP and gateway discovery
  # use UDP and stay open.
  nft -f - <<'NFT'
table inet knx_box_lan
flush table inet knx_box_lan
table inet knx_box_lan {
	chain input {
		type filter hook input priority filter; policy accept;
		iifname "lo" accept
		iifname "wlan0" accept
		tcp dport { 80, 443 } reject with tcp reset
	}
}
NFT
  echo "KNX-Box: Zugriff nur im WLAN der Box"
fi
