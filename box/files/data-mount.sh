#!/bin/bash
# Mounts the data partition KNXBOXDATA (USB SSD/NVMe, mkfs.ext4 -L KNXBOXDATA …)
# at /var/lib/knx-box (knx-box-data.service). If it is missing or cannot
# be mounted, the data stays on the SD card.
#
# Once the partition was mounted, /etc/knx-box/data-on-ssd remembers that. From
# then on a missing or broken partition is no longer the normal case: the script
# waits much longer for the drive and ends with an error (unit "failed", message
# in the journal), because the server then runs on the SD card with a different
# password, other paired devices and without the history. The server still
# starts (up to 1.8.3 the box was unreachable without its SSD). Box moved back
# to the SD card on purpose: sudo rm /etc/knx-box/data-on-ssd.
#
# Deliberately no fstab entry: StateDirectory= in the server and the .path units
# turn it into RequiresMountsFor=/var/lib/knx-box. Without the partition the
# mount would fail, and with it the server and the units, despite nofail.
set -euo pipefail

ROOT=${KNX_BOX_ROOT:-}
dev=${KNX_BOX_DATA_DEV:-/dev/disk/by-label/KNXBOXDATA}
dir=$ROOT/var/lib/knx-box
mark=$ROOT/etc/knx-box/data-on-ssd

remember() {
  [ -f "$mark" ] && return 0
  install -d -m 0700 "$(dirname "$mark")"
  : >"$mark" || true
}
# Without the mark: the SD card is the normal place. With it: say so loudly.
fallback() { # fallback <message>
  if [ -f "$mark" ]; then
    echo "Busclear Box: $1 – diese Box lief bisher auf KNXBOXDATA; auf der SD-Karte gelten ein anderes Passwort und ein anderer Verlauf" >&2
    exit 1
  fi
  echo "Busclear Box: $1, Daten auf der SD-Karte" >&2
  exit 0
}

if mountpoint -q "$dir"; then
  remember
  exit 0
fi
# USB drives sometimes show up only shortly after boot: 3 s, and 60 s for a
# box that is known to keep its data there.
udevadm settle --timeout=10 2>/dev/null || true
tries=6
[ ! -f "$mark" ] || tries=120
for ((i = 0; i < tries; i++)); do
  [ -e "$dev" ] && break
  sleep 0.5
done
[ -e "$dev" ] || fallback "keine Datenpartition KNXBOXDATA"

# 0 = clean, 1 = repaired; anything above: better continue on the SD card.
rc=0
fsck.ext4 -p "$dev" || rc=$?
[ "$rc" -le 1 ] || fallback "Prüfung von KNXBOXDATA fehlgeschlagen ($rc)"
install -d -m 0750 "$dir"
# nosuid,nodev,noexec: whoever plugs in a drive labelled KNXBOXDATA decides its
# content, so it must not bring set-uid programs, device nodes or executables.
mount -t ext4 -o noatime,commit=5,nosuid,nodev,noexec "$dev" "$dir" ||
  fallback "KNXBOXDATA lässt sich nicht einhängen"
remember
echo "Busclear Box: Daten auf KNXBOXDATA"
