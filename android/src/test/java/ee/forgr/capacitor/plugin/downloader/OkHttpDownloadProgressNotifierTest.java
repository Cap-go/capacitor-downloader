package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertFalse;
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
    public void notificationTagsAreDistinctPerDownload() {
        String first = OkHttpDownloadProgressNotifier.notificationTagForDownload("batch-1");
        String second = OkHttpDownloadProgressNotifier.notificationTagForDownload("batch-1");
        String other = OkHttpDownloadProgressNotifier.notificationTagForDownload("batch-2");
        String collisionA = OkHttpDownloadProgressNotifier.notificationTagForDownload("Aa");
        String collisionB = OkHttpDownloadProgressNotifier.notificationTagForDownload("BB");
        assertTrue(first.equals(second));
        assertFalse(first.equals(other));
        assertFalse(collisionA.equals(collisionB));
    }
}
