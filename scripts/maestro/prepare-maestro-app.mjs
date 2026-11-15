import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const exampleDir = path.join(rootDir, 'example-app');
const platform = process.argv[2];

if (!platform || !['android', 'ios'].includes(platform)) {
  throw new Error('Usage: bun scripts/maestro/prepare-maestro-app.mjs <android|ios>');
}

const deviceBaseUrl =
  process.env.CAPGO_MAESTRO_DEVICE_BASE_URL ??
  (platform === 'android' ? 'http://10.0.2.2:3192' : 'http://127.0.0.1:3192');

const buildEnv = {
  ...process.env,
  VITE_CAPGO_MAESTRO_BUILD: 'true',
  VITE_CAPGO_SERVER_URL: deviceBaseUrl,
};

function run(cmd, args, cwd) {
  const result = spawnSync(cmd, args, {
    cwd,
    env: buildEnv,
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    throw new Error(`${cmd} ${args.join(' ')} failed in ${cwd}`);
  }
}

run('bun', ['run', 'build'], rootDir);
run('bun', ['install'], exampleDir);
run('bun', ['run', 'build'], exampleDir);
run('bunx', ['cap', 'sync', platform], exampleDir);

if (platform === 'android') {
  run('./gradlew', ['assembleDebug'], path.join(exampleDir, 'android'));
  const apk = path.join(exampleDir, 'android/app/build/outputs/apk/debug/app-debug.apk');
  if (!existsSync(apk)) {
    throw new Error(`Expected APK at ${apk}`);
  }
} else {
  const derivedData = process.env.CAPGO_MAESTRO_IOS_DERIVED_DATA ?? path.join(rootDir, '.maestro-ios-derived-data');
  run('xcodebuild', [
    '-project',
    'App.xcodeproj',
    '-scheme',
    'App',
    '-configuration',
    'Debug',
    '-sdk',
    'iphonesimulator',
    '-derivedDataPath',
    derivedData,
    'build',
  ], path.join(exampleDir, 'ios/App'));
}