#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/CoPing.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_RESOURCES="$APP_CONTENTS/Resources"
ARCHIVE="$ROOT_DIR/dist/CoPing.zip"
SIGN_IDENTITY="${COPING_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${COPING_NOTARY_PROFILE:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "COPING_SIGN_IDENTITY is required (Developer ID Application identity)." >&2
  exit 2
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "COPING_NOTARY_PROFILE is required (notarytool keychain profile)." >&2
  exit 2
fi

if ! xcrun --find notarytool >/dev/null 2>&1; then
  echo "notarytool is unavailable; install and select a complete Xcode." >&2
  exit 2
fi

export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-cache"

swift build -c release --disable-sandbox --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c release --disable-sandbox --package-path "$ROOT_DIR" --show-bin-path)"

rm -rf "$APP_BUNDLE" "$ARCHIVE"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Helpers" "$APP_RESOURCES"
cp "$BIN_DIR/CoPing" "$APP_CONTENTS/MacOS/CoPing"
cp "$BIN_DIR/CoPingHook" "$APP_CONTENTS/Helpers/CoPingHook"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIR/Packaging/CoPing.icns" "$APP_RESOURCES/CoPing.icns"
cp "$ROOT_DIR/CoPing.icon/Assets/CoPing-orbit-mark.svg" "$APP_RESOURCES/CoPing-orbit-mark.svg"
chmod +x "$APP_CONTENTS/MacOS/CoPing" "$APP_CONTENTS/Helpers/CoPingHook"

/usr/bin/codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" \
  "$APP_CONTENTS/Helpers/CoPingHook"
/usr/bin/codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -vv --type execute "$APP_BUNDLE"

echo "$APP_BUNDLE"
