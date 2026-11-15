package ee.forgr.capacitor.plugin.downloader;

import android.app.Notification;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.IBinder;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;

/**
 * Optional dataSync foreground service for OkHttp {@code notification: 'progress'} downloads only.
 */
public class OkHttpDownloadForegroundService extends Service {

    private static final int SERVICE_NOTIFICATION_ID = 0x4f4b4854;
    private static final Object stateLock = new Object();
    private static boolean foregroundEstablished;
    private static boolean stopWhenForegroundReady;
    private static int lastKnownActiveDownloads;

    public static boolean requestStart(Context context) {
        try {
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
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification notification = OkHttpDownloadProgressNotifier.foregroundServiceNotification(this);
        ServiceCompat.startForeground(this, SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        synchronized (stateLock) {
            foregroundEstablished = true;
            boolean shouldStop = stopWhenForegroundReady || lastKnownActiveDownloads <= 0;
            stopWhenForegroundReady = false;
            if (shouldStop) {
                stopSelf();
            }
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
        synchronized (stateLock) {
            foregroundEstablished = false;
            stopWhenForegroundReady = false;
        }
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
