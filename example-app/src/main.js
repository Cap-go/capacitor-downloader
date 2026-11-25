import { CapacitorUpdater } from '@capgo/capacitor-updater';
import { Capacitor } from '@capacitor/core';

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
    label.htmlFor = `field-${input.name}`;

    let field;
    switch (input.type) {
      case 'textarea': {
        field = document.createElement('textarea');
        field.rows = input.rows || 4;
        break;
      }
      case 'select': {
        field = document.createElement('select');
        (input.options || []).forEach((option) => {
          const opt = document.createElement('option');
          opt.value = option.value;
          opt.textContent = option.label;
          if (input.value !== undefined && option.value === input.value) {
            opt.selected = true;
          }
          field.appendChild(opt);
        });
        break;
      }
      case 'checkbox': {
        field = document.createElement('input');
        field.type = 'checkbox';
        field.checked = Boolean(input.value);
        break;
      }
      case 'number': {
        field = document.createElement('input');
        field.type = 'number';
        if (input.value !== undefined && input.value !== null) {
          field.value = String(input.value);
        }
        break;
      }
      default: {
        field = document.createElement('input');
        field.type = 'text';
        if (input.value !== undefined && input.value !== null) {
          field.value = String(input.value);
        }
      }
    }

    field.id = `field-${input.name}`;
    field.name = input.name;
    field.dataset.type = input.type || 'text';

    if (input.placeholder && input.type !== 'checkbox') {
      field.placeholder = input.placeholder;
    }

    if (input.type === 'checkbox') {
      fieldWrapper.appendChild(field);
      fieldWrapper.appendChild(label);
    } else {
      fieldWrapper.appendChild(label);
      fieldWrapper.appendChild(field);
    }

    formContainer.appendChild(fieldWrapper);
  });
}

function getFormValues(action) {
  const values = {};
  (action.inputs || []).forEach((input) => {
    const field = document.getElementById(`field-${input.name}`);
    if (!field) return;
    switch (input.type) {
      case 'number': {
        values[input.name] = field.value === '' ? null : Number(field.value);
        break;
      }
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
    output.textContent = `Error: ${error?.message ?? error}`;
  }
});

const MAESTRO_SMALL_FILE_URL =
  'https://capgo.app/readme-banner.svg?repo=Cap-go/capacitor-downloader';

function setOutputFromMaestro(result, error) {
  delete output.dataset.maestroOutcome;
  if (error) {
    output.textContent = `Error: ${error?.message ?? error}`;
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
  await Promise.all(handles.map((handle) => handle.remove().catch(() => undefined)));
}

async function startMaestroBatchTracking(batchId, fileCount, timeoutMs = 120_000) {
  const fileStates = Array.from({ length: fileCount }, () => ({
    done: false,
    bytesWritten: 0,
    bytesTotal: 0,
    sizeOnDisk: 0,
  }));
  let downloadCompleted = false;
  let failedEvent;
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
      if (event.fileProgress >= 1) {
        entry.done = true;
      }
    }),
  );
  handles.push(
    await plugin.addListener('downloadCompleted', (event) => {
      if (event.id === batchId) {
        downloadCompleted = true;
      }
    }),
  );

  const verifyChildDoneStates = async () => {
    for (let index = 0; index < fileCount; index += 1) {
      if (fileStates[index].done) {
        continue;
      }
      const childId = `${batchId}#${index}`;
      try {
        const status = await plugin.checkStatus({ id: childId });
        const isDone = status.state === 'DONE' || status.status === 8;
        if (isDone) {
          fileStates[index].done = true;
        }
      } catch {
        // Child may be unregistered after the batch completes.
      }
    }
  };

  return {
    async waitForCompletion() {
      const deadline = Date.now() + timeoutMs;
      try {
        while (Date.now() < deadline) {
          if (failedEvent) {
            throw new Error(failedEvent.error ?? `Download failed for ${failedEvent.id}`);
          }
          if (downloadCompleted) {
            await verifyChildDoneStates();
            const allDone = fileStates.every((entry) => entry.done);
            const allSized = fileStates.every((entry) => entry.bytesTotal > 0 && entry.bytesWritten > 0);
            if (allDone && allSized) {
              for (let index = 0; index < fileStates.length; index += 1) {
                const entry = fileStates[index];
                entry.sizeOnDisk = entry.bytesWritten;
              }
              return { downloadCompleted: true, allFilesDone: true, files: fileStates };
            }
          }
          await sleep(250);
        }
        throw new Error('Timed out waiting for batch downloadCompleted and per-file DONE');
      } finally {
        await removeMaestroListeners(handles);
      }
    },
  };
}

