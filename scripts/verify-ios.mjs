#!/usr/bin/env bun
/**
 * Run CapgoCapacitorDownloader XCTest on an available iPhone simulator.
 *
 * GitHub macOS runners change bundled simulators with Xcode updates, so we
 * resolve a destination UDID at runtime instead of hardcoding a device name.
 */

import { execFileSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const SCHEME = "CapgoCapacitorDownloader";
const MAX_ATTEMPTS = 3;

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

function clearSwiftPackageManagerCaches() {
  const candidates = [
    join(homedir(), "Library", "Caches", "org.swift.swiftpm"),
    join(process.cwd(), ".build"),
  ];
  for (const path of candidates) {
    if (!existsSync(path)) {
      continue;
    }
    try {
      execFileSync("rm", ["-rf", path]);
      console.error(`Cleared SPM cache: ${path}`);
    } catch (error) {
      console.error(`Failed to clear ${path}: ${error instanceof Error ? error.message : error}`);
    }
  }
}

function isChecksumMismatch(output) {
  return output.includes("checksum of downloaded artifact");
}

function runXcodebuild(args) {
  return new Promise((resolve, reject) => {
    const outputChunks = [];
    const child = spawn("xcodebuild", args, {
      stdio: ["ignore", "pipe", "pipe"],
    });

    child.stdout.on("data", (chunk) => {
      outputChunks.push(chunk);
      process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => {
      outputChunks.push(chunk);
      process.stderr.write(chunk);
    });

    child.on("error", reject);
    child.on("close", (status) => {
      const output = Buffer.concat(outputChunks).toString("utf8");
      resolve({ status: status ?? 1, output });
    });
  });
}

const simulator = pickIphoneSimulator();
if (!simulator) {
  console.error(
    "No available iPhone simulator found. Install one in Xcode or inspect:\n  xcrun simctl list devices available -j",
  );
  process.exit(1);
}

console.log(`Using iOS Simulator: ${simulator.name} (${simulator.udid})`);

const xcodebuildArgs = [
  "test",
  "-scheme",
  SCHEME,
  "-destination",
  `platform=iOS Simulator,id=${simulator.udid}`,
  "-parallel-testing-enabled",
  "NO",
  "CODE_SIGNING_ALLOWED=NO",
];

for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
  let result;
  try {
    result = await runXcodebuild(xcodebuildArgs);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }

  if (result.status === 0) {
    process.exit(0);
  }

  if (attempt < MAX_ATTEMPTS && isChecksumMismatch(result.output)) {
    console.error(
      `xcodebuild failed with capacitor-swift-pm checksum mismatch (attempt ${attempt}/${MAX_ATTEMPTS}). Retrying after cache reset.`,
    );
    clearSwiftPackageManagerCaches();
    continue;
  }

  process.exit(result.status);
}
