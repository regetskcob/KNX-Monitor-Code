#!/bin/bash
# Mounts the data partition KNXBOXDATA (USB SSD/NVMe, mkfs.ext4 -L KNXBOXDATA …)
# at /var/lib/knx-box (knx-box-data.service). If it is missing or cannot
# be mounted, the data stays on the SD card.
#
# Deliberately no fstab entry: StateDirectory= in the server and the .path units
# turn it into RequiresMountsFor=/var/lib/knx-box. Without the partition the
# mount would fail, and with it the server and the units, despite nofail.
set -euo pipefail

ROOT=${KNX_BOX_ROOT:-}
dev=${KNX_BOX_DATA_DEV:-/dev/disk/by-label/KNXBOXDATA}
dir=$ROOT/var/lib/knx-box

if mountpoint -q "$dir"; then
  exit 0
fi
# USB drives sometimes show up only shortly after boot.
udevadm settle --timeout=10 2>/dev/null || true
for _ in 1 2 3 4 5 6; do
  [ -e "$dev" ] && break
  sleep 0.5
done
if [ ! -e "$dev" ]; then
  echo "Busclear Box: keine Datenpartition KNXBOXDATA, Daten auf der SD-Karte"
  exit 0
fi

# 0 = clean, 1 = repaired; anything above: better continue on the SD card.
rc=0
fsck.ext4 -p "$dev" || rc=$?
if [ "$rc" -gt 1 ]; then
  echo "Busclear Box: Prüfung von KNXBOXDATA fehlgeschlagen ($rc), Daten auf der SD-Karte" >&2
  exit 0
fi
install -d -m 0750 "$dir"
# nosuid,nodev,noexec: whoever plugs in a drive labelled KNXBOXDATA decides its
# content, so it must not bring set-uid programs, device nodes or executables.
if ! mount -t ext4 -o noatime,commit=5,nosuid,nodev,noexec "$dev" "$dir"; then
  echo "Busclear Box: KNXBOXDATA lässt sich nicht einhängen, Daten auf der SD-Karte" >&2
  exit 0
fi
echo "Busclear Box: Daten auf KNXBOXDATA"
