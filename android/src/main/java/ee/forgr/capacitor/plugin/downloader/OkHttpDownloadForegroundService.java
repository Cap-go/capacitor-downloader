package ee.forgr.capacitor.plugin.downloader;

import android.app.Notification;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.IBinder;
import androidx.annotation.VisibleForTesting;
import androidx.core.app.ServiceCompat;

/**
 * Optional dataSync foreground service for OkHttp {@code notification: 'progress'} downloads only.
 */
public class OkHttpDownloadForegroundService extends Service {

    static final int SERVICE_NOTIFICATION_ID = 0x4f4b4854;
    private static final Object stateLock = new Object();
    private static boolean foregroundEstablished;
    private static boolean stopWhenForegroundReady;
    private static int lastKnownActiveDownloads;
    private static int foregroundPromotionCountForTests;
    static volatile boolean throwOnStartForTests = false;
    static volatile boolean throwStartNotAllowedForTests = false;
    static volatile boolean throwOnStartForegroundForTests = false;

    public static void setThrowStartNotAllowedForTests(boolean value) {
        throwStartNotAllowedForTests = value;
    }

    public static void setThrowOnStartForegroundForTests(boolean value) {
        throwOnStartForegroundForTests = value;
    }

    public static boolean requestStart(Context context) {
        if (throwOnStartForTests) {
            return false;
        }
        try {
            if (throwStartNotAllowedForTests) {
                throw new IllegalStateException("test: background FGS start not allowed");
            }
            Intent intent = new Intent(context, OkHttpDownloadForegroundService.class);
            androidx.core.content.ContextCompat.startForegroundService(context, intent);
            return true;
        } catch (RuntimeException ignored) {
            return false;
        }
    }

    public static void notifyActiveDownloads(Context context, int activeDownloads) {
        synchronized (stateLock) {
            lastKnownActiveDownloads = activeDownloads;
            if (activeDownloads > 0) {
                stopWhenForegroundReady = false;
                return;
            }
            if (!foregroundEstablished) {
                stopWhenForegroundReady = true;
                return;
            }
        }
        context.stopService(new Intent(context, OkHttpDownloadForegroundService.class));
    }

    public static void resetLifecycleStateForTests() {
        synchronized (stateLock) {
            foregroundEstablished = false;
            stopWhenForegroundReady = false;
            lastKnownActiveDownloads = 0;
            throwOnStartForTests = false;
            throwStartNotAllowedForTests = false;
            throwOnStartForegroundForTests = false;
            foregroundPromotionCountForTests = 0;
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @VisibleForTesting
    static int peekLastKnownActiveDownloadsForTests() {
        synchronized (stateLock) {
            return lastKnownActiveDownloads;
        }
    }

    @VisibleForTesting
    static int peekForegroundPromotionCountForTests() {
        return foregroundPromotionCountForTests;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification notification = OkHttpDownloadProgressNotifier.notificationForForegroundPromotion(this);
        try {
            if (throwOnStartForegroundForTests) {
                throw new RuntimeException("test: startForeground failed");
            }
            ServiceCompat.startForeground(this, SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
            OkHttpDownloadProgressNotifier.reconcileAfterForegroundPromotion(this);
            synchronized (stateLock) {
                foregroundEstablished = true;
                foregroundPromotionCountForTests += 1;
                boolean shouldStop = stopWhenForegroundReady || lastKnownActiveDownloads <= 0;
                stopWhenForegroundReady = false;
                if (shouldStop) {
                    stopSelf();
                }
            }
        } catch (RuntimeException ignored) {
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onTimeout(int startId, int fgsType) {
        stopSelf();
        super.onTimeout(startId, fgsType);
    }

    @Override
    public void onDestroy() {
        int activeDownloadsAtDestroy;
        synchronized (stateLock) {
            foregroundEstablished = false;
            stopWhenForegroundReady = false;
            activeDownloadsAtDestroy = lastKnownActiveDownloads;
        }
        int stopBehavior = activeDownloadsAtDestroy > 0 ? ServiceCompat.STOP_FOREGROUND_DETACH : ServiceCompat.STOP_FOREGROUND_REMOVE;
        ServiceCompat.stopForeground(this, stopBehavior);
        super.onDestroy();
    }
}
