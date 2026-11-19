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
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Ongoing progress notifications for OkHttp downloads when {@code notification} is {@code progress}.
 */
final class OkHttpDownloadProgressNotifier {

    static final String CHANNEL_ID = "capgo_capacitor_downloader_okhttp";
    private static final String CHANNEL_NAME = "Downloads";
    private static final int COMPLETED_NOTIFICATION_ID_BASE = 0x44554f57;
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
        synchronized (foregroundCoordinationLock) {
            foregroundCoordinator = this;
        }
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
            entries.put(downloadId, new ProgressEntry(title, description, notificationMode, SystemClock.elapsedRealtime(), 0f));
            activeDownloads.incrementAndGet();
            postAggregateNotification();
            OkHttpDownloadForegroundService.notifyActiveDownloads(context, activeDownloads.get());
            OkHttpDownloadForegroundService.requestStart(context);
        }
        return true;
    }

    void update(String downloadId, float progress) {
        ProgressEntry entry = entries.get(downloadId);
        if (entry == null) {
            return;
        }
        entry.progress = Math.min(Math.max(progress, 0f), 1f);
        long now = SystemClock.elapsedRealtime();
        if (now - entry.lastPostedAt < UPDATE_INTERVAL_MS && progress < 1f) {
            return;
        }
        synchronized (serviceLock) {
            postAggregateNotification();
        }
        entry.lastPostedAt = now;
    }

    void finished(String downloadId, boolean success) {
        synchronized (serviceLock) {
            ProgressEntry entry = entries.remove(downloadId);
            if (entry == null) {
                return;
            }
            releaseOneActiveDownload();
            if (entries.isEmpty()) {
                cancelServiceNotification();
            } else {
                postAggregateNotification();
            }
            if (success && !"progress".equals(entry.notificationMode)) {
                postCompleted(downloadId, entry);
            }
            scheduleForegroundStopIfIdle();
        }
    }

    void abandonDownload(String downloadId) {
        synchronized (serviceLock) {
            if (entries.remove(downloadId) != null) {
                releaseOneActiveDownload();
                if (entries.isEmpty()) {
                    cancelServiceNotification();
                } else {
                    postAggregateNotification();
                }
                scheduleForegroundStopIfIdle();
            }
        }
    }

    void shutdown() {
        synchronized (serviceLock) {
            entries.clear();
            activeDownloads.set(0);
            lastForegroundNotification = null;
            sharedForegroundNotification = null;
            cancelServiceNotification();
            OkHttpDownloadForegroundService.notifyActiveDownloads(context, 0);
        }
        synchronized (foregroundCoordinationLock) {
            if (foregroundCoordinator == this) {
                foregroundCoordinator = null;
            }
        }
    }

    private static final Object foregroundCoordinationLock = new Object();
    private static volatile OkHttpDownloadProgressNotifier foregroundCoordinator;
    private static volatile Notification sharedForegroundNotification;

    @VisibleForTesting
    static volatile boolean simulateNotificationPostSecurityExceptionForTests = false;

    @VisibleForTesting
    static void setSimulateNotificationPostSecurityExceptionForTests(boolean value) {
        simulateNotificationPostSecurityExceptionForTests = value;
    }

    static Notification foregroundServiceNotification(Context context) {
        return notificationForForegroundPromotion(context);
    }

    static Notification notificationForForegroundPromotion(Context context) {
        synchronized (foregroundCoordinationLock) {
            OkHttpDownloadProgressNotifier coordinator = foregroundCoordinator;
            if (coordinator != null) {
                synchronized (coordinator.serviceLock) {
                    if (!coordinator.entries.isEmpty()) {
                        Notification notification = coordinator.buildAggregateNotification();
                        coordinator.lastForegroundNotification = notification;
                        sharedForegroundNotification = notification;
                        return notification;
                    }
                }
            }
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
    }

    static void reconcileAfterForegroundPromotion(Context context) {
        reconcileForegroundNotificationOwnership(context);
    }

    static void reconcileAfterForegroundServiceStop(Context context) {
        reconcileForegroundNotificationOwnership(context);
    }

    private static void reconcileForegroundNotificationOwnership(Context context) {
        synchronized (foregroundCoordinationLock) {
            OkHttpDownloadProgressNotifier coordinator = foregroundCoordinator;
            if (coordinator == null) {
                return;
            }
            synchronized (coordinator.serviceLock) {
                if (coordinator.entries.isEmpty()) {
                    coordinator.cancelServiceNotification();
                    return;
                }
                coordinator.postAggregateNotification();
            }
        }
    }

    private void releaseOneActiveDownload() {
        activeDownloads.updateAndGet((value) -> Math.max(0, value - 1));
    }

    private void scheduleForegroundStopIfIdle() {
        OkHttpDownloadForegroundService.notifyActiveDownloads(context, activeDownloads.get());
    }

    private void postAggregateNotification() {
        if (entries.isEmpty()) {
            return;
        }
        Notification notification = buildAggregateNotification();
        try {
            if (simulateNotificationPostSecurityExceptionForTests) {
                throw new SecurityException("test: POST_NOTIFICATIONS denied");
            }
            notificationManager.notify(null, OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID, notification);
            lastForegroundNotification = notification;
            sharedForegroundNotification = notification;
        } catch (SecurityException ignored) {
            handleNotificationPostFailure();
        }
    }

    private void handleNotificationPostFailure() {
        synchronized (serviceLock) {
            entries.clear();
            activeDownloads.set(0);
            sharedForegroundNotification = null;
            lastForegroundNotification = null;
            scheduleForegroundStopIfIdle();
        }
    }

    private Notification buildAggregateNotification() {
        List<ProgressEntry> snapshot = new ArrayList<>(entries.values());
        int count = snapshot.size();
        if (count == 1) {
            ProgressEntry entry = snapshot.get(0);
            int percentage = Math.round(entry.progress * 100f);
            String contentTitle = resolveTitle(entry);
            String contentText = percentage + "%";
            if (entry.description != null && !entry.description.isEmpty()) {
                contentText = entry.description + " · " + contentText;
            }
            return new NotificationCompat.Builder(context, CHANNEL_ID)
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
        }

        StringBuilder titleBuilder = new StringBuilder();
        float progressSum = 0f;
        for (int i = 0; i < snapshot.size(); i++) {
            if (i > 0) {
                titleBuilder.append('\n');
            }
            titleBuilder.append(resolveTitle(snapshot.get(i)));
            progressSum += snapshot.get(i).progress;
        }
        int averagePercentage = Math.round((progressSum / count) * 100f);
        String contentText = count + " downloads · " + averagePercentage + "%";
        long sortWhen = earliestStartedAt(snapshot);
        return new NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(titleBuilder.toString())
            .setContentText(contentText)
            .setProgress(100, averagePercentage, false)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(titleBuilder.toString()))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(launchIntent())
            .setWhen(sortWhen)
            .build();
    }

    private static long earliestStartedAt(List<ProgressEntry> snapshot) {
        long earliest = Long.MAX_VALUE;
        for (ProgressEntry entry : snapshot) {
            earliest = Math.min(earliest, entry.startedAt);
        }
        return earliest;
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
            int notificationId = notificationIdForCompletedDownload(downloadId);
            notificationManager.notify(notificationTagForCompletedDownload(downloadId), notificationId, notification);
        } catch (SecurityException ignored) {
            return;
        }
    }

    private void cancelServiceNotification() {
        notificationManager.cancel(null, OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID);
        sharedForegroundNotification = null;
        lastForegroundNotification = null;
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

    static String notificationTagForCompletedDownload(String downloadId) {
        return "capgo_okhttp_done_" + (downloadId != null ? downloadId : "");
    }

    static int notificationIdForCompletedDownload(String downloadId) {
        return COMPLETED_NOTIFICATION_ID_BASE ^ (downloadId != null ? downloadId.hashCode() : 0);
    }

    private boolean shouldShowProgress(String notificationMode) {
        return shouldShowProgressForMode(notificationMode);
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
        /** Wall-clock download start; keeps parallel progress notifications sorted by start order. */
        final long startedAt;
        long lastPostedAt;
        float progress;

        ProgressEntry(String title, String description, String notificationMode, long lastPostedAt, float progress) {
            this.title = title;
            this.description = description;
            this.notificationMode = notificationMode;
            this.startedAt = System.currentTimeMillis();
            this.lastPostedAt = lastPostedAt;
            this.progress = progress;
        }
    }
}
