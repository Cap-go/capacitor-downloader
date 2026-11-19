package ee.forgr.capacitor.plugin.downloader;

import okhttp3.Response;
import okhttp3.ResponseBody;

/** Resolves expected download size when Content-Length is missing or reflects compressed bytes. */
final class DownloadExpectedLength {

    private DownloadExpectedLength() {}

    static long parsePositiveHeaderValue(String raw) {
        if (raw == null) {
            return -1L;
        }
        String trimmed = raw.trim();
        if (trimmed.isEmpty()) {
            return -1L;
        }
        try {
            long value = Long.parseLong(trimmed);
            return value > 0 ? value : -1L;
        } catch (NumberFormatException e) {
            return -1L;
        }
    }

    static boolean responseHasContentEncoding(Response response) {
        String encoding = response.header("Content-Encoding");
        return encoding != null && !encoding.trim().isEmpty();
    }

    static long resolveTotalBytes(Response response, ResponseBody body, String lengthHeader) {
        if (lengthHeader != null && !responseHasContentEncoding(response)) {
            String trimmedHeader = lengthHeader.trim();
            if (!trimmedHeader.isEmpty()) {
                String headerValue = response.header(trimmedHeader);
                long fromHeader = parsePositiveHeaderValue(headerValue);
                if (fromHeader > 0) {
                    return fromHeader;
                }
            }
        }
        long contentLength = body.contentLength();
        if (contentLength <= 0) {
            contentLength = parsePositiveHeaderValue(response.header("Content-Length"));
        }
        return contentLength > 0 ? contentLength : 0L;
    }
}
