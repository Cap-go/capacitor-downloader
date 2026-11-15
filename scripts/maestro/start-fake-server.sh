#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_PATH="${1:-$ROOT_DIR/.maestro-artifacts/fake-download-server.log}"

mkdir -p "$(dirname "$LOG_PATH")"

start_fake_download_server() {
  if command -v bun >/dev/null 2>&1; then
    bun "$ROOT_DIR/scripts/maestro/fake-download-server.mjs" >"$LOG_PATH" 2>&1 &
  else
    node "$ROOT_DIR/scripts/maestro/fake-download-server.mjs" >"$LOG_PATH" 2>&1 &
  fi
  SERVER_PID=$!
  export SERVER_PID
}