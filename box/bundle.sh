#!/bin/bash
# Builds the KNX Monitor Box bundle: server for Linux arm64, web app,
# setup.sh and system files. The image is made from it (build-image.sh), and
# on a running Pi it is enough to unpack it and run "sudo ./setup.sh".
#
#   box/bundle.sh [--web build/web] [--out build/knx-box-<version>.tar.gz]
#
# Without --web the web app is built (Flutter). The server is cross-compiled
# with Dart (dart compile exe --target-os linux; the server needs
# Dart 3.13, see server/pubspec.yaml) and runs on Pi OS without further packages.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
web=""
out=""
while [ $# -gt 0 ]; do
  case $1 in
    --web) web=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

version=$(grep -E '^version:' "$root/ha-addon/knx_monitor/config.yaml" | cut -d'"' -f2)
out=${out:-$root/build/knx-box-$version.tar.gz}

if [ -z "$web" ]; then
  (cd "$root" && flutter build web --release --no-web-resources-cdn)
  # As in the add-on: leave out debug symbols and the WASM renderer.
  find "$root/build/web" -name '*.symbols' -delete
  rm -f "$root/build/web/canvaskit/skwasm"*
  web=$root/build/web
fi
[ -f "$web/index.html" ] || { echo "keine Web-App in $web" >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
dir=$stage/knx-box
mkdir -p "$dir"

(cd "$root/ha-addon/knx_monitor/server" && dart pub get --enforce-lockfile >/dev/null &&
  dart compile exe --target-os=linux --target-arch=arm64 bin/server.dart -o "$dir/server")
cp -R "$web" "$dir/web"
cp -R "$root/box/files" "$dir/files"
cp "$root/box/setup.sh" "$dir/setup.sh"
chmod +x "$dir/setup.sh" "$dir/files/"*.sh
echo "$version" >"$dir/VERSION"

mkdir -p "$(dirname "$out")"
# macOS: no ._ files and extended attributes in the bundle.
COPYFILE_DISABLE=1 tar -czf "$out" -C "$stage" knx-box
echo "Paket: $out ($(du -h "$out" | cut -f1))"
