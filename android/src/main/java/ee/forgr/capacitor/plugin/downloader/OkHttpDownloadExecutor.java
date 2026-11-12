package ee.forgr.capacitor.plugin.downloader;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import com.getcapacitor.JSObject;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import okhttp3.Call;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

public class OkHttpDownloadExecutor {

    public static final long TRACKED_DOWNLOAD_ID = -2L;

    public enum State {
        PENDING,
        RUNNING,
        DONE,
        ERROR,
        CANCELLED
    }

    public static final class ActiveDownload {

        public final String id;
        public volatile State state = State.PENDING;
        public volatile float progress;
        public volatile long bytesWritten;
        public volatile long bytesTotal;
        public volatile String errorMessage;
        public volatile Call call;
        public volatile File tempFile;
        public final AtomicBoolean cancelled = new AtomicBoolean(false);

        ActiveDownload(String id) {
            this.id = id;
        }
    }

    private final OkHttpClient client = new OkHttpClient.Builder().build();
    private final Map<String, ActiveDownload> activeDownloads = new ConcurrentHashMap<>();
    private final Context context;

    public OkHttpDownloadExecutor(Context context) {
        this.context = context.getApplicationContext();
    }

    public ActiveDownload getActive(String id) {
        return activeDownloads.get(id);
    }

    public void start(
        String id,
        String url,
        File destinationFile,
        JSObject headers,
        String network,
        ProgressReporter reporter,
        CompletionListener completionListener
    ) {
        if ("wifi-only".equals(network) && !isOnWifi()) {
            throw new IllegalStateException("Wi-Fi required for this download");
        }

        ActiveDownload active = new ActiveDownload(id);
        if (activeDownloads.putIfAbsent(id, active) != null) {
            throw new IllegalStateException("Download already exists");
        }

        File tempFile = null;
        try {
            Request.Builder requestBuilder = new Request.Builder().url(url);
            if (headers != null) {
                Iterator<String> it = headers.keys();
                if (it != null) {
                    while (it.hasNext()) {
                        String key = it.next();
                        requestBuilder.addHeader(key, headers.getString(key));
                    }
                }
            }

            Request request = requestBuilder.build();
            Call call = client.newCall(request);
            active.call = call;
            active.state = State.RUNNING;
            File parent = destinationFile.getParentFile();
            if (parent != null && !parent.exists() && !parent.mkdirs()) {
                throw new IOException("Could not create destination directory");
            }

            tempFile = File.createTempFile(
                destinationFile.getName() + "-",
                ".capgo-download",
                parent != null ? parent : destinationFile.getParentFile()
            );
            active.tempFile = tempFile;

            try (Response response = call.execute()) {
                if (active.cancelled.get()) {
                    active.state = State.CANCELLED;
                    tempFile.delete();
                    completionListener.onFinished(id, false, "Download was cancelled");
                    return;
                }

                if (!response.isSuccessful()) {
                    active.state = State.ERROR;
                    active.errorMessage = "HTTP " + response.code();
                    tempFile.delete();
                    completionListener.onFinished(id, false, active.errorMessage);
                    return;
                }

                ResponseBody body = response.body();
                if (body == null) {
                    active.state = State.ERROR;
                    active.errorMessage = "Empty response body";
                    tempFile.delete();
                    completionListener.onFinished(id, false, active.errorMessage);
                    return;
                }

                long total = body.contentLength();
                active.bytesTotal = total > 0 ? total : 0L;

                try (InputStream input = body.byteStream(); FileOutputStream output = new FileOutputStream(tempFile)) {
                    byte[] buffer = new byte[8192];
                    long written = 0L;
                    int read;
                    while ((read = input.read(buffer)) != -1) {
                        if (active.cancelled.get()) {
                            active.state = State.CANCELLED;
                            tempFile.delete();
                            completionListener.onFinished(id, false, "Download was cancelled");
                            return;
                        }
                        output.write(buffer, 0, read);
                        written += read;
                        active.bytesWritten = written;
                        if (total > 0) {
                            active.progress = (float) written / (float) total;
                        }
                        reporter.reportProgress(id, active.progress);
                    }
                }

                if (destinationFile.exists() && !destinationFile.delete()) {
                    throw new IOException("Could not replace existing destination file");
                }
                if (!tempFile.renameTo(destinationFile)) {
                    throw new IOException("Could not move downloaded file into place");
                }
                tempFile = null;
                active.tempFile = null;

                active.bytesWritten = destinationFile.length();
                active.progress = 1f;
                active.state = State.DONE;
                reporter.reportProgress(id, 1f);
                completionListener.onFinished(id, true, null);
            }
        } catch (IOException e) {
            if (tempFile != null && tempFile.exists()) {
                tempFile.delete();
            }
            if (active.cancelled.get()) {
                active.state = State.CANCELLED;
                activeDownloads.remove(id, active);
                completionListener.onFinished(id, false, "Download was cancelled");
            } else {
                active.state = State.ERROR;
                active.errorMessage = e.getMessage() != null ? e.getMessage() : "Download failed";
                completionListener.onFinished(id, false, active.errorMessage);
            }
        } catch (RuntimeException e) {
            activeDownloads.remove(id, active);
            throw e;
        }
    }

    public boolean cancel(String id, File destinationFile) {
        ActiveDownload active = activeDownloads.get(id);
        if (active == null) {
            return false;
        }
        active.cancelled.set(true);
        Call call = active.call;
        if (call != null) {
            call.cancel();
        }
        File temp = active.tempFile;
        if (temp != null && temp.exists()) {
            temp.delete();
        }
        activeDownloads.remove(id, active);
        return true;
    }

    public void clearCompleted(String id) {
        ActiveDownload active = activeDownloads.get(id);
        if (active != null && (active.state == State.DONE || active.state == State.ERROR || active.state == State.CANCELLED)) {
            activeDownloads.remove(id, active);
        }
    }

    public boolean isWifiSatisfied(String network) {
        return !"wifi-only".equals(network) || isOnWifi();
    }

    private boolean isOnWifi() {
        ConnectivityManager connectivityManager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (connectivityManager == null) {
            return false;
        }
        Network network = connectivityManager.getActiveNetwork();
        if (network == null) {
            return false;
        }
        NetworkCapabilities capabilities = connectivityManager.getNetworkCapabilities(network);
        return capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI);
    }

    public interface ProgressReporter {
        void reportProgress(String id, float progress);
    }

    public interface CompletionListener {
        void onFinished(String id, boolean success, String errorMessage);
    }
}
