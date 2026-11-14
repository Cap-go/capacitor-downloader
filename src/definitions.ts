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
  /**
   * Local file path where the download will be saved.
   *
   * On Android, relative paths without `androidHttpEngine` behave like earlier releases: every relative path,
   * including `cache/...` and `files/...`, is stored under app external files via DownloadManager.
   *
   * When you set `androidHttpEngine` to `'auto'` or `'okhttp'`, optional roots apply:
   * - `cache/...` saves under app cache (OkHttp with `'auto'`).
   * - `files/...` saves under app-private internal storage (OkHttp with `'auto'`).
   * - `public-downloads/...` saves to the public Downloads folder (DownloadManager).
   * - Any other relative path saves under app external files (DownloadManager with `'auto'`).
   * Absolute paths and `file://` URIs are supported; `'auto'` picks OkHttp when the path is under cache, data, or files dirs.
   */
  destination: string;
  /** Optional HTTP headers to include in the request */
  headers?: { [key: string]: string };
  /** Network type requirement for download */
  network?: 'cellular' | 'wifi-only';
  /** Download priority level */
  priority?: 'high' | 'normal' | 'low';
  /**
   * Android DownloadManager notification visibility.
   *
   * - `'completed'` (default): show while downloading and keep the notification after completion.
   * - `'progress'`: show while downloading, remove the notification when finished.
   * - `'hidden'`: no DownloadManager progress notification; use plugin progress events instead.
   *   `downloadCompletedNotificationText` can still post a completion notification when the transfer succeeds.
   *
   * On the OkHttp Android path, notifications are not shown during the transfer. With `'completed'`, a single
   * completion notification may be posted when the file finishes (Android 13+ requires runtime
   * `POST_NOTIFICATIONS` in the host app). Ignored on iOS and Web.
   *
   * @since 8.2.0
   */
  notification?: 'completed' | 'progress' | 'hidden';
  /**
   * Title shown on the Android DownloadManager progress notification.
   *
   * When omitted or empty, the system uses its default (typically the destination file name).
   * Ignored on iOS, Web, and the OkHttp Android download path.
   *
   * @since 8.6.0
   */
  title?: string;
  /**
   * Description shown on the Android DownloadManager progress notification.
   *
   * When omitted or empty, the system uses its default. Ignored on iOS, Web, and the OkHttp Android download path.
   *
   * @since 8.6.0
   */
  description?: string;
  /**
   * Android HTTP stack used for the download.
   *
   * - Omitted: always DownloadManager with legacy destination resolution (same as releases before this option).
   * - `'auto'`: OkHttp for app-private destinations (`cache/...`, `files/...`, or an absolute path under
   *   cache/data/files when extended roots apply); DownloadManager for legacy relative paths under app external storage
   *   and `public-downloads/...`.
   * - `'okhttp'`: always use OkHttp for extended-root destinations. Rejects `public-downloads/...` paths. Transfers run
   *   in the app process and do not continue after the process is killed (unlike DownloadManager on those paths).
   * - `'downloadManager'`: always use the system DownloadManager with legacy destination resolution.
   *
   * Ignored on iOS and Web.
   *
   * @since 8.5.0
   */
  androidHttpEngine?: 'auto' | 'okhttp' | 'downloadManager';
  /**
   * Optional localized text for a system notification when the download finishes.
   *
   * When set, iOS and Android may show a local notification after a successful download
   * if the user granted notification permission. If permission is denied, the download
   * still completes and no notification is shown. Tapping the notification reopens the app.
   *
   * Omitted or empty means no completion notification from the plugin (use
   * `downloadCompleted` events while the app is open).
   *
   * @since 8.5.0
   */
  downloadCompletedNotificationText?: string;
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
   *   destination: 'files/offline/package.zip',
   *   androidHttpEngine: 'auto',
   *   notification: 'hidden', // Android OkHttp: no notification during download; use downloadProgress events
   *   downloadCompletedNotificationText: 'Your file is ready', // opt-in completion alert
   * });
   * ```
   */
  download(options: DownloadOptions): Promise<DownloadTask>;

  /**
   * Pause an active download.
   * Download can be resumed later from the same position.
   *
   * @param options - Options containing the download task ID
   * @returns Promise that resolves when paused
   */
  pause(options: { id: string }): Promise<void>;

  /**
   * Resume a paused download.
   * Continues from where it was paused.
   *
   * @param options - Options containing the download task ID
   * @returns Promise that resolves when resumed
   */
  resume(options: { id: string }): Promise<void>;

  /**
   * Stop and cancel a download permanently.
   * Downloaded data will be deleted.
   *
   * @param options - Options containing the download task ID
   * @returns Promise that resolves when stopped
   */
  stop(options: { id: string }): Promise<void>;

  /**
   * Check the current status of a download.
   *
   * @param options - Options containing the download task ID
   * @returns Promise with current download task status
   */
  checkStatus(options: { id: string }): Promise<DownloadTask>;

  /**
   * Get information about a downloaded file.
   *
   * @param options - Options containing the file path
   * @returns Promise with file size and MIME type
   */
  getFileInfo(options: { path: string }): Promise<{ size: number; type: string }>;

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
    listenerFunc: (progress: {
      id: string;
      progress: number;
      /** Bytes written so far */
      bytesWritten?: number;
      /** Total bytes expected, or 0 when the server did not report a length */
      bytesTotal?: number;
    }) => void,
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
