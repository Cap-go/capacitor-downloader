import { App } from '@capacitor/app';
import { Capacitor } from '@capacitor/core';
import { CapacitorDownloader } from '@capgo/capacitor-downloader';

const plugin = CapacitorDownloader;
const serverUrl = import.meta.env.VITE_CAPGO_SERVER_URL ?? 'http://127.0.0.1:3192';
const storagePrefix = '__capgo_dl_maestro_';
const completionCounts = new Map();

function requireElement(id) {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`Expected #${id}`);
  }
  return element;
}

const harnessReady = requireElement('harness-ready');
const e2eSummary = requireElement('e2e-summary');
const e2eLog = requireElement('e2e-log');
const flowButtons = requireElement('e2e-flow-buttons');

function appendLog(line) {
  const stamp = new Date().toISOString();
  e2eLog.textContent = `${e2eLog.textContent}\n${stamp} ${line}`.trim();
}

function setSummary(text) {
  e2eSummary.textContent = text;
  appendLog(text);
}

function setMarker(flowId, ok, detail = '') {
  const status = ok ? 'success' : 'failure';
  const suffix = detail ? `:${detail}` : '';
  setSummary(`Marker: ${flowId}:${status}${suffix}`);
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function fileUrl(path) {
  return `${serverUrl.replace(/\/$/, '')}${path}`;
}

const ANDROID_DOWNLOAD_MANAGER_STATUS = {
  1: 'PENDING',
  2: 'RUNNING',
  4: 'PAUSED',
  8: 'DONE',
  16: 'ERROR',
};

function normalizeDownloadTask(raw) {
  if (!raw) {
    return { state: 'RUNNING', progress: 0 };
  }
  if (typeof raw.state === 'string') {
    return { state: raw.state, progress: Number(raw.progress) || 0 };
  }
  const statusCode = typeof raw.status === 'number' ? raw.status : undefined;
  if (statusCode !== undefined) {
    const total = Number(raw.bytesTotal) || 0;
    const downloaded = Number(raw.bytesDownloaded) || 0;
    const progress =
      total > 0 ? Math.min(1, downloaded / total) : statusCode === 8 ? 1 : Number(raw.progress) || 0;
    const state = ANDROID_DOWNLOAD_MANAGER_STATUS[statusCode] ?? 'RUNNING';
    return { state, progress };
  }
  return { state: 'RUNNING', progress: Number(raw.progress) || 0 };
}

async function readDownloadStatus(id) {
  try {
    return normalizeDownloadTask(await plugin.checkStatus({ id }));
  } catch (error) {
    if ((completionCounts.get(id) ?? 0) > 0) {
      return { state: 'DONE', progress: 1 };
    }
    const message = String(error?.message ?? error);
    if (/not found/i.test(message)) {
      return { state: 'ERROR', progress: 0 };
    }
    throw error;
  }
}

async function waitForTerminal(id, timeoutMs = 120_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    let status = await readDownloadStatus(id);
    if ((completionCounts.get(id) ?? 0) > 0 && status.state !== 'ERROR') {
      status = { state: 'DONE', progress: 1 };
    }
    appendLog(`STATE:${id}:${status.state}:${status.progress}`);
    if (status.state === 'DONE' || status.state === 'ERROR') {
      return status;
    }
    await sleep(750);
  }
  if ((completionCounts.get(id) ?? 0) > 0) {
    return { state: 'DONE', progress: 1 };
  }
  throw new Error(`Timed out waiting for terminal state on ${id}`);
}

async function waitForDone(id, timeoutMs = 120_000) {
  const status = await waitForTerminal(id, timeoutMs);
  if (status.state !== 'DONE') {
    throw new Error(`Expected DONE for ${id}, got ${status.state}`);
  }
  return status;
}

function trackCompletions() {
  plugin.addListener('downloadCompleted', (payload) => {
    const next = (completionCounts.get(payload.id) ?? 0) + 1;
    completionCounts.set(payload.id, next);
    setSummary(`EVENT:downloadCompleted:id=${payload.id}:count=${next}`);
  });
  plugin.addListener('downloadFailed', (payload) => {
    setSummary(`EVENT:downloadFailed:id=${payload.id}:error=${payload.error}`);
  });
  plugin.addListener('downloadProgress', (payload) => {
    if (payload.progress >= 0.99) {
      appendLog(`PROGRESS:${payload.id}:${payload.progress}`);
    }
  });
}

