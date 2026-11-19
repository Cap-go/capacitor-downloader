#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARD_COUNT="${CAPGO_MAESTRO_SHARD_COUNT:-4}"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro is required." >&2
  exit 1
fi

IFS=',' read -r -a SIMULATOR_IDS <<<"$(bash "$ROOT_DIR/scripts/maestro/setup-ios-simulator-pool.sh")"
if ((${#SIMULATOR_IDS[@]} != SHARD_COUNT)); then
  echo "Expected ${SHARD_COUNT} simulators, got ${#SIMULATOR_IDS[@]}" >&2
  exit 1
fi

pids=()
fail=0
for shard_index in $(seq 0 $((SHARD_COUNT - 1))); do
  device_id="${SIMULATOR_IDS[$shard_index]}"
  (
    CAPGO_MAESTRO_RESULTS_DIR="$ROOT_DIR/maestro-results-ios-shard-${shard_index}" \
      bash "$ROOT_DIR/scripts/maestro/maestro-shard-worker.sh" ios "$shard_index" "$SHARD_COUNT" "$device_id"
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