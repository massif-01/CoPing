#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CoPing"
BUNDLE_ID="com.coping.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"

export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-cache"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --disable-sandbox --package-path "$ROOT_DIR"
BIN_DIR="$(swift build --disable-sandbox --package-path "$ROOT_DIR" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BIN_DIR/CoPing" "$APP_MACOS/CoPing"
cp "$BIN_DIR/CoPingHook" "$APP_HELPERS/CoPingHook"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIR/Packaging/CoPing.icns" "$APP_RESOURCES/CoPing.icns"
cp "$ROOT_DIR/CoPing.icon/Assets/CoPing-orbit-mark.svg" "$APP_RESOURCES/CoPing-orbit-mark.svg"
chmod +x "$APP_MACOS/CoPing" "$APP_HELPERS/CoPingHook"

/usr/bin/codesign --force --sign - --options runtime "$APP_HELPERS/CoPingHook"
/usr/bin/codesign --force --sign - --options runtime "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --build-only|build)
    ;;
  --debug|debug)
    lldb -- "$APP_MACOS/CoPing"
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
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
