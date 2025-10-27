import type { PluginListenerHandle } from '@capacitor/core';

/**
 * The x, y and z axis acceleration values reported by the device motion sensors.
 *
 * @since 1.0.0
 */
export interface Measurement {
  /**
   * The acceleration on the x-axis in G's.
   *
   * @since 1.0.0
   */
  x: number;

  /**
   * The acceleration on the y-axis in G's.
   *
   * @since 1.0.0
   */
  y: number;

  /**
   * The acceleration on the z-axis in G's.
   *
   * @since 1.0.0
   */
  z: number;
}

/**
 * Result returned by {@link CapacitorAccelerometerPlugin.isAvailable}.
 *
 * @since 1.0.0
 */
export interface IsAvailableResult {
  /**
   * Whether an accelerometer sensor is available on the device.
   *
   * @since 1.0.0
   */
  isAvailable: boolean;
}

/**
 * Permission information returned by {@link CapacitorAccelerometerPlugin.checkPermissions}
 * and {@link CapacitorAccelerometerPlugin.requestPermissions}.
 *
 * @since 1.0.0
 */
export interface PermissionStatus {
  /**
   * The permission state for accessing motion data on the current platform.
   *
   * @since 1.0.0
   */
  accelerometer: AccelerometerPermissionState;
}

/**
 * Alias for the most recent measurement.
 *
 * @since 1.0.0
 */
export type GetMeasurementResult = Measurement;

/**
 * Permission state union including `limited` for platforms that can throttle motion access.
 *
 * @since 1.0.0
 */
export type AccelerometerPermissionState = PermissionState | 'limited';

/**
 * Platform permission states supported by Capacitor.
 *
 * @since 1.0.0
 */
export type PermissionState = 'prompt' | 'prompt-with-rationale' | 'granted' | 'denied';

/**
 * Event payload emitted when {@link CapacitorAccelerometerPlugin.startMeasurementUpdates}
 * is active.
 *
 * @since 1.0.0
 */
export type MeasurementEvent = Measurement;

/**
 * Capacitor plugin contract for working with the device accelerometer.
 *
 * @since 1.0.0
 */
export interface CapacitorAccelerometerPlugin {
  /**
   * Get the most recent accelerometer sample that was recorded by the native layer.
   *
   * @returns The latest x, y and z axis values.
   * @since 1.0.0
   */
  getMeasurement(): Promise<GetMeasurementResult>;

  /**
   * Check if the current device includes an accelerometer sensor.
   *
   * @returns Whether an accelerometer is available.
   * @since 1.0.0
   */
  isAvailable(): Promise<IsAvailableResult>;

  /**
   * Begin streaming accelerometer updates to the JavaScript layer.
   *
   * Call {@link addListener} with the `measurement` event to receive the updates.
   *
   * @since 1.0.0
   */
  startMeasurementUpdates(): Promise<void>;

  /**
   * Stop streaming accelerometer updates started via {@link startMeasurementUpdates}.
   *
   * @since 1.0.0
   */
  stopMeasurementUpdates(): Promise<void>;

  /**
   * Return the current permission state for accessing motion data.
   *
   * On platforms without explicit permissions this resolves to `granted`.
   *
   * @since 1.0.0
   */
  checkPermissions(): Promise<PermissionStatus>;

  /**
   * Request permission to access motion data if supported by the platform.
   *
   * @since 1.0.0
   */
  requestPermissions(): Promise<PermissionStatus>;

  /**
   * Listen for measurement updates.
   *
   * @param eventName Only the `measurement` event is supported.
   * @param listenerFunc Callback invoked with each measurement.
   * @since 1.0.0
   */
  addListener(eventName: 'measurement', listenerFunc: (event: MeasurementEvent) => void): Promise<PluginListenerHandle>;

  /**
   * Remove all listeners that have been registered on the plugin.
   *
   * @since 1.0.0
   */
  removeAllListeners(): Promise<void>;
}
