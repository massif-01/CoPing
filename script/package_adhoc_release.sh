#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/CoPing.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_RESOURCES="$APP_CONTENTS/Resources"
ARCHIVE_NAME="CoPing-macOS-arm64.zip"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM="$ARCHIVE.sha256"
DMG_NAME="CoPing-macOS-arm64.dmg"
DMG="$DIST_DIR/$DMG_NAME"
DMG_CHECKSUM="$DMG.sha256"
VERIFY_DIR=""
DMG_SOURCE_DIR=""
DMG_MOUNT_DIR=""
DMG_ATTACHED=false
RELEASE_VERSION="$(bash "$ROOT_DIR/script/release_version.sh" "$ROOT_DIR")"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD)"

cleanup() {
  if [[ "$DMG_ATTACHED" == true ]]; then
    /usr/bin/hdiutil detach "$DMG_MOUNT_DIR" -quiet || true
  fi
  if [[ -n "$VERIFY_DIR" && -d "$VERIFY_DIR" ]]; then
    /bin/rm -rf "$VERIFY_DIR"
  fi
  if [[ -n "$DMG_SOURCE_DIR" && -d "$DMG_SOURCE_DIR" ]]; then
    /bin/rm -rf "$DMG_SOURCE_DIR"
  fi
  if [[ -n "$DMG_MOUNT_DIR" && -d "$DMG_MOUNT_DIR" ]]; then
    /bin/rmdir "$DMG_MOUNT_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-cache"

swift build -c release --disable-sandbox --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c release --disable-sandbox --package-path "$ROOT_DIR" --show-bin-path)"

/bin/rm -rf "$APP_BUNDLE"
/bin/rm -f "$ARCHIVE" "$CHECKSUM" "$DMG" "$DMG_CHECKSUM"
/bin/mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Helpers" "$APP_RESOURCES"
/bin/cp "$BIN_DIR/CoPing" "$APP_CONTENTS/MacOS/CoPing"
/bin/cp "$BIN_DIR/CoPingHook" "$APP_CONTENTS/Helpers/CoPingHook"
/bin/cp "$ROOT_DIR/Packaging/Info.plist" "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleShortVersionString $RELEASE_VERSION" \
  "$APP_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP_CONTENTS/Info.plist"
/bin/cp "$ROOT_DIR/Packaging/CoPing.icns" "$APP_RESOURCES/CoPing.icns"
/bin/cp "$ROOT_DIR/CoPing.icon/Assets/CoPing-orbit-mark.svg" "$APP_RESOURCES/CoPing-orbit-mark.svg"
/bin/cp "$ROOT_DIR/Sources/CoPing/Resources/GitHubMark.svg" "$APP_RESOURCES/GitHubMark.svg"
/bin/chmod +x "$APP_CONTENTS/MacOS/CoPing" "$APP_CONTENTS/Helpers/CoPingHook"

# Ad-hoc signing preserves bundle integrity but does not identify the developer
# to Gatekeeper. Users must explicitly approve the app on first launch.
/usr/bin/codesign --force --sign - --options runtime "$APP_CONTENTS/Helpers/CoPingHook"
/usr/bin/codesign --force --sign - --options runtime "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"

VERIFY_DIR="$(/usr/bin/mktemp -d /tmp/coping-package.XXXXXX)"
/usr/bin/ditto -x -k "$ARCHIVE" "$VERIFY_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$VERIFY_DIR/CoPing.app"

DMG_SOURCE_DIR="$(/usr/bin/mktemp -d /tmp/coping-dmg-source.XXXXXX)"
/usr/bin/ditto "$APP_BUNDLE" "$DMG_SOURCE_DIR/CoPing.app"
/bin/ln -s /Applications "$DMG_SOURCE_DIR/Applications"
/usr/bin/hdiutil create \
  -volname "CoPing" \
  -srcfolder "$DMG_SOURCE_DIR" \
  -format UDZO \
  -ov \
  "$DMG"
/usr/bin/hdiutil verify "$DMG"

DMG_MOUNT_DIR="$(/usr/bin/mktemp -d /tmp/coping-dmg-mount.XXXXXX)"
/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$DMG_MOUNT_DIR" \
  "$DMG" >/dev/null
DMG_ATTACHED=true
/usr/bin/codesign --verify --deep --strict --verbose=2 "$DMG_MOUNT_DIR/CoPing.app"
/usr/bin/hdiutil detach "$DMG_MOUNT_DIR" -quiet
DMG_ATTACHED=false

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
  /usr/bin/shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "$ARCHIVE"
echo "$CHECKSUM"
echo "$DMG"
echo "$DMG_CHECKSUM"
echo "Version: $RELEASE_VERSION ($BUILD_NUMBER)"
