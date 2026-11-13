package ee.forgr.capacitor.plugin.downloader;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

final class DownloadCompletedNotificationPresenter {

    static final String CHANNEL_ID = "capacitor_downloader_completed";

    private DownloadCompletedNotificationPresenter() {}

    static boolean canPostNotifications(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return NotificationManagerCompat.from(context).areNotificationsEnabled();
        }
        return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    static void showIfAllowed(Context context, String downloadId, String bodyText) {
        String body = DownloadCompletedNotificationText.normalize(bodyText);
        if (body == null || downloadId == null) {
            return;
        }
        if (!canPostNotifications(context)) {
            return;
        }

        NotificationManagerCompat notificationManager = NotificationManagerCompat.from(context);
        ensureChannel(context);

        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launchIntent == null) {
            return;
        }
        launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);

        int pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingIntentFlags |= PendingIntent.FLAG_IMMUTABLE;
        }

        PendingIntent contentIntent = PendingIntent.getActivity(context, downloadId.hashCode(), launchIntent, pendingIntentFlags);

        CharSequence appLabel = context.getApplicationInfo().loadLabel(context.getPackageManager());

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(appLabel)
            .setContentText(body)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT);

        try {
            notificationManager.notify(notificationIdFor(downloadId), builder.build());
        } catch (SecurityException ignored) {
            // POST_NOTIFICATIONS denied at show time.
        }
    }

    private static void ensureChannel(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) {
            return;
        }
        NotificationChannel existing = manager.getNotificationChannel(CHANNEL_ID);
        if (existing != null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "Download completed", NotificationManager.IMPORTANCE_DEFAULT);
        channel.setDescription("Shown when a Capacitor Downloader task finishes");
        manager.createNotificationChannel(channel);
    }

    static int notificationIdFor(String downloadId) {
        return ("capacitor-downloader-completed-" + downloadId).hashCode();
    }
}
