import { WebPlugin } from '@capacitor/core';

import type { CapacitorDownloaderPlugin, DownloadTask, DownloadOptions } from './definitions';

export class CapacitorDownloaderWeb extends WebPlugin implements CapacitorDownloaderPlugin {
  async download(options: DownloadOptions): Promise<DownloadTask> {
    console.log('DOWNLOAD', options);
    throw new Error('Method not implemented.');
  }
  async pause(options: { id: string }): Promise<void> {
    console.log('PAUSE', options.id);
    throw new Error('Method not implemented.');
  }
  async resume(options: { id: string }): Promise<void> {
    console.log('RESUME', options.id);
    throw new Error('Method not implemented.');
  }
  async stop(options: { id: string }): Promise<void> {
    console.log('STOP', options.id);
    throw new Error('Method not implemented.');
  }
  async checkStatus(options: { id: string }): Promise<DownloadTask> {
    console.log('CHECK STATUS', options.id);
    throw new Error('Method not implemented.');
  }
  async getFileInfo(options: { path: string }): Promise<{ size: number; type: string }> {
    console.log('GET FILE INFO', options.path);
    throw new Error('Method not implemented.');
  }

  async getPluginVersion(): Promise<{ version: string }> {
    return { version: 'web' };
  }
}
