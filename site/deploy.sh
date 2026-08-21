#!/bin/sh
# Deploy scan.libra.wiki to Cloudflare Pages by direct upload (no git integration needed).
#
# One-time, on the Cloudflare account that owns the libra.wiki zone:
#   npx wrangler login                                   # personal account, not the company one
#   npx wrangler pages project create librascan --production-branch main
#   Dashboard → Workers & Pages → librascan → Custom domains → add scan.libra.wiki
#   (Cloudflare creates the CNAME automatically when the zone is on the same account.)
#
# The Mac dmg is staged from build/release-<version> at deploy time and is NOT committed.
set -eu
cd "$(dirname "$0")"
VERSION="${1:-1.0}"
mkdir -p download
cp "../build/release-$VERSION/LibraScan-$VERSION.dmg" "download/LibraScan-$VERSION.dmg"
npx --yes wrangler@latest pages project create librascan --production-branch main 2>/dev/null || true
npx --yes wrangler@latest pages deploy . --project-name librascan --branch main --commit-dirty=true
