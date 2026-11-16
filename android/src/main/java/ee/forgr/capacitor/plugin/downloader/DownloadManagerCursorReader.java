package ee.forgr.capacitor.plugin.downloader;

import android.app.DownloadManager;
import android.database.Cursor;

/** Interprets DownloadManager provider cursor rows without extra HTTP requests. */
final class DownloadManagerCursorReader {

    /** {@link DownloadManager#COLUMN_REASON} when {@link DownloadManager#STATUS_PAUSED} and waiting to retry. */
    static final int PAUSED_WAITING_TO_RETRY = 5;

    static final int DEFAULT_MAX_PAUSE_RETRY_POLLS = 90;

    private DownloadManagerCursorReader() {}

    static final class Snapshot {

        final String id;
        final int status;
        final int reason;
        final int httpStatus;
        final long bytesDownloaded;
        final long bytesTotal;
        final boolean found;

        private Snapshot(String id, int status, int reason, int httpStatus, long bytesDownloaded, long bytesTotal, boolean found) {
            this.id = id;
            this.status = status;
            this.reason = reason;
            this.httpStatus = httpStatus;
            this.bytesDownloaded = bytesDownloaded;
            this.bytesTotal = bytesTotal;
            this.found = found;
        }

        static Snapshot notFound(String id) {
            return new Snapshot(id, -1, 0, 0, 0, 0, false);
        }

        float progress() {
            if (bytesTotal > 0) {
                return Math.min(1f, (float) bytesDownloaded / bytesTotal);
            }
            return status == DownloadManager.STATUS_SUCCESSFUL ? 1f : 0f;
        }
    }

    static Snapshot readSnapshot(String id, Cursor cursor) {
        if (cursor == null || !cursor.moveToFirst()) {
            return Snapshot.notFound(id);
        }
        int status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
        long bytesDownloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
        long bytesTotal = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));
        int reason = readIntColumn(cursor, DownloadManager.COLUMN_REASON);
        int httpStatus = readIntColumn(cursor, "http_status");
        return new Snapshot(id, status, reason, httpStatus, bytesDownloaded, bytesTotal, true);
    }

    private static int readIntColumn(Cursor cursor, String column) {
        int index = cursor.getColumnIndex(column);
        if (index < 0 || cursor.isNull(index)) {
            return 0;
        }
        return cursor.getInt(index);
    }

    static String failureMessage(int status, int reason, int httpStatus) {
        if (status != DownloadManager.STATUS_FAILED) {
            return "Download failed";
        }
        if (reason >= 100 && reason <= 599) {
            return DownloadHttpStatusRules.formatHttpErrorMessage(reason);
        }
        if (reason == DownloadManager.ERROR_UNHANDLED_HTTP_CODE && httpStatus >= 100 && httpStatus <= 599) {
            return DownloadHttpStatusRules.formatHttpErrorMessage(httpStatus);
        }
        return "Download failed";
    }

    static boolean isPauseWaitingToRetry(int status, int reason) {
        return status == DownloadManager.STATUS_PAUSED && reason == PAUSED_WAITING_TO_RETRY;
    }

    static boolean shouldRejectReportedSuccess(int httpStatus) {
        return httpStatus > 0 && !DownloadHttpStatusRules.isSuccessfulHttpCode(httpStatus);
    }

    static String toCapacitorState(int status) {
        if (status == DownloadManager.STATUS_SUCCESSFUL) {
            return "DONE";
        }
        if (status == DownloadManager.STATUS_FAILED) {
            return "ERROR";
        }
        if (status == DownloadManager.STATUS_PAUSED) {
            return "PAUSED";
        }
        return "RUNNING";
    }
}
