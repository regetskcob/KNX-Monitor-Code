#!/bin/bash
# Dry run of setup.sh in a test directory: setup, update, rollback on a
# silent or non-starting server, manual --rollback, repetition. With
# stand-ins for systemctl, apt-get, curl and the like. Runs on Linux and macOS
# and touches neither a Pi nor the system. The real rollback is checked by
# docs/resilience-tests.md.
#
#   box/test-setup.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
fail() { echo "FEHLER: $*" >&2; exit 1; }

root=$tmp/root
mkdir -p "$tmp/bin" "$root/boot/firmware" "$root/etc" "$root/var/lib/knx-box"
: >"$root/etc/fstab"
printf 'console=serial0,115200 root=PARTUUID=1\n' >"$root/boot/firmware/cmdline.txt"
: >"$root/boot/firmware/config.txt"

# Stand-in commands. The state of the running server is in its file:
# "dead" does not start, "mute" runs but does not respond.
for cmd in apt-get useradd usermod; do
  printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/$cmd"
done
# shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
printf '#!/bin/sh\n[ "$1" = -u ] && echo 0\nexit 0\n' >"$tmp/bin/id"
printf '#!/bin/sh\necho aarch64\n' >"$tmp/bin/uname"
printf '#!/bin/bash\nexec /bin/sleep 0.1\n' >"$tmp/bin/sleep"
cat >"$tmp/bin/systemctl" <<SYSTEMCTL
#!/bin/sh
echo "systemctl \$*" >>"$tmp/calls"
server=\$(cat "$root/opt/knx-box/server" 2>/dev/null || echo none)
case "\$1 \$2" in
  "is-enabled --quiet") [ ! -f "$tmp/firewall-off" ] ;;
  "is-active --quiet") [ "\$server" != dead ] ;;
  "restart knx-box.service"|"start knx-box.service") [ "\$server" != dead ] ;;
  *) exit 0 ;;
esac
SYSTEMCTL
cat >"$tmp/bin/curl" <<CURL
#!/bin/sh
case \$(cat "$root/opt/knx-box/server") in
  mute|dead) echo 000 ;;
  *) echo 401 ;;
esac
CURL
# BSD sed (macOS) requires a suffix after -i.
if [ "$(uname -s)" = Darwin ]; then
  # shellcheck disable=SC2016 # Skript für den Ersatzbefehl, bewusst unexpandiert
  printf '#!/bin/sh\nif [ "$1" = -i ]; then shift; exec /usr/bin/sed -i "" "$@"; fi\nexec /usr/bin/sed "$@"\n' >"$tmp/bin/sed"
fi
chmod +x "$tmp/bin/"*

# Bundle as from bundle.sh, "server" is just a file holding the state.
bundle() { # bundle <directory> <version> <state>
  local dir=$tmp/$1
  rm -rf "$dir"
  mkdir -p "$dir/web"
  printf '%s\n' "$3" >"$dir/server"
  chmod +x "$dir/server"
  printf '%s\n' "$2" >"$dir/web/index.html"
  printf '%s\n' "$2" >"$dir/VERSION"
  cp -R "$here/files" "$dir/files"
  cp "$here/setup.sh" "$dir/setup.sh"
}
run() { # run <directory> [options]; output in $tmp/out
  local dir=$tmp/$1
  shift
  PATH="$tmp/bin:$PATH" KNX_BOX_ROOT="$root" KNX_BOX_HEALTH_SECONDS=1 bash "$dir/setup.sh" "$@" >"$tmp/out" 2>&1
}
installed() { cat "$root/opt/knx-box/VERSION"; }
server() { cat "$root/opt/knx-box/server"; }
web() { cat "$root/opt/knx-box/web/index.html"; }
expect_state() { # expect_state <version> <state>
  [ "$(installed)" = "$1" ] || fail "Version $(installed) statt $1"
  [ "$(web)" = "$1" ] || fail "Web-App $(web) statt $1"
  [ "$(server)" = "$2" ] || fail "Server $(server) statt $2"
}

