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
  # Every new inbound TCP connection over the cable: web app, pairing, SSH and
  # the Prometheus exporter. Replies to connections the box opens itself
  # (gateway over TCP, MQTT, InfluxDB) stay allowed; KNXnet/IP over UDP and
  # gateway discovery are not affected. SSH stays reachable in the box Wi-Fi.
  nft -f - <<'NFT'
table inet knx_box_lan
flush table inet knx_box_lan
table inet knx_box_lan {
	chain input {
		type filter hook input priority filter; policy accept;
		iifname "lo" accept
		iifname "wlan0" accept
		ct state established,related accept
		meta l4proto tcp ct state new reject with tcp reset
	}
}
NFT
  echo "KNX-Box: Zugriff nur im WLAN der Box"
fi
