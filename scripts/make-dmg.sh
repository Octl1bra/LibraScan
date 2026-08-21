#!/bin/sh
# Build the drag-to-install dmg for LibraScan for Mac.
#   scripts/make-dmg.sh <path/to/notarized/LibraScan.app> <version> [out-dir]
# Produces <out-dir>/LibraScan-<version>.dmg with the branded background, a volume icon,
# the app at left, an Applications alias at right. dmgbuild writes the Finder layout directly (no Finder scripting).
set -eu
APP="$1"; VERSION="$2"; OUT="${3:-build/release-$VERSION}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. background (1x + 2x → HiDPI TIFF)
swift "$ROOT/scripts/dmg/background.swift" "$WORK" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null 2>&1

# 2. volume icon from the app icon
ICON_SRC="$ROOT/LibraScan/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
mkdir -p "$WORK/LibraScan.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON_SRC" --out "$WORK/LibraScan.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$ICON_SRC" --out "$WORK/LibraScan.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/LibraScan.iconset" -o "$WORK/LibraScan.icns"

# 3. stage + build
mkdir -p "$WORK/src" "$OUT"
cp -R "$APP" "$WORK/src/"
rm -f "$OUT/LibraScan-$VERSION.dmg"
DMGBUILD=""
for c in "$(command -v dmgbuild 2>/dev/null)" "$HOME/.local/bin/dmgbuild"; do
  if [ -n "$c" ] && [ -x "$c" ]; then DMGBUILD="$c"; break; fi
done
[ -n "$DMGBUILD" ] || { echo "dmgbuild not found — install with: pipx install dmgbuild" >&2; exit 1; }
"$DMGBUILD" -s "$ROOT/scripts/dmg/settings.py" \
  -D app="$WORK/src/LibraScan.app" \
  -D background="$WORK/background.tiff" \
  -D volicon="$WORK/LibraScan.icns" \
  "LibraScan" "$OUT/LibraScan-$VERSION.dmg"
echo "built $OUT/LibraScan-$VERSION.dmg"
