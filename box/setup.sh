#!/bin/bash
# Sets up or updates the KNX Monitor Box on Raspberry Pi OS Lite (64 bit,
# Trixie). Runs from the bundle of bundle.sh (next to server, web/,
# files/) and is called by pi-gen in the chroot during the image build.
#
#   sudo ./setup.sh            # on a running Pi (asks first)
#   sudo ./setup.sh --yes      # without asking
#   ./setup.sh --image         # in the pi-gen chroot: start nothing, no apt
#   sudo ./setup.sh --rollback # back to the version before the last update
#
# Can be run repeatedly: server and web app are replaced, passwords, Wi-Fi and
# history are kept. The previous version stays as server.prev/web.prev;
# if the new server does not respond after the restart, the script rolls
# back on its own. Dry run without a Pi: box/test-setup.sh.
set -euo pipefail

# Only for box/test-setup.sh: all paths under a test directory, shorter timeout.
root=${KNX_BOX_ROOT:-}
health_seconds=${KNX_BOX_HEALTH_SECONDS:-40}

here=$(cd "$(dirname "$0")" && pwd)
image=no
yes=no
rollback=no
for arg in "$@"; do
  case $arg in
    --image) image=yes ;;
    --yes) yes=yes ;;
    --rollback) rollback=yes ;;
    *) echo "Unbekannte Option: $arg" >&2; exit 2 ;;
  esac
done

