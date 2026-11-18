package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.IOException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import org.junit.Test;

public class DownloadConnectionRetryTest {

    @Test
    public void normalizeRetriesDefaultsToZero() {
        assertEquals(0, DownloadConnectionRetry.normalizeRetries(null));
        assertEquals(0, DownloadConnectionRetry.normalizeRetries(0));
        assertEquals(2, DownloadConnectionRetry.normalizeRetries(2));
    }

    @Test(expected = IllegalArgumentException.class)
    public void normalizeRetriesRejectsNegative() {
        DownloadConnectionRetry.normalizeRetries(-1);
    }

    @Test
    public void delayScalesWithAttemptNumber() {
        assertEquals(5_000L, DownloadConnectionRetry.delayMillisForAttempt(1));
        assertEquals(10_000L, DownloadConnectionRetry.delayMillisForAttempt(2));
    }

    @Test
    public void detectsRetryableConnectionFailures() {
        assertTrue(DownloadConnectionRetry.isRetryableConnectionFailure(new SocketTimeoutException("timeout")));
        assertTrue(DownloadConnectionRetry.isRetryableConnectionFailure(new UnknownHostException("host")));
        assertTrue(DownloadConnectionRetry.isRetryableConnectionFailure(new SocketException("stream was reset: INTERNAL_ERROR")));
    }

    @Test
    public void filesystemMessagesAreNotConnectionFailures() {
        assertFalse(DownloadConnectionRetry.isFilesystemIoMessage("Could not create destination directory"));
        assertFalse(DownloadConnectionRetry.isRetryableConnectionFailure(new IOException("Could not move downloaded file into place")));
    }
}