function persistPending(flowId, payload) {
  localStorage.setItem(`${storagePrefix}pending_flow`, flowId);
  localStorage.setItem(`${storagePrefix}pending_payload`, JSON.stringify(payload));
}

function readPending() {
  const flowId = localStorage.getItem(`${storagePrefix}pending_flow`);
  const raw = localStorage.getItem(`${storagePrefix}pending_payload`);
  if (!flowId || !raw) {
    return null;
  }
  return { flowId, payload: JSON.parse(raw) };
}

function clearPending() {
  localStorage.removeItem(`${storagePrefix}pending_flow`);
  localStorage.removeItem(`${storagePrefix}pending_payload`);
}

const flows = {
  async 'foreground-complete'() {
    const id = 'fg-complete';
    await plugin.download({
      id,
      url: fileUrl('/bytes/65536'),
      destination: 'downloads/maestro-fg.bin',
      androidHttpEngine: 'auto',
      notification: 'hidden',
    });
    await waitForDone(id, 90_000);
    setMarker('foreground-complete', true);
  },

  async 'background-complete'() {
    const id = 'bg-complete';
    await plugin.download({
      id,
      url: fileUrl('/slow/98304'),
      destination: 'downloads/maestro-bg.bin',
      androidHttpEngine: 'downloadManager',
      notification: 'hidden',
    });
    persistPending('background-complete', { id });
    setSummary(`PHASE:background-complete:downloading:id=${id}`);
  },

  async 'kill-relaunch-resume'() {
    const id = 'kill-resume';
    await plugin.download({
      id,
      url: fileUrl('/slow/131072'),
      destination: 'downloads/maestro-kill.bin',
      androidHttpEngine: 'downloadManager',
      notification: 'hidden',
    });
    persistPending('kill-relaunch-resume', { id });
    setSummary(`PHASE:kill-relaunch-resume:downloading:id=${id}`);
  },

  async 'low-memory-kill'() {
    const id = 'low-mem';
    await plugin.download({
      id,
      url: fileUrl('/slow/131072'),
      destination: 'downloads/maestro-lowmem.bin',
      androidHttpEngine: 'downloadManager',
      notification: 'hidden',
    });
    persistPending('low-memory-kill', { id });
    setSummary(`PHASE:low-memory-kill:downloading:id=${id}`);
  },

  async 'network-drop-resume'() {
    const id = 'net-drop';
    const attemptKey = `attempt-${Date.now()}`;
    await plugin.download({
      id,
      url: fileUrl(`/recoverable/131072?attemptKey=${encodeURIComponent(attemptKey)}`),
      destination: 'cache/maestro-net.bin',
      androidHttpEngine: 'auto',
      notification: 'hidden',
    });
    await waitForDone(id, 180_000);
    setMarker('network-drop-resume', true);
  },

  async 'error-bad-url'() {
    const id = 'err-bad-url';
    try {
      await plugin.download({
        id,
        url: 'http://192.0.2.1:9/missing.bin',
        destination: 'cache/maestro-bad-url.bin',
        androidHttpEngine: 'auto',
        notification: 'hidden',
      });
      await waitForTerminal(id, 30_000);
    } catch {
      setMarker('error-bad-url', true, 'rejected');
      return;
    }
    const status = await readDownloadStatus(id);
    if (status.state === 'ERROR') {
      setMarker('error-bad-url', true, 'status-error');
      return;
    }
    throw new Error('Expected bad URL to fail');
  },

  async 'error-404'() {
    const id = 'err-404';
    await plugin.download({
      id,
      url: fileUrl('/status/404'),
      destination: 'cache/maestro-404.bin',
      androidHttpEngine: 'auto',
      notification: 'hidden',
    });
    const status = await waitForTerminal(id, 60_000);
    if (status.state !== 'ERROR') {
      throw new Error(`Expected ERROR for 404, got ${status.state}`);
    }
    setMarker('error-404', true, 'HTTP 404');
  },

  async 'error-5xx'() {
    const id = 'err-500';
    await plugin.download({
      id,
      url: fileUrl('/status/500'),
      destination: 'cache/maestro-500.bin',
      androidHttpEngine: 'auto',
      notification: 'hidden',
    });
    const status = await waitForTerminal(id, 60_000);
    if (status.state !== 'ERROR') {
      throw new Error(`Expected ERROR for 5xx, got ${status.state}`);
    }
    setMarker('error-5xx', true, 'HTTP 500');
  },

  async 'error-unwritable-destination'() {
    const id = 'err-write';
    try {
      await plugin.download({
        id,
        url: fileUrl('/bytes/1024'),
        destination: '   ',
        androidHttpEngine: 'auto',
        notification: 'hidden',
      });
    } catch (error) {
      setMarker('error-unwritable-destination', true, String(error?.message ?? error));
      return;
    }
    const status = await waitForTerminal(id, 30_000);
    if (status.state === 'ERROR') {
      setMarker('error-unwritable-destination', true, 'status-error');
      return;
    }
    throw new Error('Expected unwritable destination to fail');
  },

  async 'cancel-cleanup'() {
    const id = 'cancel-me';
    await plugin.download({
      id,
      url: fileUrl('/slow/524288'),
      destination: 'cache/maestro-cancel.bin',
      androidHttpEngine: 'auto',
      notification: 'hidden',
    });
    await sleep(1_500);
    await plugin.stop({ id });
    const status = await readDownloadStatus(id);
    setSummary(`STATE:${id}:${status.state}:${status.progress}`);
    if (status.state === 'DONE') {
      throw new Error('Download still DONE after stop');
    }
    setMarker('cancel-cleanup', true, status.state);
  },

  async 'parallel-downloads'() {
    const specs = [
      { id: 'parallel-a', destination: 'cache/maestro-pa.bin', bytes: 32768 },
      { id: 'parallel-b', destination: 'cache/maestro-pb.bin', bytes: 49152 },
      { id: 'parallel-c', destination: 'cache/maestro-pc.bin', bytes: 40960 },
    ];
    await Promise.all(
      specs.map((spec) =>
        plugin.download({
          id: spec.id,
          url: fileUrl(`/bytes/${spec.bytes}`),
          destination: spec.destination,
          androidHttpEngine: 'auto',
          notification: 'hidden',
        }),
      ),
    );
    for (const spec of specs) {
      await waitForDone(spec.id, 120_000);
      setSummary(`EVENT:downloadCompleted:id=${spec.id}:count=1`);
    }
    setMarker('parallel-downloads', true);
  },

  async 'completion-once'() {
    const id = 'once-only';
    completionCounts.set(id, 0);
    await plugin.download({
      id,
      url: fileUrl('/bytes/32768'),
      destination: 'cache/maestro-once.bin',
      androidHttpEngine: 'auto',
      notification: 'hidden',
    });
    await waitForDone(id, 90_000);
    await sleep(2_000);
    const count = completionCounts.get(id) ?? 0;
  setSummary(`ASSERT:completion-count:id=${id}:count=${count}`);
    if (count !== 1) {
      throw new Error(`Expected exactly one completion event, got ${count}`);
    }
    setMarker('completion-once', true, `count=${count}`);
  },
};