function formatMaestroBatchSuccess(task, completion, files) {
  return {
    maestroBatchComplete: true,
    downloadCompleted: completion.downloadCompleted,
    allFilesDone: completion.allFilesDone,
    enqueue: task,
    files: completion.files.map((file, index) => ({
      index,
      destination: files[index].destination,
      done: file.done,
      bytesWritten: file.bytesWritten,
      bytesTotal: file.bytesTotal,
      sizeOnDisk: file.sizeOnDisk,
    })),
  };
}

async function runMaestroOkHttpBatch() {
  const batchId = 'maestro-okhttp-batch';
  const files = [
    {
      url: MAESTRO_SMALL_FILE_URL,
      destination: 'files/maestro-a.bin',
    },
    {
      url: MAESTRO_SMALL_FILE_URL,
      destination: 'files/maestro-b.bin',
    },
  ];
  output.textContent = '';
  delete output.dataset.maestroOutcome;
  try {
    const tracking = await startMaestroBatchTracking(batchId, files.length);
    const task = await plugin.download({
      id: batchId,
      androidHttpEngine: 'okhttp',
      notification: 'hidden',
      files,
    });
    const completion = await tracking.waitForCompletion();
    setOutputFromMaestro(formatMaestroBatchSuccess(task, completion, files));
  } catch (error) {
    setOutputFromMaestro(undefined, error);
  }
}

async function runMaestroMixedEngineBatch() {
  output.textContent = '';
  delete output.dataset.maestroOutcome;
  try {
    const task = await plugin.download({
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
    });
    setOutputFromMaestro(task);
  } catch (error) {
    setOutputFromMaestro(undefined, error);
  }
}

async function runMaestroIosBatch() {
  const batchId = 'maestro-ios-batch';
  const files = [
    {
      url: MAESTRO_SMALL_FILE_URL,
      destination: 'files/maestro-ios-a.bin',
    },
    {
      url: MAESTRO_SMALL_FILE_URL,
      destination: 'files/maestro-ios-b.bin',
    },
  ];
  output.textContent = '';
  delete output.dataset.maestroOutcome;
  try {
    const tracking = await startMaestroBatchTracking(batchId, files.length);
    const task = await plugin.download({
      id: batchId,
      notification: 'hidden',
      files,
    });
    const completion = await tracking.waitForCompletion();
    setOutputFromMaestro(formatMaestroBatchSuccess(task, completion, files));
  } catch (error) {
    setOutputFromMaestro(undefined, error);
  }
}

async function runMaestroIosBatchFail() {
  output.textContent = '';
  delete output.dataset.maestroOutcome;
  try {
    const task = await plugin.download({
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
    });
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
    void runMaestroOkHttpBatch();
  });
}
if (maestroMixedBatchFail) {
  maestroMixedBatchFail.addEventListener('click', () => {
    void runMaestroMixedEngineBatch();
  });
}
if (maestroIosBatch) {
  maestroIosBatch.addEventListener('click', () => {
    void runMaestroIosBatch();
  });
}
if (maestroIosBatchFail) {
  maestroIosBatchFail.addEventListener('click', () => {
    void runMaestroIosBatchFail();
  });
}

populateActions();

if (Capacitor.isNativePlatform()) {
  CapacitorUpdater.notifyAppReady().catch((error) => {
    console.error('Capgo notifyAppReady failed', error);
  });
}
