package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;

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
}
