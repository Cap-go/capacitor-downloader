import type { PluginListenerHandle } from '@capacitor/core';

export interface DownloadTask {
  id: string;
  progress: number;
  state: 'PENDING' | 'RUNNING' | 'PAUSED' | 'DONE' | 'ERROR';
}

export interface DownloadOptions {
  id: string;
  url: string;
  destination: string;
  headers?: { [key: string]: string };
  network?: 'cellular' | 'wifi-only';
  priority?: 'high' | 'normal' | 'low';
}

export interface CapacitorDownloaderPlugin {
  download(options: DownloadOptions): Promise<DownloadTask>;
  pause(id: string): Promise<void>;
  resume(id: string): Promise<void>;
  stop(id: string): Promise<void>;
  checkStatus(id: string): Promise<DownloadTask>;
  getFileInfo(path: string): Promise<{ size: number; type: string }>;

  addListener(
    eventName: 'downloadProgress',
    listenerFunc: (progress: { id: string; progress: number }) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'downloadCompleted',
    listenerFunc: (result: { id: string }) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'downloadFailed',
    listenerFunc: (error: { id: string; error: string }) => void,
  ): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;

  /**
   * Get the native Capacitor plugin version
   *
   * @returns {Promise<{ id: string }>} an Promise with version for this device
   * @throws An error if the something went wrong
   */
  getPluginVersion(): Promise<{ version: string }>;
}
