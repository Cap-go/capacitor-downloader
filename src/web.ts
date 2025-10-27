import { WebPlugin } from '@capacitor/core';

import type {
  CapacitorAccelerometerPlugin,
  GetMeasurementResult,
  IsAvailableResult,
  Measurement,
  PermissionState,
  PermissionStatus,
} from './definitions';

type DeviceMotionWithPermission = typeof DeviceMotionEvent & {
  requestPermission?: () => Promise<'granted' | 'denied'>;
};

const DEFAULT_MEASUREMENT: Measurement = { x: 0, y: 0, z: 0 };

export class CapacitorAccelerometerWeb extends WebPlugin implements CapacitorAccelerometerPlugin {
  private lastMeasurement: Measurement = { ...DEFAULT_MEASUREMENT };
  private motionHandler: ((event: DeviceMotionEvent) => void) | null = null;
  private permissionState: PermissionState | 'limited' = 'prompt';

  private handleMotion = (event: DeviceMotionEvent) => {
    const accel = event.accelerationIncludingGravity ?? event.acceleration;
    if (!accel) {
      return;
    }

    this.lastMeasurement = {
      x: accel.x ?? 0,
      y: accel.y ?? 0,
      z: accel.z ?? 0,
    };

    this.notifyListeners('measurement', { ...this.lastMeasurement });
  };

  private supportsDeviceMotion(): boolean {
    return typeof window !== 'undefined' && typeof window.DeviceMotionEvent !== 'undefined';
  }

  private get motionEventConstructor(): DeviceMotionWithPermission | null {
    return this.supportsDeviceMotion() ? (window.DeviceMotionEvent as DeviceMotionWithPermission) : null;
  }

  async getMeasurement(): Promise<GetMeasurementResult> {
    return { ...this.lastMeasurement };
  }

  async isAvailable(): Promise<IsAvailableResult> {
    return { isAvailable: this.supportsDeviceMotion() };
  }

  async startMeasurementUpdates(): Promise<void> {
    await this.ensurePermission(true);
    if (!this.supportsDeviceMotion()) {
      throw this.unavailable('DeviceMotionEvent is not available in this browser.');
    }
    if (this.motionHandler) {
      return;
    }
    this.motionHandler = this.handleMotion;
    window.addEventListener('devicemotion', this.motionHandler);
  }

  async stopMeasurementUpdates(): Promise<void> {
    if (this.motionHandler && this.supportsDeviceMotion()) {
      window.removeEventListener('devicemotion', this.motionHandler);
    }
    this.motionHandler = null;
  }

  async checkPermissions(): Promise<PermissionStatus> {
    await this.ensurePermission(false);
    return { accelerometer: this.permissionState };
  }

  async requestPermissions(): Promise<PermissionStatus> {
    await this.ensurePermission(true);
    return { accelerometer: this.permissionState };
  }

  async addListener(eventName: 'measurement', listenerFunc: (event: Measurement) => void) {
    const handle = await super.addListener(eventName, listenerFunc);
    return handle;
  }

  async removeAllListeners(): Promise<void> {
    await super.removeAllListeners();
  }

  private async ensurePermission(request: boolean): Promise<void> {
    if (!this.supportsDeviceMotion()) {
      this.permissionState = 'denied';
      return;
    }

    const constructor = this.motionEventConstructor;
    if (!constructor?.requestPermission) {
      // Platforms without explicit permission prompts expose motion data if feature is available.
      this.permissionState = 'granted';
      return;
    }

    if (!request) {
      // We cannot probe state without prompting, assume prompt until user interacts.
      if (this.permissionState === 'prompt') {
        return;
      }
      return;
    }

    try {
      const status = await constructor.requestPermission();
      this.permissionState = status === 'granted' ? 'granted' : 'denied';
    } catch (error) {
      console.warn('CapacitorAccelerometer: permission request failed', error);
      this.permissionState = 'denied';
    }
  }
}
