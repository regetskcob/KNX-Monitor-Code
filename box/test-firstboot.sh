#!/bin/bash
# Dry run of files/firstboot.sh in a test directory, with stand-ins for
# systemctl, nmcli, raspi-config and qrencode. Runs on Linux and macOS.
# Also covers the root helpers secrets.sh, settime.sh, lan-access.sh and
# data-mount.sh, and the decisive lines of the units.
#
#   box/test-firstboot.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
fail() { echo "FEHLER: $*" >&2; exit 1; }

mkdir -p "$tmp/bin" "$tmp/root/boot/firmware" "$tmp/root/etc/NetworkManager/system-connections" \
  "$tmp/root/proc/device-tree"
for cmd in systemctl nmcli raspi-config rfkill; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 1\n' "$cmd" "$tmp" >"$tmp/bin/$cmd"
done
# shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
printf '#!/bin/sh\nwhile [ "$1" != -o ]; do shift; done\necho "$3" >"$2"\n' >"$tmp/bin/qrencode"
# setpriv (util-linux) is missing on macOS, and the test user cannot switch
# users anyway: the stand-in records the call and runs the command as is.
# shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
printf '#!/bin/sh\necho "setpriv $*" >>"%s/setpriv-calls"\nwhile [ "$1" != -- ]; do shift; done\nshift\nexec "$@"\n' "$tmp" >"$tmp/bin/setpriv"
chmod +x "$tmp/bin/"*
printf '10000000abcd1a2b\0' >"$tmp/root/proc/device-tree/serial-number"

# Stand-in for the server: records the call and the values of the sheet.
mkdir -p "$tmp/root/opt/knx-box"
# shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
printf '#!/bin/sh\necho "$1 $2" >"%s/sheet"\nenv | grep -E "^(BOX_|WLAN_|LAN_ACCESS)" | sort >>"%s/sheet"\n' "$tmp" "$tmp" >"$tmp/root/opt/knx-box/server"
chmod +x "$tmp/root/opt/knx-box/server"
run() { PATH="$tmp/bin:$PATH" KNX_BOX_ROOT="$tmp/root" bash "$here/files/firstboot.sh" >/dev/null; }
value() { sed -n "s/^$1=//p" "$tmp/root/boot/firmware/knx-box.txt"; }

# 1. Empty template: everything is generated.
cp "$here/files/knx-box.txt" "$tmp/root/boot/firmware/"
run
[ "$(value NAME)" = KNX-Box-1A2B ] || fail "Name aus Seriennummer: $(value NAME)"
[ "$(value WLAN_SSID)" = KNX-Box-1A2B ] || fail "SSID"
app=$(cat "$tmp/root/boot/firmware/knx-box-app.png")
case "$app" in
  "knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&name=KNX-Box-1A2B&ssid=KNX-Box-1A2B&fp="*"&wifi="*"&pw=$(value BOX_PASSWORD)") ;;
  *) fail "Kopplungslink für die App: $app" ;;
