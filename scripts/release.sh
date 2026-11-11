#!/bin/bash
# Builds dist/Dropshot.dmg.
#
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="dropshot-notary" \
#   SPARKLE_FEED_URL="https://example.com/appcast.xml" \
#   SPARKLE_PUBLIC_ED_KEY="base64key=" \
#   scripts/release.sh
#
# Without DEV_ID the result is ad-hoc signed and NOT notarized (fine for your own Mac,
# Gatekeeper will block it elsewhere). See RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=Dropshot
DERIVED=build
ARCHIVE="$DERIVED/$APP.xcarchive"
STAGE="$DERIVED/release"
DIST=dist
DMG="$DIST/$APP.dmg"
DEV_ID="${DEV_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

step() { printf '\n==> %s\n' "$*"; }

[ -f Dropshot/Resources/AppIcon.icns ] || scripts/make-icon.sh

step "Archiving (Release, universal)"
xcodegen generate --quiet
xcodebuild archive \
  -project "$APP.xcodeproj" -scheme "$APP" -configuration Release \
  -derivedDataPath "$DERIVED" -archivePath "$ARCHIVE" \
  -skipPackagePluginValidation \
  SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}" \
  SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}" \
  | scripts/xcfilter.sh

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
ditto "$ARCHIVE/Products/Applications/$APP.app" "$STAGE/$APP.app"
APP_PATH="$STAGE/$APP.app"

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP")"
echo "Architectures: $ARCHS"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *) echo "error: expected a universal binary, got: $ARCHS" >&2; exit 1 ;;
esac

step "Signing"
if [ -n "$DEV_ID" ]; then
  IDENTITY="$DEV_ID"
  SIGN_FLAGS=(--force --options runtime --timestamp)
  echo "Identity: $DEV_ID"
else
  IDENTITY="-"
  SIGN_FLAGS=(--force --options runtime)
  echo "DEV_ID not set — ad-hoc signing"
fi
# An ad-hoc signature has no Team ID, so library validation would stop the app loading its
# own Sparkle.framework. Only the ad-hoc build gets the exemption.
APP_ENTITLEMENTS=()
[ -z "$DEV_ID" ] && APP_ENTITLEMENTS=(--entitlements scripts/support/adhoc.entitlements)
sign() { codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" "$@"; }

# Inside-out: Sparkle's helpers, then the framework, then the app (Sparkle's documented order).
SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  for xpc in "$SPARKLE"/Versions/B/XPCServices/*.xpc; do
    [ -e "$xpc" ] || continue
    if [ "$(basename "$xpc")" = "Downloader.xpc" ]; then
      sign --preserve-metadata=entitlements "$xpc"
    else
      sign "$xpc"
    fi
  done
  sign "$SPARKLE/Versions/B/Autoupdate"
  sign "$SPARKLE/Versions/B/Updater.app"
  sign "$SPARKLE"
fi
# Anything else that is nested code.
find "$APP_PATH/Contents" \( -name '*.dylib' -o -name '*.framework' -o -name '*.bundle' \) \
  -not -path "$SPARKLE*" -print0 | while IFS= read -r -d '' nested; do
  if [ -d "$nested/Contents/MacOS" ] || [ -f "$nested" ] || [ -d "$nested/Versions" ]; then
    sign "$nested"
  fi
done
sign ${APP_ENTITLEMENTS[@]+"${APP_ENTITLEMENTS[@]}"} "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
codesign -d --verbose=2 "$APP_PATH" 2>&1 | grep -E 'flags|Signature|TeamIdentifier' || true

step "Building DMG"
rm -f "$DMG"
DMG_SRC="$STAGE/dmg"
rm -rf "$DMG_SRC"
mkdir -p "$DMG_SRC"
ditto "$APP_PATH" "$DMG_SRC/$APP.app"

# create-dmg lays the window out by scripting Finder, which can stall (locked screen, CI).
# Give it a time limit, then fall back to a layout-free image.
with_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }
CREATE_DMG_ARGS=(
  --volname "$APP" --window-size 540 380 --icon-size 110
  --icon "$APP.app" 150 180 --app-drop-link 390 180
  --hide-extension "$APP.app" --no-internet-enable
)
[ -f Dropshot/Resources/AppIcon.icns ] && CREATE_DMG_ARGS+=(--volicon Dropshot/Resources/AppIcon.icns)

made=0
if command -v create-dmg >/dev/null 2>&1; then
  if with_timeout 180 create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG" "$DMG_SRC" >/dev/null 2>&1; then
    made=1
  else
    echo "create-dmg (Finder layout) failed — retrying without layout"
    rm -f "$DMG" "$DIST"/rw.*.dmg
    hdiutil detach "/Volumes/$APP" -force >/dev/null 2>&1 || true
    if with_timeout 180 create-dmg --skip-jenkins "${CREATE_DMG_ARGS[@]}" "$DMG" "$DMG_SRC" >/dev/null 2>&1; then
      made=1
    fi
  fi
else
  echo "create-dmg not installed (brew install create-dmg) — using hdiutil"
fi
if [ "$made" -ne 1 ]; then
  rm -f "$DMG" "$DIST"/rw.*.dmg
  ln -s /Applications "$DMG_SRC/Applications"
  hdiutil create -volname "$APP" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG" >/dev/null
fi

step "Launch check"
# Catches signing mistakes that only show up at load time (library validation etc.).
CHECK_ROOT="$(mktemp -d)"
"$APP_PATH/Contents/MacOS/$APP" -rootFolderPath "$CHECK_ROOT" -onboardingCompleted YES \
  -screencaptureDomain app.dropshot.releasecheck -showMenuBarIcon NO >/dev/null 2>&1 &
CHECK_PID=$!
sleep 3
if kill -0 "$CHECK_PID" 2>/dev/null; then
  kill "$CHECK_PID"
  wait "$CHECK_PID" 2>/dev/null || true
  echo "Signed app launches."
else
  echo "error: the signed app exited immediately — run $APP_PATH/Contents/MacOS/$APP to see why" >&2
  exit 1
fi
rm -rf "$CHECK_ROOT"

echo "Created $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"

if [ -n "$DEV_ID" ]; then
  codesign --force --timestamp --sign "$DEV_ID" "$DMG"
  if [ -n "$NOTARY_PROFILE" ]; then
    step "Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    echo "Done: $DMG is signed, notarized and stapled."
  else
    cat <<MSG

$DMG is signed with your Developer ID but NOT notarized (NOTARY_PROFILE is not set).
Create a keychain profile once, then re-run with NOTARY_PROFILE=<name>:

  xcrun notarytool store-credentials dropshot-notary --apple-id <apple-id> --team-id <TEAMID>
MSG
  fi
else
  cat <<MSG

$DMG is AD-HOC signed and NOT notarized.
It runs on this Mac; on any other Mac Gatekeeper will refuse to open it.

To ship a notarized build:
  1. Join the Apple Developer Program and create a "Developer ID Application" certificate.
  2. Store notary credentials once (prompts for an app-specific password):
       xcrun notarytool store-credentials dropshot-notary --apple-id <apple-id> --team-id <TEAMID>
  3. Re-run:
       DEV_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=dropshot-notary scripts/release.sh

Details: RELEASING.md
MSG
fi
