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
        store.setText("job-1", "  Done  ");
        assertEquals("Done", store.takeText("job-1"));
        assertNull(store.takeText("job-1"));

        store.setText("job-2", "Hello");
        store.remove("job-2");
        assertNull(store.takeText("job-2"));
    }

    @Test
    public void blankTextClearsEntry() {
        store.setText("job-1", "Hello");
        store.setText("job-1", "   ");
        assertNull(store.takeText("job-1"));
    }
}
