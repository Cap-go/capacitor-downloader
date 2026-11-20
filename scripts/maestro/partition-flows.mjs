import { MAESTRO_E2E_FLOWS } from './flows.mjs';

const shardIndex = Number(process.argv[2] ?? 0);
const shardCount = Number(process.argv[3] ?? 1);

/** @type {readonly (readonly string[])[]} */
const IOS_MAESTRO_SHARDS = [
  ['error-5xx', 'completion-once'],
  ['foreground-complete', 'background-complete', 'error-bad-url', 'error-unwritable-destination'],
  ['batch-kill-mid', 'low-memory-kill', 'kill-relaunch-resume', 'cancel-cleanup'],
  ['parallel-downloads', 'network-drop-resume', 'error-404', 'batch-error-404', 'batch-error-5xx'],
];

if (!Number.isInteger(shardIndex) || !Number.isInteger(shardCount) || shardCount < 1) {
  throw new Error('Usage: partition-flows.mjs <shard-index> <shard-count>');
}
if (shardIndex < 0 || shardIndex >= shardCount) {
  throw new Error(`shard-index must be in [0, ${shardCount})`);
}

let flows;
if (shardCount === IOS_MAESTRO_SHARDS.length) {
  flows = [...IOS_MAESTRO_SHARDS[shardIndex]];
} else {
  flows = MAESTRO_E2E_FLOWS.filter((_, index) => index % shardCount === shardIndex);
}
if (flows.length === 0) {
  throw new Error(`Shard ${shardIndex}/${shardCount} has no flows`);
}
for (const flowId of flows) {
  if (!MAESTRO_E2E_FLOWS.includes(flowId)) {
    throw new Error(`Unknown Maestro flow in shard ${shardIndex}: ${flowId}`);
  }
}
process.stdout.write(`${flows.join(' ')}`);