import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const MARKER = '/* MAESTRO_BREAK_FIX_APPLIED */';

const regressions = {
  'completion-dedupe': [
    {
      file: 'android/src/main/java/ee/forgr/capacitor/plugin/downloader/CapacitorDownloaderPlugin.java',
      needle:
        'completedData.put("id", downloadId);\n                                    notifyListeners("downloadCompleted", completedData);',
      insertAfter: '\n                                    notifyListeners("downloadCompleted", completedData);' + MARKER,
    },
    {
      file: 'ios/Sources/CapacitorDownloaderPlugin/CapacitorDownloaderPlugin.swift',
      replace: [
        `                notifyListeners("downloadCompleted", data: ["id": id])\n                if let completionText = DownloadCompletedNotificationStore.shared.takeText(for: id, generation: generation) {`,
        `                notifyListeners("downloadCompleted", data: ["id": id])\n                notifyListeners("downloadCompleted", data: ["id": id])${MARKER}\n                if let completionText = DownloadCompletedNotificationStore.shared.takeText(for: id, generation: generation) {`,
      ],
    },
  ],
  'cancel-cleanup': [
    {
      file: 'android/src/main/java/ee/forgr/capacitor/plugin/downloader/CapacitorDownloaderPlugin.java',
      replace: [
        'boolean cancelled = okHttpDownloadExecutor.cancel(id, destinationFile);',
        'okHttpDownloadExecutor.cancel(id, destinationFile); boolean cancelled = false; /* MAESTRO_BREAK_FIX */',
      ],
    },
    {
      file: 'android/src/main/java/ee/forgr/capacitor/plugin/downloader/CapacitorDownloaderPlugin.java',
      replace: [
        'int removedDownloads = downloadManager.remove(systemDownloadId);',
        'int removedDownloads = 0; /* MAESTRO_BREAK_FIX: skip DM remove */',
      ],
    },
    {
      file: 'android/src/main/java/ee/forgr/capacitor/plugin/downloader/OkHttpDownloadExecutor.java',
      replace: [
        'active.cancelled.set(true);\n        Call call = active.call;\n        if (call != null) {\n            call.cancel();',
        'active.cancelled.set(true);\n        Call call = active.call;\n        if (call != null) {\n            // call.cancel(); MAESTRO_BREAK_FIX',
      ],
    },
  ],
  'error-404-map': [
    {
      file: 'android/src/main/java/ee/forgr/capacitor/plugin/downloader/OkHttpDownloadExecutor.java',
      replace: [
        'if (!response.isSuccessful()) {',
        'if (!response.isSuccessful() && code != 404) { // MAESTRO_BREAK_FIX',
      ],
    },
    {
      file: 'ios/Sources/CapacitorDownloaderPlugin/CapacitorDownloaderPlugin.swift',
      replace: [
        '!DownloadHTTPValidator.isSuccessfulStatusCode(httpResponse.statusCode)',
        '(httpResponse.statusCode != 404 && !DownloadHTTPValidator.isSuccessfulStatusCode(httpResponse.statusCode)) /* MAESTRO_BREAK_FIX */',
      ],
    },
  ],
};

function readRepoFile(relativePath) {
  return readFileSync(path.join(rootDir, relativePath), 'utf8');
}

function writeRepoFile(relativePath, content) {
  writeFileSync(path.join(rootDir, relativePath), content, 'utf8');
}

function replaceNth(content, from, to, occurrence = 1) {
  let index = -1;
  let start = 0;
  for (let i = 0; i < occurrence; i += 1) {
    index = content.indexOf(from, start);
    if (index === -1) {
      throw new Error(`Needle not found for replace: ${from}`);
    }
    start = index + from.length;
  }
  return `${content.slice(0, index)}${to}${content.slice(index + from.length)}`;
}

function insertAfterNth(content, needle, insertion, occurrence = 1) {
  let index = -1;
  let start = 0;
  for (let i = 0; i < occurrence; i += 1) {
    index = content.indexOf(needle, start);
    if (index === -1) {
      throw new Error(`Needle not found for insert: ${needle}`);
    }
    start = index + needle.length;
  }
  const at = index + needle.length;
  return `${content.slice(0, at)}${insertion}${content.slice(at)}`;
}

function applyRegression(name) {
  const steps = regressions[name];
  if (!steps) {
    throw new Error(`Unknown regression ${name}`);
  }
  for (const step of steps) {
    let content = readRepoFile(step.file);
    if (step.replace) {
      const [from, to] = step.replace;
      content = replaceNth(content, from, to, step.occurrence ?? 1);
    } else if (step.insertAfter) {
      content = insertAfterNth(content, step.needle, step.insertAfter, step.occurrence ?? 1);
    }
    writeRepoFile(step.file, content);
  }
}

function revertAll() {
  const files = new Set();
  for (const steps of Object.values(regressions)) {
    for (const step of steps) {
      files.add(step.file);
    }
  }
  if (files.size === 0) {
    return;
  }
  execSync(`git checkout -- ${[...files].join(' ')}`, { cwd: rootDir, stdio: 'inherit' });
}

const [command, name] = process.argv.slice(2);
if (command === 'apply') {
  if (!name) {
    throw new Error('Usage: bun scripts/maestro/break-fix-regression.mjs apply <case>');
  }
  applyRegression(name);
  process.stdout.write(`Applied regression: ${name}\n`);
} else if (command === 'revert') {
  revertAll();
  process.stdout.write('Reverted native break-fix regressions\n');
} else if (command === 'list') {
  process.stdout.write(`${Object.keys(regressions).join('\n')}\n`);
} else {
  throw new Error('Usage: bun scripts/maestro/break-fix-regression.mjs <apply|revert|list> [case]');
}