esac
[ "$(cat "$tmp/root/boot/firmware/knx-box-link.txt")" = "$app" ] || fail "Kopplungslink als Text"
# A certificate of its own per box, fingerprint in the link.
key=$tmp/root/etc/knx-box-tls/key.pem
[ -s "$key" ] || fail "Kein Zertifikat"
[ "$(stat -c %a "$key" 2>/dev/null || stat -f %Lp "$key")" = 640 ] || fail "Schlüssel-Rechte"
fp=$(bash "$here/files/tls-cert.sh" "$tmp/root/etc/knx-box-tls")
case "$app" in *"&fp=$fp&"*) ;; *) fail "Fingerabdruck im Link: $app (erwartet $fp)" ;; esac
grep -qx "sheet $tmp/root/boot/firmware" "$tmp/sheet" || fail "Blatt: Aufruf"
grep -qx "BOX_LINK=$app" "$tmp/sheet" || fail "Blatt: Link"
grep -qx "BOX_PASSWORD=$(value BOX_PASSWORD)" "$tmp/sheet" || fail "Blatt: Box-Passwort"
grep -qx "WLAN_PASSWORD=$(value WLAN_PASSWORD)" "$tmp/sheet" || fail "Blatt: WLAN-Passwort"
grep -qx "LAN_ACCESS=no" "$tmp/sheet" || fail "Blatt: Kabelzugang"
[ "$(value WLAN_PASSWORD | wc -c)" -eq 13 ] || fail "WLAN-Passwort: $(value WLAN_PASSWORD)"
[ "$(value BOX_PASSWORD | wc -c)" -eq 11 ] || fail "Box-Passwort: $(value BOX_PASSWORD)"
grep -q "^BOX_PASSWORD=\"$(value BOX_PASSWORD)\"$" "$tmp/root/etc/knx-box/env" || fail "env"
grep -q '^BOX_NAME="KNX-Box-1A2B"$' "$tmp/root/etc/knx-box/env" || fail "env-Name"
grep -q '^LAN_ACCESS="no"$' "$tmp/root/etc/knx-box/env" || fail "Kabel standardmäßig zu"
[ "$(value LAN_ACCESS)" = no ] || fail "LAN_ACCESS zurückgeschrieben"
! grep -q READ_ONLY "$tmp/root/etc/knx-box/env" || fail "Nur-Lesen standardmäßig an"
[ "$(value READ_ONLY)" = no ] || fail "READ_ONLY zurückgeschrieben"
! grep -q HEALTH_CHECK "$tmp/root/etc/knx-box/env" || fail "Gesundheitsprüfung standardmäßig an"
[ "$(value HEALTH_CHECK)" = no ] || fail "HEALTH_CHECK zurückgeschrieben"
ap=$tmp/root/etc/NetworkManager/system-connections/knx-box-ap.nmconnection
grep -q "^psk=$(value WLAN_PASSWORD)$" "$ap" || fail "Hotspot-Passwort"
grep -q '^ssid=KNX-Box-1A2B$' "$ap" || fail "Hotspot-SSID"
[ "$(stat -c %a "$ap" 2>/dev/null || stat -f %Lp "$ap")" = 600 ] || fail "Keyfile-Rechte"
grep -q "^WIFI:T:WPA;S:KNX-Box-1A2B;P:$(value WLAN_PASSWORD);;$" "$tmp/root/boot/firmware/knx-box-wlan.png" ||
  fail "WLAN-QR"
grep -q 'raspi-config nonint do_wifi_country DE' "$tmp/calls" || fail "Ländercode"

# 2. Filled in, with special characters and invalid values.
rm -rf "$tmp/root/etc/knx-box" "$tmp/calls"
cat >"$tmp/root/boot/firmware/knx-box.txt" <<'CONF'
NAME=Baustelle-Sued
WLAN_SSID=
WLAN_PASSWORD=Geheim;Wlan:1
BOX_PASSWORD=kurz
COUNTRY=AT
INTERNET_SHARING=yes
LAN_ACCESS=yes
READ_ONLY=yes
HEALTH_CHECK=yes
CONF
# shellcheck disable=SC2016 # darf gerade nicht ausgeführt werden
printf 'NAME=$(touch /tmp/knx-box-pwned)\r\n' >>"$tmp/root/boot/firmware/knx-box.txt"
run
[ ! -e /tmp/knx-box-pwned ] || fail "Datei wurde ausgeführt"
[ "$(value NAME)" = KNX-Box-1A2B ] || fail "ungültiger Name nicht ersetzt: $(value NAME)"
[ "$(value WLAN_PASSWORD)" = 'Geheim;Wlan:1' ] || fail "eigenes WLAN-Passwort"
[ "$(value BOX_PASSWORD)" != kurz ] || fail "zu kurzes Box-Passwort übernommen"
[ "$(value COUNTRY)" = AT ] || fail "Land"
grep -q 'disable --now knx-box-firewall.service' "$tmp/calls" || fail "Internet-Freigabe"
grep -q '^LAN_ACCESS="yes"$' "$tmp/root/etc/knx-box/env" || fail "Kabel freigegeben"
grep -q '^READ_ONLY="1"$' "$tmp/root/etc/knx-box/env" || fail "Nur-Lesen"
grep -q '^HEALTH_CHECK="true"$' "$tmp/root/etc/knx-box/env" || fail "Gesundheitsprüfung"
grep -qF 'P:Geheim\;Wlan\:1;;' "$tmp/root/boot/firmware/knx-box-wlan.png" || fail "QR-Maskierung"

