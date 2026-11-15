import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MAESTRO_E2E_FLOWS } from './flows.mjs';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const tails = {
  'foreground-complete': `    timeout: 300000`,
  'network-drop-resume': `    timeout: 180000`,
  'error-bad-url': `    timeout: 90000`,
  'error-404': `    timeout: 90000`,
  'error-5xx': `    timeout: 90000`,
  'error-unwritable-destination': `    timeout: 90000`,
  'cancel-cleanup': `    timeout: 120000`,
  'parallel-downloads': `    timeout: 180000`,
  'completion-once': `    timeout: 120000`,
};

const multiStep = {
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
  const markerTail = multiStep[flowId]
    ? multiStep[flowId]
    : `
- extendedWaitUntil:
    visible: '.*Marker: ${flowId}:success.*'
${tails[flowId] ?? '    timeout: 120000'}`;

  const content = `appId: app.capgo.downloader
---
- runFlow: ../helpers/launch-harness.yaml
- scrollUntilVisible:
    element:
      text: ${flowId}
    direction: DOWN
    timeout: 60000
    centerElement: true
- tapOn:
    text: ${flowId}
    retryTapIfNoChange: true${markerTail}
`;

  writeFileSync(path.join(rootDir, '.maestro/flows', `${flowId}.yaml`), content);
}