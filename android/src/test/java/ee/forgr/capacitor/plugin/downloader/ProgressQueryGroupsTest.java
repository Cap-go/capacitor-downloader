package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import java.util.List;
import org.junit.Test;

public class ProgressQueryGroupsTest {

    @Test
    public void smallBatchUsesOneQuery() {
        long[] ids = { 1, 2, 3 };

        List<long[]> groups = CapacitorDownloaderPlugin.progressQueryGroups(ids);

        assertEquals(1, groups.size());
        assertArrayEquals(ids, groups.get(0));
    }

    @Test
    public void largeBatchIsSplitIntoBoundedGroupsKeepingEveryId() {
        int size = CapacitorDownloaderPlugin.PROGRESS_QUERY_GROUP_SIZE * 2 + 1;
        long[] ids = new long[size];
        for (int index = 0; index < size; index++) {
            ids[index] = index;
        }

        List<long[]> groups = CapacitorDownloaderPlugin.progressQueryGroups(ids);

        assertEquals(3, groups.size());
        assertEquals(CapacitorDownloaderPlugin.PROGRESS_QUERY_GROUP_SIZE, groups.get(0).length);
        assertEquals(CapacitorDownloaderPlugin.PROGRESS_QUERY_GROUP_SIZE, groups.get(1).length);
        assertEquals(1, groups.get(2).length);
        assertEquals(size - 1, groups.get(2)[0]);
    }
}