die() { echo "setup.sh: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "bitte mit sudo starten"

opt=$root/opt/knx-box
env_file=$root/etc/knx-box/env

# Does the server respond on port 80? Since 1.9.2 /healthz returns 200 without
# login; any HTTP response counts, because a rollback to an older version gets
# 401 here. Only no connection does not. At most 40 s in total: the server reads
# the history at startup.
healthy() {
  local deadline=$((SECONDS + health_seconds)) code
  while [ $SECONDS -lt $deadline ]; do
    sleep 2
    systemctl is-active --quiet knx-box.service || continue
    code=$(curl -s -o /dev/null --connect-timeout 2 -m 3 -w '%{http_code}' http://127.0.0.1/healthz 2>/dev/null || true)
    [ -n "$code" ] && [ "$code" != 000 ] && return 0
  done
  return 1
}

# Restore and start the previous version (server.prev, web.prev).
restore_previous() {
  if [ ! -x "$opt/server.prev" ] || [ ! -d "$opt/web.prev" ]; then die "keine vorige Version vorhanden ($opt/server.prev)"; fi
  systemctl stop knx-box.service || true
  mv -f "$opt/server.prev" "$opt/server"
  rm -rf "$opt/web"
  mv "$opt/web.prev" "$opt/web"
  if [ -f "$opt/VERSION.prev" ]; then mv -f "$opt/VERSION.prev" "$opt/VERSION"; fi
  systemctl start knx-box.service || true
}

if [ "$rollback" = yes ]; then
  restore_previous
  healthy || die "auch die vorige Version antwortet nicht – journalctl -u knx-box"
  echo "Zurück auf $(cat "$opt/VERSION" 2>/dev/null || echo 'die vorige Version')."
  exit 0
fi
if ! { [ -x "$here/server" ] && [ -f "$here/web/index.html" ] && [ -d "$here/files" ]; }; then
  die "server, web/ und files/ fehlen – setup.sh aus dem Paket von box/bundle.sh starten"
fi
[ "$(uname -m)" = aarch64 ] || [ "$image" = yes ] || die "nur für 64-bit-Pi-OS (aarch64)"

boot=$root/boot/firmware
[ -d "$boot" ] || boot=$root/boot
version=$(cat "$here/VERSION" 2>/dev/null || echo unbekannt)

if [ "$image" = no ] && [ "$yes" = no ] && [ ! -f "$env_file" ]; then
  cat <<EOF
Die Box übernimmt wlan0 als eigenen Hotspot. Wer jetzt per WLAN verbunden ist,
verliert die Verbindung (danach im WLAN der Box: http://knx-box.local).
Am besten per LAN-Kabel oder direkt am Pi einrichten.
EOF
  read -r -p "Weiter? [j/N] " answer
  [[ "$answer" =~ ^[jJyY]$ ]] || exit 1
fi

echo "KNX Monitor Box $version einrichten"

if [ "$image" = no ]; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    network-manager avahi-daemon chrony nftables qrencode picocom curl openssl
fi

# --- Program -------------------------------------------------------------------
id knx-box >/dev/null 2>&1 ||
  useradd --system --home-dir /var/lib/knx-box --no-create-home --shell /usr/sbin/nologin knx-box
install -d -m 0755 "$opt"
# Keep the running version for rollback (not in the image: there is none there).
updated=no
if [ "$image" = no ] && [ -x "$opt/server" ] && [ -d "$opt/web" ]; then
  rm -rf "$opt/server.prev" "$opt/web.prev"
  cp -p "$opt/server" "$opt/server.prev"
  cp -Rp "$opt/web" "$opt/web.prev"
  [ -f "$opt/VERSION" ] && cp -p "$opt/VERSION" "$opt/VERSION.prev"
  updated=yes
fi
install -m 0755 "$here/server" "$opt/server.new"
mv -f "$opt/server.new" "$opt/server"
rm -rf "$opt/web.new"
cp -R "$here/web" "$opt/web.new"
chmod -R a+rX "$opt/web.new"
rm -rf "$opt/web.old"
[ -d "$opt/web" ] && mv "$opt/web" "$opt/web.old"
mv "$opt/web.new" "$opt/web"
rm -rf "$opt/web.old"
echo "$version" >"$opt/VERSION"

# --- Helper scripts and services ------------------------------------------------
install -d -m 0755 "$root/usr/local/lib/knx-box"
install -m 0755 "$here/files/firstboot.sh" "$here/files/settime.sh" "$here/files/lan-access.sh" \
  "$here/files/data-mount.sh" "$here/files/secrets.sh" "$here/files/tls-cert.sh" "$root/usr/local/lib/knx-box/"
install -m 0644 "$here/files/box-common.sh" "$root/usr/local/lib/knx-box/"
install -m 0644 "$here/files/firewall.nft" "$root/usr/local/lib/knx-box/"
install -d -m 0755 "$root/etc/systemd/system"
for unit in knx-box.service knx-box-firstboot.service knx-box-firewall.service knx-box-data.service \
  knx-box-time.path knx-box-time.service knx-box-lan.path knx-box-lan.service \
  knx-box-secrets.path knx-box-secrets.service knx-box-reset.service; do
  install -m 0644 "$here/files/$unit" "$root/etc/systemd/system/"
done

install -d -m 0755 "$root/etc/chrony/conf.d"
install -m 0644 "$here/files/chrony-knx-box.conf" "$root/etc/chrony/conf.d/knx-box.conf"

# Limit the journal: on a small card it otherwise took space from the recording.
install -d -m 0755 "$root/etc/systemd/journald.conf.d"
install -m 0644 "$here/files/journald-knx-box.conf" "$root/etc/systemd/journald.conf.d/knx-box.conf"

# Box already set up: add HTTPS. A new one gets the certificate on first
# boot, never in the image: every box needs its own key.
if [ "$image" = no ] && [ -f "$env_file" ] && command -v openssl >/dev/null; then
  "$here/files/tls-cert.sh" "$root/etc/knx-box-tls" >/dev/null || echo "Kein Zertifikat, die Box bleibt bei HTTP." >&2
fi

lan=$root/etc/NetworkManager/system-connections/knx-box-lan.nmconnection
if [ ! -f "$lan" ]; then
  install -d -m 0755 "$root/etc/NetworkManager/system-connections"
  install -m 0600 "$here/files/knx-box-lan.nmconnection" "$lan"
fi

# Template for the first boot; one that is already filled in is kept.
[ -f "$boot/knx-box.txt" ] || install -m 0644 "$here/files/knx-box.txt" "$boot/knx-box.txt"

# knx-box-data.service mounts data on USB SSD/NVMe (files/data-mount.sh).
# Remove the fstab entry up to 1.8.3: without the partition the server never started.
sed -i '/^LABEL=KNXBOXDATA /d' "$root/etc/fstab"

# --- KNX HAT (Weinzierl kBerry on GPIO 14/15, docs/kberry.md) ------------------
# UART0 (PL011) on GPIO 14/15 as /dev/ttyAMA0: on the Pi 4 instead of Bluetooth
# (the box does not use it), on the Pi 5 via its own overlay. No enable_uart=1:
# the Pi 5 would otherwise send kernel messages into the module. Harmless without
# a HAT. Takes effect after the next reboot.
hat_reboot=no
if [ -f "$boot/config.txt" ] && ! grep -q '^# KNX-HAT' "$boot/config.txt"; then
  cat >>"$boot/config.txt" <<'CONFIG'

# KNX-HAT (kBerry): UART0 auf GPIO 14/15 frei für das Modul
[pi4]
dtoverlay=disable-bt
[pi5]
dtoverlay=uart0-pi5
[all]
CONFIG
  hat_reboot=yes
fi
# No Linux console on the serial port (pi-gen sets it).
if [ -f "$boot/cmdline.txt" ] && grep -q 'console=serial0' "$boot/cmdline.txt"; then
  sed -i -E 's/console=serial0,[0-9]+ ?//' "$boot/cmdline.txt"
  hat_reboot=yes
fi
systemctl disable hciuart.service 2>/dev/null || true
systemctl mask serial-getty@ttyAMA0.service >/dev/null 2>&1 || true
usermod -aG dialout knx-box

# No "no internet" wait at startup: the hotspot never has internet.
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
systemctl enable NetworkManager.service avahi-daemon.service chrony.service \
  knx-box-firstboot.service knx-box-data.service knx-box.service \
  knx-box-time.path knx-box-lan.path knx-box-lan.service knx-box-secrets.path knx-box-reset.service
# A set-up box with the firewall disabled has chosen INTERNET_SHARING=yes:
# the update leaves it that way.
firewall=yes
if [ -f "$env_file" ] && ! systemctl is-enabled --quiet knx-box-firewall.service; then
  firewall=no
fi
[ "$firewall" = no ] || systemctl enable knx-box-firewall.service

if [ "$image" = no ]; then
  systemctl daemon-reload
  systemctl restart chrony.service || true
  [ "$firewall" = no ] || systemctl start knx-box-firewall.service
  [ -f "$env_file" ] || systemctl start knx-box-firstboot.service
  systemctl start knx-box-data.service
  systemctl restart knx-box-lan.service knx-box-time.path knx-box-lan.path knx-box-secrets.path
  systemctl restart systemd-journald.service || true
  # If even the start fails, treat it like a silent server: roll back.
  systemctl restart knx-box.service || true
  if [ -f "$env_file" ] && ! healthy; then
    if [ "$updated" = yes ]; then
      echo "Der neue Server ($version) antwortet nicht – zurück auf die vorige Version." >&2
      restore_previous
      healthy && die "Update zurückgenommen, die vorige Version läuft wieder. Log: journalctl -u knx-box"
      die "Update zurückgenommen, aber auch die vorige Version antwortet nicht – journalctl -u knx-box"
    fi
    die "Server antwortet nicht – journalctl -u knx-box"
  fi
  [ "$hat_reboot" = no ] || echo "Für den KNX-HAT (serieller Anschluss) einmal neu starten: sudo reboot"
  echo "Fertig. Zugangsdaten: $boot/knx-box.txt, WLAN-QR-Code: $boot/knx-box-wlan.png"
fi
