#!/bin/sh
# Copies the internal Dart packages (packages/, e.g. packages/knx) into the
# add-on folder, so the Docker build context ha-addon/knx_monitor contains
# them: the server depends on ../../../packages/knx, and the Dockerfile puts
# both in the same layout. The copy is gitignored and replaced on every run.
#
# Run before every image build: .github/workflows/addon.yml and
# tool/build_ha_addon.sh do it; for a local "docker build ha-addon/knx_monitor"
# run it by hand first.
set -e
cd "$(dirname "$0")/.."

dest=ha-addon/knx_monitor/packages
rm -rf "$dest"
mkdir -p "$dest"
for p in packages/*/; do
  name=$(basename "$p")
  cp -R "$p" "$dest/$name"
  # Local pub and build state of the package does not belong in the image.
  rm -rf "$dest/$name/.dart_tool" "$dest/$name/build"
done
