import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MAESTRO_E2E_FLOWS } from './flows.mjs';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const markerTimeout = {
  'foreground-complete': '90000',
  'network-drop-resume': '120000',
  'parallel-downloads': '90000',
  'completion-once': '90000',
  'cancel-cleanup': '90000',
  'error-bad-url': '60000',
  'error-404': '90000',
  'error-5xx': '90000',
  'error-unwritable-destination': '60000',
  'batch-error-404': '150000',
  'batch-error-5xx': '150000',
};

const extraAssertions = {
  'completion-once': `
- extendedWaitUntil:
    visible: '.*ASSERT:completion-count:id=once-only:count=1.*'
    timeout: 90000`,
  'cancel-cleanup': `
- extendedWaitUntil:
    visible: '.*STOP:cancel-me:removed=true.*'
    timeout: 90000`,
};

const multiStep = {
  'background-complete': `
- extendedWaitUntil:
    visible: '.*PHASE:background-complete:downloading.*'
    timeout: 45000
- pressKey: Home
- waitForAnimationToEnd:
    timeout: 3000
- launchApp:
    clearState: false
    arguments:
      isE2E: true
- extendedWaitUntil:
    visible: '.*Harness: ready.*'
    timeout: 120000
- extendedWaitUntil:
    visible: '.*Marker: background-complete:success.*'
    timeout: 120000`,
  'kill-relaunch-resume': `
- extendedWaitUntil:
    visible: '.*PHASE:kill-relaunch-resume:downloading.*'
    timeout: 45000
- stopApp
- launchApp:
    clearState: false
    arguments:
      isE2E: true
- extendedWaitUntil:
    visible: '.*Harness: ready.*'
    timeout: 120000
- extendedWaitUntil:
    visible: '.*Marker: kill-relaunch-resume:success.*'
    timeout: 120000`,
  'batch-kill-mid': `
- extendedWaitUntil:
    visible: '.*PHASE:batch-kill-mid:downloading.*'
    timeout: 60000
- waitForAnimationToEnd:
    timeout: 5000
- stopApp
- launchApp:
    clearState: false
    arguments:
      isE2E: true
- extendedWaitUntil:
    visible: '.*Harness: ready.*'
    timeout: 120000
- extendedWaitUntil:
    visible: '.*Marker: batch-kill-mid:success.*'
    timeout: 300000`,
  'low-memory-kill': `
- extendedWaitUntil:
    visible: '.*PHASE:low-memory-kill:downloading.*'
    timeout: 45000
- stopApp
- launchApp:
    clearState: false
    arguments:
      isE2E: true
- extendedWaitUntil:
    visible: '.*Harness: ready.*'
    timeout: 120000
- extendedWaitUntil:
    visible: '.*Marker: low-memory-kill:success.*'
    timeout: 120000`,
};

for (const flowId of MAESTRO_E2E_FLOWS) {
  const markerTail = multiStep[flowId]
    ? multiStep[flowId]
  : `${extraAssertions[flowId] ?? ''}
- extendedWaitUntil:
    visible: '.*Marker: ${flowId}:success.*'
    timeout: ${markerTimeout[flowId] ?? '90000'}`;

  const content = `appId: app.capgo.downloader
---
- runFlow: ../helpers/launch-harness.yaml
- scrollUntilVisible:
    element:
      text: ${flowId}
    direction: DOWN
    timeout: 45000
    centerElement: true
- tapOn:
    text: ${flowId}
    retryTapIfNoChange: true${markerTail}
`;

  writeFileSync(path.join(rootDir, '.maestro/flows', `${flowId}.yaml`), content);
}