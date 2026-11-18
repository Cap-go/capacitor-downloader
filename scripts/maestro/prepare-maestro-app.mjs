import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, rmSync } from 'node:fs';
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

function runWithRetries(cmd, args, cwd, { attempts = 3, backoffMs = 5000 } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      run(cmd, args, cwd);
      return;
    } catch (error) {
      lastError = error;
      if (attempt < attempts) {
        console.warn(`${cmd} attempt ${attempt}/${attempts} failed; retrying in ${backoffMs}ms`);
        spawnSync('sleep', [String(Math.max(1, Math.ceil(backoffMs / 1000)))]);
      }
    }
  }
  throw lastError;
}

function assertMaestroWebBundle() {
  const indexPath = path.join(exampleDir, 'dist/index.html');
  if (!existsSync(indexPath)) {
    throw new Error(`Missing ${indexPath}; example Vite build did not produce dist/`);
  }
  const indexHtml = readFileSync(indexPath, 'utf8');
  const match = indexHtml.match(/\/assets\/(index-[^"?]+\.js)/);
  if (!match) {
    throw new Error('dist/index.html does not reference a hashed index bundle');
  }
  const bundleName = match[1];
  const bundlePath = path.join(exampleDir, 'dist/assets', bundleName);
  if (!existsSync(bundlePath)) {
    throw new Error(`Missing bundle file dist/assets/${bundleName}`);
  }
  const assetFiles = readdirSync(path.join(exampleDir, 'dist/assets'));
  const hasHarnessMarker = assetFiles
    .filter((name) => name.endsWith('.js'))
    .some((name) =>
      readFileSync(path.join(exampleDir, 'dist/assets', name), 'utf8').includes('Harness: ready'),
    );
  if (!hasHarnessMarker) {
    throw new Error('dist/assets is missing Maestro harness markers');
  }
  for (const file of assetFiles) {
    if (!existsSync(path.join(exampleDir, 'dist/assets', file))) {
      throw new Error(`Incomplete dist/assets output (missing ${file})`);
    }
  }
  return { bundleName, assetFiles };
}

function assertSyncedWebAssets({ bundleName, assetFiles }) {
  const publicAssetsDir = path.join(exampleDir, `android/app/src/main/assets/public/assets`);
  if (platform !== 'android') {
    return;
  }
  if (!existsSync(publicAssetsDir)) {
    throw new Error(`Missing ${publicAssetsDir} after cap sync`);
  }
  const synced = new Set(readdirSync(publicAssetsDir));
  if (!synced.has(bundleName)) {
    throw new Error(
      `cap sync did not copy ${bundleName}; synced assets: ${[...synced].sort().join(', ')}`,
    );
  }
  for (const file of assetFiles) {
    if (!synced.has(file)) {
      throw new Error(`cap sync missing dist asset ${file} under public/assets`);
    }
  }
}

run('bun', ['run', 'build'], rootDir);
run('bun', ['install'], exampleDir);
run('bun', ['run', 'build'], exampleDir);

const webBundle = assertMaestroWebBundle();

const androidPublicDir = path.join(exampleDir, 'android/app/src/main/assets/public');
if (platform === 'android' && existsSync(androidPublicDir)) {
  rmSync(androidPublicDir, { recursive: true, force: true });
}

run('bunx', ['cap', 'sync', platform], exampleDir);
assertSyncedWebAssets(webBundle);

if (platform === 'android') {
  const gradleArgs =
    process.env.CAPGO_MAESTRO_SKIP_GRADLE_CLEAN === '1' ? ['assembleDebug'] : ['clean', 'assembleDebug'];
  runWithRetries('./gradlew', gradleArgs, path.join(exampleDir, 'android'));
  const apk = path.join(exampleDir, 'android/app/build/outputs/apk/debug/app-debug.apk');
  if (!existsSync(apk)) {
    throw new Error(`Expected APK at ${apk}`);
  }
} else {
  const derivedData = process.env.CAPGO_MAESTRO_IOS_DERIVED_DATA ?? path.join(rootDir, '.maestro-ios-derived-data');
  const xcodebuildArgs = [
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
  ];
  if (process.env.CAPGO_MAESTRO_SKIP_XCODE_CLEAN !== '1') {
    xcodebuildArgs.push('clean');
  }
  xcodebuildArgs.push('build');
  runWithRetries('xcodebuild', xcodebuildArgs, path.join(exampleDir, 'ios/App'));
}