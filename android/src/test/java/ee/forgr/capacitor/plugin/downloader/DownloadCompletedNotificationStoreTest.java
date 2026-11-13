package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Before;
import org.junit.Test;

public class DownloadCompletedNotificationStoreTest {

    private DownloadCompletedNotificationStore store;

    @Before
    public void setUp() {
        store = new DownloadCompletedNotificationStore();
    }

    @Test
    public void setTakeAndRemove() {
        store.setText("job-1", "  Done  ", 1L);
        assertEquals("Done", store.takeText("job-1", 1L));
        assertNull(store.takeText("job-1", 1L));

        store.setText("job-2", "Hello", 1L);
        store.remove("job-2", 1L);
        assertNull(store.takeText("job-2", 1L));
    }

    @Test
    public void blankTextClearsEntry() {
        store.setText("job-1", "Hello", 1L);
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
