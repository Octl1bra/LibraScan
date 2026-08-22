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

# Geometry. Finder stores the window *frame*; the content area is the frame minus the title bar.
# Background = exact content size (no scrolling, nothing uncovered). Icons sit centred in the space below the title block.
WIN_W=540; CONTENT_H=${CONTENT_H:-352}; TITLEBAR=${TITLEBAR:-28}
WIN_H=$((CONTENT_H + TITLEBAR)); ICON_Y=$(( 100 + (CONTENT_H - 100) / 2 ))

# 1. background (1x + 2x → HiDPI TIFF)
swift "$ROOT/scripts/dmg/background.swift" "$WORK" "$CONTENT_H" "$ICON_Y" >/dev/null
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
  -D win_h="$WIN_H" -D icon_y="$ICON_Y" \
  "LibraScan" "$OUT/LibraScan-$VERSION.dmg"
DMG="$OUT/LibraScan-$VERSION.dmg"
echo "built $DMG"

# 4. Sign + notarize + staple the dmg.
#
# Gatekeeper assesses the disk image itself, not just the app inside: an unsigned dmg is
# "rejected / no usable signature" on download, even when the app within is notarized and
# stapled (verify with: syspolicy_check distribution <dmg>).
#
# codesign only uses identities in the local keychain. The Developer ID Application
# certificate Xcode creates automatically is CLOUD-MANAGED — its private key lives on
# Apple's servers, so codesign reports "no identity found". Create a second certificate
# from a CSR instead (Keychain Access → Certificate Assistant), which keeps the private
# key local. See docs/CI.md.
# Either everything needed to ship is present, or none of it is. A half-configured
# run used to emit a plausible-looking dmg that Gatekeeper would reject on the
# user's machine — the worst possible failure, because it looks like success.
CREDS_SET=0
for v in "${DEVELOPER_ID_IDENTITY:-}" "${NOTARY_KEY_PATH:-}" "${NOTARY_KEY_ID:-}" "${NOTARY_ISSUER_ID:-}"; do
  [ -n "$v" ] && CREDS_SET=$((CREDS_SET + 1))
done

if [ "$CREDS_SET" -eq 0 ]; then
  echo >&2
  echo "WARNING: DEV BUILD — this dmg is neither signed nor notarized." >&2
  echo "         Gatekeeper WILL reject it when a user downloads it. Fine for checking" >&2
  echo "         the window layout; never publish it. See docs/CI.md." >&2
  exit 0
fi

if [ "$CREDS_SET" -ne 4 ]; then
  echo >&2
  echo "ERROR: partial signing configuration — refusing to emit a dmg that cannot ship." >&2
  for pair in "DEVELOPER_ID_IDENTITY:${DEVELOPER_ID_IDENTITY:-}" "NOTARY_KEY_PATH:${NOTARY_KEY_PATH:-}" \
              "NOTARY_KEY_ID:${NOTARY_KEY_ID:-}" "NOTARY_ISSUER_ID:${NOTARY_ISSUER_ID:-}"; do
    name="${pair%%:*}"; value="${pair#*:}"
    [ -n "$value" ] && echo "         $name: set" >&2 || echo "         $name: MISSING" >&2
  done
  rm -f "$DMG"
  exit 1
fi

[ -f "$NOTARY_KEY_PATH" ] || { echo "ERROR: NOTARY_KEY_PATH does not exist: $NOTARY_KEY_PATH" >&2; rm -f "$DMG"; exit 1; }

echo "signing the dmg as: $DEVELOPER_ID_IDENTITY"
codesign --force --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"

xcrun notarytool submit "$DMG" \
  --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# Apple's own pre-flight: the last word on whether this can ship.
syspolicy_check distribution "$DMG"
