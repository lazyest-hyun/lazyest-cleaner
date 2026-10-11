#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LazyestCleaner"
DISPLAY_NAME="Lazyest Cleaner"
BUNDLE_ID="com.lazyest.cleaner"
case "$MODE" in
  install|--install|run|build|--build|--demo|demo|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--package|package) ;;
  *) printf 'usage: %s [install|run|build|--demo|--debug|--logs|--telemetry|--verify|--package]\n' "$0" >&2; exit 2 ;;
esac

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
  for pattern in "Developer ID Application:" "Apple Development:" "Lazyest Cleaner Local Development"; do
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

resolve_swift_interface_args() {
  local requested_version="${CLEANER_SWIFT_INTERFACE_COMPILER_VERSION:-}"
  local compiler_version
  compiler_version="$(/usr/bin/xcrun swift --version | /usr/bin/sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | /usr/bin/head -n 1)"

  if [[ -z "$requested_version" ]]; then
    local sdk_path
    sdk_path="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
    local sdk_interface="$sdk_path/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
    if [[ -f "$sdk_interface" ]]; then
      requested_version="$(/usr/bin/sed -n 's@// swift-compiler-version: Apple Swift version \([0-9.]*\).*@\1@p' "$sdk_interface" | /usr/bin/head -n 1)"
    fi
  fi

  if [[ -z "$compiler_version" || -z "$requested_version" || "$compiler_version" == "$requested_version" ]]; then
    return
  fi

  if [[ "${compiler_version%.*}" != "${requested_version%.*}" ]]; then
    printf 'error: Swift compiler %s and macOS SDK interface %s are incompatible; update Command Line Tools or Xcode\n' \
      "$compiler_version" "$requested_version" >&2
    exit 1
  fi

  SWIFT_BUILD_ARGS+=(-Xswiftc -interface-compiler-version -Xswiftc "$requested_version")
  printf 'Using macOS SDK Swift interface compatibility %s for compiler %s\n' \
    "$requested_version" "$compiler_version" >&2
}

# Bash 3.2 treats an empty array as unset under nounset. Keep the required
# build argument in the array, then append optional interface compatibility flags.
SWIFT_BUILD_ARGS=(--disable-sandbox)
resolve_swift_interface_args

swift_build() {
  /usr/bin/xcrun swift build "${SWIFT_BUILD_ARGS[@]}" -Xswiftc -gnone -Xswiftc -file-prefix-map -Xswiftc "$ROOT_DIR=." "$@"
}

build_native() {
  local configuration=release
  case "$MODE" in run|--demo|demo|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) configuration=debug ;; esac
  swift_build -c "$configuration"
  swift_build -c "$configuration" --show-bin-path
}

build_universal() {
  local arm_scratch="$ROOT_DIR/.build/universal-arm64"
  local x86_scratch="$ROOT_DIR/.build/universal-x86_64"
  local output="$ROOT_DIR/.build/LazyestCleaner-universal"

  swift_build \
    -c release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$arm_scratch"
  swift_build \
    -c release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$x86_scratch"

  local arm_binary
  local x86_binary
  arm_binary="$(swift_build -c release --triple arm64-apple-macosx14.0 --scratch-path "$arm_scratch" --show-bin-path)/$APP_NAME"
  x86_binary="$(swift_build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$x86_scratch" --show-bin-path)/$APP_NAME"
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
  case "$MODE" in --debug|debug) ;; *) "$ROOT_DIR/scripts/prepare-release-binary.sh" "$APP_BINARY" ;; esac
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
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open "$APP_BUNDLE" "$@"
}

install_app() {
  local staging_root
  staging_root="$(/usr/bin/mktemp -d "/Applications/.lazyest-cleaner-install.XXXXXX")"
  local staged_app="$staging_root/$DISPLAY_NAME.app"
  local previous_app="$staging_root/previous.app"
  if ! /usr/bin/ditto "$APP_BUNDLE" "$staged_app" || ! /usr/bin/codesign --verify --deep --strict "$staged_app"; then
    /bin/rm -rf "$staging_root"
    return 1
  fi
  /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ -d "$INSTALLED_APP" ]]; then /bin/mv "$INSTALLED_APP" "$previous_app"; fi
  if ! /bin/mv "$staged_app" "$INSTALLED_APP"; then
    if [[ -d "$previous_app" ]]; then /bin/mv "$previous_app" "$INSTALLED_APP"; fi
    /bin/rm -rf "$staging_root"
    return 1
  fi
  /bin/rm -rf "$staging_root"
  "$ROOT_DIR/script/migrate_legacy_install.sh"
  /usr/bin/open "$INSTALLED_APP"
}

/bin/mkdir -p "$DIST_DIR"
cd "$ROOT_DIR"
printf 'Signing identity: %s\n' "$SIGNING_IDENTITY"

if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  BUILD_BINARY="$(build_universal | /usr/bin/tail -n 1)"
else
  BUILD_BINARY="$(build_native | /usr/bin/tail -n 1)/$APP_NAME"
fi

stage_bundle "$BUILD_BINARY"
sign_bundle

case "$MODE" in
  build|--build)
    printf '%s\n' "$APP_BUNDLE"
    ;;
  install|--install)
    install_app
    ;;
  run)
    open_app
    ;;
  --demo|demo)
    open_app --args --demo
    ;;
  --debug|debug)
    /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
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
