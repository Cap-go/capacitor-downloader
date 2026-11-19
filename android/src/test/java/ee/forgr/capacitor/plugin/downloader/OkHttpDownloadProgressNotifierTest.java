package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class OkHttpDownloadProgressNotifierTest {

    @Test
    public void progressModeOptsIntoOngoingNotifications() {
        assertFalse(OkHttpDownloadProgressNotifier.shouldShowProgressForMode(null));
        assertFalse(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("completed"));
        assertTrue(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("progress"));
        assertFalse(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("hidden"));
    }

    @Test
    public void completedNotificationTagsAreDistinctPerDownload() {
        String first = OkHttpDownloadProgressNotifier.notificationTagForCompletedDownload("batch-1");
        String second = OkHttpDownloadProgressNotifier.notificationTagForCompletedDownload("batch-1");
        String other = OkHttpDownloadProgressNotifier.notificationTagForCompletedDownload("batch-2");
        assertTrue(first.equals(second));
        assertFalse(first.equals(other));
        assertNotEquals(
            OkHttpDownloadProgressNotifier.notificationIdForCompletedDownload("batch-1"),
            OkHttpDownloadProgressNotifier.notificationIdForCompletedDownload("batch-2")
        );
    }
}
