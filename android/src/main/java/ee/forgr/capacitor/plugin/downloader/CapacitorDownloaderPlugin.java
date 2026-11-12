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
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicLong;

@CapacitorPlugin(name = "CapacitorDownloader")
public class CapacitorDownloaderPlugin extends Plugin {

    private final String pluginVersion = "8.3.20";

    private DownloadManager downloadManager;
    private final Map<String, Long> downloads = new ConcurrentHashMap<>();
    private final Map<String, DownloadBatchState> batches = new ConcurrentHashMap<>();
    private final AtomicLong pendingDownloadSequence = new AtomicLong(0);
    private ExecutorService downloadManagerExecutor;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BroadcastReceiver downloadReceiver;

    @Override
    public void load() {
        downloadManager = (DownloadManager) getContext().getSystemService(Context.DOWNLOAD_SERVICE);
        downloadManagerExecutor = Executors.newCachedThreadPool();
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
        return downloadId < 0;
    }

    private long reservePendingDownload() {
        return -pendingDownloadSequence.incrementAndGet();
    }

    private boolean isTrackedDownload(String id, long systemDownloadId) {
        Long trackedDownloadId = downloads.get(id);
        return trackedDownloadId != null && trackedDownloadId.longValue() == systemDownloadId;
    }

    @PluginMethod
    public void download(PluginCall call) {
        String id = call.getString("id");
        if (id == null) {
            call.reject("Missing required parameters");
            return;
        }

        JSArray files = call.getArray("files");
        if (files != null && files.length() > 0) {
            downloadBatch(call, id, files);
            return;
        }

        String url = call.getString("url");
        String destination = call.getString("destination");

        if (url == null || destination == null) {
            call.reject("Missing required parameters");
            return;
        }

        DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url))
            .setNotificationVisibility(DownloadNotificationVisibility.resolve(call.getString("notification")))
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true);

        // Handle custom destination
        File destinationFile = new File(getContext().getExternalFilesDir(null), destination);
        Uri destinationUri = Uri.fromFile(destinationFile);
        request.setDestinationUri(destinationUri);

        JSObject headers = call.getObject("headers");
        if (headers != null) {
            for (Iterator<String> it = headers.keys(); it.hasNext(); ) {
                String key = it.next();
                request.addRequestHeader(key, headers.getString(key));
            }
        }

        String network = call.getString("network");
        if ("wifi-only".equals(network)) {
            request.setAllowedNetworkTypes(DownloadManager.Request.NETWORK_WIFI);
        } else {
            request.setAllowedNetworkTypes(DownloadManager.Request.NETWORK_MOBILE | DownloadManager.Request.NETWORK_WIFI);
        }

        final String notification = call.getString("notification");
        final long pendingToken = reservePendingDownload();
        if (downloads.putIfAbsent(id, pendingToken) != null) {
            call.reject("Download already exists");
            return;
        }
        runDownloadManagerWork(
            call,
            () -> {
                if (!isTrackedDownload(id, pendingToken)) {
                    call.reject("Download was cancelled");
                    return;
                }

                long downloadId;
                try {
                    downloadId = downloadManager.enqueue(request);
                } catch (SecurityException e) {
                    downloads.remove(id, pendingToken);
                    if ("hidden".equals(notification)) {
                        call.reject("Hidden downloads require android.permission.DOWNLOAD_WITHOUT_NOTIFICATION in the app manifest", e);
                    } else {
                        call.reject("Download could not be enqueued due to missing permission", e);
                    }
                    return;
                } catch (RuntimeException e) {
                    downloads.remove(id, pendingToken);
                    call.reject("Download could not be enqueued", e);
                    return;
                }

                if (!downloads.replace(id, pendingToken, downloadId)) {
                    try {
                        downloadManager.remove(downloadId);
                    } catch (RuntimeException e) {
                        call.reject("Download was cancelled", e);
                        return;
                    }
                    call.reject("Download was cancelled");
                    return;
                }

                JSObject result = new JSObject();
                result.put("id", id);
                result.put("status", DownloadManager.STATUS_PENDING);
                call.resolve(result);

                // Start a periodic progress check
                startProgressCheck(id, downloadId);
            },
            () -> downloads.remove(id, pendingToken)
        );
    }

    private void downloadBatch(PluginCall call, String batchId, JSArray files) {
        if (batches.putIfAbsent(batchId, new DownloadBatchState(batchId, files.length())) != null || downloads.containsKey(batchId)) {
            call.reject("Download already exists");
            batches.remove(batchId);
            return;
        }

        final List<BatchFileRequest> fileRequests = new ArrayList<>();
        for (int index = 0; index < files.length(); index++) {
            JSObject fileObject = files.getJSObject(index);
            if (fileObject == null) {
                rollbackBatch(batchId);
                call.reject("Invalid file entry");
                return;
            }
            String url = fileObject.getString("url");
            String destination = fileObject.getString("destination");
            if (url == null || destination == null) {
                rollbackBatch(batchId);
                call.reject("Each file entry requires url and destination");
                return;
            }
            fileRequests.add(new BatchFileRequest(index, url, destination));
        }

        final JSObject headers = call.getObject("headers");
        final String network = call.getString("network");
        final String notification = call.getString("notification");

        runDownloadManagerWork(
            call,
            () -> {
                List<Long> enqueuedIds = new ArrayList<>();
                try {
                    for (BatchFileRequest fileRequest : fileRequests) {
                        if (isBatchCancelled(batchId) || !batches.containsKey(batchId)) {
                            removeSystemDownloads(enqueuedIds);
                            call.reject("Download was cancelled");
                            rollbackBatch(batchId);
                            return;
                        }

                        String childId = DownloadBatchState.fileTaskId(batchId, fileRequest.index);
                        if (downloads.putIfAbsent(childId, reservePendingDownload()) != null) {
                            removeSystemDownloads(enqueuedIds);
                            rollbackBatch(batchId);
                            call.reject("Download already exists");
                            return;
                        }

                        DownloadManager.Request request = buildDownloadRequest(
                            fileRequest.url,
                            fileRequest.destination,
                            headers,
                            network,
                            notification
                        );

                        long downloadId;
                        try {
                            downloadId = downloadManager.enqueue(request);
                        } catch (SecurityException e) {
                            downloads.remove(childId);
                            removeSystemDownloads(enqueuedIds);
                            rollbackBatch(batchId);
                            if ("hidden".equals(notification)) {
                                call.reject(
                                    "Hidden downloads require android.permission.DOWNLOAD_WITHOUT_NOTIFICATION in the app manifest",
                                    e
                                );
                            } else {
                                call.reject("Download could not be enqueued due to missing permission", e);
                            }
                            return;
                        } catch (RuntimeException e) {
                            downloads.remove(childId);
                            removeSystemDownloads(enqueuedIds);
                            rollbackBatch(batchId);
                            call.reject("Download could not be enqueued", e);
                            return;
                        }

                        if (!downloads.replace(childId, downloads.get(childId), downloadId)) {
                            try {
                                downloadManager.remove(downloadId);
                            } catch (RuntimeException ignored) {
                                // Best effort cleanup.
                            }
                            removeSystemDownloads(enqueuedIds);
                            rollbackBatch(batchId);
                            call.reject("Download was cancelled");
                            return;
                        }

                        enqueuedIds.add(downloadId);
                        startProgressCheck(childId, downloadId);
                    }

                    JSObject result = new JSObject();
                    result.put("id", batchId);
                    result.put("state", "RUNNING");
                    result.put("progress", 0);
                    call.resolve(result);
                } catch (RuntimeException e) {
                    removeSystemDownloads(enqueuedIds);
                    rollbackBatch(batchId);
                    call.reject("Download could not be enqueued", e);
                }
            },
            () -> rollbackBatch(batchId)
        );
    }

    private static final class BatchFileRequest {

        final int index;
        final String url;
        final String destination;

        BatchFileRequest(int index, String url, String destination) {
            this.index = index;
            this.url = url;
            this.destination = destination;
        }
    }

    private DownloadManager.Request buildDownloadRequest(
        String url,
        String destination,
        JSObject headers,
        String network,
        String notification
    ) {
        DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url))
            .setNotificationVisibility(DownloadNotificationVisibility.resolve(notification))
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true);

        File destinationFile = new File(getContext().getExternalFilesDir(null), destination);
        request.setDestinationUri(Uri.fromFile(destinationFile));

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

        return request;
    }

    private boolean isBatchCancelled(String batchId) {
        DownloadBatchState batch = batches.get(batchId);
        return batch != null && batch.cancelled.get();
    }

    private void rollbackBatch(String batchId) {
        DownloadBatchState batch = batches.remove(batchId);
        if (batch != null) {
            for (int index = 0; index < batch.fileCount; index++) {
                downloads.remove(DownloadBatchState.fileTaskId(batchId, index));
            }
        }
        downloads.remove(batchId);
    }

    private void removeSystemDownloads(List<Long> downloadIds) {
        for (Long downloadId : downloadIds) {
            if (downloadId == null) {
                continue;
            }
            try {
                downloadManager.remove(downloadId);
            } catch (RuntimeException ignored) {
                // Best effort cleanup.
            }
        }
    }

    private void failBatch(String batchId, String error, Integer fileIndex) {
        DownloadBatchState batch = batches.remove(batchId);
        if (batch == null || batch.failed.getAndSet(true)) {
            return;
        }

        List<Long> childDownloadIds = new ArrayList<>();
        for (int index = 0; index < batch.fileCount; index++) {
            String childId = DownloadBatchState.fileTaskId(batchId, index);
            Long childDownloadId = downloads.remove(childId);
            if (childDownloadId != null && !isPendingDownload(childDownloadId)) {
                childDownloadIds.add(childDownloadId);
            }
        }
        removeSystemDownloads(childDownloadIds);

        JSObject failedData = new JSObject();
        failedData.put("id", batchId);
        failedData.put("error", error);
        if (fileIndex != null) {
            failedData.put("fileIndex", fileIndex);
        }
        notifyListeners("downloadFailed", failedData);
    }

    private void notifyBatchProgress(String batchId, int fileIndex, float fileProgress, long bytesWritten, long bytesTotal) {
        DownloadBatchState batch = batches.get(batchId);
        if (batch == null || batch.failed.get() || batch.cancelled.get()) {
            return;
        }

        batch.updateFileProgress(fileIndex, fileProgress);
        float overall = batch.overallProgress();

        JSObject progressData = new JSObject();
        progressData.put("id", batchId);
        progressData.put("progress", overall);
        progressData.put("fileIndex", fileIndex);
        progressData.put("fileProgress", fileProgress);
        progressData.put("bytesWritten", bytesWritten);
        progressData.put("bytesTotal", bytesTotal);
        notifyListeners("downloadProgress", progressData);
    }

    private void completeBatchFile(String batchId, int fileIndex) {
        DownloadBatchState batch = batches.get(batchId);
        if (batch == null || batch.failed.get() || batch.cancelled.get()) {
            return;
        }

        boolean allDone = batch.markFileCompleted(fileIndex);
        notifyBatchProgress(batchId, fileIndex, 1f, 0, 0);

        if (allDone) {
            batches.remove(batchId);
            for (int index = 0; index < batch.fileCount; index++) {
                downloads.remove(DownloadBatchState.fileTaskId(batchId, index));
            }

            JSObject completedData = new JSObject();
            completedData.put("id", batchId);
            notifyListeners("downloadCompleted", completedData);
        }
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

        try {
            executor.execute(() -> {
                ProgressSnapshot snapshot = queryProgressSnapshot(id, systemDownloadId);
                handler.post(() -> deliverProgressSnapshot(id, systemDownloadId, scheduleNext, snapshot));
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
            return new ProgressSnapshot(id, progress, status, true, bytesDownloaded, bytesTotal);
        }
    }

    private void deliverProgressSnapshot(String id, long systemDownloadId, boolean scheduleNext, ProgressSnapshot snapshot) {
        if (snapshot == null || !snapshot.found || !isTrackedDownload(id, systemDownloadId)) {
            return;
        }

        DownloadBatchState.BatchIdParts batchParts = DownloadBatchState.parseFileTaskId(snapshot.id);
        boolean shouldContinue = true;

        if (batchParts != null) {
            if (snapshot.status == DownloadManager.STATUS_SUCCESSFUL) {
                completeBatchFile(batchParts.batchId, batchParts.fileIndex);
                shouldContinue = false;
            } else if (snapshot.status == DownloadManager.STATUS_FAILED) {
                failBatch(batchParts.batchId, "Download failed", batchParts.fileIndex);
                shouldContinue = false;
            } else {
                notifyBatchProgress(
                    batchParts.batchId,
                    batchParts.fileIndex,
                    snapshot.progress,
                    snapshot.bytesDownloaded,
                    snapshot.bytesTotal
                );
            }
        } else {
            JSObject progressData = new JSObject();
            progressData.put("id", snapshot.id);
            progressData.put("progress", snapshot.progress);
            progressData.put("bytesWritten", snapshot.bytesDownloaded);
            progressData.put("bytesTotal", snapshot.bytesTotal);
            notifyListeners("downloadProgress", progressData);

            if (snapshot.status == DownloadManager.STATUS_SUCCESSFUL) {
                JSObject completedData = new JSObject();
                completedData.put("id", snapshot.id);
                notifyListeners("downloadCompleted", completedData);
                shouldContinue = false;
            } else if (snapshot.status == DownloadManager.STATUS_FAILED) {
                JSObject failedData = new JSObject();
                failedData.put("id", snapshot.id);
                failedData.put("error", "Download failed");
                notifyListeners("downloadFailed", failedData);
                shouldContinue = false;
            }
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
        private final long bytesDownloaded;
        private final long bytesTotal;

        private ProgressSnapshot(String id, float progress, int status, boolean found, long bytesDownloaded, long bytesTotal) {
            this.id = id;
            this.progress = progress;
            this.status = status;
            this.found = found;
            this.bytesDownloaded = bytesDownloaded;
            this.bytesTotal = bytesTotal;
        }

        private static ProgressSnapshot notFound(String id) {
            return new ProgressSnapshot(id, 0f, -1, false, 0, 0);
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

        if (batches.containsKey(id)) {
            stopBatch(call, id);
            return;
        }

        Long downloadId = downloads.remove(id);
        if (downloadId == null) {
            call.reject("Download not found");
            return;
        }

        if (isPendingDownload(downloadId)) {
            call.resolve(new JSObject().put("removed", false));
            return;
        }

        final long systemDownloadId = downloadId;
        final String stoppedId = id;
        runDownloadManagerWork(
            call,
            () -> {
                try {
                    int removedDownloads = downloadManager.remove(systemDownloadId);
                    call.resolve(new JSObject().put("removed", removedDownloads > 0));
                } catch (RuntimeException e) {
                    downloads.putIfAbsent(stoppedId, systemDownloadId);
                    call.reject("Download could not be removed", e);
                }
            },
            () -> downloads.putIfAbsent(stoppedId, systemDownloadId)
        );
    }

    private void stopBatch(PluginCall call, String batchId) {
        DownloadBatchState batch = batches.remove(batchId);
        if (batch == null) {
            call.reject("Download not found");
            return;
        }
        batch.cancelled.set(true);

        List<Long> childDownloadIds = new ArrayList<>();
        for (int index = 0; index < batch.fileCount; index++) {
            String childId = DownloadBatchState.fileTaskId(batchId, index);
            Long childDownloadId = downloads.remove(childId);
            if (childDownloadId != null && !isPendingDownload(childDownloadId)) {
                childDownloadIds.add(childDownloadId);
            }
        }

        runDownloadManagerWork(
            call,
            () -> {
                removeSystemDownloads(childDownloadIds);
                call.resolve(new JSObject().put("removed", !childDownloadIds.isEmpty()));
            },
            () -> batches.putIfAbsent(batchId, batch)
        );
    }

    @PluginMethod
    public void checkStatus(PluginCall call) {
        String id = call.getString("id");
        if (id == null) {
            call.reject("Download not found");
            return;
        }

        DownloadBatchState batch = batches.get(id);
        if (batch != null) {
            JSObject result = new JSObject();
            result.put("id", id);
            result.put("state", batch.failed.get() ? "ERROR" : "RUNNING");
            result.put("progress", batch.overallProgress());
            call.resolve(result);
            return;
        }

        Long trackedDownloadId = downloads.get(id);
        if (trackedDownloadId == null || isPendingDownload(trackedDownloadId)) {
            call.reject("Download not found");
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
