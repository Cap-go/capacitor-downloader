package ee.forgr.capacitor.plugin.downloader;

import android.app.DownloadManager;

final class DownloadNotificationVisibility {

    private DownloadNotificationVisibility() {}

    static int resolve(String notification) {
        if ("progress".equals(notification)) {
            return DownloadManager.Request.VISIBILITY_VISIBLE;
        }

        if ("hidden".equals(notification)) {
            return DownloadManager.Request.VISIBILITY_HIDDEN;
        }

        return DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED;
    }
}
