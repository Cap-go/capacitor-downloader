import { WebPlugin } from '@capacitor/core';

import type { CapacitorDownloaderPlugin, DownloadBatchOptions, DownloadOptions, DownloadTask } from './definitions';

export class CapacitorDownloaderWeb extends WebPlugin implements CapacitorDownloaderPlugin {
  async download(options: DownloadOptions | DownloadBatchOptions): Promise<DownloadTask> {
    const hasFiles = 'files' in options && Array.isArray(options.files) && options.files.length > 0;
    const hasUrl = 'url' in options && typeof options.url === 'string' && options.url.length > 0;
    if (hasFiles && hasUrl) {
      throw new Error('Provide either url and destination or files, not both');
    }
    if (hasFiles) {
      const files = (options as DownloadBatchOptions).files;
      for (const file of files) {
        if (!file.url || !file.destination) {
          throw new Error('Each file entry requires url and destination');
        }
      }
    } else if (!hasUrl || !('destination' in options) || !options.destination) {
      throw new Error('url and destination are required when files is not provided');
    }
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
