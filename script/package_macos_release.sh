#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNING_IDENTITY="${CLEANER_CODESIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${CLEANER_INSTALLER_IDENTITY:-}"
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

staple_with_retry() {
  local target="$1"
  local attempt
  for attempt in 1 2 3; do
    if xcrun stapler staple "$target"; then
      return
    fi
    if ((attempt < 3)); then
      echo "warning: stapler attempt $attempt failed; retrying" >&2
      sleep 2
    fi
  done
  return 1
}

require_value CLEANER_CODESIGN_IDENTITY "$SIGNING_IDENTITY"
require_value CLEANER_INSTALLER_IDENTITY "$INSTALLER_IDENTITY"
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
if [[ "$INSTALLER_IDENTITY" != Developer\ ID\ Installer:* ]]; then
  echo "blocked: CLEANER_INSTALLER_IDENTITY must be a Developer ID Installer identity" >&2
  exit 1
fi
if ! security find-identity -v -p basic 2>/dev/null \
  | grep -F "\"$INSTALLER_IDENTITY\"" >/dev/null; then
  echo "blocked: Developer ID Installer identity is not available in the Keychain" >&2
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
PKG_NAME="Lazyest-Cleaner-$VERSION-universal.pkg"
PKG_PATH="$DIST_DIR/$PKG_NAME"

CODESIGN_IDENTITY="$SIGNING_IDENTITY" "$SCRIPT_DIR/build_and_run.sh" --package

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ACTUAL_TEAM_ID="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 \
  | sed -n 's/^TeamIdentifier=//p')"
if [ "$ACTUAL_TEAM_ID" != "$TEAM_ID" ]; then
  echo "blocked: signed app TeamIdentifier does not match CLEANER_TEAM_ID" >&2
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
staple_with_retry "$APP_PATH"
if ! xcrun stapler validate "$APP_PATH"; then
  echo "warning: stapled ticket validation was unavailable; continuing to Gatekeeper assessment" >&2
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

# The ZIP exists only to obtain and staple the app notarization ticket.
/bin/rm -f "$ZIP_PATH"

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Contents/Info.plist")"
pkgbuild \
  --component "$APP_PATH" \
  --install-location "/Applications" \
  --identifier "$BUNDLE_ID.pkg" \
  --version "$VERSION" \
  --sign "$INSTALLER_IDENTITY" \
  "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH"
xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
staple_with_retry "$PKG_PATH"
if ! xcrun stapler validate "$PKG_PATH"; then
  echo "warning: PKG stapled ticket validation was unavailable; continuing to Installer Gatekeeper assessment" >&2
fi
spctl --assess --type install --verbose=4 "$PKG_PATH"

(cd "$DIST_DIR" && shasum -a 256 "$PKG_NAME" >"$PKG_NAME.sha256")

echo "RELEASE_ARTIFACT_READY: $PKG_PATH"
