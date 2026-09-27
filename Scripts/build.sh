#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

CONFIG="${1:-debug}"
if [[ "$CONFIG" == "--test" ]]; then
    CONFIG="debug"
    RUN_TEST=1
else
    RUN_TEST="${2:-0}"
fi

case "$CONFIG" in
    debug)   SWIFT_CONFIG="debug" ;;
    release) SWIFT_CONFIG="release" ;;
    *) echo "用法: $0 [debug|release] [--test]" >&2; exit 2 ;;
esac

# Keep the macOS 12 deployment floor explicit so newer-only APIs (e.g.
# NSBezierPath.cgPath) are caught at build time instead of crashing on launch.
EXTRA_ARGS=("--disable-sandbox" "-Xswiftc" "-target" "-Xswiftc" "arm64-apple-macos12.0")

echo "==> Compiling ATools ($SWIFT_CONFIG)..."
swift build -c "$SWIFT_CONFIG" "${EXTRA_ARGS[@]}" -debug-info-format none

BIN=".build/$SWIFT_CONFIG/ATools"
if [[ ! -x "$BIN" ]]; then
    BIN=".build/arm64-apple-macosx/$SWIFT_CONFIG/ATools"
fi

echo "==> Build complete: $BIN"

if [[ "${RUN_TEST:-0}" == "1" || "${RUN_TEST:-0}" == "--test" ]]; then
    echo "==> Running diagnostic suite..."
    "$BIN" --test
fi
