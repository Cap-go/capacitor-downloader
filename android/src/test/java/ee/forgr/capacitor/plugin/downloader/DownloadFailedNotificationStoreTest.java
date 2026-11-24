package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Before;
import org.junit.Test;

public class DownloadFailedNotificationStoreTest {

    private DownloadFailedNotificationStore store;

    @Before
    public void setUp() {
        store = new DownloadFailedNotificationStore();
    }

    @Test
    public void setTakeAndRemove() {
        store.setText("job-1", "  Failed  ", 1L);
        assertEquals("Failed", store.takeText("job-1", 1L));
        assertNull(store.takeText("job-1", 1L));

        store.setText("job-2", "Try again", 1L);
        store.remove("job-2", 1L);
        assertNull(store.takeText("job-2", 1L));
    }

    @Test
    public void blankTextClearsEntry() {
        store.setText("job-1", "Try again", 1L);
        store.setText("job-1", "   ", 2L);
        assertNull(store.takeText("job-1", 1L));
    }

    @Test
    public void generationMismatchPreservesEntry() {
        store.setText("job-1", "New", 2L);
        store.remove("job-1", 1L);
        assertEquals("New", store.takeText("job-1", 2L));
    }
}
