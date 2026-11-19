import { MAESTRO_E2E_FLOWS } from './flows.mjs';

const shardIndex = Number(process.argv[2] ?? 0);
const shardCount = Number(process.argv[3] ?? 1);

if (!Number.isInteger(shardIndex) || !Number.isInteger(shardCount) || shardCount < 1) {
  throw new Error('Usage: partition-flows.mjs <shard-index> <shard-count>');
}
if (shardIndex < 0 || shardIndex >= shardCount) {
  throw new Error(`shard-index must be in [0, ${shardCount})`);
}

const flows = MAESTRO_E2E_FLOWS.filter((_, index) => index % shardCount === shardIndex);
if (flows.length === 0) {
  throw new Error(`Shard ${shardIndex}/${shardCount} has no flows`);
}
process.stdout.write(`${flows.join(' ')}`);