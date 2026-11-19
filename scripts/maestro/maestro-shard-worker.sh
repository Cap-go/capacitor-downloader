#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/maestro/start-fake-server.sh
source "$ROOT_DIR/scripts/maestro/start-fake-server.sh"

PLATFORM="${1:?platform}"
SHARD_INDEX="${2:?shard-index}"
SHARD_COUNT="${3:?shard-count}"
DEVICE_ID="${4:?device-id}"

APP_ID="app.capgo.downloader"
HOST_PORT=$((3192 + SHARD_INDEX))
APP_PORT=3192
HOST_SERVER_URL="http://127.0.0.1:${HOST_PORT}"
if command -v bun >/dev/null 2>&1; then
  FLOWS="$(bun "$ROOT_DIR/scripts/maestro/partition-flows.mjs" "$SHARD_INDEX" "$SHARD_COUNT")"
else
  FLOWS="$(node "$ROOT_DIR/scripts/maestro/partition-flows.mjs" "$SHARD_INDEX" "$SHARD_COUNT")"
fi
read -r -a FLOW_IDS <<<"$FLOWS"

RESULTS_DIR="${CAPGO_MAESTRO_RESULTS_DIR:-$ROOT_DIR/maestro-results-${PLATFORM}-shard-${SHARD_INDEX}}"
MAESTRO_TIMEOUT_SECONDS="${CAPGO_MAESTRO_TIMEOUT_SECONDS:-480}"
MAESTRO_TEST_RETRIES="${CAPGO_MAESTRO_TEST_RETRIES:-2}"
LIGHT_RETRY_SLEEP_SECONDS="${CAPGO_MAESTRO_LIGHT_RETRY_SLEEP_SECONDS:-2}"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

wait_for_server() {
  for _ in $(seq 1 30); do
    if curl --silent --fail "$HOST_SERVER_URL/health" >/dev/null; then
      curl --silent --show-error --fail -X POST "$HOST_SERVER_URL/control/reset" >/dev/null
      return 0
    fi
    sleep 1
  done
  echo "Fake download server did not start on port ${HOST_PORT}." >&2
  return 1
}

mkdir -p "$ROOT_DIR/.maestro-artifacts"
export CAPGO_MAESTRO_PORT="$HOST_PORT"
start_fake_download_server "$ROOT_DIR/.maestro-artifacts/fake-download-server-${PLATFORM}-${SHARD_INDEX}.log"
wait_for_server

if [[ "$PLATFORM" == "ios" ]]; then
  APP_PATH="${CAPGO_MAESTRO_IOS_APP_PATH:-$ROOT_DIR/maestro-ios-app/App.app}"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing iOS app at $APP_PATH" >&2
    exit 1
  fi
  xcrun simctl spawn "$DEVICE_ID" launchctl setenv CAPGO_MAESTRO_PORT "$HOST_PORT" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$DEVICE_ID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$DEVICE_ID" "$APP_PATH"
  export CAPGO_MAESTRO_IOS_SIMULATOR_ID="$DEVICE_ID"
else
  APK_PATH="$ROOT_DIR/example-app/android/app/build/outputs/apk/debug/app-debug.apk"
  if [[ ! -f "$APK_PATH" ]]; then
    echo "Missing APK at $APK_PATH" >&2
    exit 1
  fi
  export ANDROID_SERIAL="$DEVICE_ID"
  adb -s "$DEVICE_ID" reverse --remove "tcp:${APP_PORT}" >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" reverse "tcp:${APP_PORT}" "tcp:${HOST_PORT}" >/dev/null
  adb -s "$DEVICE_ID" uninstall "$APP_ID" >/dev/null 2>&1 || true
  adb -s "$DEVICE_ID" install -r "$APK_PATH" >/dev/null
fi

rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

attempt=1
while (( attempt <= MAESTRO_TEST_RETRIES )); do
  echo "Maestro ${PLATFORM} shard ${SHARD_INDEX}/${SHARD_COUNT} attempt ${attempt}/${MAESTRO_TEST_RETRIES} flows=${FLOWS}"
  if python3 "$ROOT_DIR/scripts/maestro/run-maestro.py" \
    "$MAESTRO_TIMEOUT_SECONDS" \
  "${FLOW_IDS[@]}" \
    "$DEVICE_ID" \
    "$PLATFORM" \
    "$RESULTS_DIR"; then
    exit 0
  fi
  if [[ "$PLATFORM" == "ios" ]] &&
    find "$RESULTS_DIR/debug" -type f -print0 2>/dev/null | xargs -0 grep -q 'IOSDriverTimeoutException' 2>/dev/null; then
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
    xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$DEVICE_ID" -b
    xcrun simctl spawn "$DEVICE_ID" launchctl setenv CAPGO_MAESTRO_PORT "$HOST_PORT" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$DEVICE_ID" "$APP_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$DEVICE_ID" "$APP_PATH"
  fi
  attempt=$((attempt + 1))
  sleep "$LIGHT_RETRY_SLEEP_SECONDS"
done

exit 1