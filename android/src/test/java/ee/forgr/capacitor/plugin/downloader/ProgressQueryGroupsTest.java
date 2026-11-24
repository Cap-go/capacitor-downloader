package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import java.util.Arrays;
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
        for (int groupIndex = 0; groupIndex < groups.size(); groupIndex++) {
            int start = groupIndex * CapacitorDownloaderPlugin.PROGRESS_QUERY_GROUP_SIZE;
            int end = Math.min(size, start + CapacitorDownloaderPlugin.PROGRESS_QUERY_GROUP_SIZE);
            assertArrayEquals(Arrays.copyOfRange(ids, start, end), groups.get(groupIndex));
        }
    }
}
