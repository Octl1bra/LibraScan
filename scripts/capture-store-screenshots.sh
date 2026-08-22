#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData-store"
RAW_DIR="$PROJECT_DIR/build/store/raw"
SIMULATOR_NAME="${LIBRASCAN_SIMULATOR_NAME:-iPhone 17}"
BUNDLE_ID="com.Libra.Scan"

mkdir -p "$RAW_DIR"

UDID="$(xcrun simctl list devices available | awk -F '[()]' -v name="$SIMULATOR_NAME" '$0 ~ "^[[:space:]]*" name "[[:space:]]*\\(" { print $2; exit }')"
if [[ -z "$UDID" ]]; then
  echo "No available simulator named '$SIMULATOR_NAME'." >&2
  exit 1
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularBars 4 \
  --wifiBars 3

xcodebuild \
  -project "$PROJECT_DIR/LibraScan.xcodeproj" \
  -scheme LibraScan \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/LibraScan.app"
xcrun swift -module-cache-path "$DERIVED_DATA/SwiftModuleCache" \
  "$SCRIPT_DIR/bake-demo-camera-background.swift" \
  "$PROJECT_DIR/scripts/store-assets/demo-camera-background.png" \
  "$APP_PATH/demo-camera-background.png" \
  "https://scan.libra.wiki"
xcrun simctl install "$UDID" "$APP_PATH"

capture() {
  local scene="$1"
  local output="$2"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    -AppleLanguages "(zh-Hans)" \
    -AppleLocale "zh_CN" \
    -LibraScanDemoMode \
    -LibraScanDemoScreen "$scene"
  sleep 2
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --cellularBars 4 \
    --wifiBars 3
  xcrun simctl io "$UDID" screenshot --type=png "$RAW_DIR/$output"
}

capture scan 01-scan.png
capture history 02-history.png
capture bridge 03-type-to-mac.png

"$SCRIPT_DIR/make-store-screenshots.swift"
