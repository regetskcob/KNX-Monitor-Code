# Shared by firstboot.sh and secrets.sh (sourced, not executed).
# shellcheck shell=bash

# Printable characters without spaces and without " ' \ $ ` (env file, keyfile).
valid_password() { [[ ${#1} -ge 8 && ${#1} -le 63 && "$1" =~ ^[[:graph:]]+$ && "$1" != *[\"\'\\\$\`]* ]]; }

# Escape special characters in the Wi-Fi QR code (WIFI:…;;).
qr_escape() { printf '%s' "$1" | sed 's/[;,:]/\\&/g'; }

# Percent-encoding for the pairing link (letters, digits and -._~ are kept).
urlencode() {
  # Byte by byte (umlauts too, as UTF-8 bytes).
  local LC_ALL=C
  local s=$1 out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case "$c" in
      [A-Za-z0-9._~-]) out+=$c ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

# (Re)write link, QR codes and sheet on the boot partition. Empty
# passwords appear nowhere: whoever changed them no longer finds them there.
#
# The link keeps the HTTP address so that older apps can pair as well; with
# the fingerprint, newer ones switch to HTTPS themselves (lib/platform/box_link.dart).
#
#   write_boot_files <boot> <server> <name> <ssid> <wlan> <box> <lan> <fingerprint>
write_boot_files() {
  local boot=$1 server=$2 name=$3 ssid=$4 wlan=$5 box=$6 lan=$7 fp=$8 link
  link="knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&name=$(urlencode "$name")&ssid=$(urlencode "$ssid")"
  if [ -n "$fp" ]; then link+="&fp=$fp"; fi
  if [ -n "$wlan" ]; then link+="&wifi=$(urlencode "$wlan")"; fi
  if [ -n "$box" ]; then link+="&pw=$(urlencode "$box")"; fi
  printf '%s\n' "$link" >"$boot/knx-box-link.txt"
  rm -f "$boot/knx-box-wlan.png" "$boot/knx-box-app.png" "$boot/knx-box-de.pdf" "$boot/knx-box-en.pdf"
  if command -v qrencode >/dev/null; then
    if [ -n "$wlan" ]; then
      qrencode -s 8 -o "$boot/knx-box-wlan.png" "WIFI:T:WPA;S:$(qr_escape "$ssid");P:$(qr_escape "$wlan");;" || true
    fi
    qrencode -s 8 -o "$boot/knx-box-app.png" "$link" || true
  fi
  # Sheet with sticker, Wi-Fi, passwords, link and instructions, one PDF per
  # language. The server builds it; the values are passed via the environment,
  # not via the process list.
  if [ -x "$server" ]; then
    BOX_NAME=$name WLAN_SSID=$ssid WLAN_PASSWORD=$wlan BOX_PASSWORD=$box \
      BOX_LINK=$link LAN_ACCESS=$lan "$server" sheet "$boot" ||
      echo "Blatt (knx-box-de.pdf) nicht erzeugt"
  fi
}
