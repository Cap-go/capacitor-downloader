#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

SHARD_COUNT="${CAPGO_MAESTRO_SHARD_COUNT:-4}"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
EMULATOR="${SDK_ROOT}/emulator/emulator"
ADB="${SDK_ROOT}/platform-tools/adb"
EMULATOR_BOOT_TIMEOUT_SECONDS="${CAPGO_MAESTRO_EMULATOR_BOOT_TIMEOUT_SECONDS:-90}"
EMULATOR_EXTRA_FLAGS=(-no-window -no-boot-anim -gpu swiftshader_indirect -no-audio -camera-back none -cores 2 -memory 2048)

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
  local emu_pid="${2:-}"
  local booted=""
  local elapsed=0
  if ! "$ADB" -s "$serial" wait-for-device; then
    return 1
  fi
  while (( elapsed < EMULATOR_BOOT_TIMEOUT_SECONDS )); do
    if [[ -n "$emu_pid" ]] && ! kill -0 "$emu_pid" 2>/dev/null; then
      echo "Emulator process exited before ${serial} finished booting." >&2
      return 1
    fi
    booted="$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [[ "$booted" == "1" ]]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "Emulator ${serial} failed to boot within ${EMULATOR_BOOT_TIMEOUT_SECONDS}s." >&2
  return 1
}

run_shard_worker() {
  local shard_index="$1"
  local device_id="$2"
  CAPGO_MAESTRO_RESULTS_DIR="$ROOT_DIR/maestro-results-shard-${shard_index}" \
    bash "$ROOT_DIR/scripts/maestro/maestro-shard-worker.sh" android "$shard_index" "$SHARD_COUNT" "$device_id"
}

ensure_shard_avd() {
  local base_avd="$1"
  local port="$2"
  local shard_avd="capgo_maestro_${port}"
  if "$EMULATOR" -list-avds | grep -qx "$shard_avd"; then
    printf '%s\n' "$shard_avd"
    return 0
  fi
  local avd_home="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
  local src_dir="${avd_home}/${base_avd}.avd"
  local dst_dir="${avd_home}/${shard_avd}.avd"
  if [[ ! -d "$src_dir" ]]; then
    echo "Base AVD directory missing: ${src_dir}" >&2
    return 1
  fi
  cp -a "$src_dir" "$dst_dir"
  if [[ -f "${avd_home}/${base_avd}.ini" ]]; then
    cp "${avd_home}/${base_avd}.ini" "${avd_home}/${shard_avd}.ini"
    sed -i "s/${base_avd}/${shard_avd}/g" "${avd_home}/${shard_avd}.ini"
  fi
  if [[ -f "${dst_dir}/config.ini" ]]; then
    sed -i "s/${base_avd}/${shard_avd}/g" "${dst_dir}/config.ini" || true
  fi
  printf '%s\n' "$shard_avd"
}

start_extra_emulator() {
  local port="$1"
  local avd_name="$2"
  local shard_avd=""
  local serial="emulator-${port}"
  local log_file="$ROOT_DIR/.maestro-artifacts/emulator-${port}.log"
  mkdir -p "$ROOT_DIR/.maestro-artifacts"
  if ! shard_avd="$(ensure_shard_avd "$avd_name" "$port")"; then
    return 1
  fi
  set +e
  "$EMULATOR" -avd "$shard_avd" -port "$port" "${EMULATOR_EXTRA_FLAGS[@]}" >"$log_file" 2>&1 &
  local emu_pid=$!
  set -e
  if ! wait_for_android_boot "$serial" "$emu_pid"; then
    if ! kill -0 "$emu_pid" 2>/dev/null; then
      echo "Extra emulator ${serial} log:" >&2
      tail -n 40 "$log_file" >&2 || true
    fi
    if kill -0 "$emu_pid" 2>/dev/null; then
      kill "$emu_pid" >/dev/null 2>&1 || true
    fi
    return 1
  fi
  return 0
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
    if ! start_extra_emulator "$port" "$avd_name"; then
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