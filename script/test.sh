#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-cache"

swift build --disable-sandbox --package-path "$ROOT_DIR" -Xswiftc -warnings-as-errors
swift run --disable-sandbox --package-path "$ROOT_DIR" CoPingSelfTests
