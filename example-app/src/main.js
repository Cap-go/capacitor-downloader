
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
              inputs: [{ name: 'id', label: 'Download id', type: 'text', value: 'example-download' }, { name: 'url', label: 'File URL', type: 'text', value: 'https://ipv4.download.thinkbroadband.com/200MB.zip' }, { name: 'destination', label: 'Destination path', type: 'text', value: 'downloads/sample.zip' }],
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
              inputs: [{ name: 'id', label: 'Download id', type: 'text', placeholder: 'Reuse last id automatically' }],
              run: async (values) => {
                const id = values.id || state.lastDownloadId;
if (!id) {
  throw new Error('Provide a download id first.');
}
const status = await plugin.checkStatus(id);
return status;
              },
            },
{
              id: 'pause-download',
              label: 'Pause download',
              description: 'Pauses a running download (Android).',
              inputs: [{ name: 'id', label: 'Download id', type: 'text', placeholder: 'Reuse last id automatically' }],
              run: async (values) => {
                const id = values.id || state.lastDownloadId;
if (!id) {
  throw new Error('Provide a download id first.');
}
await plugin.pause(id);
return `Pause requested for ${id}.`;
              },
            },
{
              id: 'resume-download',
              label: 'Resume download',
              description: 'Resumes a paused download (Android).',
              inputs: [{ name: 'id', label: 'Download id', type: 'text', placeholder: 'Reuse last id automatically' }],
              run: async (values) => {
                const id = values.id || state.lastDownloadId;
if (!id) {
  throw new Error('Provide a download id first.');
}
await plugin.resume(id);
return `Resume requested for ${id}.`;
              },
            },
{
              id: 'stop-download',
              label: 'Stop download',
              description: 'Stops a download task.',
              inputs: [{ name: 'id', label: 'Download id', type: 'text', placeholder: 'Reuse last id automatically', value: 'example-download' }],
              run: async (values) => {
                const id = values.id || state.lastDownloadId;
if (!id) {
  throw new Error('Provide a download id first.');
}
await plugin.stop(id);
return `Stop requested for ${id}.`;
              },
            },
{
              id: 'get-file-info',
              label: 'Get file info',
              description: 'Reads metadata for a downloaded file.',
              inputs: [{ name: 'path', label: 'Absolute file path', type: 'text', placeholder: '/storage/emulated/0/Download/sample.zip' }],
              run: async (values) => {
                if (!values.path) {
  throw new Error('Provide a file path.');
}
const info = await plugin.getFileInfo(values.path);
return info;
              },
            }
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

populateActions();
