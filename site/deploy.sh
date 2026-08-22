#!/bin/sh
# Deploy scan.libra.wiki to Cloudflare Pages by direct upload (no git integration needed).
#
# One-time, on the Cloudflare account that owns the libra.wiki zone:
#   (the token in 1Password → Agents → cloudflare-libra belongs to that account)
#   npx wrangler pages project create librascan --production-branch main
#   Dashboard → Workers & Pages → librascan → Custom domains → add scan.libra.wiki
#   (Cloudflare creates the CNAME automatically when the zone is on the same account.)
#
# Static only. The Mac dmg lives on GitHub Releases; the site links to
# releases/latest/download/LibraScan.dmg and never has to be redeployed for one.
#
# Cache note: the libra.wiki zone edge-caches .dmg/.js/.css for hours and this token cannot purge.
# When assets or the dmg change, bump the ?v= / ?b= query strings in index.html and app.js.
# These are opaque, monotonic cache keys — NOT the app's build number (CI uses the run number).
# After deploying, wait ~30 s before requesting a NEW ?v= URL through scan.libra.wiki: an early request can
# be served by a PoP still on the previous deployment and the stale copy gets cached under the new key.
set -eu
cd "$(dirname "$0")"
# Credentials: CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID from the environment, else from the
# 1Password Agents vault item "cloudflare-libra" (fields: credential, account_id) via opsa.
OPSA="$HOME/.claude/bin/opsa"
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && [ -x "$OPSA" ]; then
  # Local runs: opsa can only read the Agents vault, so bootstrap through the
  # service-account token kept there into gh-action, which holds the real
  # credential. CI skips this entirely — the workflow has already exported it.
  OP_SERVICE_ACCOUNT_TOKEN="$("$OPSA" read 'op://Agents/gh-action-sa/credential')"
  export OP_SERVICE_ACCOUNT_TOKEN
  CLOUDFLARE_API_TOKEN="$(op read 'op://gh-action/cloudflare-libra/credential')"
  CLOUDFLARE_ACCOUNT_ID="$(op read 'op://gh-action/cloudflare-libra/account_id')"
  export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
fi

npx --yes wrangler@latest pages project create librascan --production-branch main 2>/dev/null || true
npx --yes wrangler@latest pages deploy . --project-name librascan --branch main --commit-dirty=true
