#!/bin/sh
# Builds the web app for the Home Assistant add-on and copies it to
# ha-addon/knx_monitor/web, the internal packages to ha-addon/knx_monitor/packages
# (tool/addon_packages.sh). Optionally transfers it straight to Home Assistant:
#
#   tool/build_ha_addon.sh                              # build only
#   tool/build_ha_addon.sh hassio@homeassistant.local   # build and copy to /addons
#
# The transfer needs the "Advanced SSH & Web Terminal" add-on
# (or Samba: copy ha-addon/knx_monitor into the "addons" share).
set -e
cd "$(dirname "$0")/.."

flutter build web --release --no-web-resources-cdn
out=ha-addon/knx_monitor/web
rm -rf "$out"
mkdir -p "$out"
# Skip debug symbols and the WebAssembly renderer (only needed for --wasm).
rsync -a --exclude '*.symbols' --exclude 'skwasm*' build/web/ "$out/"
du -sh "$out"
# The server's internal packages (packages/knx): Home Assistant builds the
# image from this folder alone, see the Dockerfile.
tool/addon_packages.sh

if [ -n "$1" ]; then
  # One connection for all steps – the password is asked only once.
  sock="$(mktemp -u /tmp/knx-addon-ssh.XXXXXX)"
  ssh_opts="-o ControlMaster=auto -o ControlPath=$sock -o ControlPersist=60"
  ssh $ssh_opts "$1" 'mkdir -p /tmp/knx_monitor'
  rsync -a --delete --exclude '.dart_tool' -e "ssh $ssh_opts" ha-addon/knx_monitor/ "$1:/tmp/knx_monitor/"
  # Non-root users (e.g. "hassio" in the Advanced SSH add-on) need sudo for /addons.
  ssh -t $ssh_opts "$1" 'if [ "$(id -u)" = 0 ]; then s=; else s=sudo; fi
    $s mkdir -p /addons/knx_monitor && $s rsync -a --delete /tmp/knx_monitor/ /addons/knx_monitor/ && rm -rf /tmp/knx_monitor
    # Local development: build locally instead of pulling the published image.
    $s sed -i "/^image:/d" /addons/knx_monitor/config.yaml'
  ssh $ssh_opts -O exit "$1" 2>/dev/null || true
  echo "Copied. In Home Assistant: Settings → Add-ons → Add-on Store → ⋮ → Check for updates,"
  echo "then install KNX Monitor under \"Local add-ons\" and enable \"Show in sidebar\"."
fi
