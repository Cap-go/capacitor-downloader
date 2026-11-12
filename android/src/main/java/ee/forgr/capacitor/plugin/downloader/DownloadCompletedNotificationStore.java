package ee.forgr.capacitor.plugin.downloader;

import java.util.concurrent.ConcurrentHashMap;

final class DownloadCompletedNotificationStore {

    private final ConcurrentHashMap<String, String> textsByDownloadId = new ConcurrentHashMap<>();

    void setText(String downloadId, String text) {
        if (downloadId == null) {
            return;
        }
        String normalized = DownloadCompletedNotificationText.normalize(text);
        if (normalized == null) {
            textsByDownloadId.remove(downloadId);
            return;
        }
        textsByDownloadId.put(downloadId, normalized);
    }

    String takeText(String downloadId) {
        if (downloadId == null) {
            return null;
        }
        return textsByDownloadId.remove(downloadId);
    }

    void remove(String downloadId) {
        if (downloadId != null) {
            textsByDownloadId.remove(downloadId);
        }
    }
}