# 2a. Clear passwords from the card when the server asks for it.
secrets() { PATH="$tmp/bin:$PATH" KNX_BOX_ROOT="$tmp/root" bash "$here/files/secrets.sh" "$@" >"$tmp/secrets.out"; }
boot=$tmp/root/boot/firmware
rm -rf "$tmp/root/etc/knx-box" "$tmp/calls"
cp "$here/files/knx-box.txt" "$boot/"
run
old_box=$(value BOX_PASSWORD)
old_wlan=$(value WLAN_PASSWORD)
grep -q BOX_PASSWORD "$tmp/root/etc/knx-box/env" || fail "env ohne Passwort"
mkdir -p "$tmp/root/var/lib/knx-box"
data=$tmp/root/var/lib/knx-box

# Box password changed: removed everywhere, Wi-Fi stays.
printf 'box
' >"$data/sticker-scrub"
secrets
[ ! -e "$data/sticker-scrub" ] || fail "Bitte bleibt liegen"
[ -z "$(value BOX_PASSWORD)" ] || fail "Box-Passwort noch in knx-box.txt"
[ "$(value WLAN_PASSWORD)" = "$old_wlan" ] || fail "WLAN-Passwort zu früh entfernt"
[ "$(value NAME)" = KNX-Box-1A2B ] || fail "knx-box.txt beschädigt"
! grep -q BOX_PASSWORD "$tmp/root/etc/knx-box/env" || fail "Box-Passwort noch in env"
grep -q '^BOX_NAME=' "$tmp/root/etc/knx-box/env" || fail "env beschädigt"
! grep -rqF "$old_box" "$boot" || fail "Box-Passwort noch auf der Karte: $(grep -rlF "$old_box" "$boot")"
case "$(cat "$boot/knx-box-link.txt")" in
  *"&pw="*) fail "Link enthält das Box-Passwort" ;;
  *"&fp="*"&wifi="*) ;;
  *) fail "Link ohne WLAN oder Fingerabdruck: $(cat "$boot/knx-box-link.txt")" ;;
esac
[ "$(cat "$boot/knx-box-app.png")" = "$(cat "$boot/knx-box-link.txt")" ] || fail "QR-Code nicht neu"
grep -qx "BOX_PASSWORD=" "$tmp/sheet" || fail "Blatt: Box-Passwort noch drauf"
grep -qx "WLAN_PASSWORD=$old_wlan" "$tmp/sheet" || fail "Blatt: WLAN-Passwort"

# Change the Wi-Fi password: new hotspot, removed everywhere.
printf 'Neues;Wlan:1
' >"$data/wifi-request"
secrets
[ ! -e "$data/wifi-request" ] || fail "WLAN-Bitte bleibt liegen"
grep -qxF 'psk=Neues;Wlan:1' "$ap" || fail "Hotspot-Passwort nicht geändert: $(grep '^psk' "$ap")"
grep -q "^setpriv --reuid=knx-box --regid=knx-box --clear-groups -- head -c 4096 -- $data/wifi-request$" "$tmp/setpriv-calls" ||
  fail "WLAN-Bitte nicht als Server-Benutzer gelesen"
[ "$(stat -c %a "$ap" 2>/dev/null || stat -f %Lp "$ap")" = 600 ] || fail "Keyfile-Rechte danach"
[ -z "$(value WLAN_PASSWORD)" ] || fail "WLAN-Passwort noch in knx-box.txt"
! grep -rqF "$old_wlan" "$boot" || fail "altes WLAN-Passwort noch auf der Karte"
! grep -rqF 'Neues' "$boot" || fail "neues WLAN-Passwort auf der Karte"
[ ! -e "$boot/knx-box-wlan.png" ] || fail "WLAN-QR-Code noch da"
case "$(cat "$boot/knx-box-link.txt")" in *"&wifi="*) fail "Link enthält das WLAN-Passwort" ;; esac

