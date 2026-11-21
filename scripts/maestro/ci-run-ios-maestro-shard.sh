#!/usr/bin/env bash
set -euo pipefail

SHARD_INDEX="${1:?shard-index}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

bash "$ROOT_DIR/scripts/maestro/ci-extract-ios-maestro-bundle.sh" "$SHARD_INDEX"
exec "$ROOT_DIR/scripts/test-maestro-downloader-ios-parallel.sh"