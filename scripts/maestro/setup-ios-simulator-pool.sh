#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARD_COUNT="${CAPGO_MAESTRO_SHARD_COUNT:-4}"

if ! [[ "$SHARD_COUNT" =~ ^[0-9]+$ ]] || (( SHARD_COUNT < 1 || SHARD_COUNT > 6 )); then
  echo "CAPGO_MAESTRO_SHARD_COUNT must be 1..6" >&2
  exit 1
fi

BASE_ID="$("$ROOT_DIR/scripts/maestro/select-ios-simulator.sh")"
xcrun simctl boot "$BASE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$BASE_ID" -b

POOL_FILE="$(mktemp)"
printf '%s\n' "$BASE_ID" >"$POOL_FILE"

for index in $(seq 1 $((SHARD_COUNT - 1))); do
  clone_name="Capgo Maestro Shard ${index}"
  existing="$(xcrun simctl list devices available | sed -n "s/^   ${clone_name} (\\([0-9A-F-]\\{36\\}\\)\\).*/\\1/p" | head -n 1 || true)"
  if [[ -n "$existing" ]]; then
    xcrun simctl delete "$existing" >/dev/null 2>&1 || true
  fi
  clone_id="$(xcrun simctl clone "$BASE_ID" "$clone_name")"
  printf '%s\n' "$clone_id" >>"$POOL_FILE"
done

while IFS= read -r simulator_id; do
  xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator_id" -b
  # shellcheck source=scripts/maestro/disable-device-animations.sh
  source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"
  disable_ios_simulator_animations "$simulator_id"
done <"$POOL_FILE"

POOL_CSV="$(paste -sd, "$POOL_FILE")"
rm -f "$POOL_FILE"
printf '%s\n' "$POOL_CSV"