# Invalid or a link instead of a file: change nothing, remove the request anyway.
printf 'mit leerzeichen
' >"$data/wifi-request"
secrets
grep -qxF 'psk=Neues;Wlan:1' "$ap" || fail "ungültiges Passwort übernommen"
[ ! -e "$data/wifi-request" ] || fail "ungültige Bitte bleibt liegen"
# shellcheck disable=SC2016 # Das Zeichen selbst ist die Prüfung.
printf '$(touch /tmp/knx-box-pwned)
' >"$data/wifi-request"
secrets
[ ! -e /tmp/knx-box-pwned ] || fail "Bitte wurde ausgeführt"
grep -qxF 'psk=Neues;Wlan:1' "$ap" || fail "Kommando als Passwort übernommen"
printf 'psk-aus-link
' >"$tmp/geheim"
ln -s "$tmp/geheim" "$data/wifi-request"
secrets
[ ! -L "$data/wifi-request" ] || fail "Link bleibt liegen"
grep -qxF 'psk=Neues;Wlan:1' "$ap" || fail "folgt symbolischem Link"

# Restore from the card: takes effect, file removed, no plain text left.
# Written as the server user; a link the server left behind is replaced, not
# written through.
printf 'BOX_PASSWORD=von-der-karte
WLAN_PASSWORD=WlanKarte-1
' >"$boot/knx-box-reset.txt"
printf 'unberuehrt\n' >"$tmp/fremd"
ln -s "$tmp/fremd" "$data/password-reset.new"
: >"$tmp/setpriv-calls"
secrets --reset
[ ! -e "$boot/knx-box-reset.txt" ] || fail "knx-box-reset.txt bleibt liegen"
[ "$(cat "$data/password-reset")" = von-der-karte ] || fail "Box-Passwort nicht für den Server abgelegt"
[ ! -L "$data/password-reset" ] || fail "password-reset ist ein Link"
[ "$(cat "$tmp/fremd")" = unberuehrt ] || fail "durch einen Link in fremde Datei geschrieben"
grep -q '^setpriv --reuid=knx-box --regid=knx-box --clear-groups -- sh -c ' "$tmp/setpriv-calls" ||
  fail "password-reset nicht als Server-Benutzer geschrieben"
[ "$(stat -c %a "$data/password-reset" 2>/dev/null || stat -f %Lp "$data/password-reset")" = 600 ] || fail "Rechte password-reset"
grep -qx 'psk=WlanKarte-1' "$ap" || fail "WLAN-Passwort von der Karte"
rm "$data/password-reset"
printf 'BOX_PASSWORD=kurz
' >"$boot/knx-box-reset.txt"
secrets --reset
[ ! -e "$boot/knx-box-reset.txt" ] || fail "ungültige Datei bleibt liegen"
[ ! -e "$data/password-reset" ] || fail "zu kurzes Passwort übernommen"
secrets --reset # without file: nothing to do

# Clock: the request is read as the server user, a link or a time out of range
# changes nothing.
mkdir -p "$tmp/bin-time"
for cmd in chronyc hwclock; do
  # shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
  printf '#!/bin/sh\necho "%s $*" >>"%s/time-calls"\n' "$cmd" "$tmp" >"$tmp/bin-time/$cmd"
done
# BSD date (macOS) knows no -d.
printf '#!/bin/sh\necho "Jan 01, 2026 00:00:00"\n' >"$tmp/bin-time/date"
chmod +x "$tmp/bin-time/"*
settime() {
  rm -f "$tmp/time-calls"
  PATH="$tmp/bin-time:$tmp/bin:$PATH" bash "$here/files/settime.sh" "$data/time-request.json" >/dev/null
}
printf '{"epochMs": 1767225600000}' >"$data/time-request.json"
: >"$tmp/setpriv-calls"
settime
grep -q '^chronyc -m settime Jan 01, 2026' "$tmp/time-calls" || fail "Uhr nicht gestellt"
[ ! -e "$data/time-request.json" ] || fail "Zeitwunsch bleibt liegen"
grep -q -- "-- head -c 4096 -- $data/time-request.json$" "$tmp/setpriv-calls" || fail "Zeitwunsch nicht als Server-Benutzer gelesen"
printf '{"epochMs": 1000000000000}' >"$data/time-request.json"
settime
[ ! -e "$tmp/time-calls" ] || fail "Zeit außerhalb des Bereichs gestellt"
printf '{"epochMs": 1767225600000}' >"$tmp/zeit"
ln -s "$tmp/zeit" "$data/time-request.json"
settime
[ ! -e "$tmp/time-calls" ] || fail "Zeitwunsch über einen Link gelesen"
[ ! -L "$data/time-request.json" ] || fail "Link als Zeitwunsch bleibt liegen"
[ -f "$tmp/zeit" ] || fail "Ziel des Links entfernt"

