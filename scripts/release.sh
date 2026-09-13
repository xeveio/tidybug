#!/bin/bash
set -euo pipefail

# TidyBug release: build → sign → notarize → staple → DMG → Sparkle-sign → appcast → (upload)
#
# Usage:
#   scripts/release.sh <version> [--notes notes.md] [--upload] [--github] [--skip-notarize]
#
# Examples:
#   scripts/release.sh 1.0.1                      # build + notarize locally, nothing published
#   scripts/release.sh 1.0.1 --notes notes.md --upload --github
#
# Output: build/release/TidyBug-<version>.dmg and build/release/appcast.xml
#
# Credentials (the script picks the first that is configured):
#   Notarization
#     NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER   App Store Connect API key (CI)
#     APPLE_ID + APP_SPECIFIC_PASSWORD                  Apple ID (CI)
#     keychain profile "${NOTARY_PROFILE:-xeve}"        local default (already set up on this Mac)
#   Sparkle EdDSA signing
#     SPARKLE_KEY_FILE                                  private key file (CI; `generate_keys -x`)
#     Keychain account "tidybug"                        local default
#   Upload (only with --upload)
#     DO_SPACES_KEY + DO_SPACES_SECRET                  write access to the xeve-downloads Space
#
# Release order matters: the appcast is uploaded LAST and only after the DMG it
# names is reachable, so clients are never offered an update that 404s.

APP="TidyBug"
TEAM_ID="KD8GRYUXWZ"
IDENTITY="Developer ID Application"
SPACE="s3://xeve-downloads"
SPACE_PREFIX="tidybug"
SPACE_ENDPOINT="https://nyc3.digitaloceanspaces.com"
PUBLIC_BASE="https://dl.xeve.io/${SPACE_PREFIX}"
MIN_MACOS="26.0"

VERSION=""
NOTES=""
UPLOAD=false
GITHUB=false
NOTARIZE=true
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2 ;;
    --upload) UPLOAD=true; shift ;;
    --github) GITHUB=true; shift ;;
    --skip-notarize) NOTARIZE=false; shift ;;
    -*) echo "Unknown option $1"; exit 1 ;;
    *) VERSION="$1"; shift ;;
  esac
done
[ -n "$VERSION" ] || { echo "Usage: $0 <version> [--notes file] [--upload] [--github] [--skip-notarize]"; exit 1; }
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Version must look like 1.2 or 1.2.3"; exit 1; }
if $UPLOAD && ! $NOTARIZE; then echo "Refusing to publish an un-notarized build."; exit 1; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
DD="$OUT/DerivedData"
cd "$ROOT"

