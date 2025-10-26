import type { PluginListenerHandle } from '@capacitor/core';

/**
 * Represents the current state and progress of a download task.
 */
export interface DownloadTask {
  /** Unique identifier for the download task */
  id: string;
  /** Download progress from 0 to 100 */
  progress: number;
  /** Current state of the download */
  state: 'PENDING' | 'RUNNING' | 'PAUSED' | 'DONE' | 'ERROR';
}

/**
 * Configuration options for starting a download.
 */
export interface DownloadOptions {
  /** Unique identifier for this download task */
  id: string;
  /** URL of the file to download */
  url: string;
  /** Local file path where the download will be saved */
  destination: string;
  /** Optional HTTP headers to include in the request */
  headers?: { [key: string]: string };
  /** Network type requirement for download */
  network?: 'cellular' | 'wifi-only';
  /** Download priority level */
  priority?: 'high' | 'normal' | 'low';
}

/**
 * Capacitor plugin for downloading files with background support.
 * Provides resumable downloads with progress tracking.
 */
export interface CapacitorDownloaderPlugin {
  /**
   * Start a new download task.
   *
   * @param options - Download configuration
   * @returns Promise with initial download task status
   * @example
   * ```typescript
   * const task = await Downloader.download({
   *   id: 'my-download',
   *   url: 'https://example.com/file.pdf',
   *   destination: 'downloads/file.pdf'
   * });
   * ```
   */
  download(options: DownloadOptions): Promise<DownloadTask>;

  /**
   * Pause an active download.
   * Download can be resumed later from the same position.
   *
   * @param id - ID of the download task to pause
   * @returns Promise that resolves when paused
   */
  pause(id: string): Promise<void>;

  /**
   * Resume a paused download.
   * Continues from where it was paused.
   *
   * @param id - ID of the download task to resume
   * @returns Promise that resolves when resumed
   */
  resume(id: string): Promise<void>;

  /**
   * Stop and cancel a download permanently.
   * Downloaded data will be deleted.
   *
   * @param id - ID of the download task to stop
   * @returns Promise that resolves when stopped
   */
  stop(id: string): Promise<void>;

  /**
   * Check the current status of a download.
   *
   * @param id - ID of the download task to check
   * @returns Promise with current download task status
   */
  checkStatus(id: string): Promise<DownloadTask>;

  /**
   * Get information about a downloaded file.
   *
   * @param path - Local file path to inspect
   * @returns Promise with file size and MIME type
   */
  getFileInfo(path: string): Promise<{ size: number; type: string }>;

  /**
   * Listen for download progress updates.
   * Fired periodically as download progresses.
   *
   * @param eventName - Must be 'downloadProgress'
   * @param listenerFunc - Callback receiving progress updates
   * @returns Promise with listener handle for removal
   * @example
   * ```typescript
   * const listener = await Downloader.addListener('downloadProgress', (data) => {
   *   console.log(`Download ${data.id}: ${data.progress}%`);
   * });
   * ```
   */
  addListener(
    eventName: 'downloadProgress',
    listenerFunc: (progress: { id: string; progress: number }) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Listen for download completion.
   * Fired when a download finishes successfully.
   *
   * @param eventName - Must be 'downloadCompleted'
   * @param listenerFunc - Callback receiving completion notification
   * @returns Promise with listener handle for removal
   */
  addListener(
    eventName: 'downloadCompleted',
    listenerFunc: (result: { id: string }) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Listen for download failures.
   * Fired when a download encounters an error.
   *
   * @param eventName - Must be 'downloadFailed'
   * @param listenerFunc - Callback receiving error information
   * @returns Promise with listener handle for removal
   */
  addListener(
    eventName: 'downloadFailed',
    listenerFunc: (error: { id: string; error: string }) => void,
  ): Promise<PluginListenerHandle>;

  /**
   * Remove all event listeners.
   * Cleanup method to prevent memory leaks.
   *
   * @returns Promise that resolves when all listeners removed
   */
  removeAllListeners(): Promise<void>;

  /**
   * Get the plugin version number.
   *
   * @returns Promise with version string
   */
  getPluginVersion(): Promise<{ version: string }>;
}
