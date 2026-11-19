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

base_id="$(create_pool_device 0 | head -n 1 | tr -d '\r')"
if [[ -z "$base_id" ]]; then
  echo "Failed to create base iOS simulator for the pool." >&2
  exit 1
fi
printf '%s\n' "$base_id" >>"$POOL_MANIFEST"

if (( SHARD_COUNT > 1 )); then
  xcrun simctl shutdown "$base_id" >/dev/null 2>&1 || true
  for (( index = 1; index < SHARD_COUNT; index++ )); do
    clone_name="Capgo Maestro Pool ${MAESTRO_POOL_TOKEN}-${index}"
    clone_id="$(xcrun simctl clone "$base_id" "$clone_name" | head -n 1 | tr -d '\r')"
    printf '%s\n' "$clone_id" >>"$POOL_MANIFEST"
  done
fi

manifest_lines="$(wc -l <"$POOL_MANIFEST" | tr -d '[:space:]')"
if [[ "$manifest_lines" != "$SHARD_COUNT" ]]; then
  echo "Simulator pool manifest has ${manifest_lines} entries, expected ${SHARD_COUNT}." >&2
  exit 1
fi

printf '%s\n' "$POOL_MANIFEST"