import { CapacitorUpdater } from '@capgo/capacitor-updater';
import { Capacitor } from '@capacitor/core';
import { Directory, Filesystem } from '@capacitor/filesystem';

import './style.css';
import { CapacitorDownloader } from '@capgo/capacitor-downloader';

const plugin = CapacitorDownloader;
const state = {};
state.lastDownloadId = undefined;

const actions = [
  {
    id: 'start-download',
    label: 'Start download',
    description: 'Starts a background download (native platforms).',
    inputs: [
      { name: 'id', label: 'Download id', type: 'text', value: 'example-download' },
      {
        name: 'url',
        label: 'File URL',
        type: 'text',
        value: 'https://ipv4.download.thinkbroadband.com/200MB.zip',
      },
      {
        name: 'destination',
        label: 'Destination path',
        type: 'text',
        value: 'downloads/sample.zip',
      },
    ],
    run: async (values) => {
      const id = values.id || 'example-download';
      const url = values.url || '';
      if (!url) {
        throw new Error('Provide a URL to download.');
      }
      const destination = values.destination || 'downloads/sample.zip';
      const task = await plugin.download({ id, url, destination });
      state.lastDownloadId = task.id;
      return task;
    },
  },
  {
    id: 'check-status',
    label: 'Check status',
    description: 'Queries progress for an existing download id.',
    inputs: [
      {
        name: 'id',
        label: 'Download id',
        type: 'text',
        placeholder: 'Reuse last id automatically',
      },
    ],
    run: async (values) => {
      const id = values.id || state.lastDownloadId;
      if (!id) {
        throw new Error('Provide a download id first.');
      }
      const status = await plugin.checkStatus({ id });
      return status;
    },
  },
  {
    id: 'pause-download',
    label: 'Pause download',
    description: 'Pauses a running download (Android).',
    inputs: [
      {
        name: 'id',
        label: 'Download id',
        type: 'text',
        placeholder: 'Reuse last id automatically',
      },
    ],
    run: async (values) => {
      const id = values.id || state.lastDownloadId;
      if (!id) {
        throw new Error('Provide a download id first.');
      }
      await plugin.pause({ id });
      return `Pause requested for ${id}.`;
    },
  },
  {
    id: 'resume-download',
    label: 'Resume download',
    description: 'Resumes a paused download (Android).',
    inputs: [
      {
        name: 'id',
        label: 'Download id',
        type: 'text',
        placeholder: 'Reuse last id automatically',
      },
    ],
    run: async (values) => {
      const id = values.id || state.lastDownloadId;
      if (!id) {
        throw new Error('Provide a download id first.');
      }
      await plugin.resume({ id });
      return `Resume requested for ${id}.`;
    },
  },
  {
    id: 'stop-download',
    label: 'Stop download',
    description: 'Stops a download task.',
    inputs: [
      {
        name: 'id',
        label: 'Download id',
        type: 'text',
        placeholder: 'Reuse last id automatically',
        value: 'example-download',
      },
    ],
    run: async (values) => {
      const id = values.id || state.lastDownloadId;
      if (!id) {
        throw new Error('Provide a download id first.');
      }
      await plugin.stop({ id });
      return `Stop requested for ${id}.`;
    },
  },
  {
    id: 'get-file-info',
    label: 'Get file info',
    description: 'Reads metadata for a downloaded file.',
    inputs: [
      {
        name: 'path',
        label: 'Absolute file path',
        type: 'text',
        placeholder: '/storage/emulated/0/Download/sample.zip',
      },
    ],
    run: async (values) => {
      if (!values.path) {
        throw new Error('Provide a file path.');
      }
      const info = await plugin.getFileInfo({ path: values.path });
      return info;
    },
  },
];

const actionSelect = document.getElementById('action-select');
const formContainer = document.getElementById('action-form');
const descriptionBox = document.getElementById('action-description');
const runButton = document.getElementById('run-action');
const output = document.getElementById('plugin-output');
const maestroStatus = document.getElementById('maestro-status');
const maestroHarnessDiagnostics = [];
const MAESTRO_STEP_TIMEOUT_MS = 15_000;
const MAESTRO_CHILD_CHECKSTATUS_POLL_MS = 5_000;