# 3. Without qrencode: the setup link is still available as text.
mkdir "$tmp/sys"
for d in /usr/bin /bin /usr/sbin /sbin; do
  for f in "$d"/*; do
    n=${f##*/}
    [ "$n" = qrencode ] || [ -e "$tmp/sys/$n" ] || ln -s "$f" "$tmp/sys/$n"
  done
done
rm -rf "$tmp/root/etc/knx-box" "$tmp/root/boot/firmware/"knx-box-*
cp "$here/files/knx-box.txt" "$tmp/root/boot/firmware/"
mkdir "$tmp/bin-noqr"
for cmd in systemctl nmcli raspi-config rfkill; do cp "$tmp/bin/$cmd" "$tmp/bin-noqr/"; done
PATH="$tmp/bin-noqr:$tmp/sys" KNX_BOX_ROOT="$tmp/root" bash "$here/files/firstboot.sh" >/dev/null
[ ! -e "$tmp/root/boot/firmware/knx-box-app.png" ] || fail "qrencode nicht abgeschaltet"
case "$(cat "$tmp/root/boot/firmware/knx-box-link.txt")" in
  "knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&name=KNX-Box-1A2B&"*"&pw=$(value BOX_PASSWORD)") ;;
  *) fail "Kopplungslink als Text ohne qrencode" ;;
esac

# 4. Access via cable: the block is the static table in lan.nft (loaded before
# the network); lan-access.sh only adds or removes the exception in lan_open.
nft_rules=$here/files/lan.nft
grep -q 'iifname "wlan0" accept' "$nft_rules" || fail "WLAN der Box gesperrt"
grep -q 'meta l4proto tcp ct state new reject' "$nft_rules" || fail "Kabel nicht gesperrt"
[ "$(grep -n 'jump lan_open' "$nft_rules" | cut -d: -f1)" -lt "$(grep -n 'ct state new reject' "$nft_rules" | cut -d: -f1)" ] ||
  fail "Ausnahme steht hinter der Sperre"
mkdir -p "$tmp/nft" "$tmp/root/var/lib/knx-box"
# NFT_FAIL: every call fails. NFT_NO_TABLE: the table is not loaded yet.
# shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
printf '#!/bin/sh\necho "nft $*" >>"%s/nft/calls"\n[ -z "${NFT_FAIL:-}" ] || exit 1\ncase "$1 $2" in\n  "-f -") cat >>"%s/nft/calls" ;;\n  "-f "*) cat "$2" >>"%s/nft/calls" ;;\n  "list chain") [ -z "${NFT_NO_TABLE:-}" ] || exit 1 ;;\nesac\nexit 0\n' \
  "$tmp" "$tmp" "$tmp" >"$tmp/nft/nft"
