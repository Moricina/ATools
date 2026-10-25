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

HOST_ARCH="$(uname -m)"
TARGET_ARCH="${ATOOLS_ARCH:-$HOST_ARCH}"

# Keep the macOS 12 deployment floor explicit so newer-only APIs (e.g.
# NSBezierPath.cgPath) are caught at build time instead of crashing on launch.
EXTRA_ARGS=("--disable-sandbox" "-Xswiftc" "-target" "-Xswiftc" "${TARGET_ARCH}-apple-macos12.0")

echo "==> Compiling ATools ($SWIFT_CONFIG, $TARGET_ARCH)..."
swift build -c "$SWIFT_CONFIG" "${EXTRA_ARGS[@]}" -debug-info-format none

BIN=".build/$SWIFT_CONFIG/ATools"
if [[ ! -x "$BIN" ]]; then
    BIN=".build/${TARGET_ARCH}-apple-macosx/$SWIFT_CONFIG/ATools"
fi
if [[ ! -x "$BIN" ]]; then
    BIN=".build/out/Products/$(tr '[:lower:]' '[:upper:]' <<< "${SWIFT_CONFIG:0:1}")${SWIFT_CONFIG:1}/ATools"
fi

echo "==> Build complete: $BIN"

if [[ "${RUN_TEST:-0}" == "1" || "${RUN_TEST:-0}" == "--test" ]]; then
    echo "==> Running diagnostic suite..."
    "$BIN" --test
    TEST_STATUS=$?
    if [[ $TEST_STATUS -ne 0 ]]; then
        echo "错误: 诊断测试套件未通过 (退出码: $TEST_STATUS)" >&2
        exit "$TEST_STATUS"
    fi
fi
