#!/bin/sh
# Xcode Cloud — runs after the clone, before xcodebuild.
#
# Stamps a build number into the project's single project-level
# CURRENT_PROJECT_VERSION. MARKETING_VERSION stays hand-edited.
#
# NOT CI_BUILD_NUMBER: that counter is per-workflow and starts at 1, so a fresh
# Xcode Cloud workflow would re-emit build numbers TestFlight has already seen
# and reject the upload. The commit count is monotonic and is the same number
# the macOS pipeline uses, so the two platforms stay comparable.
set -eu

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

# Everything already published is at or below build 3 (dmg + TestFlight, 2026-08-22).
BUILD_FLOOR=4

if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
    git fetch --unshallow >/dev/null 2>&1 || git fetch --depth=1000000 >/dev/null 2>&1 || true
fi

BUILD="$(git rev-list --count HEAD)"
if [ "$BUILD" -lt "$BUILD_FLOOR" ]; then
    echo "error: computed build number $BUILD is below the floor $BUILD_FLOOR — shallow clone?" >&2
    exit 1
fi

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${BUILD};/g" \
    LibraScan.xcodeproj/project.pbxproj
echo "CURRENT_PROJECT_VERSION -> ${BUILD} (commit count)"
grep -c "CURRENT_PROJECT_VERSION = ${BUILD};" LibraScan.xcodeproj/project.pbxproj
