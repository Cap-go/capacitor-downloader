#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"
# shellcheck source=scripts/maestro/start-fake-server.sh
source "$ROOT_DIR/scripts/maestro/start-fake-server.sh"

FLOW_ID="${CAPGO_MAESTRO_FLOW:-foreground-complete}"
APK_PATH="$ROOT_DIR/example-app/android/app/build/outputs/apk/debug/app-debug.apk"
RESULTS_DIR="$ROOT_DIR/maestro-results"
HOST_SERVER_PORT="${CAPGO_MAESTRO_PORT:-3192}"
HOST_SERVER_URL="${CAPGO_MAESTRO_HOST_BASE_URL:-http://127.0.0.1:${HOST_SERVER_PORT}}"
DEVICE_SERVER_URL="${CAPGO_MAESTRO_DEVICE_BASE_URL:-http://127.0.0.1:${HOST_SERVER_PORT}}"
MAESTRO_TIMEOUT_SECONDS="${CAPGO_MAESTRO_TIMEOUT_SECONDS:-150}"
MAESTRO_TEST_RETRIES="${CAPGO_MAESTRO_TEST_RETRIES:-1}"
APP_ID="app.capgo.downloader"
EMULATOR_BOOT_TIMEOUT_SECONDS="${CAPGO_MAESTRO_EMULATOR_BOOT_TIMEOUT_SECONDS:-180}"
SERVER_PID=""

cleanup() {
  restore_android_animation_settings
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

wait_for_emulator_boot() {
  timeout "${EMULATOR_BOOT_TIMEOUT_SECONDS}s" adb wait-for-device
  local deadline=$((SECONDS + EMULATOR_BOOT_TIMEOUT_SECONDS))
  while (( SECONDS < deadline )); do
    local booted
    booted="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [[ "$booted" == "1" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "Emulator boot timed out" >&2
  return 1
}

wait_for_server() {
  for _ in $(seq 1 40); do
    if curl --silent --fail "$HOST_SERVER_URL/health" >/dev/null; then
      curl --silent --show-error --fail -X POST "$HOST_SERVER_URL/control/reset" >/dev/null
      return 0
    fi
    sleep 1
  done
  echo "Fake download server did not start." >&2
  return 1
}

configure_server_routing() {
  adb reverse --remove "tcp:${HOST_SERVER_PORT}" >/dev/null 2>&1 || true
  adb reverse "tcp:${HOST_SERVER_PORT}" "tcp:${HOST_SERVER_PORT}" >/dev/null
}

if ! command -v adb >/dev/null 2>&1 || ! command -v maestro >/dev/null 2>&1; then
  echo "adb and maestro are required." >&2
  exit 1
fi

cd "$ROOT_DIR"
export CAPGO_MAESTRO_DEVICE_BASE_URL="$DEVICE_SERVER_URL"

mkdir -p "$ROOT_DIR/.maestro-artifacts"
start_fake_download_server "$ROOT_DIR/.maestro-artifacts/fake-download-server.log"
wait_for_server

wait_for_emulator_boot
disable_android_emulator_animations
configure_server_routing

if [[ ! -f "$APK_PATH" ]]; then
  echo "Missing APK at $APK_PATH" >&2
  exit 1
fi

adb uninstall "$APP_ID" >/dev/null 2>&1 || true
adb install -r "$APK_PATH" >/dev/null

DEVICE_ID="${CAPGO_MAESTRO_ANDROID_DEVICE_ID:-$(adb get-serialno | tr -d '\r')}"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

attempt=1
while (( attempt <= MAESTRO_TEST_RETRIES )); do
  echo "Maestro Android flow ${FLOW_ID} attempt ${attempt}/${MAESTRO_TEST_RETRIES}"
  if python3 "$ROOT_DIR/scripts/maestro/run-maestro.py" "$MAESTRO_TIMEOUT_SECONDS" "$FLOW_ID" "$DEVICE_ID"; then
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 5
done

exit 1