chmod +x "$tmp/nft/nft"
lan() {
  rm -f "$tmp/nft/calls"
  PATH="$tmp/nft:$tmp/bin:$PATH" KNX_BOX_ROOT="$tmp/root" bash "$here/files/lan-access.sh" >/dev/null 2>&1
}
closed() { grep -q '^nft flush chain inet knx_box_lan lan_open$' "$tmp/nft/calls" && ! grep -q 'lan_open accept' "$tmp/nft/calls"; }
opened() { grep -q '^add rule inet knx_box_lan lan_open accept$' "$tmp/nft/calls"; }
printf 'BOX_NAME="x"\nLAN_ACCESS="no"\n' >"$tmp/root/etc/knx-box/env"
lan
closed || fail "LAN_ACCESS=no nicht gesperrt"
printf 'BOX_NAME="x"\nLAN_ACCESS="yes"\n' >"$tmp/root/etc/knx-box/env"
lan
opened || fail "LAN_ACCESS=yes nicht freigegeben"
! grep -q 'delete table' "$tmp/nft/calls" || fail "Freigabe löscht die Sperre"
echo no >"$tmp/root/var/lib/knx-box/lan-access"
: >"$tmp/setpriv-calls"
lan
closed || fail "Wahl der App gilt nicht vor LAN_ACCESS"
grep -q -- "-- head -c 4096 -- $tmp/root/var/lib/knx-box/lan-access$" "$tmp/setpriv-calls" || fail "Wahl nicht als Server-Benutzer gelesen"
# A link instead of the file counts as no choice: LAN_ACCESS from env applies.
rm "$tmp/root/var/lib/knx-box/lan-access"
printf 'BOX_NAME="x"\nLAN_ACCESS="no"\n' >"$tmp/root/etc/knx-box/env"
echo yes >"$tmp/link-ziel"
ln -s "$tmp/link-ziel" "$tmp/root/var/lib/knx-box/lan-access"
lan
closed || fail "Link als Wahl gefolgt"
rm "$tmp/root/etc/knx-box/env" "$tmp/root/var/lib/knx-box/lan-access"
lan
closed || fail "ohne Angaben nicht gesperrt"
# Table missing (lock unit did not run): load it first, then decide.
echo yes >"$tmp/root/var/lib/knx-box/lan-access"
NFT_NO_TABLE=1 lan
grep -q "^nft -f $here/files/lan.nft$" "$tmp/nft/calls" || fail "fehlende Tabelle nicht geladen"
opened || fail "nach dem Laden nicht freigegeben"
# nft fails: error status, so the unit shows it.
if NFT_FAIL=1 lan; then fail "Fehler von nft beim Freigeben verschwiegen"; fi
echo no >"$tmp/root/var/lib/knx-box/lan-access"
if NFT_FAIL=1 lan; then fail "Fehler von nft beim Sperren verschwiegen"; fi
rm "$tmp/root/var/lib/knx-box/lan-access"

# 5. SSH key: key only, sudo without password for the maintenance account.
rm -rf "$tmp/root/etc/knx-box" "$tmp/calls"
mkdir -p "$tmp/bin-ssh" "$tmp/root/etc/ssh/sshd_config.d" "$tmp/root/home/knxadmin"
cp "$tmp/bin/"* "$tmp/bin-ssh/"
printf '#!/bin/sh\necho "knxadmin:x:1000:1000::%s/root/home/knxadmin:/bin/bash"\n' "$tmp" >"$tmp/bin-ssh/getent"
# The test machine does not know knxadmin: drop -o/-g on install, swallow chown.
# shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
printf '#!/bin/bash\na=()\nwhile [ $# -gt 0 ]; do case $1 in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done\nexec /usr/bin/install "${a[@]}"\n' >"$tmp/bin-ssh/install"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin-ssh/chown"
chmod +x "$tmp/bin-ssh/"*
key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnxTestKey test@mac'
cp "$here/files/knx-box.txt" "$tmp/root/boot/firmware/"
printf 'SSH_PUBKEY=%s\n' "$key" >>"$tmp/root/boot/firmware/knx-box.txt"
PATH="$tmp/bin-ssh:$PATH" KNX_BOX_ROOT="$tmp/root" bash "$here/files/firstboot.sh" >/dev/null
grep -qxF "$key" "$tmp/root/home/knxadmin/.ssh/authorized_keys" || fail "SSH-Schlüssel"
grep -q '^PasswordAuthentication no$' "$tmp/root/etc/ssh/sshd_config.d/knx-box.conf" || fail "SSH nur mit Schlüssel"
grep -q 'enable --now ssh' "$tmp/calls" || fail "SSH nicht eingeschaltet"
sudoers=$tmp/root/etc/sudoers.d/010_knx-box-admin
[ "$(cat "$sudoers")" = 'knxadmin ALL=(ALL) NOPASSWD: ALL' ] || fail "sudo für das Wartungskonto"
[ "$(stat -c %a "$sudoers" 2>/dev/null || stat -f %Lp "$sudoers")" = 440 ] || fail "sudoers-Rechte"

# 6. Data partition: mount it if present and clean, otherwise stay on the SD card.
mkdir -p "$tmp/bin-data"
for cmd in mountpoint udevadm fsck.ext4 mount sleep; do
  # shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
  printf '#!/bin/sh\necho "%s $*" >>"%s/data-calls"\ncase %s in mountpoint) exit 1 ;; fsck.ext4) exit "${FSCK_RC:-0}" ;; mount) exit "${MOUNT_RC:-0}" ;; esac\n' \
    "$cmd" "$tmp" "$cmd" >"$tmp/bin-data/$cmd"
