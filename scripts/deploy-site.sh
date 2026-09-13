#!/bin/bash
set -euo pipefail

# Deploy the marketing site (site/) to Cloudflare Pages project "tidybug",
# served at https://tidybug.xeve.io.
#
# Usage: scripts/deploy-site.sh [--preview]
#
# If a notarized DMG exists in build/release/ (from scripts/release.sh), it is
# bundled at /download/TidyBug-<version>.dmg and /download redirects to it.
# Otherwise /download redirects to the Sparkle channel's latest DMG.
#
# Credentials: CF_XEVE_API_TOKEN + CF_XEVE_ACCOUNT_ID in ~/.secrets/cloudflare.env
# (the "Kvyn.14" Cloudflare account that owns the xeve.io zone).

BRANCH=main
[ "${1:-}" = "--preview" ] && BRANCH=preview

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/site-dist"
cd "$ROOT"

rm -rf "$OUT"
cp -R site "$OUT"
rm -f "$OUT/.DS_Store"

DMG=$(ls -t build/release/TidyBug-*.dmg 2>/dev/null | head -1 || true)
if [ -n "$DMG" ]; then
  VERSION=$(basename "$DMG" .dmg | sed 's/^TidyBug-//')
  SIZE=$(du -h "$DMG" | cut -f1 | sed 's/M$/ MB/')
  # Only ever ship a notarized, stapled image from the website.
  xcrun stapler validate -q "$DMG" || { echo "ERROR: $DMG is not stapled — run scripts/release.sh first"; exit 1; }
  mkdir -p "$OUT/download"
  cp "$DMG" "$OUT/download/"
  printf '/download /download/%s 302\n' "$(basename "$DMG")" > "$OUT/_redirects"
  perl -pi -e "s#(id=\"dl-version\">)v[0-9.]+#\${1}v$VERSION#; s#(id=\"dl-meta\">)v[0-9.]+#\${1}v$VERSION · $SIZE#" "$OUT/index.html"
  echo "Bundling $(basename "$DMG") ($SIZE)"
else
  printf '/download https://dl.xeve.io/tidybug/TidyBug-latest.dmg 302\n' > "$OUT/_redirects"
  echo "No local DMG; /download → dl.xeve.io"
fi

cat > "$OUT/_headers" <<'HEADERS'
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  X-Frame-Options: DENY
  Permissions-Policy: camera=(), microphone=(), geolocation=()
/shots/*
  Cache-Control: public, max-age=86400
/download/*
  Content-Type: application/x-apple-diskimage
  Content-Disposition: attachment
  Cache-Control: public, max-age=3600
HEADERS

for f in shots/overview.png icon.png og.png; do
  [ -f "$OUT/$f" ] || echo "WARNING: $f missing (run scripts/screenshots.sh)"
done

CLOUDFLARE_API_TOKEN="$(grep '^CF_XEVE_API_TOKEN=' ~/.secrets/cloudflare.env | cut -d= -f2-)" \
CLOUDFLARE_ACCOUNT_ID="$(grep '^CF_XEVE_ACCOUNT_ID=' ~/.secrets/cloudflare.env | cut -d= -f2-)" \
  wrangler pages deploy "$OUT" --project-name tidybug --branch "$BRANCH" --commit-dirty=true
