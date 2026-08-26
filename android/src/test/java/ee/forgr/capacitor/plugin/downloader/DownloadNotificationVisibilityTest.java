package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;

import android.app.DownloadManager;
import org.junit.Test;

public class DownloadNotificationVisibilityTest {

    @Test
    public void omittedOrCompletedUsesVisibleNotifyCompleted() {
        assertEquals(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED, DownloadNotificationVisibility.resolve(null));
        assertEquals(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED, DownloadNotificationVisibility.resolve("completed"));
    }

    @Test
    public void progressUsesVisibleOnly() {
        assertEquals(DownloadManager.Request.VISIBILITY_VISIBLE, DownloadNotificationVisibility.resolve("progress"));
    }

    @Test
    public void hiddenUsesVisibilityHidden() {
        assertEquals(DownloadManager.Request.VISIBILITY_HIDDEN, DownloadNotificationVisibility.resolve("hidden"));
    }

    @Test
    public void unknownValuesFallBackToDefault() {
        assertEquals(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED, DownloadNotificationVisibility.resolve("unknown"));
    }
}
