#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

POOL_MANIFEST="${1:?pool-manifest}"
BOOT_TIMEOUT_SECONDS="${CAPGO_MAESTRO_IOS_BOOT_TIMEOUT_SECONDS:-180}"

simulator_id="$(head -n 1 "$POOL_MANIFEST" | tr -d '\r')"
if [[ -z "$simulator_id" ]]; then
  echo "Missing simulator id in ${POOL_MANIFEST}" >&2
  exit 1
fi

if xcrun simctl spawn "$simulator_id" true >/dev/null 2>&1; then
  disable_ios_simulator_animations "$simulator_id"
  exit 0
fi

xcrun simctl boot "$simulator_id" 2>/dev/null || true
python3 -c "
import subprocess, sys
subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], timeout=int(sys.argv[2]), check=True)
" "$simulator_id" "$BOOT_TIMEOUT_SECONDS"
disable_ios_simulator_animations "$simulator_id"