#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARD_COUNT="${1:-${CAPGO_MAESTRO_SHARD_COUNT:-4}}"
POOL_MANIFEST="${2:-${CAPGO_MAESTRO_IOS_POOL_MANIFEST:-$ROOT_DIR/.maestro-artifacts/ios-simulator-pool.txt}}"

if ! [[ "$SHARD_COUNT" =~ ^[0-9]+$ ]] || (( SHARD_COUNT < 1 || SHARD_COUNT > 6 )); then
  echo "CAPGO_MAESTRO_SHARD_COUNT must be 1..6" >&2
  exit 1
fi

MAESTRO_POOL_TOKEN="${GITHUB_RUN_ID:-$$}"
mkdir -p "$(dirname "$POOL_MANIFEST")"
: >"$POOL_MANIFEST"

create_pool_device() {
  local suffix="$1"
  local display_name="Capgo Maestro Pool ${MAESTRO_POOL_TOKEN}-${suffix}"
  bash "$ROOT_DIR/scripts/maestro/create-ios-simulator-named.sh" "$display_name"
}

for (( index = 0; index < SHARD_COUNT; index++ )); do
  device_id="$(create_pool_device "$index" | head -n 1 | tr -d '\r')"
  if [[ -z "$device_id" ]]; then
    echo "Failed to create iOS simulator shard ${index} for the pool." >&2
    exit 1
  fi
  printf '%s\n' "$device_id" >>"$POOL_MANIFEST"
done

manifest_lines="$(wc -l <"$POOL_MANIFEST" | tr -d '[:space:]')"
if [[ "$manifest_lines" != "$SHARD_COUNT" ]]; then
  echo "Simulator pool manifest has ${manifest_lines} entries, expected ${SHARD_COUNT}." >&2
  exit 1
fi

printf '%s\n' "$POOL_MANIFEST"