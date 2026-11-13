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
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicBoolean;
import okhttp3.Call;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

public class OkHttpDownloadExecutor {

    public static final long TRACKED_DOWNLOAD_ID = -2L;
    private static final int MAX_CONCURRENT_TRANSFERS = 4;

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
        public volatile File committedDestination;
        public volatile Network boundWifiNetwork;
        public final AtomicBoolean cancelled = new AtomicBoolean(false);

        ActiveDownload(String id) {
            this.id = id;
        }
    }

    private final OkHttpClient defaultClient;
    private final Map<String, ActiveDownload> activeDownloads = new ConcurrentHashMap<>();
    private final Semaphore transferSlots = new Semaphore(MAX_CONCURRENT_TRANSFERS);
    private final Context context;

    public OkHttpDownloadExecutor(Context context) {
        this.context = context.getApplicationContext();
        this.defaultClient = new OkHttpClient.Builder().followRedirects(true).followSslRedirects(false).build();
    }

    public ActiveDownload getActive(String id) {
        return activeDownloads.get(id);
    }

    /**
     * Reserve an in-memory slot before the transfer id is published to JS. Prevents a race where
     * {@code stop()} runs between marker publication and worker registration.
     */
    public boolean beginTransfer(String id) {
        ActiveDownload active = new ActiveDownload(id);
        active.state = State.PENDING;
        return activeDownloads.putIfAbsent(id, active) == null;
    }

    public void abandonTransfer(String id) {
        ActiveDownload active = activeDownloads.remove(id);
        if (active != null && active.call != null) {
            active.call.cancel();
        }
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
        ActiveDownload active = activeDownloads.get(id);
        if (active == null) {
            throw new IllegalStateException("Download not registered");
        }

        Network wifiNetwork = resolveWifiNetworkForTransfer(network);
        if ("wifi-only".equals(network) && (wifiNetwork == null || !isWifiNetworkUsable(wifiNetwork))) {
            activeDownloads.remove(id, active);
            throw new IllegalStateException("Wi-Fi required for this download");
        }

        boolean acquired = false;
        try {
            transferSlots.acquire();
            acquired = true;

            synchronized (active) {
                if (active.cancelled.get()) {
                    finishCancelled(active, null, id, completionListener);
                    return;
                }
            }

            if (wifiNetwork != null) {
                active.boundWifiNetwork = wifiNetwork;
            }
            OkHttpClient client = buildClientForNetwork(network, wifiNetwork);

            File tempFile = null;
            try {
                synchronized (active) {
                    if (active.cancelled.get()) {
                        finishCancelled(active, null, id, completionListener);
                        return;
                    }
                }

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
                synchronized (active) {
                    if (active.cancelled.get()) {
                        call.cancel();
                        finishCancelled(active, null, id, completionListener);
                        return;
                    }
                    active.call = call;
                }
                active.state = State.RUNNING;

                File parent = destinationFile.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) {
                    throw new IOException("Could not create destination directory");
                }

                tempFile = createTempDownloadFile(destinationFile, parent);
                active.tempFile = tempFile;

                try (Response response = call.execute()) {
                    if (active.cancelled.get()) {
                        finishCancelled(active, tempFile, id, completionListener);
                        return;
                    }

                    if (url.regionMatches(true, 0, "https:", 0, 6) && !response.request().url().isHttps()) {
                        active.state = State.ERROR;
                        active.errorMessage = "HTTPS to HTTP redirect is not allowed";
                        tempFile.delete();
                        completionListener.onFinished(id, false, false, active.errorMessage);
                        return;
                    }

                    int code = response.code();
                    if (code == 206) {
                        active.state = State.ERROR;
                        active.errorMessage = "Partial content (HTTP 206) is not supported";
                        tempFile.delete();
                        completionListener.onFinished(id, false, false, active.errorMessage);
                        return;
                    }

                    if (!response.isSuccessful()) {
                        active.state = State.ERROR;
                        active.errorMessage = "HTTP " + code;
                        tempFile.delete();
                        completionListener.onFinished(id, false, false, active.errorMessage);
                        return;
                    }

                    ResponseBody body = response.body();
                    if (body == null) {
                        active.state = State.ERROR;
                        active.errorMessage = "Empty response body";
                        tempFile.delete();
                        completionListener.onFinished(id, false, false, active.errorMessage);
                        return;
                    }

                    long total = body.contentLength();
                    active.bytesTotal = total > 0 ? total : 0L;

                    try (InputStream input = body.byteStream(); FileOutputStream output = new FileOutputStream(tempFile)) {
                        byte[] buffer = new byte[8192];
                        long written = 0L;
                        int read;
                        int lastReportedPercent = -1;
                        while ((read = input.read(buffer)) != -1) {
                            if (active.cancelled.get()) {
                                finishCancelled(active, tempFile, id, completionListener);
                                return;
                            }
                            output.write(buffer, 0, read);
                            written += read;
                            active.bytesWritten = written;
                            if (total > 0) {
                                active.progress = (float) written / (float) total;
                            }
                            int percent = (int) (active.progress * 100f);
                            if (percent != lastReportedPercent) {
                                lastReportedPercent = percent;
                                reporter.reportProgress(id, active.progress);
                            }
                        }
                    }

                    if (!commitTempToDestination(active, tempFile, destinationFile)) {
                        finishCancelled(active, tempFile, id, completionListener);
                        return;
                    }
                    tempFile = null;

                    reporter.reportProgress(id, 1f);
                    completionListener.onFinished(id, true, false, null);
                }
            } catch (IOException e) {
                if (tempFile != null && tempFile.exists()) {
                    tempFile.delete();
                }
                if (active.cancelled.get()) {
                    active.state = State.CANCELLED;
                    completionListener.onFinished(id, false, true, null);
                } else {
                    active.state = State.ERROR;
                    active.errorMessage = e.getMessage() != null ? e.getMessage() : "Download failed";
                    completionListener.onFinished(id, false, false, active.errorMessage);
                }
            } catch (RuntimeException e) {
                activeDownloads.remove(id, active);
                throw e;
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            active.state = State.ERROR;
            active.errorMessage = "Download interrupted";
            completionListener.onFinished(id, false, false, active.errorMessage);
        } finally {
            if (acquired) {
                transferSlots.release();
            }
        }
    }

    private boolean commitTempToDestination(ActiveDownload active, File tempFile, File destinationFile) throws IOException {
        synchronized (active) {
            if (active.cancelled.get()) {
                tempFile.delete();
                active.state = State.CANCELLED;
                return false;
            }
            active.tempFile = null;
            if (destinationFile.exists() && !destinationFile.delete()) {
                throw new IOException("Could not replace existing destination file");
            }
            if (active.cancelled.get()) {
                tempFile.delete();
                active.state = State.CANCELLED;
                return false;
            }
            if (!tempFile.renameTo(destinationFile)) {
                throw new IOException("Could not move downloaded file into place");
            }
            if (active.cancelled.get()) {
                destinationFile.delete();
                active.state = State.CANCELLED;
                return false;
            }
            active.committedDestination = destinationFile;
            active.bytesWritten = destinationFile.length();
            active.progress = 1f;
            active.state = State.DONE;
            return true;
        }
    }

    private void finishCancelled(ActiveDownload active, File tempFile, String id, CompletionListener completionListener) {
        active.state = State.CANCELLED;
        File toDelete = tempFile;
        if (toDelete == null) {
            synchronized (active) {
                toDelete = active.tempFile;
            }
        }
        if (toDelete != null && toDelete.exists()) {
            toDelete.delete();
        }
        completionListener.onFinished(id, false, true, null);
    }

    private static File createTempDownloadFile(File destinationFile, File parent) throws IOException {
        String baseName = destinationFile.getName();
        if (baseName.isEmpty()) {
            baseName = "download";
        }
        String prefix = baseName.length() >= 3 ? baseName : "dl" + baseName;
        if (prefix.length() < 3) {
            prefix = "cap";
        }
        return File.createTempFile(prefix + "-", ".capgo-download", parent != null ? parent : destinationFile.getParentFile());
    }

    private OkHttpClient buildClientForNetwork(String network, Network wifiNetwork) {
        if (!"wifi-only".equals(network)) {
            return defaultClient;
        }
        if (wifiNetwork == null) {
            throw new IllegalStateException("Wi-Fi required for this download");
        }
        return defaultClient.newBuilder().socketFactory(wifiNetwork.getSocketFactory()).build();
    }

    Network resolveWifiNetworkForTransfer(String network) {
        if (!"wifi-only".equals(network)) {
            return null;
        }
        return findWifiNetwork();
    }

    private Network findWifiNetwork() {
        ConnectivityManager connectivityManager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (connectivityManager == null) {
            return null;
        }
        for (Network network : connectivityManager.getAllNetworks()) {
            NetworkCapabilities capabilities = connectivityManager.getNetworkCapabilities(network);
            if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                return network;
            }
        }
        return null;
    }

    public boolean cancel(String id, File destinationFile) {
        ActiveDownload active = activeDownloads.get(id);
        if (active == null) {
            if (destinationFile != null && destinationFile.exists()) {
                return destinationFile.delete();
            }
            return false;
        }
        active.cancelled.set(true);
        Call call = active.call;
        if (call != null) {
            call.cancel();
        }
        synchronized (active) {
            File temp = active.tempFile;
            if (temp != null && temp.exists()) {
                temp.delete();
            }
            File committed = active.committedDestination;
            if (committed != null && committed.exists()) {
                committed.delete();
            } else if (destinationFile != null && destinationFile.exists() && active.state == State.DONE) {
                destinationFile.delete();
            }
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
        if (!"wifi-only".equals(network)) {
            return true;
        }
        Network wifi = resolveWifiNetworkForTransfer(network);
        return wifi != null && isWifiNetworkUsable(wifi);
    }

    private boolean isWifiNetworkUsable(Network network) {
        ConnectivityManager connectivityManager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (connectivityManager == null || network == null) {
            return false;
        }
        NetworkCapabilities capabilities = connectivityManager.getNetworkCapabilities(network);
        return (
            capabilities != null &&
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        );
    }

    public interface ProgressReporter {
        void reportProgress(String id, float progress);
    }

    public interface CompletionListener {
        void onFinished(String id, boolean success, boolean cancelled, String errorMessage);
    }
}