function buildForm(action) {
  formContainer.innerHTML = '';
  if (!action.inputs || !action.inputs.length) {
    const note = document.createElement('p');
    note.className = 'no-input-note';
    note.textContent = 'This action does not require any inputs.';
    formContainer.appendChild(note);
    return;
  }
  action.inputs.forEach((input) => {
    const fieldWrapper = document.createElement('div');
    fieldWrapper.className = input.type === 'checkbox' ? 'form-field inline' : 'form-field';

    const label = document.createElement('label');
    label.textContent = input.label;
    label.htmlFor = input.name;

    let field;
    if (input.type === 'checkbox') {
      field = document.createElement('input');
      field.type = 'checkbox';
      field.checked = Boolean(input.value);
    } else {
      field = document.createElement('input');
      field.type = input.type || 'text';
      if (input.value !== undefined) {
        field.value = input.value;
      }
      if (input.placeholder) {
        field.placeholder = input.placeholder;
      }
    }
    field.id = input.name;
    field.name = input.name;

    fieldWrapper.appendChild(label);
    fieldWrapper.appendChild(field);
    formContainer.appendChild(fieldWrapper);
  });
}

function getFormValues(action) {
  const values = {};
  if (!action.inputs) {
    return values;
  }
  action.inputs.forEach((input) => {
    const field = document.getElementById(input.name);
    if (!field) {
      return;
    }
    switch (input.type) {
      case 'checkbox': {
        values[input.name] = field.checked;
        break;
      }
      default: {
        values[input.name] = field.value;
      }
    }
  });
  return values;
}

function setAction(action) {
  descriptionBox.textContent = action.description || '';
  buildForm(action);
  output.textContent = 'Ready to run the selected action.';
}

function populateActions() {
  actionSelect.innerHTML = '';
  actions.forEach((action) => {
    const option = document.createElement('option');
    option.value = action.id;
    option.textContent = action.label;
    actionSelect.appendChild(option);
  });
  setAction(actions[0]);
}

actionSelect.addEventListener('change', () => {
  const action = actions.find((item) => item.id === actionSelect.value);
  if (action) {
    setAction(action);
  }
});

runButton.addEventListener('click', async () => {
  const action = actions.find((item) => item.id === actionSelect.value);
  if (!action) return;
  const values = getFormValues(action);
  try {
    const result = await action.run(values);
    if (result === undefined) {
      output.textContent = 'Action completed.';
    } else if (typeof result === 'string') {
      output.textContent = result;
    } else {
      output.textContent = JSON.stringify(result, null, 2);
    }
  } catch (error) {
    output.textContent = `Error: ${pluginErrorMessage(error)}`;
  }
});

const MAESTRO_SMALL_FILE_URL =
  'https://raw.githubusercontent.com/Cap-go/capacitor-downloader/main/assets/github-social-preview.png';

function pluginErrorMessage(error) {
  if (!error) {
    return 'unknown error';
  }
  if (typeof error === 'string') {
    return error;
  }
  const code = error.code ?? error.errorCode;
  const message =
    error.message ||
    error.errorMessage ||
    (typeof error.error === 'string' ? error.error : undefined);
  const parts = [];
  if (message) {
    parts.push(message);
  }
  if (code) {
    parts.push(`code=${code}`);
  }
  if (parts.length) {
    return parts.join(' | ');
  }
  try {
    const serialized = JSON.stringify(error);
    if (serialized && serialized !== '{}') {
      return serialized;
    }
  } catch {
    // Ignore circular structures.
  }
  return 'unknown error';
}

function enrichCapacitorError(scope, error) {
  const details = pluginErrorMessage(error);
  if (error instanceof Error && error.message && error.message !== 'unknown error') {
    if (!error.message.includes(scope)) {
      error.message = `${scope}: ${error.message}`;
    }
    return error;
  }
  const wrapped = new Error(`${scope}: ${details}`);
  if (error && typeof error === 'object' && (error.code ?? error.errorCode)) {
    wrapped.code = error.code ?? error.errorCode;
  }
  return wrapped;
}

async function invokeCapacitor(scope, fn) {
  try {
    return await fn();
  } catch (error) {
    throw enrichCapacitorError(scope, error);
  }
}

function resetMaestroHarnessDiagnostics() {
  maestroHarnessDiagnostics.length = 0;
}

function setMaestroHarnessReady() {
  if (!maestroStatus) {
    return;
  }
  maestroStatus.textContent = 'maestroReady';
  maestroStatus.dataset.maestroPhase = 'ready';
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      maestroStatus.textContent = 'maestroReady\nmaestroLayoutSettled';
      maestroStatus.dataset.maestroPhase = 'layoutSettled';
    });
  });
}

