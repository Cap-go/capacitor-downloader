#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

SHARD_COUNT="${CAPGO_MAESTRO_SHARD_COUNT:-4}"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
EMULATOR="${SDK_ROOT}/emulator/emulator"
ADB="${SDK_ROOT}/platform-tools/adb"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro is required." >&2
  exit 1
fi
if [[ ! -x "$EMULATOR" ]] || [[ ! -x "$ADB" ]]; then
  echo "Android SDK emulator/adb are required." >&2
  exit 1
fi

wait_for_android_boot() {
  local serial="$1"
  local booted=""
  if ! "$ADB" -s "$serial" wait-for-device; then
    return 1
  fi
  for _ in $(seq 1 90); do
    booted="$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [[ "$booted" == "1" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "Emulator ${serial} failed to boot." >&2
  return 1
}

run_shard_worker() {
  local shard_index="$1"
  local device_id="$2"
  CAPGO_MAESTRO_RESULTS_DIR="$ROOT_DIR/maestro-results-shard-${shard_index}" \
    bash "$ROOT_DIR/scripts/maestro/maestro-shard-worker.sh" android "$shard_index" "$SHARD_COUNT" "$device_id"
}

"$ADB" wait-for-device
if ! wait_for_android_boot "$("$ADB" get-serialno | tr -d '\r')"; then
  echo "Primary emulator failed to boot." >&2
  exit 1
fi

primary_serial="$("$ADB" get-serialno | tr -d '\r')"
export ANDROID_SERIAL="$primary_serial"
disable_android_emulator_animations

avd_name=""
if [[ -n "${CAPGO_MAESTRO_AVD:-}" ]]; then
  avd_name="$CAPGO_MAESTRO_AVD"
else
  avd_name="$("$EMULATOR" -list-avds | head -n 1 || true)"
fi

pids=()
fail=0

(
  run_shard_worker 0 "$primary_serial"
) &
pids+=("$!")

for shard_index in $(seq 1 $((SHARD_COUNT - 1))); do
  port=$((5554 + shard_index * 2))
  serial="emulator-${port}"
  if "$ADB" -s "$serial" get-state >/dev/null 2>&1; then
    if wait_for_android_boot "$serial"; then
      export ANDROID_SERIAL="$serial"
      disable_android_emulator_animations
      (
        run_shard_worker "$shard_index" "$serial"
      ) &
      pids+=("$!")
    else
      fail=1
    fi
    continue
  fi
  if [[ -z "$avd_name" ]]; then
    echo "Need CAPGO_MAESTRO_AVD or a listed AVD to start extra emulators (shard ${shard_index})." >&2
    fail=1
    continue
  fi
  (
    "$EMULATOR" -avd "$avd_name" -port "$port" -no-window -no-boot-anim -gpu swiftshader_indirect -no-audio -camera-back none -cores 2 -memory 2048 &
    if ! wait_for_android_boot "$serial"; then
      exit 1
    fi
    export ANDROID_SERIAL="$serial"
    disable_android_emulator_animations
    run_shard_worker "$shard_index" "$serial"
  ) &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    fail=1
  fi
done

mkdir -p "$ROOT_DIR/maestro-results"
rm -rf "$ROOT_DIR/maestro-results"/*
for shard_index in $(seq 0 $((SHARD_COUNT - 1))); do
  src="$ROOT_DIR/maestro-results-shard-${shard_index}"
  if [[ -d "$src" ]]; then
    cp -R "$src/." "$ROOT_DIR/maestro-results/" 2>/dev/null || true
  fi
done

exit "$fail"