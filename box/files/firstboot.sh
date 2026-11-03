#!/bin/bash
# First boot of the KNX Monitor Box (knx-box-firstboot.service).
#
# Reads knx-box.txt from the boot partition, generates missing values, sets up
# hotspot, server environment, firewall and SSH and writes the values back
# (including the Wi-Fi QR code) so that they can be read from the SD card on a PC.
# The file is only read, never executed: anyone with the card can change it.
set -euo pipefail

# KNX_BOX_ROOT for tests only: all paths under a test directory.
ROOT=${KNX_BOX_ROOT:-}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091 # liegt daneben, siehe setup.sh
. "$here/box-common.sh"
BOOT=$ROOT/boot/firmware
[ -d "$BOOT" ] || BOOT=$ROOT/boot
CONF="$BOOT/knx-box.txt"
ENV_DIR=$ROOT/etc/knx-box
AP=$ROOT/etc/NetworkManager/system-connections/knx-box-ap.nmconnection

log() { echo "knx-box-firstboot: $*"; }

# Value from knx-box.txt (last line wins, Windows line endings removed).
get() {
  [ -f "$CONF" ] || return 0
  sed -n "s/^$1=//p" "$CONF" | tail -n 1 | tr -d '\r'
}

# Random string without confusable characters (0/O, 1/l/I).
# No "tr </dev/urandom | head": that ends with SIGPIPE and aborts under pipefail.
gen() {
  local s=""
  while [ ${#s} -lt "$1" ]; do
    s+=$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'abcdefghjkmnpqrstuvwxyz23456789')
  done
  printf '%s' "${s:0:$1}"
}

valid_name() { [[ "$1" =~ ^[A-Za-z0-9._-]{1,32}$ ]]; }

# Last four digits of the serial number: two boxes on one site do not interfere.
serial=$(tr -d '\0' <"$ROOT/proc/device-tree/serial-number" 2>/dev/null || cat "$ROOT/etc/machine-id")
suffix=$(printf '%s' "$serial" | tail -c 4 | tr '[:lower:]' '[:upper:]')

name=$(get NAME)
valid_name "$name" || name="KNX-Box-$suffix"
ssid=$(get WLAN_SSID)
valid_name "$ssid" || ssid="$name"
wlan_password=$(get WLAN_PASSWORD)
valid_password "$wlan_password" || wlan_password=$(gen 12)
box_password=$(get BOX_PASSWORD)
valid_password "$box_password" || box_password=$(gen 10)
country=$(get COUNTRY)
[[ "$country" =~ ^[A-Z]{2}$ ]] || country=DE
sharing=$(get INTERNET_SHARING)
[ "$sharing" = yes ] || sharing=no
lan=$(get LAN_ACCESS)
[ "$lan" = yes ] || lan=no
read_only=$(get READ_ONLY)
[ "$read_only" = yes ] || read_only=no
ssh_key=$(get SSH_PUBKEY)

# --- Server -------------------------------------------------------------------
install -d -m 0700 "$ENV_DIR"
umask 077
cat >"$ENV_DIR/env" <<EOF
BOX_NAME="$name"
BOX_PASSWORD="$box_password"
LAN_ACCESS="$lan"
EOF
[ "$read_only" = no ] || echo 'READ_ONLY="1"' >>"$ENV_DIR/env"

# --- Wi-Fi hotspot ------------------------------------------------------------
# Without a country code Wi-Fi stays blocked on the Pi.
if command -v raspi-config >/dev/null; then
  raspi-config nonint do_wifi_country "$country" || log "Ländercode $country nicht gesetzt"
fi
rfkill unblock wifi 2>/dev/null || true
cat >"$AP" <<EOF
[connection]
id=knx-box-ap
type=wifi
interface-name=wlan0
autoconnect=true

[wifi]
mode=ap
ssid=$ssid
band=bg
channel=6

[wifi-security]
key-mgmt=wpa-psk
proto=rsn
pairwise=ccmp
group=ccmp
psk=$wlan_password

[ipv4]
method=shared
address1=10.42.0.1/24

[ipv6]
method=disabled
EOF
chmod 0600 "$AP"
if systemctl is-active --quiet NetworkManager; then
  nmcli connection reload
  nmcli connection up knx-box-ap || log "Hotspot startet beim nächsten Neustart"
fi

# --- Firewall and SSH ---------------------------------------------------------
if [ "$sharing" = yes ]; then
  systemctl disable --now knx-box-firewall.service || true
fi
# Only "type key [comment]": no options such as command= in front.
if [[ "$ssh_key" =~ ^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa)\ [A-Za-z0-9+/=]+(\ .*)?$ ]]; then
  user=$(getent passwd 1000 | cut -d: -f1)
  if [ -n "$user" ]; then
    home=$(getent passwd "$user" | cut -d: -f6)
    install -d -m 0700 -o "$user" -g "$user" "$home/.ssh"
    printf '%s\n' "$ssh_key" >>"$home/.ssh/authorized_keys"
    chown "$user:$user" "$home/.ssh/authorized_keys"
    chmod 0600 "$home/.ssh/authorized_keys"
    # Keys only, no passwords.
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' >"$ROOT/etc/ssh/sshd_config.d/knx-box.conf"
    # Maintenance needs root. The account has no password (otherwise sudo would
    # ask for nothing) and is reachable only with this key.
    install -d -m 0750 "$ROOT/etc/sudoers.d"
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" >"$ROOT/etc/sudoers.d/010_knx-box-admin"
    chmod 0440 "$ROOT/etc/sudoers.d/010_knx-box-admin"
    systemctl enable --now ssh || true
  fi
