import type { PluginListenerHandle } from '@capacitor/core';

/**
 * Legacy batch file limit constant.
 *
 * @deprecated No longer enforced. Kept for compatibility within the Capacitor 8 line and removed in the next major.
 * Non-empty native batches no longer have a fixed maximum file count; native layers schedule transfers instead.
 */
export const DOWNLOAD_BATCH_MAX_FILES = 32;

/**
 * Represents the current state and progress of a download task.
 */
export interface DownloadTask {
  /** Unique identifier for the download task */
  id: string;
  /** Download progress from 0 to 1 */
  progress: number;
  /** Current state of the download */
  state: 'PENDING' | 'RUNNING' | 'PAUSED' | 'DONE' | 'ERROR';
  /** Absolute on-disk path when `checkStatus` resolves a finished batch child on iOS */
  path?: string;
  /**
   * Batch-only metadata returned when `download()` starts a multi-file batch.
   * Pair with `childTaskIds` to correlate `checkStatus()` while a batch is active.
   */
  batchGeneration?: number;
  /** Ordered child task ids for batch entries (same order as `files`). */
  childTaskIds?: string[];
}

/**
 * One file entry inside a multi-file download batch.
 */
export interface DownloadFileSpec {
  /** URL of the file to download */
  url: string;
  /**
   * Local file path where the download will be saved.
   *
   * On Android single-file downloads, relative paths without `androidHttpEngine` behave like earlier releases: every relative path,
   * including `cache/...` and `files/...`, is stored under app external files via DownloadManager.
   *
   * When you set `androidHttpEngine` to `'auto'` or `'okhttp'` on a single download, optional roots apply:
   * - `cache/...` saves under app cache (OkHttp with `'auto'`).
   * - `files/...` saves under app-private internal storage (OkHttp with `'auto'`).
   * - `public-downloads/...` saves to the public Downloads folder (DownloadManager).
   * - Any other relative path saves under app external files (DownloadManager with `'auto'`).
   *
   * Multi-file batches on Android use the same destination rules as single downloads for the batch `androidHttpEngine` value (including extended roots when `'auto'` or `'okhttp'` is set). Since 8.12.0 a batch can use OkHttp when every file resolves to it (for example `cache/...` or `files/...`); a batch that mixes engines is rejected.
   *
   * Absolute paths and `file://` URIs are supported on iOS and on Android single downloads.
   *
   * On iOS (since 8.8.0), optional roots:
   * - `files/...` and `cache/...` stay under Documents as in 8.7.0 (`Documents/files/...`, `Documents/cache/...`).
   * - `private/...` (iOS only) writes under Application Support/CapacitorDownloader/.
   * Path segments containing `..` are rejected. On Android, `private/` is not special (treated as a relative path under app storage).
   * Any other relative path still uses the app Documents directory.
   */
  destination: string;
}

