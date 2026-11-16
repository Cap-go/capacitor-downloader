package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.app.DownloadManager;
import android.database.MatrixCursor;
import org.junit.Test;

public class DownloadManagerCursorReaderTest {

    @Test
    public void failureMessageUsesHttpCodeInReasonColumn() {
        assertEquals("HTTP 500", DownloadManagerCursorReader.failureMessage(DownloadManager.STATUS_FAILED, 500, 0));
        assertEquals("HTTP 404", DownloadManagerCursorReader.failureMessage(DownloadManager.STATUS_FAILED, 404, 0));
    }

    @Test
    public void failureMessageUsesHttpStatusForUnhandledHttpCode() {
        assertEquals(
            "HTTP 503",
            DownloadManagerCursorReader.failureMessage(DownloadManager.STATUS_FAILED, DownloadManager.ERROR_UNHANDLED_HTTP_CODE, 503)
        );
    }

    @Test
    public void shouldRejectReportedSuccessForNon2xxHttpStatus() {
        assertTrue(DownloadManagerCursorReader.shouldRejectReportedSuccess(500));
        assertFalse(DownloadManagerCursorReader.shouldRejectReportedSuccess(200));
        assertFalse(DownloadManagerCursorReader.shouldRejectReportedSuccess(0));
    }

    @Test
    public void readSnapshotIncludesHttpStatusColumnWhenPresent() {
        MatrixCursor cursor = new MatrixCursor(new String[] {
            DownloadManager.COLUMN_STATUS,
            DownloadManager.COLUMN_REASON,
            DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
            DownloadManager.COLUMN_TOTAL_SIZE_BYTES,
            "http_status"
        });
        cursor.addRow(new Object[] { DownloadManager.STATUS_SUCCESSFUL, 0, 12L, 12L, 500 });
        DownloadManagerCursorReader.Snapshot snapshot = DownloadManagerCursorReader.readSnapshot("child", cursor);
        assertEquals(500, snapshot.httpStatus);
        assertEquals(DownloadManager.STATUS_SUCCESSFUL, snapshot.status);
    }

    @Test
    public void detectsPauseWaitingToRetry() {
        assertTrue(
            DownloadManagerCursorReader.isPauseWaitingToRetry(
                DownloadManager.STATUS_PAUSED,
                DownloadManagerCursorReader.PAUSED_WAITING_TO_RETRY
            )
        );
        assertFalse(DownloadManagerCursorReader.isPauseWaitingToRetry(DownloadManager.STATUS_RUNNING, 0));
    }

    @Test
    public void progressPollingDoesNotUseOkHttpProbe() throws Exception {
        for (java.lang.reflect.Method method : OkHttpDownloadExecutor.class.getDeclaredMethods()) {
            org.junit.Assert.assertNotEquals("fetchResponseCode", method.getName());
        }
    }
}
