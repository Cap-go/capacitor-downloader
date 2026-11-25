#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGRESSION="${1:?regression name}"
MODE="${2:?broken or fixed}"

cd "$REPO_ROOT"

cleanup() {
  bun scripts/maestro/break-fix-regression.mjs revert >/dev/null 2>&1 || true
}

trap cleanup EXIT

case "$MODE" in
  broken)
    bun scripts/maestro/break-fix-regression.mjs apply "$REGRESSION"
    ;;
  fixed)
    bun scripts/maestro/break-fix-regression.mjs revert
    ;;
  *)
    echo "MODE must be broken or fixed" >&2
    exit 2
    ;;
esac

export CAPGO_MAESTRO_DEVICE_BASE_URL="${CAPGO_MAESTRO_DEVICE_BASE_URL:-http://127.0.0.1:3192}"
export CAPGO_MAESTRO_IOS_DERIVED_DATA="${CAPGO_MAESTRO_IOS_DERIVED_DATA:-$REPO_ROOT/.maestro-ios-derived-data}"
export CAPGO_MAESTRO_SKIP_XCODE_CLEAN=1

bun scripts/maestro/prepare-maestro-app.mjs ios

mkdir -p maestro-ios-app
APP_PATH="$CAPGO_MAESTRO_IOS_DERIVED_DATA/Build/Products/Debug-iphonesimulator/App.app"
ditto "$APP_PATH" maestro-ios-app/App.app
tar -czf break-fix-ios-app.tar.gz -C maestro-ios-app App.app