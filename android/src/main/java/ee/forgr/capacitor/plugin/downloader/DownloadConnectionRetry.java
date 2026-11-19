package ee.forgr.capacitor.plugin.downloader;

import java.io.IOException;
import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import javax.net.ssl.SSLException;

final class DownloadConnectionRetry {

    static final long MAX_RETRY_DELAY_MS = 600_000L;

    private DownloadConnectionRetry() {}

    static int normalizeRetries(Integer raw) {
        if (raw == null) {
            return 0;
        }
        if (raw < 0) {
            throw new IllegalArgumentException("retries must be >= 0");
        }
        return raw;
    }

    static long delayMillisForAttempt(int connectionFailureAttempt) {
        long delay = 5_000L * (long) connectionFailureAttempt;
        return Math.min(delay, MAX_RETRY_DELAY_MS);
    }

    static boolean isRetryableConnectionFailure(IOException error) {
        if (isFilesystemIoMessage(error.getMessage())) {
            return false;
        }
        if (error instanceof SocketTimeoutException) {
            return true;
        }
        if (error instanceof SocketException) {
            return true;
        }
        if (error instanceof UnknownHostException) {
            return true;
        }
        if (error instanceof ConnectException) {
            return true;
        }
        if (error instanceof SSLException) {
            return true;
        }
        String message = error.getMessage();
        if (message != null) {
            String lower = message.toLowerCase();
            if (
                lower.contains("stream was reset") ||
                lower.contains("connection reset") ||
                lower.contains("unexpected end of stream") ||
                lower.contains("failed to connect") ||
                lower.contains("broken pipe")
            ) {
                return true;
            }
        }
        Throwable cause = error.getCause();
        if (cause instanceof IOException causeIo && cause != error) {
            return isRetryableConnectionFailure(causeIo);
        }
        return false;
    }

    static boolean isFilesystemIoMessage(String message) {
        if (message == null) {
            return false;
        }
        return (
            message.startsWith("Could not create destination directory") ||
            message.startsWith("Could not replace existing destination file") ||
            message.startsWith("Could not move downloaded file into place")
        );
    }
}
