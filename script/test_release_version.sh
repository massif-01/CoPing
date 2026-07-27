#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO="$(/usr/bin/mktemp -d /tmp/coping-version-test.XXXXXX)"

cleanup() {
  /bin/rm -rf "$TEST_REPO"
}
trap cleanup EXIT

git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" config user.name "CoPing Tests"
git -C "$TEST_REPO" config user.email "tests@coping.invalid"
git -C "$TEST_REPO" commit --allow-empty -qm "test"
git -C "$TEST_REPO" tag v1.2.3

VERSION="$(bash "$ROOT_DIR/script/release_version.sh" "$TEST_REPO")"
if [[ "$VERSION" != "1.2.3" ]]; then
  echo "Expected v1.2.3 to produce 1.2.3, got '$VERSION'." >&2
  exit 1
fi

if COPING_RELEASE_TAG=invalid \
  bash "$ROOT_DIR/script/release_version.sh" "$TEST_REPO" >/dev/null 2>&1
then
  echo "Invalid release tag was accepted." >&2
  exit 1
fi

echo "ReleaseVersionTests: PASS"