function markMaestroHarnessRunning(flowId) {
  if (!maestroStatus) {
    return;
  }
  maestroStatus.textContent = `maestroRunning: ${flowId}`;
  maestroStatus.dataset.maestroPhase = 'running';
}

async function withMaestroStepTimeout(stepName, fn) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const message = `stuck at: ${stepName}`;
      appendMaestroHarnessDiagnostic(message);
      reject(new Error(message));
    }, MAESTRO_STEP_TIMEOUT_MS);
  });
  try {
    return await Promise.race([Promise.resolve().then(fn), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

function isMaestroStopNotFoundError(error) {
  const message = pluginErrorMessage(error).toLowerCase();
  return message.includes('task not found') || message.includes('download not found');
}

function appendMaestroHarnessDiagnostic(message) {
  maestroHarnessDiagnostics.push(message);
  output.textContent = maestroHarnessDiagnostics.join('\n');
  output.dataset.maestroOutcome = 'error';
}

function formatMaestroDownloadFailedEvent(event) {
  const parts = [];
  if (event?.error) {
    parts.push(event.error);
  }
  if (event?.errorDomain) {
    parts.push(`domain=${event.errorDomain}`);
  }
  if (typeof event?.errorCode === 'number') {
    parts.push(`code=${event.errorCode}`);
  }
  if (typeof event?.fileIndex === 'number') {
    parts.push(`fileIndex=${event.fileIndex}`);
  }
  if (event?.id) {
    parts.push(`id=${event.id}`);
  }
  return parts.length ? parts.join(' | ') : 'downloadFailed';
}

function setOutputFromMaestro(result, error) {
  delete output.dataset.maestroOutcome;
  if (error) {
    const diagnosticLines = maestroHarnessDiagnostics.length ? `${maestroHarnessDiagnostics.join('\n')}\n` : '';
    output.textContent = `${diagnosticLines}Error: ${pluginErrorMessage(error)}`;
    output.dataset.maestroOutcome = 'error';
    return;
  }
  if (result === undefined) {
    output.textContent = 'Action completed.';
    output.dataset.maestroOutcome = 'ok';
    return;
  }
  if (typeof result === 'string') {
    output.textContent = result;
    output.dataset.maestroOutcome = 'ok';
    return;
  }
  output.textContent = JSON.stringify(result, null, 2);
  output.dataset.maestroOutcome = 'ok';
}

async function removeMaestroListeners(handles) {
  const failures = [];
  for (const handle of handles) {
    try {
      await handle.remove();
    } catch (error) {
      const msg = pluginErrorMessage(error);
      failures.push(msg);
      appendMaestroHarnessDiagnostic(`removeMaestroListeners: ${msg}`);
    }
  }
  if (failures.length) {
    throw new Error(`removeMaestroListeners: ${failures.join('; ')}`);
  }
}

async function resolveFileInfoPath(destination) {
  if (!destination?.startsWith('files/')) {
    throw new Error(`Unsupported maestro destination: ${destination}`);
  }
  const relative = destination.slice('files/'.length);
  if (Capacitor.getPlatform() === 'ios') {
    const { uri } = await invokeCapacitor('Filesystem.getUri', () =>
      Filesystem.getUri({ directory: Directory.Documents, path: `files/${relative}` }),
    );
    const path = decodeURIComponent(uri.replace(/^file:\/\//, ''));
    return path;
  }
  const { uri } = await invokeCapacitor('Filesystem.getUri', () =>
    Filesystem.getUri({ directory: Directory.Data, path: relative }),
  );
  return uri;
}

async function fillSizesOnDisk(destinations, fileStates) {
  for (let index = 0; index < destinations.length; index += 1) {
    const path = await resolveFileInfoPath(destinations[index]);
    const info = await invokeCapacitor('getFileInfo', () => plugin.getFileInfo({ path }));
    const size = info.size ?? 0;
    if (size <= 0) {
      throw new Error(`File missing or empty on disk: ${destinations[index]}`);
    }
    fileStates[index].sizeOnDisk = size;
  }
}

async function clearMaestroBatch(batchId) {
  try {
    await invokeCapacitor(`stop(${batchId})`, () => plugin.stop({ id: batchId }));
  } catch (error) {
    if (isMaestroStopNotFoundError(error)) {
      return;
    }
    appendMaestroHarnessDiagnostic(`clearMaestroBatch stop(${batchId}): ${pluginErrorMessage(error)}`);
    throw error;
  }
}

function maestroChildTaskId(batchId, fileIndex, batchGeneration, childTaskIds) {
  if (Array.isArray(childTaskIds) && childTaskIds[fileIndex]) {
    return childTaskIds[fileIndex];
  }
  if (Capacitor.getPlatform() === 'ios') {
    if (batchGeneration == null) {
      return null;
    }
    return `${batchId}#${batchGeneration}:${fileIndex}`;
  }
  return `${batchId}#${fileIndex}`;
}

function applyMaestroBatchEnqueueMetadata(task, tracking) {
  if (typeof task?.batchGeneration === 'number') {
    tracking.setBatchGeneration(task.batchGeneration);
  }
  if (Array.isArray(task?.childTaskIds) && task.childTaskIds.length) {
    tracking.setChildTaskIds(task.childTaskIds);
  }
}

function isMaestroChildCheckStatusCompleted(status) {
  if (status.state === 'DONE') {
    return true;
  }
  // DownloadManager STATUS_SUCCESSFUL (OkHttp maps completed transfers here).
  return status.status === 8;
}

function maestroChildCheckStatusLabel(status) {
  return isMaestroChildCheckStatusCompleted(status) ? 'COMPLETED' : status.state ?? `status=${status.status}`;
}

async function startMaestroBatchTracking(batchId, fileCount, timeoutMs = 120_000) {
  let batchGeneration = null;
  let childTaskIds = null;
  const checkStatusInFlight = Array.from({ length: fileCount }, () => null);
  const fileStates = Array.from({ length: fileCount }, () => ({
    done: false,
    bytesWritten: 0,
    bytesTotal: 0,
    sizeOnDisk: 0,
    childTaskId: null,
    checkStatusState: null,
    checkStatusLabel: null,
    checkStatusCompleted: false,
    checkStatusSource: null,
  }));
  let downloadCompleted = false;
  let failedEvent;
  let verificationError;
  const handles = [];

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  handles.push(
    await plugin.addListener('downloadFailed', (event) => {
      if (event.id === batchId || (typeof event.id === 'string' && event.id.startsWith(`${batchId}#`))) {
        failedEvent = event;
      }
    }),
  );
  handles.push(
    await plugin.addListener('downloadProgress', (event) => {
      if (event.id !== batchId || typeof event.fileIndex !== 'number') {
        return;
      }
      const index = event.fileIndex;
      if (index < 0 || index >= fileCount) {
        return;
      }
      const entry = fileStates[index];
      if (typeof event.bytesWritten === 'number') {
        entry.bytesWritten = event.bytesWritten;
      }
      if (typeof event.bytesTotal === 'number' && event.bytesTotal > 0) {
        entry.bytesTotal = event.bytesTotal;
      }
      if (typeof event.fileProgress === 'number' && event.fileProgress >= 1) {
        entry.done = true;
        queueVerifyChildDoneStateViaCheckStatus(index);
      } else if (entry.bytesTotal > 0 && entry.bytesWritten >= entry.bytesTotal) {
        entry.done = true;
        queueVerifyChildDoneStateViaCheckStatus(index);
      }
    }),
  );
  handles.push(
    await plugin.addListener('downloadCompleted', (event) => {
      if (event.id === batchId) {
        downloadCompleted = true;
        fileStates.forEach((entry) => {
          entry.done = true;
        });
      }
    }),
  );

  const verifyChildDoneStateViaCheckStatus = async (fileIndex) => {
    const entry = fileStates[fileIndex];
    if (entry.checkStatusCompleted) {
      return;
    }
    const metadataDeadline = Date.now() + MAESTRO_CHILD_CHECKSTATUS_POLL_MS;
    let childId;
    while (Date.now() < metadataDeadline) {
      childId = maestroChildTaskId(batchId, fileIndex, batchGeneration, childTaskIds);
      if (childId) {
        break;
      }
      await sleep(50);
    }
    if (!childId) {
      throw new Error(`Missing child task id for file index ${fileIndex}`);
    }
    entry.childTaskId = childId;
    const deadline = Date.now() + MAESTRO_CHILD_CHECKSTATUS_POLL_MS;
    let lastReject;
    while (Date.now() < deadline) {
      try {
        const status = await invokeCapacitor('checkStatus', () => plugin.checkStatus({ id: childId }));
        entry.checkStatusState = status.state ?? null;
        entry.checkStatusLabel = maestroChildCheckStatusLabel(status);
        entry.checkStatusSource = 'checkStatus';
        if (isMaestroChildCheckStatusCompleted(status)) {
          entry.checkStatusCompleted = true;
          entry.done = true;
          return;
        }
        lastReject = new Error(
          `checkStatus(${childId}): not completed (state=${String(status.state)}, status=${String(status.status)})`,
        );
      } catch (error) {
        lastReject = error instanceof Error ? error : new Error(pluginErrorMessage(error));
      }
      await sleep(200);
    }
    throw lastReject ?? new Error(`checkStatus(${childId}): timed out waiting for COMPLETED`);
  };

  const queueVerifyChildDoneStateViaCheckStatus = (fileIndex) => {
    if (checkStatusInFlight[fileIndex]) {
      return checkStatusInFlight[fileIndex];
    }
    const promise = verifyChildDoneStateViaCheckStatus(fileIndex)
      .catch((error) => {
        verificationError = error;
      })
      .finally(() => {
        if (checkStatusInFlight[fileIndex] === promise) {
          checkStatusInFlight[fileIndex] = null;
        }
      });
    checkStatusInFlight[fileIndex] = promise;
    return promise;
  };

  const verifyAllChildDoneStatesViaCheckStatus = async () => {
    for (let index = 0; index < fileCount; index += 1) {
      await verifyChildDoneStateViaCheckStatus(index);
    }
    return true;
  };

  let disposed = false;
  const dispose = async () => {
    if (disposed) {
      return;
    }
    disposed = true;
    await removeMaestroListeners(handles);
  };

  return {
    dispose,
    setBatchGeneration(generation) {
      batchGeneration = generation;
    },
    setChildTaskIds(ids) {
      childTaskIds = ids;
    },
    async waitForCompletion(destinations) {
      const deadline = Date.now() + timeoutMs;
      try {
        while (Date.now() < deadline) {
          if (failedEvent) {
            throw new Error(formatMaestroDownloadFailedEvent(failedEvent));
          }
          if (verificationError) {
            throw verificationError;
          }
          if (downloadCompleted) {
            const allChildrenCompleted = await verifyAllChildDoneStatesViaCheckStatus();
            const allDone = fileStates.every((entry) => entry.done);
            if (!allDone || !allChildrenCompleted) {
              await sleep(250);
              continue;
            }
            await fillSizesOnDisk(destinations, fileStates);
            if (!fileStates.every((entry) => entry.sizeOnDisk > 0)) {
              throw new Error('One or more batch files have zero size on disk');
            }
            return {
              downloadCompleted: true,
              allFilesDone: true,
              allChildrenCompleted: fileStates.every((entry) => entry.checkStatusCompleted),
              files: fileStates,
            };
          }
          await sleep(250);
        }
        throw new Error('Timed out waiting for batch downloadCompleted and per-file completion');
      } finally {
        await dispose();
      }
    },
  };
}

function formatMaestroBatchSuccess(task, completion, files) {
  const allFileSizesVerified = completion.files.every((file) => file.sizeOnDisk > 0);
  const allChildrenCompleted = completion.files.every((file) => file.checkStatusCompleted);
  return {
    maestroHarnessDone: true,
    maestroBatchComplete: true,
    allFileSizesVerified,
    allChildrenCompleted,
    downloadCompleted: completion.downloadCompleted,
    allFilesDone: completion.allFilesDone,
    enqueue: task,
    files: completion.files.map((file, index) => ({
      index,
      destination: files[index].destination,
      done: file.done,
      childTaskId: file.childTaskId,
      checkStatusState: file.checkStatusState,
      checkStatusLabel: file.checkStatusLabel,
      checkStatusCompleted: file.checkStatusCompleted,
      checkStatusSource: file.checkStatusSource,
      bytesWritten: file.bytesWritten,
      bytesTotal: file.bytesTotal,
      sizeOnDisk: file.sizeOnDisk,
    })),
  };
}

async function runMaestroBatchHarness({
  batchId,
  files,
  downloadOptions,
}) {
  output.textContent = '';
  delete output.dataset.maestroOutcome;
  resetMaestroHarnessDiagnostics();
  let tracking;
  try {
    await withMaestroStepTimeout('clearMaestroBatch', () => clearMaestroBatch(batchId));
    tracking = await withMaestroStepTimeout('startMaestroBatchTracking', () =>
      startMaestroBatchTracking(batchId, files.length),
    );
    const task = await withMaestroStepTimeout('download', () =>
      invokeCapacitor('download', () =>
        plugin.download({
          id: batchId,
          notification: 'hidden',
          files,
          ...downloadOptions,
        }),
      ),
    );
    applyMaestroBatchEnqueueMetadata(task, tracking);
    if (
      typeof task?.batchGeneration !== 'number' ||
      !Array.isArray(task?.childTaskIds) ||
      task.childTaskIds.length !== files.length
    ) {
      throw new Error(
        `download() missing batch metadata (batchGeneration=${String(task?.batchGeneration)}, childTaskIds=${JSON.stringify(task?.childTaskIds)})`,
      );
    }
    const completion = await tracking.waitForCompletion(files.map((file) => file.destination));
    setOutputFromMaestro(formatMaestroBatchSuccess(task, completion, files));
  } catch (error) {
    setOutputFromMaestro(undefined, error);
  } finally {
    await tracking?.dispose();
  }
}

async function runMaestroOkHttpBatch() {
  await runMaestroBatchHarness({
    batchId: 'maestro-okhttp-batch',
    files: [
      {
        url: MAESTRO_SMALL_FILE_URL,
        destination: 'files/maestro-a.bin',
      },
      {
        url: MAESTRO_SMALL_FILE_URL,
        destination: 'files/maestro-b.bin',
      },
    ],
    downloadOptions: {
      androidHttpEngine: 'okhttp',
    },
  });
}

async function runMaestroMixedEngineBatch() {
  try {
    const task = await withMaestroStepTimeout('download', () =>
      invokeCapacitor('download', () =>
      plugin.download({
        id: 'maestro-mixed-batch',
        androidHttpEngine: 'auto',
        notification: 'hidden',
        files: [
          {
            url: MAESTRO_SMALL_FILE_URL,
            destination: 'files/maestro-mixed-a.bin',
          },
          {
            url: MAESTRO_SMALL_FILE_URL,
            destination: 'offline/maestro-mixed-b.bin',
          },
        ],
      }),
    ),
    );
    setOutputFromMaestro(task);
  } catch (error) {
    setOutputFromMaestro(undefined, error);
  }
}

async function runMaestroIosBatch() {
  await runMaestroBatchHarness({
    batchId: 'maestro-ios-batch',
    files: [
      {
        url: MAESTRO_SMALL_FILE_URL,
        destination: 'files/maestro-ios-a.bin',
      },
      {
        url: MAESTRO_SMALL_FILE_URL,
        destination: 'files/maestro-ios-b.bin',
      },
    ],
    downloadOptions: {
      iosContinuedProcessing: true,
      title: 'Maestro batch',
      description: 'Multi-file continued processing',
    },
  });
}

async function runMaestroIosBatchFail() {
  try {
    const task = await withMaestroStepTimeout('download', () =>
      invokeCapacitor('download', () =>
      plugin.download({
        id: 'maestro-ios-batch-fail',
        url: 'https://example.com/only-single',
        destination: 'files/maestro-ios-single.bin',
        notification: 'hidden',
        files: [
          {
            url: MAESTRO_SMALL_FILE_URL,
            destination: 'files/maestro-ios-batch-only.bin',
          },
        ],
      }),
    ),
    );
    setOutputFromMaestro(task);
  } catch (error) {
    setOutputFromMaestro(undefined, error);
  }
}

const maestroOkHttpBatch = document.getElementById('maestro-okhttp-batch');
const maestroMixedBatchFail = document.getElementById('maestro-mixed-batch-fail');
const maestroIosBatch = document.getElementById('maestro-ios-batch');
const maestroIosBatchFail = document.getElementById('maestro-ios-batch-fail');
if (maestroOkHttpBatch) {
  maestroOkHttpBatch.addEventListener('click', () => {
    markMaestroHarnessRunning('maestro-okhttp-batch');
    void runMaestroOkHttpBatch();
  });
}
if (maestroMixedBatchFail) {
  maestroMixedBatchFail.addEventListener('click', () => {
    markMaestroHarnessRunning('maestro-mixed-batch');
    void runMaestroMixedEngineBatch();
  });
}
if (maestroIosBatch) {
  maestroIosBatch.addEventListener('click', () => {
    markMaestroHarnessRunning('maestro-ios-batch');
    void runMaestroIosBatch();
  });
}
if (maestroIosBatchFail) {
  maestroIosBatchFail.addEventListener('click', () => {
    markMaestroHarnessRunning('maestro-ios-batch-fail');
    void runMaestroIosBatchFail();
  });
}

populateActions();
setMaestroHarnessReady();

if (Capacitor.isNativePlatform()) {
  CapacitorUpdater.notifyAppReady().catch((error) => {
    console.error('Capgo notifyAppReady failed', error);
  });
}