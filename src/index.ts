import { registerPlugin } from '@capacitor/core';

import type { CapacitorAccelerometerPlugin } from './definitions';

const CapacitorAccelerometer = registerPlugin<CapacitorAccelerometerPlugin>('CapacitorAccelerometer', {
  web: () => import('./web').then((m) => new m.CapacitorAccelerometerWeb()),
});

export * from './definitions';
export { CapacitorAccelerometer };
