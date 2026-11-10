#!/usr/bin/env bash
# Copies the Busclear icon set exported by Horizont into every platform.
#
#   tool/copy_brand_icons.sh <path to a horizont checkout>
#
# The icons are rendered in the horizont repository (tool/export_icons.py from
# web/partials/app-icon.html, product "knx"). They are copied, never redrawn
# or rescaled here; after a change there, run this again.
set -euo pipefail

HZ="${1:?usage: tool/copy_brand_icons.sh <horizont checkout>}"
SRC="$HZ/icons/export/knx"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$SRC" ] || { echo "no icon export at $SRC" >&2; exit 1; }

# App asset: the square icon; the app rounds it (connect screen, splash).
cp "$SRC/ios/AppIcon.appiconset/AppIcon-1024.png" "$ROOT/assets/brand/icon_1024.png"

# iOS: single-size app icon.
IOS="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
rm -f "$IOS"/*.png
cp "$SRC/ios/AppIcon.appiconset/"* "$IOS/"
# Launch screen: the rounded icon without transparency (iOS puts transparent
# launch images on white). Its corners are filled with the launch background,
# the system background (white / black, identical in every colour space, so
# image and screen never differ), one image for light and one for dark; the storyboard sizes it to
# 144 pt. Needs Pillow (like tool/launch_graphics.py).
python3 - "$SRC/web/icon-512.png" "$ROOT/ios/Runner/Assets.xcassets/LaunchImage.imageset" <<'PY'
import json, sys
from pathlib import Path
from PIL import Image
icon = Image.open(sys.argv[1]).convert('RGBA')
out = Path(sys.argv[2])
for f in out.glob('*.png'):
    f.unlink()
images = []
for name, bg, dark in (('LaunchImage', '#FFFFFF', False), ('LaunchImageDark', '#000000', True)):
    flat = Image.new('RGBA', icon.size, bg)
    flat.alpha_composite(icon)
    flat.convert('RGB').save(out / f'{name}.png')
    entry = {'idiom': 'universal', 'filename': f'{name}.png', 'scale': '1x'}
    if dark:
        entry['appearances'] = [{'appearance': 'luminosity', 'value': 'dark'}]
    images.append(entry)
(out / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
PY

# Android: adaptive icon (background, foreground, monochrome) per density.
RES="$ROOT/android/app/src/main/res"
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p "$RES/mipmap-$d"
  rm -f "$RES/mipmap-$d/"*.png
  cp "$SRC/android/mipmap-$d/"*.png "$RES/mipmap-$d/"
done
cp "$SRC/android/mipmap-anydpi-v26/ic_launcher.xml" "$RES/mipmap-anydpi-v26/ic_launcher.xml"
cp "$SRC/android/mipmap-anydpi-v26/ic_launcher.xml" "$RES/mipmap-anydpi-v26/ic_launcher_round.xml"
rm -f "$RES/drawable/ic_launcher_background.xml"
cp "$SRC/web/icon-512.png" "$RES/drawable-nodpi/splash_logo.png"

# macOS: Flutter's names for the iconset sizes.
MAC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
cp "$SRC/macos/AppIcon.iconset/icon_16x16.png" "$MAC/app_icon_16.png"
cp "$SRC/macos/AppIcon.iconset/icon_32x32.png" "$MAC/app_icon_32.png"
cp "$SRC/macos/AppIcon.iconset/icon_32x32@2x.png" "$MAC/app_icon_64.png"
cp "$SRC/macos/AppIcon.iconset/icon_128x128.png" "$MAC/app_icon_128.png"
cp "$SRC/macos/AppIcon.iconset/icon_256x256.png" "$MAC/app_icon_256.png"
cp "$SRC/macos/AppIcon.iconset/icon_512x512.png" "$MAC/app_icon_512.png"
cp "$SRC/macos/AppIcon.iconset/icon_512x512@2x.png" "$MAC/app_icon_1024.png"

# Windows: an .ico that embeds the exported PNGs unchanged.
python3 - "$SRC/macos/AppIcon.iconset" "$ROOT/windows/runner/resources/app_icon.ico" <<'EOF'
import struct, sys
from pathlib import Path
src, out = Path(sys.argv[1]), Path(sys.argv[2])
frames = [(s, (src / f"icon_{s}x{s}.png").read_bytes()) for s in (16, 32, 128, 256)]
header = struct.pack("<HHH", 0, 1, len(frames))
offset = 6 + 16 * len(frames)
entries, data = b"", b""
for size, png in frames:
    dim = 0 if size >= 256 else size
    entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(png), offset + len(data))
    data += png
out.write_bytes(header + entries + data)
EOF

# Web (app and add-on): favicons, touch icon, manifest icons.
WEB="$ROOT/web"
cp "$SRC/web/favicon-32.png" "$WEB/favicon.png"
cp "$SRC/web/favicon.svg" "$WEB/favicon.svg"
cp "$SRC/web/apple-touch-icon.png" "$WEB/icons/apple-touch-icon.png"
cp "$SRC/web/icon-192.png" "$WEB/icons/Icon-192.png"
cp "$SRC/web/icon-512.png" "$WEB/icons/Icon-512.png"
cp "$SRC/web/icon-512-maskable.png" "$WEB/icons/Icon-maskable-512.png"
rm -f "$WEB/icons/Icon-maskable-192.png"

# Home Assistant add-on store: icon and logo.
cp "$SRC/web/icon-192.png" "$ROOT/ha-addon/knx_monitor/icon.png"
cp "$SRC/web/icon-512.png" "$ROOT/ha-addon/knx_monitor/logo.png"

# Home Assistant integration: the same icon as the add-on, so both look alike in the update list
# (256 px and 512 px, as Home Assistant's brand folders expect).
BRAND="$ROOT/ha-integration/custom_components/knx_monitor/brand"
cp "$SRC/web/icon-512.png" "$BRAND/icon@2x.png"
cp "$SRC/web/icon-512.png" "$BRAND/logo@2x.png"
sips -Z 256 "$SRC/web/icon-512.png" --out "$BRAND/icon.png" >/dev/null
cp "$BRAND/icon.png" "$BRAND/logo.png"

echo "copied the Horizont icon set from $SRC"
