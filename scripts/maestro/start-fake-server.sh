#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

start_fake_download_server() {
  local log_path="${1:-$ROOT_DIR/.maestro-artifacts/fake-download-server.log}"
  mkdir -p "$(dirname "$log_path")"
  if command -v bun >/dev/null 2>&1; then
    bun "$ROOT_DIR/scripts/maestro/fake-download-server.mjs" >"$log_path" 2>&1 &
  else
    node "$ROOT_DIR/scripts/maestro/fake-download-server.mjs" >"$log_path" 2>&1 &
  fi
  SERVER_PID=$!
  export SERVER_PID
}