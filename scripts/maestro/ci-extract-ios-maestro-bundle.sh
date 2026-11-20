#!/usr/bin/env bash
set -euo pipefail

SHARD_INDEX="${1:?shard-index}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

POOL_MANIFEST="${GITHUB_WORKSPACE}/.maestro-artifacts/ios-simulator-pool-shard-${SHARD_INDEX}.txt"
export CAPGO_MAESTRO_SHARD_INDEX="$SHARD_INDEX"
export CAPGO_MAESTRO_SHARD_COUNT=4

bash "$ROOT_DIR/scripts/maestro/setup-ios-simulator-pool.sh" 1 "$POOL_MANIFEST" &
POOL_PID=$!
mkdir -p maestro-ios-app maestro-cli
tar -xzf maestro-ios-e2e-bundle.tar.gz -C .
wait "$POOL_PID"

bash "$ROOT_DIR/scripts/maestro/warm-boot-ios-pool-simulator.sh" "$POOL_MANIFEST" &
BOOT_PID=$!

rm -rf "$HOME/.maestro"
mkdir -p "$HOME/.maestro"
ditto maestro-cli/ "$HOME/.maestro/"
chmod 0755 "$HOME/.maestro/bin/maestro"
mv App.app maestro-ios-app/App.app
echo "$HOME/.maestro/bin" >>"$GITHUB_PATH"

wait "$BOOT_PID"
touch "${POOL_MANIFEST%.txt}.prebooted"