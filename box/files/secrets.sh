#!/bin/bash
# Box passwords that are none of the server's business: it runs without rights
# on /etc and on the boot partition and only leaves requests in the data directory.
#
#   secrets.sh          knx-box-secrets.path: new Wi-Fi password (wifi-request)
#                       and cleanup of the boot partition (sticker-scrub)
#   secrets.sh --reset  knx-box-reset.service, at boot: set passwords from
#                       knx-box-reset.txt on the boot partition
#
# The requests come from the server and are treated like untrusted input: only
# check them, never execute them, never follow symbolic links.
set -euo pipefail

ROOT=${KNX_BOX_ROOT:-}
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091 # liegt daneben, siehe setup.sh
. "$here/box-common.sh"

BOOT=$ROOT/boot/firmware
[ -d "$BOOT" ] || BOOT=$ROOT/boot
CONF=$BOOT/knx-box.txt
DATA=$ROOT/var/lib/knx-box
ENV_FILE=$ROOT/etc/knx-box/env
AP=$ROOT/etc/NetworkManager/system-connections/knx-box-ap.nmconnection
CERT=$ROOT/etc/knx-box-tls/cert.pem

log() { echo "knx-box-secrets: $*"; }

# Value from a file like knx-box.txt (last line wins).
value() {
  [ -f "$2" ] || return 0
  sed -n "s/^$1=//p" "$2" | tail -n 1 | tr -d '\r'
}

# Replaces the content, keeps file and permissions (FAT has none anyway).
replace() { # replace <file> <content>
  printf '%s' "$2" >"$1"
}

set_psk() {
  [ -f "$AP" ] || { log "kein Hotspot-Profil"; return 0; }
  # The password has been checked: no backslash, so awk reads it unchanged.
  replace "$AP" "$(awk -v p="$1" '/^psk=/ { print "psk=" p; next } { print }' "$AP")
"
  chmod 0600 "$AP"
}

# Take the passwords out of knx-box.txt and /etc/knx-box/env, then rewrite link,
# QR codes and sheet without them. On a FAT partition the old content may still
# physically be on the card: that does not help against someone who reads the card
# (the data is there anyway), but it does against photos and copies.
scrub() { # scrub <box: yes/no> <wlan: yes/no>
  local box=$1 wlan=$2 text
  if [ -f "$CONF" ]; then
    text=$(awk -v box="$box" -v wlan="$wlan" '
      box == "yes" && /^BOX_PASSWORD=/ { print "BOX_PASSWORD="; next }
      wlan == "yes" && /^WLAN_PASSWORD=/ { print "WLAN_PASSWORD="; next }
      { print }
    ' "$CONF")
    replace "$CONF" "$text
"
  fi
  if [ "$box" = yes ] && [ -f "$ENV_FILE" ]; then
    text=$(grep -v '^BOX_PASSWORD=' "$ENV_FILE" || true)
    replace "$ENV_FILE" "$text
"
  fi
  local fp="" name ssid
  if [ -f "$CERT" ] && command -v openssl >/dev/null; then
    fp=$("$here/tls-cert.sh" "$(dirname "$CERT")" 2>/dev/null) || fp=""
  fi
  name=$(value NAME "$CONF")
  ssid=$(value WLAN_SSID "$CONF")
  write_boot_files "$BOOT" "$ROOT/opt/knx-box/server" "$name" "$ssid" \
    "$(value WLAN_PASSWORD "$CONF")" "$(value BOX_PASSWORD "$CONF")" "$(value LAN_ACCESS "$CONF")" "$fp"
  sync
  log "Boot-Partition aufgeräumt (Box-Passwort: $box, WLAN-Passwort: $wlan)"
}

if [ "${1:-}" = --reset ]; then
  reset_file=$BOOT/knx-box-reset.txt
  [ -f "$reset_file" ] || exit 0
  box=$(value BOX_PASSWORD "$reset_file")
  wlan=$(value WLAN_PASSWORD "$reset_file")
  # Out of the way first: even with invalid content no plain text is left behind.
  rm -f "$reset_file"
  sync
  if valid_password "$box"; then
    mkdir -p "$DATA"
    umask 077
    printf '%s\n' "$box" >"$DATA/password-reset.new"
    chown knx-box:knx-box "$DATA/password-reset.new" 2>/dev/null || true
    mv -f "$DATA/password-reset.new" "$DATA/password-reset"
    log "neues Box-Passwort übernommen"
  elif [ -n "$box" ]; then
    log "Box-Passwort ungültig (8-63 Zeichen, ohne Leerzeichen und \" ' \\ \$ \`)"
  fi
  if valid_password "$wlan"; then
    set_psk "$wlan"
    log "neues WLAN-Passwort übernommen"
    # NetworkManager may already have started the hotspot with the old password.
    if systemctl is-active --quiet NetworkManager; then
      nmcli connection reload || true
      nmcli connection up knx-box-ap || log "Hotspot startet beim nächsten Neustart"
    fi
  elif [ -n "$wlan" ]; then
    log "WLAN-Passwort ungültig (8-63 Zeichen, ohne Leerzeichen und \" ' \\ \$ \`)"
  fi
  exit 0
fi

new_wlan=""
request=$DATA/wifi-request
if [ -L "$request" ]; then
  rm -f "$request"
elif [ -f "$request" ]; then
  candidate=$(head -n 1 "$request" | tr -d '\r')
  rm -f "$request"
  if valid_password "$candidate"; then new_wlan=$candidate; else log "ungültiges WLAN-Passwort, nichts geändert"; fi
fi

scrub_box=no
scrub_wlan=no
request=$DATA/sticker-scrub
if [ -L "$request" ]; then
  rm -f "$request"
elif [ -f "$request" ]; then
  if grep -qx box "$request"; then scrub_box=yes; fi
  if grep -qx wifi "$request"; then scrub_wlan=yes; fi
  rm -f "$request"
fi

if [ -n "$new_wlan" ]; then
  set_psk "$new_wlan"
  scrub_wlan=yes
fi
if [ "$scrub_box" = yes ] || [ "$scrub_wlan" = yes ]; then scrub "$scrub_box" "$scrub_wlan"; fi
if [ -n "$new_wlan" ]; then
  # Only at the very end: afterwards everyone is kicked off the Wi-Fi, including
  # the app that is just receiving the server's response.
  sleep 3
  if systemctl is-active --quiet NetworkManager; then
    nmcli connection reload || true
    nmcli connection up knx-box-ap || log "Hotspot startet beim nächsten Neustart"
  fi
  log "WLAN-Passwort geändert"
fi
