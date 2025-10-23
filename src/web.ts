import { WebPlugin } from '@capacitor/core';

import type { CapacitorDownloaderPlugin, DownloadTask, DownloadOptions } from './definitions';

export class CapacitorDownloaderWeb extends WebPlugin implements CapacitorDownloaderPlugin {
  async download(options: DownloadOptions): Promise<DownloadTask> {
    console.log('DOWNLOAD', options);
    throw new Error('Method not implemented.');
  }
  async pause(id: string): Promise<void> {
    console.log('PAUSE', id);
    throw new Error('Method not implemented.');
  }
  async resume(id: string): Promise<void> {
    console.log('RESUME', id);
    throw new Error('Method not implemented.');
  }
  async stop(id: string): Promise<void> {
    console.log('STOP', id);
    throw new Error('Method not implemented.');
  }
  async checkStatus(id: string): Promise<DownloadTask> {
    console.log('CHECK STATUS', id);
    throw new Error('Method not implemented.');
  }
  async getFileInfo(path: string): Promise<{ size: number; type: string }> {
    console.log('GET FILE INFO', path);
    throw new Error('Method not implemented.');
  }

  async getPluginVersion(): Promise<{ version: string }> {
    return { version: 'web' };
  }
}
