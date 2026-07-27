#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RELEASE_TAG="${COPING_RELEASE_TAG:-}"

if [[ -z "$RELEASE_TAG" ]]; then
  if ! RELEASE_TAG="$(git -C "$ROOT_DIR" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null)"; then
    echo "Release packaging requires an exact vMAJOR.MINOR.PATCH Git tag." >&2
    exit 2
  fi
fi

if [[ ! "$RELEASE_TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Invalid release tag '$RELEASE_TAG'; expected vMAJOR.MINOR.PATCH." >&2
  exit 2
fi

printf '%s.%s.%s\n' \
  "${BASH_REMATCH[1]}" \
  "${BASH_REMATCH[2]}" \
  "${BASH_REMATCH[3]}"
