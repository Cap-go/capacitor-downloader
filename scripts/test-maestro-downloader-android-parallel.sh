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

"$ADB" wait-for-device
booted=""
for _ in $(seq 1 90); do
  booted="$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [[ "$booted" == "1" ]]; then
    break
  fi
  sleep 2
done
if [[ "$booted" != "1" ]]; then
  echo "Primary emulator failed to boot." >&2
  exit 1
fi

primary_serial="$("$ADB" get-serialno | tr -d '\r')"
serial_list=("$primary_serial")

avd_name=""
if [[ -n "${CAPGO_MAESTRO_AVD:-}" ]]; then
  avd_name="$CAPGO_MAESTRO_AVD"
else
  avd_name="$("$EMULATOR" -list-avds | head -n 1 || true)"
fi

ports_to_boot=()
while ((${#serial_list[@]} < SHARD_COUNT)); do
  shard_index="${#serial_list[@]}"
  port=$((5554 + shard_index * 2))
  serial="emulator-${port}"
  if "$ADB" -s "$serial" get-state >/dev/null 2>&1; then
    serial_list+=("$serial")
    continue
  fi
  if [[ -z "$avd_name" ]]; then
    echo "Need CAPGO_MAESTRO_AVD or a listed AVD to start extra emulators." >&2
    break
  fi
  ports_to_boot+=("$port")
  serial_list+=("$serial")
done

if ((${#ports_to_boot[@]} > 0)); then
  for port in "${ports_to_boot[@]}"; do
    "$EMULATOR" -avd "$avd_name" -port "$port" -no-window -no-snapshot -no-boot-anim -gpu swiftshader_indirect -no-audio -camera-back none &
  done
  boot_fail=0
  for port in "${ports_to_boot[@]}"; do
    serial="emulator-${port}"
    if ! "$ADB" -s "$serial" wait-for-device; then
      boot_fail=1
      continue
    fi
    booted=""
    for _ in $(seq 1 90); do
      booted="$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      if [[ "$booted" == "1" ]]; then
        break
      fi
      sleep 2
    done
    if [[ "$booted" != "1" ]]; then
      echo "Emulator ${serial} failed to boot." >&2
      boot_fail=1
    fi
  done
  if (( boot_fail != 0 )); then
    exit 1
  fi
fi

effective_shards="${#serial_list[@]}"
if (( effective_shards < SHARD_COUNT )); then
  echo "Running ${effective_shards} Android shard(s) instead of ${SHARD_COUNT}." >&2
  SHARD_COUNT="$effective_shards"
fi

for serial in "${serial_list[@]}"; do
  export ANDROID_SERIAL="$serial"
  disable_android_emulator_animations
done

pids=()
fail=0
for shard_index in $(seq 0 $((SHARD_COUNT - 1))); do
  device_id="${serial_list[$shard_index]}"
  (
    CAPGO_MAESTRO_RESULTS_DIR="$ROOT_DIR/maestro-results-shard-${shard_index}" \
      bash "$ROOT_DIR/scripts/maestro/maestro-shard-worker.sh" android "$shard_index" "$SHARD_COUNT" "$device_id"
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