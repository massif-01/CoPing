#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
OBJECTS=()
for MODULE in CoPingCore CoPingIPC CoPingAppSupport; do
  if [[ -f "$BIN_DIR/$MODULE.o" ]]; then
    OBJECTS+=("$BIN_DIR/$MODULE.o")
  else
    OBJECTS+=("$BIN_DIR/$MODULE.build/"*.o)
  fi
done
# Compile the actual AppModel and its platform adapters, without the SwiftUI app entry point.
xcrun swiftc -parse-as-library -warnings-as-errors -sdk "$SDKROOT" -I "$BIN_DIR" \
  Sources/CoPing/Stores/AppModel.swift Sources/CoPing/Services/CodexDetector.swift \
  Sources/CoPing/Services/HookTrustLauncher.swift Sources/CoPing/Services/LoginItemManager.swift \
  Tests/CoPingLifecycleRegressions/main.swift \
  "${OBJECTS[@]}" \
  -lsqlite3 -o "$BIN_DIR/CoPingLifecycleRegressions"
"$BIN_DIR/CoPingLifecycleRegressions"