done
chmod +x "$tmp/bin-data/"*
data() {
  rm -f "$tmp/data-calls"
  PATH="$tmp/bin-data:$PATH" KNX_BOX_ROOT="$tmp/root" KNX_BOX_DATA_DEV="$tmp/KNXBOXDATA" \
    bash "$here/files/data-mount.sh" >/dev/null 2>&1 || fail "data-mount.sh bricht ab"
}
rm -f "$tmp/KNXBOXDATA"
data
! grep -q '^mount ' "$tmp/data-calls" || fail "ohne Partition eingehängt"
touch "$tmp/KNXBOXDATA"
data
grep -qx "mount -t ext4 -o noatime,commit=5,nosuid,nodev,noexec $tmp/KNXBOXDATA $tmp/root/var/lib/knx-box" "$tmp/data-calls" ||
  fail "Partition nicht eingehängt"
FSCK_RC=1 data
grep -q '^mount ' "$tmp/data-calls" || fail "nach Reparatur nicht eingehängt"
FSCK_RC=4 data
! grep -q '^mount ' "$tmp/data-calls" || fail "trotz Dateisystemfehler eingehängt"
MOUNT_RC=32 data

# 7. Services: systemd does not run here, so check the decisive lines.
grep -q '^Environment=BOX_STICKER=1$' "$here/files/knx-box.service" || fail "Aufkleber-Pflicht nicht gesetzt"
grep -q 'TLS_CERT=/etc/knx-box-tls/cert.pem' "$here/files/knx-box.service" || fail "HTTPS nicht gesetzt"
! grep -q '^RemainAfterExit' "$here/files/knx-box-secrets.service" || fail "Zweite Bitte startet nicht"
grep -q '^Before=knx-box.service$' "$here/files/knx-box-reset.service" || fail "Wiederherstellen nach dem Serverstart"
# firstboot runs after NetworkManager: a "Before=NetworkManager" here would be a cycle.
! grep -q '^Before=.*NetworkManager' "$here/files/knx-box-reset.service" || fail "Zyklus mit firstboot"
! grep -q '^RemainAfterExit' "$here/files/knx-box-lan.service" || fail "Schalter wirkt erst nach Neustart"
grep -q '^ExecStop=.*delete table inet knx_box$' "$here/files/knx-box-firewall.service" ||
  fail "Freigabe lässt die Firewall-Regeln stehen"
lock=$here/files/knx-box-lan-lock.service
grep -q '^Before=.*network-pre.target' "$lock" || fail "Kabelsperre erst nach dem Netz"
grep -q '^Before=.*ssh.service' "$lock" || fail "Kabelsperre erst nach SSH"
grep -q '^ExecStart=.*lan.nft$' "$lock" || fail "Kabelsperre lädt lan.nft nicht"
grep -q '^After=.*knx-box-lan-lock.service' "$here/files/knx-box-lan.service" || fail "Freigabe vor der Sperre"
# knx-box-lan.service runs after first boot, which itself enables ssh: an
# ordering against ssh there would deadlock first boot.
! grep -q '^Before=.*ssh' "$here/files/knx-box-lan.service" || fail "knx-box-lan vor ssh: Verklemmung beim Erststart"
server_unit=$here/files/knx-box.service
grep -q '^TemporaryFileSystem=/boot:ro$' "$server_unit" || fail "Server sieht die Boot-Partition"
grep -q '^UMask=0077$' "$server_unit" || fail "UMask des Servers"
! grep -q '^SystemCallFilter=\|^MemoryDenyWriteExecute=' "$server_unit" || fail "ungetestete Sperre für die Dart-VM"
for unit in knx-box-time.service knx-box-lan.service knx-box-secrets.service knx-box-reset.service; do
  grep -q '^NoNewPrivileges=yes$' "$here/files/$unit" || fail "$unit ohne NoNewPrivileges"
  grep -q '^CapabilityBoundingSet=.*CAP_SETUID' "$here/files/$unit" || fail "$unit: setpriv ohne CAP_SETUID"
done
# shellcheck disable=SC2016 # sucht den Text wörtlich
grep -q '^\[ "$firewall" = no \] || systemctl enable knx-box-firewall.service$' "$here/setup.sh" ||
  fail "Update schaltet die Firewall ohne Prüfung ein"

echo "firstboot.sh: alles in Ordnung"
