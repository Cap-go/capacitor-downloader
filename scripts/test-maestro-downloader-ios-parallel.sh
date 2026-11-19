#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

SHARD_COUNT="${CAPGO_MAESTRO_SHARD_COUNT:-4}"
export CAPGO_MAESTRO_SHARD_COUNT="$SHARD_COUNT"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro is required." >&2
  exit 1
fi

SIMULATOR_IDS=()
while IFS= read -r simulator_id; do
  [[ -n "$simulator_id" ]] || continue
  SIMULATOR_IDS+=("$simulator_id")
done < <(bash "$ROOT_DIR/scripts/maestro/setup-ios-simulator-pool.sh" "$SHARD_COUNT")
if ((${#SIMULATOR_IDS[@]} != SHARD_COUNT)); then
  echo "Expected ${SHARD_COUNT} simulators, got ${#SIMULATOR_IDS[@]}" >&2
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
  xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
  if ! python3 -c "
import subprocess, sys
subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], timeout=int(sys.argv[2]), check=True)
" "$simulator_id" "$IOS_BOOT_TIMEOUT_SECONDS"; then
    echo "Simulator ${simulator_id} failed to boot within ${IOS_BOOT_TIMEOUT_SECONDS}s." >&2
    exit 1
  fi
  disable_ios_simulator_animations "$simulator_id"
}

for simulator_id in "${SIMULATOR_IDS[@]}"; do
  boot_ios_simulator "$simulator_id"
done

pids=()
fail=0
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

mkdir -p "$ROOT_DIR/maestro-results-ios"
rm -rf "$ROOT_DIR/maestro-results-ios"/*
for shard_index in $(seq 0 $((SHARD_COUNT - 1))); do
  src="$ROOT_DIR/maestro-results-ios-shard-${shard_index}"
  if [[ -d "$src" ]]; then
    cp -R "$src/." "$ROOT_DIR/maestro-results-ios/" 2>/dev/null || true
  fi
done

exit "$fail"