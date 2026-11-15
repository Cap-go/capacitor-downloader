/** @type {readonly string[]} */
export const MAESTRO_E2E_FLOWS = [
  'foreground-complete',
  'background-complete',
  'kill-relaunch-resume',
  'low-memory-kill',
  'network-drop-resume',
  'error-bad-url',
  'error-404',
  'error-5xx',
  'error-unwritable-destination',
  'cancel-cleanup',
  'parallel-downloads',
  'completion-once',
];

export function flowYamlPath(flowId, rootDir) {
  return `${rootDir}/.maestro/flows/${flowId}.yaml`;
}