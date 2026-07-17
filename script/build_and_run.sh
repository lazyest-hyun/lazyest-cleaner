#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LazyestCleaner"
DISPLAY_NAME="Lazyest Cleaner"
BUNDLE_ID="com.tidymac.cleaner"
LEGACY_APP_NAME="TidyMac"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INSTALLED_APP="/Applications/$DISPLAY_NAME.app"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INFO_PLIST_SOURCE="$ROOT_DIR/Resources/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_SOURCE")"
PACKAGE_ZIP="$DIST_DIR/Lazyest-Cleaner-$VERSION-universal.zip"

resolve_signing_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return
  fi

  local identities
  identities="$(/usr/bin/security find-identity -p codesigning -v 2>/dev/null || true)"

  local pattern
  for pattern in "Developer ID Application:" "Apple Development:" "Lazyest Cleaner Local Development" "Lazyest Tidy Local Development" "TidyMac Local Development"; do
    local identity
    identity="$(printf '%s\n' "$identities" | /usr/bin/awk -F '"' -v pattern="$pattern" '
      index($2, pattern) { print $2; exit }
    ')"
    if [[ -n "$identity" ]]; then
      printf '%s\n' "$identity"
      return
    fi
  done

  printf '%s\n' "-"
}

SIGNING_IDENTITY="$(resolve_signing_identity)"

build_debug() {
  /usr/bin/xcrun swift build --disable-sandbox
  /usr/bin/xcrun swift build --disable-sandbox --show-bin-path
}

build_universal() {
  local arm_scratch="$ROOT_DIR/.build/universal-arm64"
  local x86_scratch="$ROOT_DIR/.build/universal-x86_64"
  local output="$ROOT_DIR/.build/LazyestCleaner-universal"

  /usr/bin/xcrun swift build \
    -c release \
    --triple arm64-apple-macosx14.0 \
    --disable-sandbox \
    --scratch-path "$arm_scratch"
  /usr/bin/xcrun swift build \
    -c release \
    --triple x86_64-apple-macosx14.0 \
    --disable-sandbox \
    --scratch-path "$x86_scratch"

  local arm_binary
  local x86_binary
  arm_binary="$(/usr/bin/xcrun swift build -c release --triple arm64-apple-macosx14.0 --disable-sandbox --scratch-path "$arm_scratch" --show-bin-path)/$APP_NAME"
  x86_binary="$(/usr/bin/xcrun swift build -c release --triple x86_64-apple-macosx14.0 --disable-sandbox --scratch-path "$x86_scratch" --show-bin-path)/$APP_NAME"
  /bin/rm -f "$output"
  /usr/bin/lipo -create "$arm_binary" "$x86_binary" -output "$output"
  printf '%s\n' "$output"
}

stage_bundle() {
  local source_binary="$1"
  /bin/rm -rf "$APP_BUNDLE"
  /bin/mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  /bin/cp "$source_binary" "$APP_BINARY"
  /bin/cp "$INFO_PLIST_SOURCE" "$INFO_PLIST"
  if [[ -f "$APP_ICON_SOURCE" ]]; then
    /bin/cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
  fi
  /bin/chmod +x "$APP_BINARY"
}

sign_bundle() {
  local sign_args=(--force --sign "$SIGNING_IDENTITY")
  if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
    sign_args+=(--options runtime --timestamp)
  elif [[ "$SIGNING_IDENTITY" != "-" ]]; then
    sign_args+=(--options runtime)
  fi
  /usr/bin/codesign "${sign_args[@]}" "$APP_BINARY"
  /usr/bin/codesign "${sign_args[@]}" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

create_archive() {
  /bin/rm -f "$PACKAGE_ZIP"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$PACKAGE_ZIP"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" "$@"
}

install_app() {
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/pkill -x "LazyestTidy" >/dev/null 2>&1 || true
  /usr/bin/pkill -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true
  /bin/rm -rf "$INSTALLED_APP"
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP"
  for legacy_app in "/Applications/Lazyest Tidy.app" "/Applications/정돈.app" "/Applications/TidyMac.app"; do
    if [[ "$legacy_app" != "$INSTALLED_APP" && -d "$legacy_app" ]]; then
      /bin/rm -rf "$legacy_app"
    fi
  done
  /usr/bin/open "$INSTALLED_APP"
}

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
/usr/bin/pkill -x "LazyestTidy" >/dev/null 2>&1 || true
/usr/bin/pkill -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true
/bin/mkdir -p "$DIST_DIR"
cd "$ROOT_DIR"
printf 'Signing identity: %s\n' "$SIGNING_IDENTITY"

if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  BUILD_BINARY="$(build_universal | /usr/bin/tail -n 1)"
else
  BUILD_BINARY="$(build_debug | /usr/bin/tail -n 1)/$APP_NAME"
fi

stage_bundle "$BUILD_BINARY"
sign_bundle

case "$MODE" in
  install|--install)
    install_app
    ;;
  run)
    open_app
    ;;
  --demo|demo)
    open_app --args -LazyestCleanerDemo YES --demo
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    /bin/sleep 2
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package)
    create_archive
    /usr/bin/lipo -info "$APP_BINARY"
    printf '%s\n' "$PACKAGE_ZIP"
    ;;
  *)
    printf 'usage: %s [install|run|--demo|--debug|--logs|--telemetry|--verify|--package]\n' "$0" >&2
    exit 2
    ;;
esac
