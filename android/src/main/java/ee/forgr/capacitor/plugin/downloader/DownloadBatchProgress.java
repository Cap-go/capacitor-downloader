package ee.forgr.capacitor.plugin.downloader;

final class DownloadBatchProgress {

    private DownloadBatchProgress() {}

    static float overallProgress(float[] fileProgress, int fileCount) {
        if (fileCount <= 0 || fileProgress == null || fileProgress.length == 0) {
            return 0f;
        }

        float total = 0f;
        int counted = Math.min(fileCount, fileProgress.length);
        for (int index = 0; index < counted; index++) {
            total += Math.max(0f, Math.min(1f, fileProgress[index]));
        }
        return total / fileCount;
    }
}