# 1. First setup: no first boot yet, so no check and no rollback.
bundle v1 1.0 v1
run v1 --yes || { cat "$tmp/out"; fail "Einrichten"; }
expect_state 1.0 v1
[ ! -e "$root/opt/knx-box/server.prev" ] || fail "server.prev beim ersten Einrichten"
[ -f "$root/etc/systemd/system/knx-box.service" ] || fail "Dienst nicht installiert"
[ -x "$root/usr/local/lib/knx-box/firstboot.sh" ] || fail "Hilfsskripte fehlen"
[ -x "$root/usr/local/lib/knx-box/secrets.sh" ] || fail "secrets.sh fehlt"
[ -f "$root/usr/local/lib/knx-box/box-common.sh" ] || fail "box-common.sh fehlt"
[ -f "$root/etc/systemd/system/knx-box-secrets.path" ] || fail "Bitten werden nicht beobachtet"
grep -q 'enable .*knx-box-secrets.path' "$tmp/calls" || fail "knx-box-secrets.path nicht eingeschaltet"
grep -q 'enable .*knx-box-reset.service' "$tmp/calls" || fail "knx-box-reset.service nicht eingeschaltet"
[ -f "$root/usr/local/lib/knx-box/lan.nft" ] || fail "lan.nft fehlt"
[ -f "$root/etc/systemd/system/knx-box-lan-lock.service" ] || fail "Kabelsperre nicht installiert"
grep -q 'enable .*knx-box-lan-lock.service' "$tmp/calls" || fail "Kabelsperre nicht eingeschaltet"
grep -q '^SystemMaxUse=' "$root/etc/systemd/journald.conf.d/knx-box.conf" || fail "Journal nicht begrenzt"
# No certificate before the first boot: every box needs its own key.
[ ! -e "$root/etc/knx-box-tls/key.pem" ] || fail "Zertifikat schon vor dem ersten Start"
grep -q 'enable .*knx-box-firewall.service\|enable knx-box-firewall.service' "$tmp/calls" || fail "Firewall nicht eingeschaltet"
grep -q '^# KNX-HAT' "$root/boot/firmware/config.txt" || fail "UART nicht eingetragen"
grep -A1 -x '\[pi3\]' "$root/boot/firmware/config.txt" | grep -qx 'dtoverlay=disable-bt' || fail "UART for the Pi 3 missing"
grep -q console=serial0 "$root/boot/firmware/cmdline.txt" && fail "serielle Konsole noch an"

# Set-up box with its own data and settings.
mkdir -p "$root/etc/knx-box"
echo 'BOX_NAME=Test' >"$root/etc/knx-box/env"
echo verlauf >"$root/var/lib/knx-box/history.ndjson"
echo meine-lan-datei >"$root/etc/NetworkManager/system-connections/knx-box-lan.nmconnection"
echo PASSWORT=mein >"$root/boot/firmware/knx-box.txt"
keep() {
  [ "$(cat "$root/etc/knx-box/env")" = 'BOX_NAME=Test' ] || fail "env verändert"
  [ "$(cat "$root/var/lib/knx-box/history.ndjson")" = verlauf ] || fail "Verlauf verändert"
  [ "$(cat "$root/etc/NetworkManager/system-connections/knx-box-lan.nmconnection")" = meine-lan-datei ] || fail "LAN-Einstellung verändert"
  [ "$(cat "$root/boot/firmware/knx-box.txt")" = PASSWORT=mein ] || fail "knx-box.txt verändert"
  [ "$(grep -c '^# KNX-HAT' "$root/boot/firmware/config.txt")" = 1 ] || fail "UART-Eintrag doppelt"
}

# 2. Update that responds: the previous version is ready for rollback.
# The box was set up before 1.9.4: its UART section lacks the Pi 3.
printf '[pi3]\narm_boost=1\n[all]\n\n# KNX-HAT (kBerry): UART0 auf GPIO 14/15 frei für das Modul\n[pi4]\ndtoverlay=disable-bt\n[pi5]\ndtoverlay=uart0-pi5\n[all]\n' >"$root/boot/firmware/config.txt"
bundle v2 2.0 v2
run v2 --yes || { cat "$tmp/out"; fail "Update"; }
expect_state 2.0 v2
# An unrelated [pi3] section earlier in the file must not count as the HAT's.
[ "$(awk '/^# KNX-HAT/ { getline l; print l; exit }' "$root/boot/firmware/config.txt")" = '[pi3]' ] ||
  fail "Pi 3 section not added to an old box"
[ "$(grep -cx '\[pi3\]' "$root/boot/firmware/config.txt")" = 2 ] || fail "Pi 3 section added more than once"
if command -v openssl >/dev/null; then
  [ -s "$root/etc/knx-box-tls/key.pem" ] || fail "Update ohne Zertifikat"
  key_before=$(cat "$root/etc/knx-box-tls/key.pem")