fi

# --- HTTPS --------------------------------------------------------------------
# A key of its own per box, hence only here and not in the image. Without openssl
# the box runs on HTTP only.
fingerprint=""
if command -v openssl >/dev/null; then
  fingerprint=$("$here/tls-cert.sh" "$ROOT/etc/knx-box-tls") || log "Kein Zertifikat, nur HTTP"
fi

# --- Write back ---------------------------------------------------------------
umask 022
cat >"$CONF" <<EOF
# KNX Monitor Box – eingerichtet am $(date '+%d.%m.%Y %H:%M')
#
# Diese Werte gelten jetzt. Änderungen hier wirken nicht mehr. Beim ersten
# Anmelden verlangt die Box ein eigenes Passwort (App oder
# http://knx-box.local/pair); danach verschwindet es von dieser Karte, ebenso
# das WLAN-Passwort, wenn man es in der App ändert. Vergessen? Eine Datei
# knx-box-reset.txt mit BOX_PASSWORD=… und/oder WLAN_PASSWORD=… auf diese Karte
# legen und neu starten.
# Alles auf einem Blatt zum Ausdrucken: knx-box-de.pdf, knx-box-en.pdf.
# Aufkleber: knx-box-app.png. In der App "KNX-Box hinzufügen" und diesen
# QR-Code scannen: Die App tritt dem WLAN bei, koppelt sich und stellt die Uhr.
# Ohne Kamera (Linux-App, Desktop): den Link aus knx-box-link.txt einfügen.
# Ohne App: knx-box-wlan.png (WLAN-QR-Code für die Kamera), dann im Browser
# http://knx-box.local oder http://10.42.0.1 mit dem Box-Passwort.

NAME=$name
WLAN_SSID=$ssid
WLAN_PASSWORD=$wlan_password
BOX_PASSWORD=$box_password
COUNTRY=$country
INTERNET_SHARING=$sharing
LAN_ACCESS=$lan
READ_ONLY=$read_only
SSH_PUBKEY=$ssh_key
EOF
# Setup link for the app: Wi-Fi, box password, fixed address in the box Wi-Fi.
# As a QR code for the sticker and as text for pasting on the desktop.
write_boot_files "$BOOT" "$ROOT/opt/knx-box/server" "$name" "$ssid" "$wlan_password" "$box_password" "$lan" "$fingerprint"
sync
log "eingerichtet: $name, WLAN $ssid"
