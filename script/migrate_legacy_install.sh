#!/usr/bin/env bash
set -euo pipefail
# Compatibility only: remove recognized previous product bundles after successful installation.
for legacy_app in "/Applications/Lazyest Tidy.app" "/Applications/정돈.app" "/Applications/TidyMac.app"; do
  [[ -d "$legacy_app" ]] || continue
  identity="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$legacy_app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$identity" == "com.tidymac.cleaner" ]] || continue
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$legacy_app/Contents/Info.plist" 2>/dev/null || true)"
  case "$executable" in LazyestTidy|TidyMac) /usr/bin/pkill -x "$executable" >/dev/null 2>&1 || true ;; esac
  /bin/rm -rf "$legacy_app"
done
