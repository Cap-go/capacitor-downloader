package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class DownloadCompletedNotificationTextTest {

    @Test
    public void nullOrBlankReturnsNull() {
        assertNull(DownloadCompletedNotificationText.normalize(null));
        assertNull(DownloadCompletedNotificationText.normalize(""));
        assertNull(DownloadCompletedNotificationText.normalize("   "));
    }

    @Test
    public void trimsWhitespace() {
        assertEquals("Ready", DownloadCompletedNotificationText.normalize("  Ready  "));
    }
}
