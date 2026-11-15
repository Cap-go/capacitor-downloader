import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MAESTRO_E2E_FLOWS } from './flows.mjs';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const tails = {
  'foreground-complete': `
- extendedWaitUntil:
    visible: '.*Marker: foreground-complete:success.*'
    timeout: 120000`,
  'network-drop-resume': `
- extendedWaitUntil:
    visible: '.*Marker: network-drop-resume:success.*'
    timeout: 180000`,
  'error-bad-url': `
- extendedWaitUntil:
    visible: '.*Marker: error-bad-url:success.*'
    timeout: 90000`,
  'error-404': `
- extendedWaitUntil:
    visible: '.*Marker: error-404:success.*'
    timeout: 90000`,
  'error-5xx': `
- extendedWaitUntil:
    visible: '.*Marker: error-5xx:success.*'
    timeout: 90000`,
  'error-unwritable-destination': `
- extendedWaitUntil:
    visible: '.*Marker: error-unwritable-destination:success.*'
    timeout: 90000`,
  'cancel-cleanup': `
- extendedWaitUntil:
    visible: '.*Marker: cancel-cleanup:success.*'
    timeout: 120000`,
  'parallel-downloads': `
- extendedWaitUntil:
    visible: '.*Marker: parallel-downloads:success.*'
    timeout: 180000`,
  'completion-once': `
- extendedWaitUntil:
    visible: '.*Marker: completion-once:success.*'
    timeout: 120000`,
  'background-complete': `
- extendedWaitUntil:
    visible: '.*PHASE:background-complete:downloading.*'
    timeout: 60000
- pressKey: Home
- extendedWaitUntil:
    visible: '.*'
    timeout: 10000
- launchApp:
    clearState: false
- extendedWaitUntil:
    visible: '.*Marker: background-complete:success.*'
    timeout: 240000`,
  'kill-relaunch-resume': `
- extendedWaitUntil:
    visible: '.*PHASE:kill-relaunch-resume:downloading.*'
    timeout: 60000
- stopApp
- launchApp:
    clearState: false
- extendedWaitUntil:
    visible: '.*Marker: kill-relaunch-resume:success.*'
    timeout: 240000`,
  'low-memory-kill': `
- extendedWaitUntil:
    visible: '.*PHASE:low-memory-kill:downloading.*'
    timeout: 60000
- stopApp
- launchApp:
    clearState: false
- extendedWaitUntil:
    visible: '.*Marker: low-memory-kill:success.*'
    timeout: 240000`,
};

for (const flowId of MAESTRO_E2E_FLOWS) {
  const flowPath = path.join(rootDir, '.maestro/flows', `${flowId}.yaml`);
  const base = readFileSync(flowPath, 'utf8').trimEnd();
  const tail = tails[flowId] ?? '';
  writeFileSync(flowPath, `${base}${tail}\n`);
}