/**
 * Configuration options for starting a single-file download.
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
   *
   * On iOS, optional roots match batch entries (see {@link DownloadFileSpec.destination}).
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
   * On the OkHttp Android path, `'completed'` (default) keeps 8.7.0 behavior: no ongoing notification and no foreground
   * service. Set `'progress'` to opt in to ongoing progress notifications and an optional `dataSync` foreground service
   * (API 24+; may be blocked in the background on Android 12+). Downloads continue if the service cannot start.
   * Android 13+ requires runtime `POST_NOTIFICATIONS` when notifications are shown. Ignored on iOS and Web.
   *
   * @since 8.2.0
   */
  notification?: 'completed' | 'progress' | 'hidden';
  /**
   * Title shown on the Android DownloadManager progress notification, and on iOS on the continued processing task
   * when `iosContinuedProcessing` is set.
   *
   * When omitted or empty, DownloadManager uses its default (typically the destination file name). On Android OkHttp,
   * used when `notification` is `'progress'`. iOS continued processing requires a non-empty `title`. Ignored on Web.
   *
   * @since 8.6.0
   */
  title?: string;
  /**
   * Description shown on the Android DownloadManager progress notification, and on iOS as the subtitle of the
   * continued processing task when `iosContinuedProcessing` is set.
   *
   * When omitted or empty, the system uses its default. On Android OkHttp, used when `notification` is `'progress'`
   * (including OkHttp batches). Ignored on Web.
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
  /**
   * Optional localized text for a system notification when the download fails.
   *
   * When set, iOS and Android may show a local notification after a failed download
   * if the user granted notification permission. If permission is denied, the failure
   * still occurs and no notification is shown. Tapping the notification reopens the app.
   * Uses the same notification slot as `downloadCompletedNotificationText`, so a failure
   * alert replaces a prior completion alert for the same download id instead of stacking.
   * Not shown when the download is stopped by the app.
   *
   * Omitted or empty means no failure notification from the plugin (use
   * `downloadFailed` events while the app is open).
   *
   * @since 8.9.0
   */
  downloadFailedNotificationText?: string;
  /**
   * HTTP response header that carries the uncompressed byte length when the body is transferred
   * compressed (for example `Content-Encoding: gzip`) and `Content-Length` is missing or wrong.
   *
   * When the response includes this header with a positive integer, native code uses it for
   * `downloadProgress` totals and progress is clamped at 1. Examples: `X-Uncompressed-Length`.
   *
   * Single downloads: Android OkHttp and iOS. Ignored on Web and Android DownloadManager.
   * On Android OkHttp, ignored when the response still includes `Content-Encoding` (for example
   * after setting `Accept-Encoding: gzip` on the request). Do not set request `Accept-Encoding`;
   * OkHttp handles decompression by default.
   *
   * @since 8.9.0
   */
  lengthHeader?: string;
  /**
   * iOS 26 and later: run the download in a `BGContinuedProcessingTask`, which shows `title` and `description` with the
   * download progress while the device is locked. Requires `title`. Falls back to the background URL session when the
   * task does not launch in time. If the task expires, the download fails with `downloadFailed` and is not resumed
   * automatically. The host app must allow `$(PRODUCT_BUNDLE_IDENTIFIER).CapacitorDownloader.continuedProcessing.*` in
   * `BGTaskSchedulerPermittedIdentifiers` (see plugin README). Ignored on Android and Web.
   *
   * @since 8.12.0
   */
  iosContinuedProcessing?: boolean;
  /**
   * Title of the iOS continued processing task.
   *
   * @deprecated Use `title` with `iosContinuedProcessing: true`.
   * @since 8.8.0
   */
  iosContinuedProcessingTitle?: string;
  /**
   * Subtitle of the iOS continued processing task.
   *
   * @deprecated Use `description` with `iosContinuedProcessing: true`.
   * @since 8.8.0
   */
  iosContinuedProcessingSubtitle?: string;
  /**
   * Number of times to retry the file after a connection failure (OkHttp on Android and iOS URLSession).
   *
   * Defaults to `0` (no retries). On a retry, the file is downloaded again from the start after a delay of
   * 5 seconds times the attempt number (5 s, then 10 s, then 15 s, and so on). Progress for the file resets to 0.
   * HTTP errors, cancellation, and file-system errors are not retried. Android DownloadManager and Web ignore this option.
   *
   * @default 0
   * @since 8.9.0
   */
  retries?: number;
  /**
   * Multi-file batches use `files` instead. Omit for single-file downloads.
   *
   * @since 8.7.0
   */
  files?: never;
}

/**
 * Configuration options for a multi-file batch download.
 *
 * On Android, each file uses the same `androidHttpEngine` destination rules as a single download. Since 8.12.0 a batch whose files all resolve to OkHttp runs through OkHttp, with one progress notification and optional foreground service for the whole batch when `notification` is `'progress'` (transfers continue if the service cannot start). A batch that mixes engines is rejected.
 *
 * **Process death:** On Android, batch state lives in memory only and is lost when the host process is killed. DownloadManager batch work may still finish in the system, but the plugin does not rebuild batch progress. OkHttp batch transfers stop when the process is killed and are not resumed. On iOS, batch metadata is persisted in `DownloadBatchStore` (UserDefaults) and restored when the plugin initializes.
 *
 * When one file fails, remaining transfers are cancelled. Files that already finished successfully stay on disk. On Android DownloadManager batches, completed children stop being tracked without calling DownloadManager.remove on them. On OkHttp batches, in-flight transfers are cancelled without deleting files that already finished.
 *
 * **`stop({ id })` on a batch id:** On iOS, deletes every path stored via `recordMovedDestination` for that batch (files written before `stop()`). A later batch failure does not delete those paths; only `stop()` removes them. On Android DownloadManager batches, removes active DownloadManager entries for in-flight children; finished children stay on disk. On OkHttp batches, cancels in-flight transfers and removes their temp files; files from children that already finished stay on disk.
 */