fi
grep -q 'restart .*knx-box-secrets.path' "$tmp/calls" || fail "knx-box-secrets.path nicht gestartet"
# On a running box: closed table first, then the choice opens it again.
lock_line=$(grep -n '^systemctl start knx-box-lan-lock.service$' "$tmp/calls" | tail -n 1 | cut -d: -f1)
lan_line=$(grep -n '^systemctl restart knx-box-lan.service' "$tmp/calls" | tail -n 1 | cut -d: -f1)
if [ -z "$lock_line" ] || [ -z "$lan_line" ] || [ "$lock_line" -ge "$lan_line" ]; then
  fail "Kabelsperre nicht vor der Wahl gestartet"
fi
[ "$(cat "$root/opt/knx-box/server.prev")" = v1 ] || fail "server.prev"
[ "$(cat "$root/opt/knx-box/web.prev/index.html")" = 1.0 ] || fail "web.prev"
[ "$(cat "$root/opt/knx-box/VERSION.prev")" = 1.0 ] || fail "VERSION.prev"
keep

# Another update: the certificate is kept, otherwise the QR code would no longer match.
run v2 --yes || { cat "$tmp/out"; fail "Update 2"; }
if command -v openssl >/dev/null; then
  [ "$(cat "$root/etc/knx-box-tls/key.pem")" = "$key_before" ] || fail "Update ersetzt das Zertifikat"
fi

# The startup check queries the health endpoint, which responds without login too.
grep -q 'http://127.0.0.1/healthz' "$here/setup.sh" || fail "Startprüfung nicht über /healthz"

# 3. Firewall: whoever disabled it (INTERNET_SHARING=yes) keeps it that way.
: >"$tmp/calls"
touch "$tmp/firewall-off"
run v2 --yes || { cat "$tmp/out"; fail "Update ohne Firewall"; }
if grep -E 'enable .*knx-box-firewall|start knx-box-firewall' "$tmp/calls" >/dev/null; then
  fail "Update hat die abgeschaltete Firewall wieder eingeschaltet"
fi
rm "$tmp/firewall-off"
: >"$tmp/calls"
run v2 --yes || { cat "$tmp/out"; fail "Update mit Firewall"; }
grep -q 'start knx-box-firewall' "$tmp/calls" || fail "Firewall nicht gestartet"

# 4. New server does not start: rolls back on its own, error status, data is kept.
bundle dead 3.0 dead
if run dead --yes; then fail "Update mit totem Server meldet Erfolg"; fi
grep -q 'zurück auf die vorige Version' "$tmp/out" || fail "keine Meldung zum Rückweg"
grep -q 'die vorige Version läuft wieder' "$tmp/out" || fail "keine Erfolgsmeldung zum Rückweg"
expect_state 2.0 v2
keep

# 5. New server runs but does not respond: same.
bundle mute 3.1 mute
if run mute --yes; then fail "Update mit stummem Server meldet Erfolg"; fi
expect_state 2.0 v2
keep

# 6. Manual --rollback: back, after that there is no second step.
bundle v5 5.0 v5
run v5 --yes || { cat "$tmp/out"; fail "Update auf 5.0"; }
expect_state 5.0 v5
run v5 --rollback || { cat "$tmp/out"; fail "--rollback"; }
expect_state 2.0 v2
grep -q 'Zurück auf 2.0' "$tmp/out" || fail "Meldung von --rollback: $(cat "$tmp/out")"
if run v5 --rollback; then fail "zweites --rollback ohne Vorversion"; fi
grep -q 'keine vorige Version' "$tmp/out" || fail "Meldung ohne Vorversion"
expect_state 2.0 v2
keep

# 7. Previous version itself broken: --rollback says so.
run v5 --yes || { cat "$tmp/out"; fail "Update auf 5.0"; }
printf 'mute\n' >"$root/opt/knx-box/server.prev"
if run v5 --rollback; then fail "--rollback auf stumme Vorversion"; fi
grep -q 'auch die vorige Version antwortet nicht' "$tmp/out" || fail "Meldung: $(cat "$tmp/out")"

# 8. Without bundle: touch nothing.
mkdir -p "$tmp/leer"
cp "$here/setup.sh" "$tmp/leer/setup.sh"
before=$(server)
if run leer --yes; then fail "ohne Paket"; fi
[ "$(server)" = "$before" ] || fail "ohne Paket verändert"

echo "setup.sh: alle Prüfungen bestanden"
