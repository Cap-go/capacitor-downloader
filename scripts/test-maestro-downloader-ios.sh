#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/start-fake-server.sh
source "$ROOT_DIR/scripts/maestro/start-fake-server.sh"

FLOW_ID="${CAPGO_MAESTRO_FLOW:-foreground-complete}"
FLOW_PATH="$ROOT_DIR/.maestro/flows/${FLOW_ID}.yaml"
RESULTS_DIR="${CAPGO_MAESTRO_RESULTS_DIR:-$ROOT_DIR/maestro-results-ios}"
HOST_SERVER_PORT="${CAPGO_MAESTRO_PORT:-3192}"
HOST_SERVER_URL="${CAPGO_MAESTRO_HOST_BASE_URL:-http://127.0.0.1:${HOST_SERVER_PORT}}"
DEVICE_SERVER_URL="${CAPGO_MAESTRO_DEVICE_BASE_URL:-$HOST_SERVER_URL}"
MAESTRO_TIMEOUT_SECONDS="${CAPGO_MAESTRO_TIMEOUT_SECONDS:-360}"
APP_ID="app.capgo.downloader"
SIMULATOR_ID="${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-$("$ROOT_DIR/scripts/maestro/select-ios-simulator.sh")}"
APP_PATH="${CAPGO_MAESTRO_IOS_APP_PATH:-$ROOT_DIR/maestro-ios-app/App.app}"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

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

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro is required." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing iOS app at $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$FLOW_PATH" ]]; then
  echo "Missing flow at $FLOW_PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"
export CAPGO_MAESTRO_DEVICE_BASE_URL="$DEVICE_SERVER_URL"

mkdir -p "$ROOT_DIR/.maestro-artifacts"
start_fake_download_server "$ROOT_DIR/.maestro-artifacts/fake-download-server-ios.log"
wait_for_server

xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl uninstall "$SIMULATOR_ID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

maestro test \
  --config "$ROOT_DIR/.maestro/config.yaml" \
  "$FLOW_PATH" \
  --platform ios \
  --udid "$SIMULATOR_ID" \
  --format junit \
  --output "$RESULTS_DIR/junit.xml"