async function resumePendingFlowIfNeeded() {
  const pending = readPending();
  if (!pending) {
    return;
  }
  const { flowId, payload } = pending;
  if (!payload?.id) {
    return;
  }
  const status = await waitForDone(payload.id, 240_000);
  if (status.state !== 'DONE') {
    throw new Error(`Pending flow ${flowId} failed with ${status.state}`);
  }
  clearPending();
  setMarker(flowId, true, 'resumed');
}

async function runFlow(flowId) {
  appendLog(`RUN:${flowId}`);
  const runner = flows[flowId];
  if (!runner) {
    throw new Error(`Unknown flow ${flowId}`);
  }
  await runner();
}

function installFlowButtons() {
  const flowIds = Object.keys(flows);
  flowButtons.innerHTML = '';
  for (const flowId of flowIds) {
    const button = document.createElement('button');
    button.type = 'button';
    button.id = `e2e-flow-${flowId}`;
    button.setAttribute('data-testid', `e2e-flow-${flowId}`);
    button.textContent = flowId;
    button.addEventListener('click', async () => {
      try {
        await runFlow(flowId);
      } catch (error) {
        setMarker(flowId, false, String(error?.message ?? error));
      }
    });
    flowButtons.appendChild(button);
  }
}

export async function initMaestroHarness() {
  harnessReady.textContent = 'Harness: booting';

  installFlowButtons();
  harnessReady.textContent = 'Harness: ready';
  setSummary('Harness: ready');
  trackCompletions();

  await resumePendingFlowIfNeeded();

  App.addListener('appStateChange', (state) => {
    appendLog(`APP:${state.isActive ? 'active' : 'background'}`);
    if (state.isActive) {
      resumePendingFlowIfNeeded().catch((error) => {
        setSummary(`APP:resume-error:${error?.message ?? error}`);
      });
    }
  });
}