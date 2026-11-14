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
 * Keeps OkHttp transfers alive long enough to update ongoing progress notifications.
 */
public class OkHttpDownloadForegroundService extends Service {

    private static final int SERVICE_NOTIFICATION_ID = 0x4f4b4854;

    public static void start(Context context) {
        Intent intent = new Intent(context, OkHttpDownloadForegroundService.class);
        androidx.core.content.ContextCompat.startForegroundService(context, intent);
    }

    public static void stop(Context context) {
        context.stopService(new Intent(context, OkHttpDownloadForegroundService.class));
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification notification = new NotificationCompat.Builder(this, OkHttpDownloadProgressNotifier.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setSilent(true)
            .build();
        ServiceCompat.startForeground(this, SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