export interface DownloadBatchOptions {
  /** Unique identifier for this batch (shared by every file in `files`) */
  id: string;
  /**
   * Download multiple files as one native-owned batch.
   *
   * The batch shares the top-level `id`. Progress events use `progress` and `fileProgress` from 0 to 1 (same scale as DownloadTask).
   * `downloadCompleted` fires once when every file succeeds. Any failure cancels the batch.
   * There is no fixed maximum file count. On Android, each file uses the batch `androidHttpEngine` rules (DownloadManager or OkHttp when all files resolve to the same engine). On Android, single-file OkHttp downloads and all-OkHttp batches share one fair queue capped at 4 concurrent transfers. On iOS, URLSession queues work per host.
   *
   * @since 8.7.0
   */
  files: DownloadFileSpec[];
  url?: never;
  destination?: never;
  /** Optional HTTP headers to include in the request */
  headers?: { [key: string]: string };
  /** Network type requirement for download */
  network?: 'cellular' | 'wifi-only';
  /** Download priority level */
  priority?: 'high' | 'normal' | 'low';
  /**
   * Android notification visibility for batch transfers.
   *
   * DownloadManager batches:
   * - `'completed'` (default): show while downloading and keep the notification after completion.
   * - `'progress'`: show while downloading, remove the notification when finished.
   * - `'hidden'`: no DownloadManager progress notification; use plugin progress events instead.
   *
   * OkHttp batches:
   * - `'completed'` (default): no notification during the transfer, one completion notification when the whole batch succeeds.
   * - `'progress'`: one ongoing progress notification for the whole batch, from an optional foreground service that keeps the
   *   batch going while the app is in the background. If the service cannot start, the transfers continue without it.
   * - `'hidden'`: no notification; use plugin progress events instead.
   *
   * `downloadCompletedNotificationText` can still post a completion notification when the batch succeeds.
   * Ignored on iOS and Web.
   *
   * @since 8.2.0
   */
  notification?: 'completed' | 'progress' | 'hidden';
  /**
   * Title shown on the Android progress notification of the batch, and on iOS on the continued processing task when
   * `iosContinuedProcessing` is set.
   *
   * When omitted or empty, DownloadManager uses its default (typically the destination file name); OkHttp uses
   * "Downloading". iOS continued processing requires a non-empty `title`. Ignored on Web.
   *
   * @since 8.6.0
   */
  title?: string;
  /**
   * Description shown on the Android progress notification of the batch, and on iOS as the subtitle of the continued
   * processing task when `iosContinuedProcessing` is set.
   *
   * When omitted or empty, the system uses its default. Ignored on Web.
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
   * Ignored on iOS and Web. On Android batches, each file uses these rules; the call is rejected if the files resolve to different engines.
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
  /**
   * Optional localized text for a system notification when the batch fails.
   *
   * When set, iOS and Android may show a local notification after a failed batch download
   * if the user granted notification permission. If permission is denied, the failure
   * still occurs and no notification is shown. Tapping the notification reopens the app.
   * Uses the same notification slot as `downloadCompletedNotificationText`, so a failure
   * alert replaces a prior completion alert for the same batch id instead of stacking.
   * Not shown when the batch is stopped by the app.
   *
   * Omitted or empty means no failure notification from the plugin (use
   * `downloadFailed` events while the app is open).
   *
   * @since 8.9.0
   */
  downloadFailedNotificationText?: string;
  /**
   * HTTP response header that carries the uncompressed byte length when the body is transferred
   * compressed (for example `Content-Encoding: gzip`) and `Content-Length` is missing or wrong.
   *
   * When the response includes this header with a positive integer, native code uses it for
   * `downloadProgress` totals and progress is clamped at 1. Examples: `X-Uncompressed-Length`.
   *
   * Batch downloads: iOS and Android OkHttp (same header name applies to every file in `files`). Ignored on Web and
   * Android DownloadManager batches.
   *
   * @since 8.9.0
   */
  lengthHeader?: string;
  /**
   * Number of times to retry each file after a connection failure (OkHttp on Android and iOS URLSession).
   *
   * Defaults to `0` (no retries). Applied to every entry in `files`. See {@link DownloadOptions.retries} for delay and
   * error rules. While one file retries, the batch continues and other files are unaffected. Android DownloadManager
   * batches ignore this option.
   *
   * @default 0
   * @since 8.9.0
   */
  retries?: number;
  /**
   * iOS 26 and later: run the whole batch in one `BGContinuedProcessingTask` that shows `title` and `description`, see
   * {@link DownloadOptions.iosContinuedProcessing}. If the task expires, the batch fails with `downloadFailed`.
   *
   * @since 8.12.0
   */
  iosContinuedProcessing?: boolean;
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
   *
   * // Multi-file batch (one completion event when all files finish):
   * const batch = await Downloader.download({
   *   id: 'update-bundle',
   *   files: [
   *     { url: 'https://example.com/a.zip', destination: 'updates/a.zip' },
   *     { url: 'https://example.com/b.zip', destination: 'updates/b.zip' },
   *   ],
   *   notification: 'hidden',
   * });
   * ```
   */
  download(options: DownloadOptions | DownloadBatchOptions): Promise<DownloadTask>;

  /**
   * Pause an active download.
   * Download can be resumed later from the same position.
   *
   * iOS supports pause and resume for single downloads and batches. Android rejects pause and resume for every download, including batches (use `stop()` instead).
   *
   * @param options - Options containing the download task ID
   * @returns Promise that resolves when paused
   */
  pause(options: { id: string }): Promise<void>;

  /**
   * Resume a paused download.
   * Continues from where it was paused.
   *
   * iOS supports pause and resume for single downloads and batches. Android rejects pause and resume for every download, including batches.
   *
   * @param options - Options containing the download task ID
   * @returns Promise that resolves when resumed
   */
  resume(options: { id: string }): Promise<void>;

  /**
   * Stop and cancel a download permanently.
   *
   * **Single downloads:** Cancels the transfer. Platform cleanup depends on the OS; the plugin does not guarantee file removal for singles.
   *
   * **Batch id on iOS:** Deletes each path recorded by `recordMovedDestination` for that batch. Batch failure alone does not delete finished files.
   *
   * **Batch id on Android:** Removes DownloadManager work for non-finished children. Completed batch files (marked complete or `STATUS_SUCCESSFUL` in DownloadManager) stay on disk.
   *
   * @param options - Options containing the download task ID
   * @returns Promise that resolves when stopped
   */
  stop(options: { id: string }): Promise<void>;

  /**
   * Check the current status of a download.
   *
   * Reports active URLSession/OkHttp/DownloadManager work. Batch child ids also resolve from in-memory batch
   * progress while that batch row exists. On iOS, children from a finished batch keep resolving as `DONE`
   * (with `path` when known) until the app restarts or a new batch reuses the same batch id; if a batch
   * fails or is stopped, or after an app restart, those child ids reject with "Task not found".
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
   * For batch downloads, `progress` and `fileProgress` use the same 0 to 1 scale as DownloadTask.
   *
   * @param eventName - Must be 'downloadProgress'
   * @param listenerFunc - Callback receiving progress updates
   * @returns Promise with listener handle for removal
   * @example
   * ```typescript
   * const listener = await Downloader.addListener('downloadProgress', (data) => {
   *   console.log(`Download ${data.id}: ${data.progress}`);
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
      /** Index of the file within a batch when `files` was used */
      fileIndex?: number;
      /** Progress of the file at `fileIndex` from 0 to 1 for batch downloads */
      fileProgress?: number;
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
    listenerFunc: (error: {
      id: string;
      error: string;
      fileIndex?: number;
      /** NSError code on iOS when available */
      errorCode?: number;
      /** NSError domain on iOS when available */
      errorDomain?: string;
    }) => void,
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
