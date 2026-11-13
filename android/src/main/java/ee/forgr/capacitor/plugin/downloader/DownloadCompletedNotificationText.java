package ee.forgr.capacitor.plugin.downloader;

final class DownloadCompletedNotificationText {

    private DownloadCompletedNotificationText() {}

    static String normalize(String text) {
        if (text == null) {
            return null;
        }
        String trimmed = text.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
