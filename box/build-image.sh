#!/bin/bash
# Builds the finished Raspberry Pi OS image of the KNX Monitor Box with pi-gen.
#
#   box/build-image.sh build/knx-box-<version>.tar.gz
#
# Needs Linux with Docker; fastest on arm64 (e.g. GitHub runner
# ubuntu-24.04-arm), on x86 pi-gen builds via QEMU, much more slowly.
# Result: build/knx-box-image/pi-gen/deploy/*.img.xz – write it to an SD card/SSD
# with Raspberry Pi Imager ("Use custom") or balenaEtcher.
#
# PI_GEN_REF selects the pi-gen revision (default: branch "arm64"). For releases
# use a fixed tag so that the image stays reproducible; PI_GEN_COMMIT
# (full commit) additionally checks that the tag was not moved.
set -euo pipefail

bundle=${1:?Paket von bundle.sh angeben}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
work=${WORK_DIR:-$root/build/knx-box-image}
ref=${PI_GEN_REF:-arm64}
commit=${PI_GEN_COMMIT:-}

[ "$(uname -s)" = Linux ] || { echo "pi-gen läuft nur unter Linux (mit Docker)" >&2; exit 1; }
command -v docker >/dev/null || { echo "Docker fehlt" >&2; exit 1; }

rm -rf "$work"
mkdir -p "$work"
git clone --depth 1 --branch "$ref" https://github.com/RPi-Distro/pi-gen.git "$work/pi-gen"
cd "$work/pi-gen"
if [ -n "$commit" ] && [ "$(git rev-parse HEAD)" != "$commit" ]; then
  echo "pi-gen $ref zeigt auf $(git rev-parse HEAD), erwartet $commit" >&2
  exit 1
fi

cp -R "$here/pi-gen/stage-knx-box" .
mkdir -p stage-knx-box/00-knx-box/files
tar -xzf "$bundle" -C stage-knx-box/00-knx-box/files
mv stage-knx-box/00-knx-box/files/knx-box stage-knx-box/00-knx-box/files/bundle
# Export only the box image, not the plain Lite system as well.
touch stage2/SKIP_IMAGES

version=$(cat stage-knx-box/00-knx-box/files/bundle/VERSION)
{
  cat "$here/pi-gen/config"
  echo "IMG_FILENAME=\"knx-box-$version\""
  echo "ARCHIVE_FILENAME=\"knx-box-$version\""
  # Only because pi-gen requires one; the stage removes it again.
  echo "FIRST_USER_PASS=\"$(head -c 24 /dev/urandom | base64 | tr -d '/+=')\""
} >config

./build-docker.sh
ls -lh deploy/
