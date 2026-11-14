package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class DownloadBatchProgressTest {

    @Test
    public void overallProgressAveragesFiles() {
        float[] progress = { 1f, 0.5f, 0f };
        assertEquals(0.5f, DownloadBatchProgress.overallProgress(progress, 3), 0.0001f);
    }

    @Test
    public void parseFileTaskIdExtractsBatchParts() {
        DownloadBatchState.BatchIdParts parts = DownloadBatchState.parseFileTaskId("bundle#2");
        assertEquals("bundle", parts.batchId);
        assertEquals(2, parts.fileIndex);
    }

    @Test
    public void shouldPreserveCompletedChildWhenProgressComplete() {
        DownloadBatchState batch = new DownloadBatchState("bundle", 2, 1L, "hidden");
        batch.updateFileProgress(0, 1f);
        assertTrue(batch.shouldPreserveCompletedChild(0));
        assertFalse(batch.shouldPreserveCompletedChild(1));
    }

    @Test
    public void markFileCompletedIsIdempotent() {
        DownloadBatchState batch = new DownloadBatchState("bundle", 2, 1L, "hidden");
        assertEquals(false, batch.markFileCompleted(0));
        assertEquals(false, batch.markFileCompleted(0));
        assertEquals(true, batch.markFileCompleted(1));
        assertEquals(true, batch.markFileCompleted(1));
    }
}
