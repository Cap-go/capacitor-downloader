package ee.forgr.capacitor.plugin.downloader;

import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

final class DownloadBatchState {

    static String fileTaskId(String batchId, int fileIndex) {
        return batchId + "#" + fileIndex;
    }

    static BatchIdParts parseFileTaskId(String taskId) {
        int hashIndex = taskId.lastIndexOf('#');
        if (hashIndex < 0) {
            return null;
        }
        String batchId = taskId.substring(0, hashIndex);
        try {
            int fileIndex = Integer.parseInt(taskId.substring(hashIndex + 1));
            return new BatchIdParts(batchId, fileIndex);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    static final class BatchIdParts {

        final String batchId;
        final int fileIndex;

        BatchIdParts(String batchId, int fileIndex) {
            this.batchId = batchId;
            this.fileIndex = fileIndex;
        }
    }

    final String batchId;
    final int fileCount;
    final float[] fileProgress;
    final AtomicBoolean failed = new AtomicBoolean(false);
    final AtomicBoolean cancelled = new AtomicBoolean(false);
    int completedCount;

    DownloadBatchState(String batchId, int fileCount) {
        this.batchId = batchId;
        this.fileCount = fileCount;
        this.fileProgress = new float[fileCount];
        Arrays.fill(this.fileProgress, 0f);
        this.completedCount = 0;
    }

    float overallProgress() {
        return DownloadBatchProgress.overallProgress(fileProgress, fileCount);
    }

    synchronized boolean markFileCompleted(int fileIndex) {
        if (fileIndex < 0 || fileIndex >= fileCount) {
            return false;
        }
        fileProgress[fileIndex] = 1f;
        completedCount++;
        return completedCount >= fileCount;
    }

    synchronized void updateFileProgress(int fileIndex, float progress) {
        if (fileIndex < 0 || fileIndex >= fileCount) {
            return;
        }
        fileProgress[fileIndex] = Math.max(0f, Math.min(1f, progress));
    }

    synchronized float fileProgressAt(int fileIndex) {
        if (fileIndex < 0 || fileIndex >= fileCount) {
            return 0f;
        }
        return fileProgress[fileIndex];
    }
}