step() { printf "\n\033[1;31m▸\033[0m \033[1m%s\033[0m\n" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "Preflight"
command -v xcodegen >/dev/null || die "xcodegen missing (brew install xcodegen)"
security find-identity -v -p codesigning | grep -q "$IDENTITY" || die "No '$IDENTITY' certificate in the keychain"
rm -rf "$OUT"; mkdir -p "$OUT"

# ---------------------------------------------------------------------------
step "Version $VERSION"
sed -i '' "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"${VERSION}\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"${VERSION}\"/" project.yml
xcodegen generate >/dev/null

# ---------------------------------------------------------------------------
step "Build (Release, arm64 + x86_64)"
xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Release \
  -derivedDataPath "$DD" ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
  build 2>&1 | grep -E "error:|warning: .*sign|BUILD" || true
APP_PATH="$DD/Build/Products/Release/$APP.app"
[ -d "$APP_PATH" ] || die "Build failed — no $APP.app"
lipo -archs "$APP_PATH/Contents/MacOS/$APP"

# ---------------------------------------------------------------------------
step "Sign (hardened runtime + secure timestamp)"
# Sparkle's documented order: XPC services, helpers, framework, then the app.
SPK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
if [ -d "$SPK" ]; then
  sign "$SPK/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$SPK/Versions/B/XPCServices/Downloader.xpc"
  sign "$SPK/Versions/B/Autoupdate"
  sign "$SPK/Versions/B/Updater.app"
  sign "$SPK"
fi
sign "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -2
if codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | grep -q "get-task-allow"; then
  die "get-task-allow entitlement present — notarization would reject this build"
fi

# ---------------------------------------------------------------------------
notarize() {
  local file="$1" json id status
  if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    json=$(xcrun notarytool submit "$file" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER" --wait --timeout 45m --output-format json)
  elif [ -n "${APPLE_ID:-}" ] && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    json=$(xcrun notarytool submit "$file" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" \
      --team-id "$TEAM_ID" --wait --timeout 45m --output-format json)
  else
    json=$(xcrun notarytool submit "$file" --keychain-profile "${NOTARY_PROFILE:-xeve}" \
      --wait --timeout 45m --output-format json)
  fi
  id=$(echo "$json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("id",""))')
  status=$(echo "$json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))')
  echo "  submission $id: $status"
  if [ "$status" != "Accepted" ]; then
    echo "  Apple's log:"
    if [ -n "${NOTARY_KEY_PATH:-}" ]; then
      xcrun notarytool log "$id" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" || true
    elif [ -n "${APPLE_ID:-}" ]; then
      xcrun notarytool log "$id" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" || true
    else
      xcrun notarytool log "$id" --keychain-profile "${NOTARY_PROFILE:-xeve}" || true
    fi
    die "Notarization failed for $(basename "$file")"
  fi
}

if $NOTARIZE; then
  step "Notarize + staple the app"
  ditto -c -k --keepParent "$APP_PATH" "$OUT/$APP-notarize.zip"
  notarize "$OUT/$APP-notarize.zip"
  rm -f "$OUT/$APP-notarize.zip"
  xcrun stapler staple -q "$APP_PATH"
  spctl --assess --type execute --verbose=2 "$APP_PATH" 2>&1 | tail -2
else
  step "Skipping notarization (--skip-notarize): this build will warn on other Macs"
fi

# ---------------------------------------------------------------------------
step "Disk image"
DMG="$OUT/$APP-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP_PATH" "$STAGE/$APP.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
sign "$DMG"
if $NOTARIZE; then
  step "Notarize + staple the disk image"
  notarize "$DMG"
  xcrun stapler staple -q "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1 | tail -2
fi

# ---------------------------------------------------------------------------
step "Sparkle EdDSA signature"
SIGN_UPDATE=$(find "$DD/SourcePackages/artifacts" -path "*Sparkle/bin/sign_update" -type f | head -1)
[ -x "$SIGN_UPDATE" ] || die "sign_update not found in $DD/SourcePackages"
if [ -n "${SPARKLE_KEY_FILE:-}" ]; then
  ED=$("$SIGN_UPDATE" -f "$SPARKLE_KEY_FILE" "$DMG")
else
  ED=$("$SIGN_UPDATE" --account tidybug "$DMG")
fi
[[ "$ED" == *"sparkle:edSignature"* ]] || die "sign_update produced no signature"
echo "  $ED" | cut -c1-80

# ---------------------------------------------------------------------------
step "appcast.xml"
DMG_NAME="$(basename "$DMG")"
NOTES_HTML=""
if [ -n "$NOTES" ]; then
  [ -f "$NOTES" ] || die "notes file not found: $NOTES"
  # "- item" lines become a list; other lines become paragraphs.
  NOTES_HTML=$(python3 - "$NOTES" <<'PY'
import html, sys
out, in_list = [], False
for line in open(sys.argv[1]).read().splitlines():
    s = line.strip()
    if s.startswith(("- ", "* ")):
        if not in_list: out.append("<ul>"); in_list = True
        out.append("<li>%s</li>" % html.escape(s[2:]))
    else:
        if in_list: out.append("</ul>"); in_list = False
        if s: out.append("<p>%s</p>" % html.escape(s))
if in_list: out.append("</ul>")
print("\n".join(out))
PY
)
fi
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>TidyBug</title>
    <link>${PUBLIC_BASE}/appcast.xml</link>
    <description>TidyBug updates</description>
    <language>en</language>
    <item>
      <title>TidyBug ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_MACOS}</sparkle:minimumSystemVersion>
      <description><![CDATA[${NOTES_HTML}]]></description>
      <enclosure url="${PUBLIC_BASE}/${DMG_NAME}" type="application/x-apple-diskimage" ${ED} />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT/appcast.xml" && echo "  appcast valid"

# ---------------------------------------------------------------------------
if $UPLOAD; then
  step "Upload to ${SPACE}/${SPACE_PREFIX}/ (served at ${PUBLIC_BASE}/)"
  [ -n "${DO_SPACES_KEY:-}" ] && [ -n "${DO_SPACES_SECRET:-}" ] || die "DO_SPACES_KEY / DO_SPACES_SECRET not set"
  export AWS_ACCESS_KEY_ID="$DO_SPACES_KEY" AWS_SECRET_ACCESS_KEY="$DO_SPACES_SECRET" AWS_DEFAULT_REGION=nyc3
  s3() { aws s3 cp "$1" "$2" --endpoint-url "$SPACE_ENDPOINT" --acl public-read --content-type "$3" --only-show-errors; }
  s3 "$DMG" "$SPACE/$SPACE_PREFIX/$DMG_NAME" application/x-apple-diskimage
  s3 "$DMG" "$SPACE/$SPACE_PREFIX/$APP-latest.dmg" application/x-apple-diskimage
  # The feed is only true if what it points at is fetchable — check before publishing it.
  curl -fsSI --retry 5 --retry-delay 5 --retry-all-errors "${PUBLIC_BASE}/${DMG_NAME}" >/dev/null \
    || die "${PUBLIC_BASE}/${DMG_NAME} is not reachable; appcast NOT published"
  s3 "$OUT/appcast.xml" "$SPACE/$SPACE_PREFIX/appcast.xml" application/xml
  curl -fsS "${PUBLIC_BASE}/appcast.xml" | grep -q "<sparkle:version>${VERSION}</sparkle:version>" \
    && echo "  live: ${PUBLIC_BASE}/appcast.xml → ${VERSION}" \
    || die "appcast uploaded but ${PUBLIC_BASE}/appcast.xml does not show ${VERSION} yet"
fi

if $GITHUB; then
  step "GitHub release tidybug-v${VERSION}"
  gh release create "tidybug-v${VERSION}" "$DMG" --title "TidyBug ${VERSION}" \
    ${NOTES:+--notes-file "$NOTES"} ${NOTES:---notes "TidyBug ${VERSION}"}
fi

step "Done"
echo "  DMG:     $DMG ($(du -h "$DMG" | cut -f1))"
echo "  Appcast: $OUT/appcast.xml"
$UPLOAD || echo "  Not published. Re-run with --upload to ship it to ${PUBLIC_BASE}/."
