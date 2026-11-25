#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
if ! command -v maestro >/dev/null 2>&1; then
  echo "Maestro CLI is not installed. See https://maestro.mobile.dev/" >&2
  exit 1
fi
maestro test "$ROOT/.maestro/android/okhttp-batch-success.yaml"
maestro test "$ROOT/.maestro/android/mixed-engine-batch-fail.yaml"