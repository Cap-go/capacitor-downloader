package ee.forgr.capacitor.plugin.downloader;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.os.Build;
import androidx.core.app.NotificationCompat;

/**
 * Optional completion-only notifications for OkHttp downloads (DownloadManager has its own).
 */
public final class DownloadCompletionNotifier {

    private static final String CHANNEL_ID = "capgo_capacitor_downloader";
    private static final int NOTIFICATION_ID = 0x44554c44; // "DOWNL"

    private DownloadCompletionNotifier() {}

    public static void notifyIfRequested(Context context, String downloadId, String notificationMode, boolean success) {
        if (context == null) {
            return;
        }
        if (!"completed".equals(notificationMode)) {
            return;
        }

        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager == null) {
            return;
        }

        ensureChannel(context, notificationManager);

        String title = success ? "Download complete" : "Download failed";
        String text = success ? "Finished: " + downloadId : "Failed: " + downloadId;

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT);

        notificationManager.notify(NOTIFICATION_ID, builder.build());
    }

    private static void ensureChannel(Context context, NotificationManager notificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "Capacitor Downloader", NotificationManager.IMPORTANCE_DEFAULT);
        channel.setDescription("Download completion notifications");
        notificationManager.createNotificationChannel(channel);
    }
}
