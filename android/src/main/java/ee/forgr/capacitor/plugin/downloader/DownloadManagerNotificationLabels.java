package ee.forgr.capacitor.plugin.downloader;

import android.app.DownloadManager;

final class DownloadManagerNotificationLabels {

    private DownloadManagerNotificationLabels() {}

    static void apply(DownloadManager.Request request, String title, String description) {
        String normalizedTitle = DownloadCompletedNotificationText.normalize(title);
        if (normalizedTitle != null) {
            request.setTitle(normalizedTitle);
        }

        String normalizedDescription = DownloadCompletedNotificationText.normalize(description);
        if (normalizedDescription != null) {
            request.setDescription(normalizedDescription);
        }
    }
}
