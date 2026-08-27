#!/usr/bin/env bun
/**
 * Run CapgoCapacitorDownloader XCTest on an available iPhone simulator.
 *
 * GitHub macOS runners change bundled simulators with Xcode updates, so we
 * resolve a destination UDID at runtime instead of hardcoding a device name.
 */

import { execFileSync, spawnSync } from "node:child_process";

const SCHEME = "CapgoCapacitorDownloader";

function parseIosRuntimeVersion(runtimeKey) {
  const match = runtimeKey.match(/iOS-(\d+)-(\d+)/);
  if (!match) {
    return -1;
  }
  return Number(match[1]) * 100 + Number(match[2]);
}

function pickIphoneSimulator() {
  let payload;
  try {
    payload = execFileSync("xcrun", ["simctl", "list", "devices", "available", "-j"], {
      encoding: "utf8",
    });
  } catch (error) {
    console.error("Failed to list available iOS simulators with xcrun simctl.");
    if (error && typeof error === "object" && "stderr" in error && error.stderr) {
      console.error(String(error.stderr).trim());
    } else if (error instanceof Error && error.message) {
      console.error(error.message);
    }
    process.exit(1);
  }

  const { devices = {} } = JSON.parse(payload);
  const iosRuntimes = Object.entries(devices)
    .filter(([runtimeKey]) => runtimeKey.includes("iOS"))
    .sort(([left], [right]) => parseIosRuntimeVersion(right) - parseIosRuntimeVersion(left));

  for (const [, runtimeDevices] of iosRuntimes) {
    const iphone = runtimeDevices.find(
      (device) => device.isAvailable !== false && device.name?.startsWith("iPhone"),
    );
    if (iphone) {
      return iphone;
    }
  }

  return null;
}

const simulator = pickIphoneSimulator();
if (!simulator) {
  console.error(
    "No available iPhone simulator found. Install one in Xcode or inspect:\n  xcrun simctl list devices available -j",
  );
  process.exit(1);
}

console.log(`Using iOS Simulator: ${simulator.name} (${simulator.udid})`);

const result = spawnSync(
  "xcodebuild",
  [
    "test",
    "-scheme",
    SCHEME,
    "-destination",
    `platform=iOS Simulator,id=${simulator.udid}`,
    "-parallel-testing-enabled",
    "NO",
    "CODE_SIGNING_ALLOWED=NO",
  ],
  { stdio: "inherit" },
);

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
