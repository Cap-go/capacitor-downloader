package ee.forgr.capacitor.plugin.downloader;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.SystemClock;
import androidx.annotation.VisibleForTesting;
import androidx.core.app.NotificationCompat;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Ongoing progress notifications for OkHttp downloads when {@code notification} is {@code progress}.
 */
final class OkHttpDownloadProgressNotifier {

    static final String CHANNEL_ID = "capgo_capacitor_downloader_okhttp";
    private static final String CHANNEL_NAME = "Downloads";
    private static final int NOTIFICATION_ID = 0x44554f57;
    private static final long UPDATE_INTERVAL_MS = 1_000L;

    private final Context context;
    private final NotificationManager notificationManager;
    private final ConcurrentHashMap<String, ProgressEntry> entries = new ConcurrentHashMap<>();
    private final AtomicInteger activeDownloads = new AtomicInteger(0);
    private final Object serviceLock = new Object();
    private volatile Notification lastForegroundNotification;

    OkHttpDownloadProgressNotifier(Context context) {
        this.context = context.getApplicationContext();
        this.notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        ensureChannel();
    }

    /**
     * Registers progress tracking. Always returns true: a foreground service or notification failure
     * must not block the download (8.7.0 behavior for default {@code completed}).
     */
    boolean started(String downloadId, String title, String description, String notificationMode) {
        if (!shouldShowProgress(notificationMode)) {
            return true;
        }
        synchronized (serviceLock) {
            entries.put(downloadId, new ProgressEntry(title, description, notificationMode));
            activeDownloads.incrementAndGet();
            OkHttpDownloadForegroundService.notifyActiveDownloads(context, activeDownloads.get());
            OkHttpDownloadForegroundService.requestStart(context);
        }
        postProgress(downloadId, 0f, true);
        return true;
    }

    void update(String downloadId, float progress) {
        ProgressEntry entry = entries.get(downloadId);
        if (entry == null) {
            return;
        }
        long now = SystemClock.elapsedRealtime();
        if (now - entry.lastPostedAt < UPDATE_INTERVAL_MS && progress < 1f) {
            return;
        }
        postProgress(downloadId, progress, false);
        entry.lastPostedAt = now;
    }

    void finished(String downloadId, boolean success) {
        synchronized (serviceLock) {
            ProgressEntry entry = entries.remove(downloadId);
            if (entry == null) {
                return;
            }
            releaseOneActiveDownload();
            if (!success || "progress".equals(entry.notificationMode)) {
                cancelNotification(downloadId);
            } else if (success) {
                postCompleted(downloadId, entry);
            }
            scheduleForegroundStopIfIdle();
        }
    }

    void abandonDownload(String downloadId) {
        synchronized (serviceLock) {
            if (entries.remove(downloadId) != null) {
                releaseOneActiveDownload();
                cancelNotification(downloadId);
                scheduleForegroundStopIfIdle();
            }
        }
    }

    void shutdown() {
        synchronized (serviceLock) {
            for (String downloadId : entries.keySet()) {
                cancelNotification(downloadId);
            }
            entries.clear();
            activeDownloads.set(0);
            lastForegroundNotification = null;
            sharedForegroundNotification = null;
            OkHttpDownloadForegroundService.notifyActiveDownloads(context, 0);
        }
    }

    private static volatile Notification sharedForegroundNotification;

    @VisibleForTesting
    static volatile boolean simulateNotificationPostSecurityExceptionForTests = false;

    @VisibleForTesting
    static void setSimulateNotificationPostSecurityExceptionForTests(boolean value) {
        simulateNotificationPostSecurityExceptionForTests = value;
    }

    static Notification foregroundServiceNotification(Context context) {
        Notification pinned = sharedForegroundNotification;
        if (pinned != null) {
            return pinned;
        }
        ensureChannelStatic(context);
        return new NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build();
    }

    private void releaseOneActiveDownload() {
        activeDownloads.updateAndGet((value) -> Math.max(0, value - 1));
    }

    private void scheduleForegroundStopIfIdle() {
        OkHttpDownloadForegroundService.notifyActiveDownloads(context, activeDownloads.get());
    }

    private void postProgress(String downloadId, float progress, boolean force) {
        ProgressEntry entry = entries.get(downloadId);
        if (entry == null) {
            return;
        }
        int percentage = Math.round(Math.min(Math.max(progress, 0f), 1f) * 100f);
        String contentTitle = resolveTitle(entry);
        String contentText = percentage + "%";
        if (entry.description != null && !entry.description.isEmpty()) {
            contentText = entry.description + " · " + contentText;
        }
        Notification notification = new NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setProgress(100, percentage, false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(launchIntent())
            .setWhen(entry.startedAt)
            .build();
        try {
            if (simulateNotificationPostSecurityExceptionForTests) {
                throw new SecurityException("test: POST_NOTIFICATIONS denied");
            }
            notificationManager.notify(notificationTagFor(downloadId), NOTIFICATION_ID, notification);
            lastForegroundNotification = notification;
            sharedForegroundNotification = notification;
        } catch (SecurityException ignored) {
            handleNotificationPostFailure(downloadId);
        }
    }

    private void handleNotificationPostFailure(String downloadId) {
        synchronized (serviceLock) {
            if (entries.remove(downloadId) != null) {
                releaseOneActiveDownload();
                scheduleForegroundStopIfIdle();
            }
        }
    }

    private void postCompleted(String downloadId, ProgressEntry entry) {
        Notification notification = new NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(resolveTitle(entry))
            .setContentText(entry.description != null && !entry.description.isEmpty() ? entry.description : "Download complete")
            .setOngoing(false)
            .setAutoCancel(true)
            .setContentIntent(launchIntent())
            .setWhen(entry.startedAt)
            .build();
        try {
            notificationManager.notify(notificationTagFor(downloadId), NOTIFICATION_ID, notification);
        } catch (SecurityException ignored) {
            return;
        }
    }

    private void cancelNotification(String downloadId) {
        notificationManager.cancel(notificationTagFor(downloadId), NOTIFICATION_ID);
    }

    private String resolveTitle(ProgressEntry entry) {
        if (entry.title != null && !entry.title.isEmpty()) {
            return entry.title;
        }
        return "Downloading";
    }

    static boolean shouldShowProgressForMode(String notificationMode) {
        return "progress".equals(notificationMode);
    }

    static String notificationTagForDownload(String downloadId) {
        return "capgo_okhttp_" + (downloadId != null ? downloadId : "");
    }

    static int notificationIdForDownload(String downloadId) {
        return NOTIFICATION_ID;
    }

    private boolean shouldShowProgress(String notificationMode) {
        return shouldShowProgressForMode(notificationMode);
    }

    private String notificationTagFor(String downloadId) {
        return notificationTagForDownload(downloadId);
    }

    private PendingIntent launchIntent() {
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launch == null) {
            return null;
        }
        return PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private void ensureChannel() {
        ensureChannelStatic(context);
    }

    private static void ensureChannelStatic(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager == null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Download progress");
        notificationManager.createNotificationChannel(channel);
    }

    private static final class ProgressEntry {

        final String title;
        final String description;
        final String notificationMode;
        final long startedAt;
        long lastPostedAt;

        ProgressEntry(String title, String description, String notificationMode) {
            this.title = title;
            this.description = description;
            this.notificationMode = notificationMode;
            this.startedAt = System.currentTimeMillis();
            this.lastPostedAt = SystemClock.elapsedRealtime();
        }
    }
}
