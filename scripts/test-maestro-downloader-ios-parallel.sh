#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

SHARD_COUNT="${CAPGO_MAESTRO_SHARD_COUNT:-4}"
export CAPGO_MAESTRO_SHARD_COUNT="$SHARD_COUNT"
SHARD_INDEX="${CAPGO_MAESTRO_SHARD_INDEX:-}"
POOL_MANIFEST="${CAPGO_MAESTRO_IOS_POOL_MANIFEST:-$ROOT_DIR/.maestro-artifacts/ios-simulator-pool.txt}"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro is required." >&2
  exit 1
fi

POOL_DEVICE_COUNT="$SHARD_COUNT"
if [[ -n "$SHARD_INDEX" ]]; then
  if ! [[ "$SHARD_INDEX" =~ ^[0-9]+$ ]] || (( SHARD_INDEX < 0 || SHARD_INDEX >= SHARD_COUNT )); then
    echo "CAPGO_MAESTRO_SHARD_INDEX must be in [0, ${SHARD_COUNT})." >&2
    exit 1
  fi
  POOL_DEVICE_COUNT=1
  POOL_MANIFEST="${POOL_MANIFEST%.txt}-shard-${SHARD_INDEX}.txt"
fi

POOL_MANIFEST="$(bash "$ROOT_DIR/scripts/maestro/setup-ios-simulator-pool.sh" "$POOL_DEVICE_COUNT" "$POOL_MANIFEST")"

delete_pool_simulators() {
  local simulator_id=""
  [[ -f "$POOL_MANIFEST" ]] || return 0
  while IFS= read -r simulator_id; do
    [[ -n "$simulator_id" ]] || continue
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  done <"$POOL_MANIFEST"
}

trap delete_pool_simulators EXIT

SIMULATOR_IDS=()
while IFS= read -r simulator_id; do
  [[ -n "$simulator_id" ]] || continue
  SIMULATOR_IDS+=("$simulator_id")
done <"$POOL_MANIFEST"
if ((${#SIMULATOR_IDS[@]} != POOL_DEVICE_COUNT)); then
  echo "Expected ${POOL_DEVICE_COUNT} simulators in ${POOL_MANIFEST}, got ${#SIMULATOR_IDS[@]}" >&2
  exit 1
fi

run_shard_worker() {
  local shard_index="$1"
  local device_id="$2"
  CAPGO_MAESTRO_RESULTS_DIR="$ROOT_DIR/maestro-results-ios-shard-${shard_index}" \
    bash "$ROOT_DIR/scripts/maestro/maestro-shard-worker.sh" ios "$shard_index" "$SHARD_COUNT" "$device_id"
}

IOS_BOOT_TIMEOUT_SECONDS="${CAPGO_MAESTRO_IOS_BOOT_TIMEOUT_SECONDS:-120}"

boot_ios_simulator() {
  local simulator_id="$1"
  if xcrun simctl spawn "$simulator_id" true >/dev/null 2>&1; then
    disable_ios_simulator_animations "$simulator_id"
    return 0
  fi
  local attempt=1
  while (( attempt <= 2 )); do
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
    if python3 -c "
import subprocess, sys
subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], timeout=int(sys.argv[2]), check=True)
" "$simulator_id" "$IOS_BOOT_TIMEOUT_SECONDS"; then
      disable_ios_simulator_animations "$simulator_id"
      return 0
    fi
  if (( attempt == 1 )); then
      echo "Simulator ${simulator_id} boot slow; recreating once." >&2
      xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
      xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
      simulator_id="$(bash "$ROOT_DIR/scripts/maestro/create-ios-simulator-named.sh" "Capgo Maestro retry-${IOS_BOOT_TIMEOUT_SECONDS}-${RANDOM}")"
      printf '%s\n' "$simulator_id" >"$POOL_MANIFEST"
    fi
    attempt=$((attempt + 1))
  done
  echo "Simulator failed to boot within ${IOS_BOOT_TIMEOUT_SECONDS}s." >&2
  exit 1
}

fail=0
if [[ -n "$SHARD_INDEX" ]]; then
  boot_ios_simulator "${SIMULATOR_IDS[0]}"
  SIMULATOR_IDS[0]="$(head -n 1 "$POOL_MANIFEST" | tr -d '\r')"
  if ! run_shard_worker "$SHARD_INDEX" "${SIMULATOR_IDS[0]}"; then
    fail=1
  fi
else
  boot_fail=0
  for simulator_id in "${SIMULATOR_IDS[@]}"; do
    if ! boot_ios_simulator "$simulator_id"; then
      boot_fail=1
    fi
  done
  if (( boot_fail != 0 )); then
    exit 1
  fi

  pids=()
  for shard_index in "${!SIMULATOR_IDS[@]}"; do
    device_id="${SIMULATOR_IDS[$shard_index]}"
    (
      run_shard_worker "$shard_index" "$device_id"
    ) &
    pids+=("$!")
  done

  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      fail=1
    fi
  done
fi

mkdir -p "$ROOT_DIR/maestro-results-ios"
rm -rf "$ROOT_DIR/maestro-results-ios"/*
if [[ -n "$SHARD_INDEX" ]]; then
  src="$ROOT_DIR/maestro-results-ios-shard-${SHARD_INDEX}"
  if [[ -d "$src" ]]; then
    cp -R "$src/." "$ROOT_DIR/maestro-results-ios/" 2>/dev/null || true
  fi
else
  for (( shard_index = 0; shard_index < SHARD_COUNT; shard_index++ )); do
    src="$ROOT_DIR/maestro-results-ios-shard-${shard_index}"
    if [[ -d "$src" ]]; then
      cp -R "$src/." "$ROOT_DIR/maestro-results-ios/" 2>/dev/null || true
    fi
  done
fi

exit "$fail"