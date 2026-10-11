#!/bin/bash
# Exercise the production argument construction on macOS system Bash (3.2).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="${1:-$ROOT_DIR/script/build_and_run.sh}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# Load only the build argument setup and function, without packaging or launching.
sed -n '/^resolve_swift_interface_args()/,/^build_native()/p' "$BUILD_SCRIPT" \
  | sed '$d' > "$TEST_DIR/build-functions.sh"

for requested_version in '' 6.1.2 6.1.3; do
  (
    export CLEANER_SWIFT_INTERFACE_COMPILER_VERSION="$requested_version"
    function /usr/bin/xcrun() {
      case "$*" in
        'swift --version') printf 'Apple Swift version 6.1.2\n' ;;
        '--sdk macosx --show-sdk-path') printf '%s\n' "$TEST_DIR" ;;
        *) printf '%s\0' "$@" > "$TEST_DIR/actual" ;;
      esac
    }
    source "$TEST_DIR/build-functions.sh"
    swift_build -c release --scratch-path "$TEST_DIR/path with spaces"
  )
  expected=(swift build --disable-sandbox)
  if [[ "$requested_version" == 6.1.3 ]]; then
    expected+=(-Xswiftc -interface-compiler-version -Xswiftc "$requested_version")
  fi
  expected+=(-Xswiftc -gnone -Xswiftc -file-prefix-map -Xswiftc "$ROOT_DIR=."
    -c release --scratch-path "$TEST_DIR/path with spaces")
  printf '%s\0' "${expected[@]}" > "$TEST_DIR/expected"
  cmp "$TEST_DIR/expected" "$TEST_DIR/actual"
done

# Preserve compiler incompatibility rejection and strict build failure handling.
if (
  export CLEANER_SWIFT_INTERFACE_COMPILER_VERSION=6.2.0
  function /usr/bin/xcrun() { printf 'Apple Swift version 6.1.2\n'; }
  source "$TEST_DIR/build-functions.sh"
); then
  printf 'Expected incompatible compiler versions to fail\n' >&2
  exit 1
fi

if /bin/bash -euo pipefail -c '
  ROOT_DIR="$1"
  function /usr/bin/xcrun() {
    case "$*" in
      "swift --version") printf "Apple Swift version 6.1.2\n" ;;
      "--sdk macosx --show-sdk-path") printf "%s\n" "$2" ;;
      *) return 42 ;;
    esac
  }
  export CLEANER_SWIFT_INTERFACE_COMPILER_VERSION=6.1.2
  source "$2/build-functions.sh"
  swift_build -c release
  touch "$2/unexpected-success"
' _ "$ROOT_DIR" "$TEST_DIR"; then
  printf 'Expected a failed Swift build to stop the shell\n' >&2
  exit 1
fi
[[ ! -e "$TEST_DIR/unexpected-success" ]]

printf 'Build argument regression checks passed (%s)\n' "$BASH_VERSION"
