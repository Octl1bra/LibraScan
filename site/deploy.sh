#!/bin/sh
# Deploy scan.libra.wiki to Cloudflare Pages by direct upload (no git integration needed).
#
# One-time, on the Cloudflare account that owns the libra.wiki zone:
#   (the token in 1Password → Agents → cloudflare-libra belongs to that account)
#   npx wrangler pages project create librascan --production-branch main
#   Dashboard → Workers & Pages → librascan → Custom domains → add scan.libra.wiki
#   (Cloudflare creates the CNAME automatically when the zone is on the same account.)
#
# The Mac dmg is staged from build/release-<version> at deploy time and is NOT committed.
#
# Cache note: the libra.wiki zone edge-caches .dmg/.js/.css for hours and this token cannot purge.
# When assets or the dmg change, bump the ?v= / ?b= query strings in index.html and app.js.
# After deploying, wait ~30 s before requesting a NEW ?v= URL through scan.libra.wiki: an early request can
# be served by a PoP still on the previous deployment and the stale copy gets cached under the new key.
set -eu
cd "$(dirname "$0")"
# Credentials: CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID from the environment, else from the
# 1Password Agents vault item "cloudflare-libra" (fields: credential, account_id) via opsa.
OPSA="$HOME/.claude/bin/opsa"
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && [ -x "$OPSA" ]; then
  CLOUDFLARE_API_TOKEN="$("$OPSA" read 'op://Agents/cloudflare-libra/credential')"
  CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-$("$OPSA" item get cloudflare-libra --vault Agents --fields label=account_id --reveal)}"
  export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
fi
VERSION="${1:-1.0}"
mkdir -p download dl
cp "../build/release-$VERSION/LibraScan-$VERSION.dmg" "download/LibraScan-$VERSION.dmg"
cp "../build/release-$VERSION/LibraScan-$VERSION.dmg" "dl/LibraScan-$VERSION.dmg"   # /dl/ is the linked path; /download/ kept for old links
npx --yes wrangler@latest pages project create librascan --production-branch main 2>/dev/null || true
npx --yes wrangler@latest pages deploy . --project-name librascan --branch main --commit-dirty=true
