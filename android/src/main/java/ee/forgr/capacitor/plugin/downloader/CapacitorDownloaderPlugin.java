package ee.forgr.capacitor.plugin.downloader;

import android.app.DownloadManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import androidx.core.content.ContextCompat;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicLong;

@CapacitorPlugin(name = "CapacitorDownloader")
public class CapacitorDownloaderPlugin extends Plugin {

    private final String pluginVersion = "8.5.0";

    private DownloadManager downloadManager;
    private final Map<String, Long> downloads = new ConcurrentHashMap<>();
    private final Map<String, File> okHttpDestinationFiles = new ConcurrentHashMap<>();
    private final Map<String, Long> downloadGenerations = new ConcurrentHashMap<>();
    private final AtomicLong pendingDownloadSequence = new AtomicLong(0);
    private ExecutorService downloadManagerExecutor;
    private OkHttpDownloadExecutor okHttpDownloadExecutor;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BroadcastReceiver downloadReceiver;
    private DownloadCompletedNotificationStore completedNotificationStore;

    @Override
    public void load() {
        downloadManager = (DownloadManager) getContext().getSystemService(Context.DOWNLOAD_SERVICE);
        downloadManagerExecutor = Executors.newCachedThreadPool();
        okHttpDownloadExecutor = new OkHttpDownloadExecutor(getContext());
        completedNotificationStore = new DownloadCompletedNotificationStore(getContext());
        registerDownloadReceiver();
    }

