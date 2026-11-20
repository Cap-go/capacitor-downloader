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
  if [[ "${CAPGO_MAESTRO_IOS_SKIP_BOOT:-}" != 1 ]]; then
    xcrun simctl launch "$DEVICE_ID" "$APP_ID" >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl terminate "$DEVICE_ID" "$APP_ID" >/dev/null 2>&1 || true
    sleep 1
  fi
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
  apk_install_attempt=1
  while (( apk_install_attempt <= 3 )); do
    if adb -s "$DEVICE_ID" install -r "$APK_PATH" >/dev/null 2>&1; then
      break
    fi
    if (( apk_install_attempt == 3 )); then
      adb -s "$DEVICE_ID" install -r "$APK_PATH" >&2
      exit 1
    fi
    adb -s "$DEVICE_ID" wait-for-device
    sleep 2
    apk_install_attempt=$((apk_install_attempt + 1))
  done
fi

rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

ios_driver_recovery() {
  xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$DEVICE_ID" -b
  xcrun simctl spawn "$DEVICE_ID" launchctl setenv CAPGO_MAESTRO_PORT "$HOST_PORT" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$DEVICE_ID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$DEVICE_ID" "$APP_PATH"
  xcrun simctl launch "$DEVICE_ID" "$APP_ID" >/dev/null 2>&1 || true
  sleep 3
  xcrun simctl terminate "$DEVICE_ID" "$APP_ID" >/dev/null 2>&1 || true
}

ios_driver_timeout_in_results() {
  find "$RESULTS_DIR/debug" -type f -print0 2>/dev/null | xargs -0 grep -q 'IOSDriverTimeoutException' 2>/dev/null
}

attempt=1
driver_recovery_used=0
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
  if [[ "$PLATFORM" == "ios" ]] && ios_driver_timeout_in_results; then
  if (( driver_recovery_used == 0 )); then
    echo "iOS driver startup timed out; rebooting simulator once before retry." >&2
    ios_driver_recovery
    driver_recovery_used=1
    sleep "$LIGHT_RETRY_SLEEP_SECONDS"
    continue
  fi
  fi
  attempt=$((attempt + 1))
  if [[ "$PLATFORM" == "ios" ]] && ios_driver_timeout_in_results; then
    ios_driver_recovery
  fi
  sleep "$LIGHT_RETRY_SLEEP_SECONDS"
done

exit 1