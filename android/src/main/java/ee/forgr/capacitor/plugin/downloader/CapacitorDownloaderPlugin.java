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
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

@CapacitorPlugin(name = "CapacitorDownloader")
public class CapacitorDownloaderPlugin extends Plugin {

    private DownloadManager downloadManager;
    private final Map<String, Long> downloads = new HashMap<>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BroadcastReceiver downloadReceiver;

    @Override
    public void load() {
        downloadManager = (DownloadManager) getContext().getSystemService(Context.DOWNLOAD_SERVICE);
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
        getContext().registerReceiver(downloadReceiver, new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE));
    }

    private String getDownloadIdByValue(long value) {
        for (Map.Entry<String, Long> entry : downloads.entrySet()) {
            if (entry.getValue() == value) {
                return entry.getKey();
            }
        }
        return null;
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

        DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url))
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true);

        // Handle custom destination
        File destinationFile = new File(getContext().getExternalFilesDir(null), destination);
        Uri destinationUri = Uri.fromFile(destinationFile);
        request.setDestinationUri(destinationUri);

        JSObject headers = call.getObject("headers");
        if (headers != null) {
            for (Iterator<String> it = headers.keys(); it.hasNext();) {
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

        long downloadId = downloadManager.enqueue(request);
        downloads.put(id, downloadId);

        JSObject result = new JSObject();
        result.put("id", id);
        result.put("status", DownloadManager.STATUS_PENDING);
        call.resolve(result);

        // Start a periodic progress check
        startProgressCheck(id, downloadId);
    }

    private void startProgressCheck(final String id, final long downloadId) {
        handler.post(
            new Runnable() {
                @Override
                public void run() {
                    if (checkDownloadStatus(id)) {
                        handler.postDelayed(this, 1000); // Check every second
                    }
                }
            }
        );
    }

    private boolean checkDownloadStatus(String id) {
        DownloadManager.Query query = new DownloadManager.Query().setFilterById(downloads.get(id));
        try (Cursor cursor = downloadManager.query(query)) {
            if (cursor.moveToFirst()) {
                int status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
                long bytesDownloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
                long bytesTotal = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));

                float progress = bytesTotal > 0 ? (float) bytesDownloaded / bytesTotal : 0f;

                JSObject progressData = new JSObject();
                progressData.put("id", id);
                progressData.put("progress", progress);
                notifyListeners("downloadProgress", progressData);

                if (status == DownloadManager.STATUS_SUCCESSFUL) {
                    JSObject completedData = new JSObject();
                    completedData.put("id", id);
                    notifyListeners("downloadCompleted", completedData);
                    return false; // Stop checking progress
                } else if (status == DownloadManager.STATUS_FAILED) {
                    JSObject failedData = new JSObject();
                    failedData.put("id", id);
                    failedData.put("error", "Download failed");
                    notifyListeners("downloadFailed", failedData);
                    return false; // Stop checking progress
                }
            }
        }
        return true; // Continue checking progress
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
        if (id == null || !downloads.containsKey(id)) {
            call.reject("Download not found");
            return;
        }
        int removedDownloads = downloadManager.remove(downloads.get(id));
        downloads.remove(id);
        call.resolve(new JSObject().put("removed", removedDownloads > 0));
    }

    @PluginMethod
    public void checkStatus(PluginCall call) {
        String id = call.getString("id");
        if (id == null || !downloads.containsKey(id)) {
            call.reject("Download not found");
            return;
        }

        DownloadManager.Query query = new DownloadManager.Query().setFilterById(downloads.get(id));
        try (Cursor cursor = downloadManager.query(query)) {
            if (cursor.moveToFirst()) {
                JSObject result = getDownloadStatus(cursor);
                call.resolve(result);
            } else {
                call.reject("Download not found");
            }
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
    }
}
