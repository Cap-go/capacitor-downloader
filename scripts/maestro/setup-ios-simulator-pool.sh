#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARD_COUNT="${CAPGO_MAESTRO_SHARD_COUNT:-4}"

if ! [[ "$SHARD_COUNT" =~ ^[0-9]+$ ]] || (( SHARD_COUNT < 1 || SHARD_COUNT > 6 )); then
  echo "CAPGO_MAESTRO_SHARD_COUNT must be 1..6" >&2
  exit 1
fi

simulator_id_for_name() {
  local target_name="$1"
  local line=""
  local name=""
  local simulator_id=""
  local device_line_regex='^[[:space:]]*(.*)[[:space:]]\(([0-9A-F-]{36})\)[[:space:]]\([^)]*\)[[:space:]]*$'
  while IFS= read -r line; do
    if [[ "$line" =~ $device_line_regex ]]; then
      name="${BASH_REMATCH[1]}"
      simulator_id="${BASH_REMATCH[2]}"
      if [[ "$name" == "$target_name" ]]; then
        printf '%s\n' "$simulator_id"
        return 0
      fi
    fi
  done < <(xcrun simctl list devices available)
  return 1
}

BASE_ID="$("$ROOT_DIR/scripts/maestro/select-ios-simulator.sh")"
xcrun simctl shutdown "$BASE_ID" >/dev/null 2>&1 || true

POOL_FILE="$(mktemp)"
printf '%s\n' "$BASE_ID" >"$POOL_FILE"

for index in $(seq 1 $((SHARD_COUNT - 1))); do
  clone_name="Capgo Maestro Shard ${index}"
  if existing="$(simulator_id_for_name "$clone_name")"; then
    xcrun simctl delete "$existing" >/dev/null 2>&1 || true
  fi
  xcrun simctl shutdown "$BASE_ID" >/dev/null 2>&1 || true
  clone_id="$(xcrun simctl clone "$BASE_ID" "$clone_name")"
  printf '%s\n' "$clone_id" >>"$POOL_FILE"
done

boot_pids=()
boot_fail=0
while IFS= read -r simulator_id; do
  (
    xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$simulator_id" -b
  ) &
  boot_pids+=("$!")
done <"$POOL_FILE"
for pid in "${boot_pids[@]}"; do
  if ! wait "$pid"; then
    boot_fail=1
  fi
done
if (( boot_fail != 0 )); then
  echo "One or more iOS simulators failed to boot." >&2
  exit 1
fi
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"
while IFS= read -r simulator_id; do
  disable_ios_simulator_animations "$simulator_id"
done <"$POOL_FILE"

POOL_CSV="$(paste -sd, "$POOL_FILE")"
rm -f "$POOL_FILE"
printf '%s\n' "$POOL_CSV"