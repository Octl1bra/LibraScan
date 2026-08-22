#!/bin/sh
# Waits for App Store Connect to finish processing a build, then adds it to a
# beta group. Uploading only makes a build exist; testers see it once it is
# attached, and attaching is refused until processing completes.
#
#   testflight-attach.sh <key.p8> <key-id> <issuer-id> <build-number> <group-id>
set -eu

KEY="$1"; KEY_ID="$2"; ISSUER="$3"; BUILD="$4"; GROUP="$5"
API="https://api.appstoreconnect.apple.com/v1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/asc-jwt.swift" ] || { echo "missing $SCRIPT_DIR/asc-jwt.swift" >&2; exit 1; }
JWT="$(swift "$SCRIPT_DIR/asc-jwt.swift" "$KEY" "$KEY_ID" "$ISSUER" 1200)"
# An empty token turns every request into a 401 and the poll below would just
# report PENDING until it timed out — fail here instead, where the cause is plain.
[ -n "$JWT" ] || { echo "could not mint an App Store Connect token" >&2; exit 1; }
PROBE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
    -H "Authorization: Bearer $JWT" "$API/builds?limit=1")"
[ "$PROBE" = "200" ] || { echo "App Store Connect rejected the token (HTTP $PROBE)" >&2; exit 1; }

BUILD_ID=""
i=0
while [ "$i" -lt 30 ]; do
    i=$((i + 1))
    BODY="$(curl -sS --max-time 30 -H "Authorization: Bearer $JWT" \
        "$API/builds?limit=10&sort=-uploadedDate" || true)"
    if [ -z "$BODY" ]; then
        echo "  [$((i * 30))s] request failed, retrying"
        sleep 30
        continue
    fi
    LINE="$(printf '%s' "$BODY" \
        | BUILD="$BUILD" python3 -c 'import json, os, sys
target = os.environ["BUILD"]
for b in json.load(sys.stdin).get("data", []):
    if b["attributes"].get("version") == target:
        print(b["attributes"].get("processingState"), b["id"])
        break
else:
    print("PENDING", "-")')"
    STATE="${LINE% *}"; ID="${LINE#* }"
    echo "  [$((i * 30))s] build $BUILD: $STATE"
    case "$STATE" in
        VALID) BUILD_ID="$ID"; break ;;
        INVALID|FAILED) echo "processing failed: $STATE" >&2; exit 1 ;;
    esac
    sleep 30
done

if [ -z "$BUILD_ID" ]; then
    echo "build $BUILD is still processing after 15 minutes; attach it by hand" >&2
    exit 2
fi

CODE="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 -X POST \
    -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
    -d "{\"data\":[{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}]}" \
    "$API/betaGroups/$GROUP/relationships/builds")"
case "$CODE" in
    204) echo "build $BUILD added to group $GROUP" ;;
    # A group that takes every build already has this one; saying so is not a
    # failure, and a re-run of the same release must not turn red because of it.
    422) echo "build $BUILD was already in group $GROUP" ;;
    *)   echo "could not add build $BUILD to group $GROUP (HTTP $CODE)" >&2; exit 1 ;;
esac
