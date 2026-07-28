#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNING_IDENTITY="${CLEANER_CODESIGN_IDENTITY:-}"
TEAM_ID="${CLEANER_TEAM_ID:-}"
NOTARY_PROFILE="${CLEANER_NOTARY_PROFILE:-}"
PREFLIGHT_ONLY=0

if [ "${1:-}" = "--preflight" ]; then
  PREFLIGHT_ONLY=1
elif (($#)); then
  echo "Usage: $0 [--preflight]" >&2
  exit 2
fi

require_value() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "blocked: set $name in the shell environment" >&2
    exit 1
  fi
}

require_value CLEANER_CODESIGN_IDENTITY "$SIGNING_IDENTITY"
require_value CLEANER_TEAM_ID "$TEAM_ID"
require_value CLEANER_NOTARY_PROFILE "$NOTARY_PROFILE"

if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "blocked: CLEANER_CODESIGN_IDENTITY must be a Developer ID Application identity" >&2
  exit 1
fi
if ! security find-identity -v -p codesigning 2>/dev/null \
  | grep -F "\"$SIGNING_IDENTITY\"" >/dev/null; then
  echo "blocked: Developer ID signing identity is not available in the Keychain" >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "blocked: notarization Keychain profile is missing or invalid" >&2
  exit 1
fi

echo "PREFLIGHT_OK"
((PREFLIGHT_ONLY)) && exit 0

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$ROOT_DIR/Resources/Info.plist")"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/Lazyest Cleaner.app"
ZIP_NAME="Lazyest-Cleaner-$VERSION-universal.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
DMG_NAME="Lazyest-Cleaner-$VERSION-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

CODESIGN_IDENTITY="$SIGNING_IDENTITY" "$SCRIPT_DIR/build_and_run.sh" --package

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ACTUAL_TEAM_ID="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 \
  | sed -n 's/^TeamIdentifier=//p')"
if [ "$ACTUAL_TEAM_ID" != "$TEAM_ID" ]; then
  echo "blocked: signed app TeamIdentifier does not match CLEANER_TEAM_ID" >&2
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
if ! xcrun stapler validate "$APP_PATH"; then
  echo "warning: stapled ticket validation was unavailable; continuing to Gatekeeper assessment" >&2
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

# Replace the notarization upload with a ZIP containing the stapled app.
/bin/rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create \
  -volname "Lazyest Cleaner" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

(cd "$DIST_DIR" && shasum -a 256 "$ZIP_NAME" >"$ZIP_NAME.sha256")
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" >"$DMG_NAME.sha256")

echo "RELEASE_ARTIFACT_READY: $ZIP_PATH"
echo "RELEASE_ARTIFACT_READY: $DMG_PATH"
