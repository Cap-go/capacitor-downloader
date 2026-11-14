package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class OkHttpDownloadProgressNotifierTest {

    @Test
    public void shouldShowProgressUnlessHidden() {
        assertTrue(OkHttpDownloadProgressNotifier.shouldShowProgressForMode(null));
        assertTrue(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("completed"));
        assertTrue(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("progress"));
        assertFalse(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("hidden"));
    }

    @Test
    public void notificationIdsAreStablePerDownload() {
        int first = OkHttpDownloadProgressNotifier.notificationIdForDownload("batch-1");
        int second = OkHttpDownloadProgressNotifier.notificationIdForDownload("batch-1");
        int other = OkHttpDownloadProgressNotifier.notificationIdForDownload("batch-2");
        assertTrue(first == second);
        assertNotEquals(first, other);
    }
}
