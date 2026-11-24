import { describe, expect, test } from 'bun:test';

import { CapacitorDownloaderWeb } from './web';

describe('CapacitorDownloaderWeb batch validation', () => {
  test('accepts more than 32 files', async () => {
    const plugin = new CapacitorDownloaderWeb();
    const files = Array.from({ length: 33 }, (_, i) => ({
      url: `https://example.com/${i}.bin`,
      destination: `f-${i}.bin`,
    }));
    await expect(plugin.download({ id: 'batch', files })).rejects.toThrow('Method not implemented.');
  });
});
