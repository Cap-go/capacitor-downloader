#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGRESSION="${1:?regression name}"
FLOW="${2:?flow id}"
PLATFORM="${3:-android}"
MODE="${4:?broken or fixed}"

cd "$REPO_ROOT"

if [[ "${CAPGO_MAESTRO_BREAK_FIX_MAESTRO_ONLY:-}" != "1" ]]; then
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
fi

if [[ "$PLATFORM" == "android" ]]; then
  export CAPGO_MAESTRO_DEVICE_BASE_URL="${CAPGO_MAESTRO_DEVICE_BASE_URL:-http://127.0.0.1:3192}"
  export CAPGO_MAESTRO_SKIP_GRADLE_CLEAN=1
  export CAPGO_MAESTRO_TEST_RETRIES=1
  bun scripts/maestro/prepare-maestro-app.mjs android
  export CAPGO_MAESTRO_SKIP_BUILD=1
  export CAPGO_MAESTRO_FLOW="$FLOW"
  export CAPGO_MAESTRO_TIMEOUT_SECONDS=300
  bash "$REPO_ROOT/scripts/test-maestro-downloader-android.sh"
elif [[ "$PLATFORM" == "ios" ]]; then
  export CAPGO_MAESTRO_DEVICE_BASE_URL="${CAPGO_MAESTRO_DEVICE_BASE_URL:-http://127.0.0.1:3192}"
  export CAPGO_MAESTRO_TEST_RETRIES=1
  if [[ "${CAPGO_MAESTRO_BREAK_FIX_MAESTRO_ONLY:-}" != "1" ]]; then
    export CAPGO_MAESTRO_IOS_DERIVED_DATA="${CAPGO_MAESTRO_IOS_DERIVED_DATA:-$REPO_ROOT/.maestro-ios-derived-data}"
    export CAPGO_MAESTRO_SKIP_XCODE_CLEAN=1
    bun scripts/maestro/prepare-maestro-app.mjs ios
    mkdir -p maestro-ios-app
    APP_PATH="$CAPGO_MAESTRO_IOS_DERIVED_DATA/Build/Products/Debug-iphonesimulator/App.app"
    ditto "$APP_PATH" maestro-ios-app/App.app
    export CAPGO_MAESTRO_IOS_APP_PATH=maestro-ios-app/App.app
  elif [[ -z "${CAPGO_MAESTRO_IOS_APP_PATH:-}" ]]; then
    echo "CAPGO_MAESTRO_IOS_APP_PATH is required when CAPGO_MAESTRO_BREAK_FIX_MAESTRO_ONLY=1" >&2
    exit 2
  fi
  export CAPGO_MAESTRO_FLOW="$FLOW"
  export CAPGO_MAESTRO_TIMEOUT_SECONDS=300
  bash "$REPO_ROOT/scripts/test-maestro-downloader-ios.sh"
else
  echo "Unsupported platform $PLATFORM" >&2
  exit 2
fi