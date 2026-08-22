#!/bin/sh
# Xcode Cloud — runs after the clone, before xcodebuild.
#
# Xcode Cloud does not manage the build number for us, and TestFlight rejects a
# build number it has already seen. CI_BUILD_NUMBER is monotonic per workflow,
# so stamp it into the project's single project-level CURRENT_PROJECT_VERSION.
# MARKETING_VERSION stays hand-edited in the project.
set -eu

[ -n "${CI_BUILD_NUMBER:-}" ] || { echo "not running in Xcode Cloud; leaving the build number alone"; exit 0; }

PROJECT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}/LibraScan.xcodeproj/project.pbxproj"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" "$PROJECT"
echo "CURRENT_PROJECT_VERSION -> ${CI_BUILD_NUMBER}"
grep -c "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};" "$PROJECT"