    private void registerDownloadReceiver() {
        downloadReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                long receivedDownloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1);
                String downloadId = getDownloadIdByValue(receivedDownloadId);
                if (downloadId != null) {
                    checkDownloadStatus(downloadId);
                }
            }
        };
        ContextCompat.registerReceiver(
            getContext(),
            downloadReceiver,
            new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
            ContextCompat.RECEIVER_EXPORTED
        );
    }

    private String getDownloadIdByValue(long value) {
        for (Map.Entry<String, Long> entry : downloads.entrySet()) {
            if (entry.getValue() == value && value > 0) {
                return entry.getKey();
            }
        }
        return null;
    }

    private static boolean isPendingDownload(long downloadId) {
        return downloadId < 0 && downloadId != OkHttpDownloadExecutor.TRACKED_DOWNLOAD_ID;
    }

    private long reservePendingDownload() {
        long token;
        do {
            token = -pendingDownloadSequence.incrementAndGet();
        } while (token == OkHttpDownloadExecutor.TRACKED_DOWNLOAD_ID);
        return token;
    }

    private boolean isTrackedDownload(String id, long systemDownloadId) {
        Long trackedDownloadId = downloads.get(id);
        return trackedDownloadId != null && trackedDownloadId.longValue() == systemDownloadId;
    }

    private boolean isCurrentOkHttpDownload(String id) {
        Long trackedDownloadId = downloads.get(id);
        return trackedDownloadId != null && isOkHttpDownload(trackedDownloadId);
    }

    private long nextGeneration(String id) {
        while (true) {
            Long current = downloadGenerations.get(id);
            long next = (current == null ? 0L : current.longValue()) + 1L;
            if (current == null) {
                if (downloadGenerations.putIfAbsent(id, next) == null) {
                    return next;
                }
            } else if (downloadGenerations.replace(id, current, next)) {
                return next;
            }
        }
    }

    private Long generationFor(String id) {
        return downloadGenerations.get(id);
    }

    private static boolean usesExtendedDestinationRoots(String androidHttpEngine) {
        if (androidHttpEngine == null || androidHttpEngine.isEmpty()) {
            return false;
        }
        if ("downloadManager".equalsIgnoreCase(androidHttpEngine) || "download_manager".equalsIgnoreCase(androidHttpEngine)) {
            return false;
        }
        return true;
    }

    private boolean isCurrentOkHttpGeneration(String id, long expectedGeneration) {
        Long current = generationFor(id);
        return current != null && current.longValue() == expectedGeneration;
    }

    void applyOkHttpStartFailureIfCurrent(String id, long storedGeneration, File destinationFile, String errorMessage) {
        if (!isCurrentOkHttpGeneration(id, storedGeneration)) {
            return;
        }
        downloads.remove(id, OkHttpDownloadExecutor.TRACKED_DOWNLOAD_ID);
        okHttpDestinationFiles.remove(id, destinationFile);
        completedNotificationStore.remove(id, storedGeneration);
        JSObject failedData = new JSObject();
        failedData.put("id", id);
        failedData.put("error", errorMessage != null ? errorMessage : "Download failed");
        notifyListeners("downloadFailed", failedData);
    }

    @PluginMethod
    public void download(PluginCall call) {
        String id = call.getString("id");
        String url = call.getString("url");
        String destination = call.getString("destination");

        if (id == null || url == null || destination == null) {
            call.reject("Missing required parameters");
            return;
        }

        if (downloads.containsKey(id)) {
            call.reject("Download already exists");
            return;
        }

        final boolean extendedDestinationRoots = usesExtendedDestinationRoots(call.getString("androidHttpEngine"));

        final AndroidDownloadDestination.ResolvedDestination resolvedDestination;
        try {
            resolvedDestination = AndroidDownloadDestination.resolve(getContext(), destination, extendedDestinationRoots);
        } catch (IllegalArgumentException e) {
            call.reject(e.getMessage(), e);
            return;
        }

        final AndroidHttpEngineSelector.Engine httpEngine;
        try {
            httpEngine = AndroidHttpEngineSelector.resolve(call.getString("androidHttpEngine"), resolvedDestination.preferOkHttpInAutoMode);
        } catch (IllegalArgumentException e) {
            call.reject(e.getMessage(), e);
            return;
        }

        if (
            httpEngine == AndroidHttpEngineSelector.Engine.OKHTTP &&
            extendedDestinationRoots &&
            destination.trim().startsWith("public-downloads/")
        ) {
            call.reject("OkHttp cannot write to public-downloads/ paths. Use androidHttpEngine 'auto' or 'downloadManager'.");
            return;
        }

        final String completionNotificationText = call.getString("downloadCompletedNotificationText");

        if (httpEngine == AndroidHttpEngineSelector.Engine.OKHTTP) {
            downloadWithOkHttp(
                call,
                id,
                url,
                resolvedDestination.file,
                call.getObject("headers"),
                call.getString("network"),
                call.getString("notification"),
                completionNotificationText
            );
            return;
        }

        downloadWithDownloadManager(
            call,
            id,
            url,
            resolvedDestination.file,
            call.getObject("headers"),
            call.getString("network"),
            call.getString("notification"),
            completionNotificationText
        );
    }

    private void downloadWithDownloadManager(
        PluginCall call,
        String id,
        String url,
        File destinationFile,
        JSObject headers,
        String network,
        String notification,
        String completionNotificationText
    ) {
        final DownloadManager.Request request;
        try {
            request = new DownloadManager.Request(Uri.parse(url))
                .setNotificationVisibility(DownloadNotificationVisibility.resolve(notification))
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true);

            Uri destinationUri = Uri.fromFile(destinationFile);
            request.setDestinationUri(destinationUri);

            if (headers != null) {
                for (Iterator<String> it = headers.keys(); it.hasNext(); ) {
                    String key = it.next();
                    request.addRequestHeader(key, headers.getString(key));
                }
            }

            if ("wifi-only".equals(network)) {
                request.setAllowedNetworkTypes(DownloadManager.Request.NETWORK_WIFI);
            } else {
                request.setAllowedNetworkTypes(DownloadManager.Request.NETWORK_MOBILE | DownloadManager.Request.NETWORK_WIFI);
            }
        } catch (RuntimeException e) {
            call.reject("Invalid download request", e);
            return;
        }

        final long pendingToken = reservePendingDownload();
        if (downloads.putIfAbsent(id, pendingToken) != null) {
            call.reject("Download already exists");
            return;
        }
        final long downloadGeneration = nextGeneration(id);
        completedNotificationStore.setText(id, completionNotificationText, downloadGeneration);
        runDownloadManagerWork(
            call,
            () -> {
                if (!isTrackedDownload(id, pendingToken)) {
                    completedNotificationStore.remove(id, downloadGeneration);
                    call.reject("Download was cancelled");
                    return;
                }

                long downloadId;
                try {
                    downloadId = downloadManager.enqueue(request);
                } catch (SecurityException e) {
                    downloads.remove(id, pendingToken);
                    completedNotificationStore.remove(id, downloadGeneration);
                    if ("hidden".equals(notification)) {
                        call.reject("Hidden downloads require android.permission.DOWNLOAD_WITHOUT_NOTIFICATION in the app manifest", e);
                    } else {
                        call.reject("Download could not be enqueued due to missing permission", e);
                    }
                    return;
                } catch (RuntimeException e) {
                    downloads.remove(id, pendingToken);
                    completedNotificationStore.remove(id, downloadGeneration);
                    call.reject("Download could not be enqueued", e);
                    return;
                }

                if (!downloads.replace(id, pendingToken, downloadId)) {
                    try {
                        downloadManager.remove(downloadId);
                    } catch (RuntimeException e) {
                        completedNotificationStore.remove(id, downloadGeneration);
                        call.reject("Download was cancelled", e);
                        return;
                    }
                    completedNotificationStore.remove(id, downloadGeneration);
                    call.reject("Download was cancelled");
                    return;
                }

                JSObject result = new JSObject();
                result.put("id", id);
                result.put("status", DownloadManager.STATUS_PENDING);
                call.resolve(result);

                startProgressCheck(id, downloadId);
            },
            () -> {
                downloads.remove(id, pendingToken);
                completedNotificationStore.remove(id, downloadGeneration);
            }
        );
    }

    private void downloadWithOkHttp(
        PluginCall call,
        String id,
        String url,
        File destinationFile,
        JSObject headers,
        String network,
        String notification,
        String completionNotificationText
    ) {
        if (notification == null) {
            notification = "completed";
        }

        final long pendingToken = reservePendingDownload();
        if (downloads.putIfAbsent(id, pendingToken) != null) {
            call.reject("Download already exists");
            return;
        }
        okHttpDestinationFiles.put(id, destinationFile);
        final long downloadGeneration = nextGeneration(id);
        completedNotificationStore.setText(id, completionNotificationText, downloadGeneration);

        final String notificationMode = notification;
        final long storedGeneration = downloadGeneration;
        runDownloadManagerWork(
            call,
            () -> {
                if (!isTrackedDownload(id, pendingToken)) {
                    okHttpDestinationFiles.remove(id);
                    completedNotificationStore.remove(id, storedGeneration);
                    call.reject("Download was cancelled");
                    return;
                }

                if (!okHttpDownloadExecutor.isWifiSatisfied(network)) {
                    downloads.remove(id, pendingToken);
                    okHttpDestinationFiles.remove(id);
                    completedNotificationStore.remove(id, storedGeneration);
                    call.reject("Wi-Fi required for this download");
                    return;
                }

                OkHttpDownloadExecutor.ActiveDownload okHttpReservation = okHttpDownloadExecutor.beginTransfer(id);
                if (okHttpReservation == null) {
                    downloads.remove(id, pendingToken);
                    okHttpDestinationFiles.remove(id);
                    completedNotificationStore.remove(id, storedGeneration);
                    call.reject("Download already exists");
                    return;
                }

                if (!downloads.replace(id, pendingToken, OkHttpDownloadExecutor.TRACKED_DOWNLOAD_ID)) {
                    okHttpDownloadExecutor.abandonTransfer(okHttpReservation);
                    okHttpDestinationFiles.remove(id, destinationFile);
                    completedNotificationStore.remove(id, storedGeneration);
                    call.reject("Download was cancelled");
                    return;
                }

                JSObject result = new JSObject();
                result.put("id", id);
                result.put("status", DownloadManager.STATUS_PENDING);
                call.resolve(result);

                try {
                    okHttpDownloadExecutor.start(
                        okHttpReservation,
                        url,
                        destinationFile,
                        headers,
                        network,
                        (downloadId, progress) ->
                            handler.post(() -> {
                                if (!isCurrentOkHttpDownload(downloadId) || !isCurrentOkHttpGeneration(downloadId, storedGeneration)) {
                                    return;
                                }
                                JSObject progressData = new JSObject();
                                progressData.put("id", downloadId);
                                progressData.put("progress", progress);
                                notifyListeners("downloadProgress", progressData);
                            }),
                        (downloadId, success, cancelled, errorMessage) ->
                            handler.post(() -> {
                                if (!isCurrentOkHttpDownload(downloadId) || !isCurrentOkHttpGeneration(downloadId, storedGeneration)) {
                                    return;
                                }
                                if (cancelled) {
                                    return;
                                }
                                if (success) {
                                    JSObject completedData = new JSObject();
                                    completedData.put("id", downloadId);
                                    notifyListeners("downloadCompleted", completedData);
                                    DownloadCompletionNotifier.notifyIfRequested(getContext(), downloadId, notificationMode, true);
                                    String completionText = completedNotificationStore.takeText(downloadId, storedGeneration);
                                    if (completionText != null) {
                                        DownloadCompletedNotificationPresenter.showIfAllowed(getContext(), downloadId, completionText);
                                    }
                                } else {
                                    okHttpDestinationFiles.remove(downloadId, destinationFile);
                                    completedNotificationStore.remove(downloadId, storedGeneration);
                                    JSObject failedData = new JSObject();
                                    failedData.put("id", downloadId);
                                    failedData.put("error", errorMessage != null ? errorMessage : "Download failed");
                                    notifyListeners("downloadFailed", failedData);
                                }
                            })
                    );
                } catch (RuntimeException e) {
                    okHttpDownloadExecutor.abandonTransfer(okHttpReservation);
                    applyOkHttpStartFailureIfCurrent(id, storedGeneration, destinationFile, e.getMessage());
                }
            },
            () -> {
                downloads.remove(id, pendingToken);
                okHttpDestinationFiles.remove(id);
                completedNotificationStore.remove(id, storedGeneration);
            }
        );
    }

    private boolean isOkHttpDownload(long trackedDownloadId) {
        return trackedDownloadId == OkHttpDownloadExecutor.TRACKED_DOWNLOAD_ID;
    }

    private void startProgressCheck(final String id, final long downloadId) {
        runProgressQuery(id, true, downloadId);
    }

    private void checkDownloadStatus(String id) {
        Long trackedDownloadId = downloads.get(id);
        if (trackedDownloadId == null || isPendingDownload(trackedDownloadId)) {
            return;
        }
        runProgressQuery(id, false, trackedDownloadId);
    }

    private void runProgressQuery(final String id, final boolean scheduleNext, final long systemDownloadId) {
        if (!isTrackedDownload(id, systemDownloadId)) {
            return;
        }

        ExecutorService executor = downloadManagerExecutor;
        if (executor == null) {
            return;
        }

        final Long capturedGeneration = generationFor(id);

        try {
            executor.execute(() -> {
                ProgressSnapshot snapshot = queryProgressSnapshot(id, systemDownloadId);
                handler.post(() -> deliverProgressSnapshot(id, systemDownloadId, scheduleNext, snapshot, capturedGeneration));
            });
        } catch (RejectedExecutionException ignored) {
            // Plugin is shutting down; stop polling quietly.
        }
    }

    private ProgressSnapshot queryProgressSnapshot(String id, long systemDownloadId) {
        if (!isTrackedDownload(id, systemDownloadId)) {
            return null;
        }

        DownloadManager.Query query = new DownloadManager.Query().setFilterById(systemDownloadId);
        Cursor cursor = downloadManager.query(query);
        if (cursor == null) {
            return ProgressSnapshot.notFound(id);
        }
        try (cursor) {
            if (!cursor.moveToFirst()) {
                return ProgressSnapshot.notFound(id);
            }

            int status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
            long bytesDownloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
            long bytesTotal = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));
            float progress = bytesTotal > 0 ? (float) bytesDownloaded / bytesTotal : 0f;
            return new ProgressSnapshot(id, progress, status, true);
        }
    }

    private void deliverProgressSnapshot(
        String id,
        long systemDownloadId,
        boolean scheduleNext,
        ProgressSnapshot snapshot,
        Long capturedGeneration
    ) {
        if (snapshot == null || !snapshot.found || !isTrackedDownload(id, systemDownloadId)) {
            return;
        }

        JSObject progressData = new JSObject();
        progressData.put("id", snapshot.id);
        progressData.put("progress", snapshot.progress);
        notifyListeners("downloadProgress", progressData);

        boolean shouldContinue = true;
        if (snapshot.status == DownloadManager.STATUS_SUCCESSFUL) {
            JSObject completedData = new JSObject();
            completedData.put("id", snapshot.id);
            notifyListeners("downloadCompleted", completedData);
            String completionText =
                capturedGeneration != null ? completedNotificationStore.takeText(snapshot.id, capturedGeneration) : null;
            if (completionText != null) {
                DownloadCompletedNotificationPresenter.showIfAllowed(getContext(), snapshot.id, completionText);
            }
            shouldContinue = false;
        } else if (snapshot.status == DownloadManager.STATUS_FAILED) {
            JSObject failedData = new JSObject();
            failedData.put("id", snapshot.id);
            failedData.put("error", "Download failed");
            notifyListeners("downloadFailed", failedData);
            if (capturedGeneration != null) {
                completedNotificationStore.remove(snapshot.id, capturedGeneration);
            }
            shouldContinue = false;
        }

        if (scheduleNext && shouldContinue) {
            handler.postDelayed(() -> runProgressQuery(id, true, systemDownloadId), 1000);
        }
    }

    private static final class ProgressSnapshot {

        private final String id;
        private final float progress;
        private final int status;
        private final boolean found;

        private ProgressSnapshot(String id, float progress, int status, boolean found) {
            this.id = id;
            this.progress = progress;
            this.status = status;
            this.found = found;
        }

        private static ProgressSnapshot notFound(String id) {
            return new ProgressSnapshot(id, 0f, -1, false);
        }
    }

    @PluginMethod
    public void pause(PluginCall call) {
        // DownloadManager doesn't support pausing individual downloads
        call.reject("Pausing individual downloads is not supported on Android");
    }

    @PluginMethod
    public void resume(PluginCall call) {
        // DownloadManager doesn't support resuming individual downloads
        call.reject("Resuming individual downloads is not supported on Android");
    }

    @PluginMethod
    public void stop(PluginCall call) {
        String id = call.getString("id");
        if (id == null) {
            call.reject("Download not found");
            return;
        }

        final Long stoppedGeneration = generationFor(id);
        Long downloadId = downloads.remove(id);
        if (downloadId == null) {
            call.reject("Download not found");
            return;
        }

        if (isPendingDownload(downloadId)) {
            okHttpDestinationFiles.remove(id);
            if (stoppedGeneration != null) {
                completedNotificationStore.remove(id, stoppedGeneration);
            }
            call.resolve(new JSObject().put("removed", false));
            return;
        }

        if (isOkHttpDownload(downloadId)) {
            File destinationFile = okHttpDestinationFiles.remove(id);
            boolean cancelled = okHttpDownloadExecutor.cancel(id, destinationFile);
            okHttpDownloadExecutor.clearCompleted(id);
            if (stoppedGeneration != null) {
                completedNotificationStore.remove(id, stoppedGeneration);
            }
            call.resolve(new JSObject().put("removed", cancelled));
            return;
        }

        final long systemDownloadId = downloadId;
        final String stoppedId = id;
        final long generation = stoppedGeneration != null ? stoppedGeneration.longValue() : 0L;
        runDownloadManagerWork(
            call,
            () -> {
                try {
                    int removedDownloads = downloadManager.remove(systemDownloadId);
                    if (stoppedGeneration != null) {
                        completedNotificationStore.remove(stoppedId, generation);
                    }
                    call.resolve(new JSObject().put("removed", removedDownloads > 0));
                } catch (RuntimeException e) {
                    downloads.putIfAbsent(stoppedId, systemDownloadId);
                    call.reject("Download could not be removed", e);
                }
            },
            () -> downloads.putIfAbsent(stoppedId, systemDownloadId)
        );
    }

    @PluginMethod
    public void checkStatus(PluginCall call) {
        String id = call.getString("id");
        if (id == null) {
            call.reject("Download not found");
            return;
        }

        Long trackedDownloadId = downloads.get(id);
        if (trackedDownloadId == null || isPendingDownload(trackedDownloadId)) {
            call.reject("Download not found");
            return;
        }

        if (isOkHttpDownload(trackedDownloadId)) {
            OkHttpDownloadExecutor.ActiveDownload active = okHttpDownloadExecutor.getActive(id);
            JSObject result = new JSObject();
            result.put("id", id);
            if (active == null) {
                call.reject("Download not found");
                return;
            } else {
                result.put("status", mapOkHttpStateToDownloadManagerStatus(active.state));
                result.put("bytesDownloaded", active.bytesWritten);
                result.put("bytesTotal", active.bytesTotal);
                if (active.state == OkHttpDownloadExecutor.State.ERROR && active.errorMessage != null) {
                    result.put("reasonText", active.errorMessage);
                }
            }
            call.resolve(result);
            return;
        }

        final long downloadId = trackedDownloadId;
        runDownloadManagerWork(call, () -> {
            DownloadManager.Query query = new DownloadManager.Query().setFilterById(downloadId);
            try {
                Cursor cursor = downloadManager.query(query);
                if (cursor == null) {
                    call.reject("Download not found");
                    return;
                }
                try (cursor) {
                    if (cursor.moveToFirst()) {
                        call.resolve(getDownloadStatus(cursor));
                    } else {
                        call.reject("Download not found");
                    }
                }
            } catch (RuntimeException e) {
                call.reject("Download status could not be read", e);
            }
        });
    }

    private void runDownloadManagerWork(PluginCall call, Runnable work) {
        runDownloadManagerWork(call, work, null);
    }

    private void runDownloadManagerWork(PluginCall call, Runnable work, Runnable onFailure) {
        ExecutorService executor = downloadManagerExecutor;
        if (executor == null) {
            if (onFailure != null) {
                onFailure.run();
            }
            call.reject("Download manager is not available");
            return;
        }

        try {
            executor.execute(work);
        } catch (RejectedExecutionException e) {
            if (onFailure != null) {
                onFailure.run();
            }
            call.reject("Download manager is shutting down", e);
        }
    }

    private JSObject getDownloadStatus(Cursor cursor) {
        int status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
        long bytesDownloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
        long bytesTotal = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));

        JSObject result = new JSObject();
        result.put("status", status);
        result.put("bytesDownloaded", bytesDownloaded);
        result.put("bytesTotal", bytesTotal);

        if (status == DownloadManager.STATUS_FAILED) {
            int reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON));
            result.put("reason", reason);
            result.put("reasonText", getReasonText(status, reason));
        }

        return result;
    }

    private int mapOkHttpStateToDownloadManagerStatus(OkHttpDownloadExecutor.State state) {
        switch (state) {
            case PENDING:
                return DownloadManager.STATUS_PENDING;
            case RUNNING:
                return DownloadManager.STATUS_RUNNING;
            case DONE:
                return DownloadManager.STATUS_SUCCESSFUL;
            case ERROR:
            case CANCELLED:
                return DownloadManager.STATUS_FAILED;
            default:
                return DownloadManager.STATUS_PENDING;
        }
    }

    private String getReasonText(int status, int reason) {
        if (status == DownloadManager.STATUS_FAILED) {
            switch (reason) {
                case DownloadManager.ERROR_CANNOT_RESUME:
                    return "ERROR_CANNOT_RESUME";
                case DownloadManager.ERROR_DEVICE_NOT_FOUND:
                    return "ERROR_DEVICE_NOT_FOUND";
                case DownloadManager.ERROR_FILE_ALREADY_EXISTS:
                    return "ERROR_FILE_ALREADY_EXISTS";
                case DownloadManager.ERROR_FILE_ERROR:
                    return "ERROR_FILE_ERROR";
                case DownloadManager.ERROR_HTTP_DATA_ERROR:
                    return "ERROR_HTTP_DATA_ERROR";
                case DownloadManager.ERROR_INSUFFICIENT_SPACE:
                    return "ERROR_INSUFFICIENT_SPACE";
                case DownloadManager.ERROR_TOO_MANY_REDIRECTS:
                    return "ERROR_TOO_MANY_REDIRECTS";
                case DownloadManager.ERROR_UNHANDLED_HTTP_CODE:
                    return "ERROR_UNHANDLED_HTTP_CODE";
                default:
                    return "ERROR_UNKNOWN";
            }
        }
        return "UNKNOWN";
    }

    @PluginMethod
    public void getFileInfo(PluginCall call) {
        String path = call.getString("path");
        if (path == null) {
            call.reject("Missing path");
            return;
        }

        Uri fileUri = Uri.parse(path);
        JSObject result = new JSObject();
        result.put("size", fileUri.getPath() != null ? new java.io.File(fileUri.getPath()).length() : 0);
        result.put("type", getContext().getContentResolver().getType(fileUri));
        call.resolve(result);
    }

    @Override
    protected void handleOnDestroy() {
        super.handleOnDestroy();
        if (downloadReceiver != null) {
            getContext().unregisterReceiver(downloadReceiver);
        }
        if (downloadManagerExecutor != null) {
            downloadManagerExecutor.shutdown();
            downloadManagerExecutor = null;
        }
    }

    @PluginMethod
    public void getPluginVersion(final PluginCall call) {
        try {
            final JSObject ret = new JSObject();
            ret.put("version", this.pluginVersion);
            call.resolve(ret);
        } catch (final Exception e) {
            call.reject("Could not get plugin version", e);
        }
    }
}
