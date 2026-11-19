#!/usr/bin/env bash
set -euo pipefail

device_name="${1:?simulator display name}"

device_line_regex='^[[:space:]]*(.*)[[:space:]]\(([0-9A-F-]{36})\)[[:space:]]\([^)]*\)[[:space:]]*$'
available_device_types="$(xcrun simctl list devicetypes)"

device_type_identifier_for_name() {
  local target_name="$1"
  local line=""
  local name=""
  local identifier=""

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    identifier="${line##* (}"
    identifier="${identifier%)}"
    name="${line% ($identifier)}"
    if [[ "$name" == "$target_name" && "$identifier" == com.apple.CoreSimulator.SimDeviceType.* ]]; then
      printf '%s\n' "$identifier"
      return 0
    fi
  done <<<"$available_device_types"
}

latest_ios_runtime() {
  xcrun simctl list runtimes available |
    sed -nE 's/^iOS .* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+)$/\1/p' |
    tail -n 1
}

preferred_models=(
  'iPhone SE (3rd generation)'
  'iPhone SE (2nd generation)'
  'iPhone 16e'
  'iPhone 15'
  'iPhone 14'
  'iPhone 16'
  'iPhone 13'
  'iPhone 12'
)

runtime_id="$(latest_ios_runtime)"
if [[ -z "$runtime_id" ]]; then
  echo "No available iOS simulator runtime." >&2
  exit 1
fi

for model in "${preferred_models[@]}"; do
  device_type="$(device_type_identifier_for_name "$model")"
  if [[ -n "$device_type" ]]; then
    simulator_id="$(xcrun simctl create "$device_name" "$device_type" "$runtime_id")"
    printf '%s\n' "$simulator_id"
    exit 0
  fi
done

echo "Could not create iOS simulator for ${device_name}." >&2
exit 1