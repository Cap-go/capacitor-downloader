package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.app.DownloadManager;
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
    public void onlyWaitingToRetryIncrementsPausePollCounter() {
        int base = 10;
        DownloadManagerCursorReader.PauseRetryPollUpdate retry = DownloadManagerCursorReader.pauseRetryPollUpdate(
            DownloadManager.STATUS_PAUSED,
            DownloadManagerCursorReader.PAUSED_WAITING_TO_RETRY,
            base
        );
        assertTrue(retry.trackCount);
        assertEquals(base + 1, retry.nextCount);
        assertFalse(retry.shouldFailExhausted);

        DownloadManagerCursorReader.PauseRetryPollUpdate network = DownloadManagerCursorReader.pauseRetryPollUpdate(
            DownloadManager.STATUS_PAUSED,
            DownloadManager.PAUSED_WAITING_FOR_NETWORK,
            base
        );
        assertFalse(network.trackCount);
        assertFalse(network.shouldFailExhausted);

        DownloadManagerCursorReader.PauseRetryPollUpdate wifi = DownloadManagerCursorReader.pauseRetryPollUpdate(
            DownloadManager.STATUS_PAUSED,
            DownloadManager.PAUSED_QUEUED_FOR_WIFI,
            base
        );
        assertFalse(wifi.trackCount);

        DownloadManagerCursorReader.PauseRetryPollUpdate unknown = DownloadManagerCursorReader.pauseRetryPollUpdate(
            DownloadManager.STATUS_PAUSED,
            99,
            base
        );
        assertFalse(unknown.trackCount);

        DownloadManagerCursorReader.PauseRetryPollUpdate running = DownloadManagerCursorReader.pauseRetryPollUpdate(
            DownloadManager.STATUS_RUNNING,
            0,
            base
        );
        assertFalse(running.trackCount);
    }

    @Test
    public void onlyWaitingToRetryCanExhaustPauseRetryBudget() {
        int overBudget = DownloadManagerCursorReader.DEFAULT_MAX_PAUSE_RETRY_POLLS;
        DownloadManagerCursorReader.PauseRetryPollUpdate exhausted = DownloadManagerCursorReader.pauseRetryPollUpdate(
            DownloadManager.STATUS_PAUSED,
            DownloadManagerCursorReader.PAUSED_WAITING_TO_RETRY,
            overBudget
        );
        assertTrue(exhausted.shouldFailExhausted);

        DownloadManagerCursorReader.PauseRetryPollUpdate networkNever = DownloadManagerCursorReader.pauseRetryPollUpdate(
            DownloadManager.STATUS_PAUSED,
            DownloadManager.PAUSED_WAITING_FOR_NETWORK,
            overBudget + 1000
        );
        assertFalse(networkNever.shouldFailExhausted);
    }

    @Test
    public void progressPollingDoesNotUseOkHttpProbe() throws Exception {
        for (java.lang.reflect.Method method : OkHttpDownloadExecutor.class.getDeclaredMethods()) {
            org.junit.Assert.assertNotEquals("fetchResponseCode", method.getName());
        }
    }
}
