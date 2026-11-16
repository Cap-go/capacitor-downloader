package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import okhttp3.MediaType;
import okhttp3.Protocol;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.junit.Test;

public class DownloadExpectedLengthTest {

    @Test
    public void parsePositiveHeaderValueRejectsInvalid() {
        assertEquals(-1L, DownloadExpectedLength.parsePositiveHeaderValue(null));
        assertEquals(-1L, DownloadExpectedLength.parsePositiveHeaderValue(""));
        assertEquals(-1L, DownloadExpectedLength.parsePositiveHeaderValue("  "));
        assertEquals(-1L, DownloadExpectedLength.parsePositiveHeaderValue("0"));
        assertEquals(-1L, DownloadExpectedLength.parsePositiveHeaderValue("-5"));
        assertEquals(-1L, DownloadExpectedLength.parsePositiveHeaderValue("abc"));
    }

    @Test
    public void parsePositiveHeaderValueAcceptsPositive() {
        assertEquals(1024L, DownloadExpectedLength.parsePositiveHeaderValue("1024"));
        assertEquals(99L, DownloadExpectedLength.parsePositiveHeaderValue(" 99 "));
    }

    @Test
    public void resolveTotalBytesPrefersLengthHeaderOverContentLength() {
        Response response = new Response.Builder()
            .request(new Request.Builder().url("http://127.0.0.1/").build())
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .header("Content-Length", "100")
            .header("X-Uncompressed-Length", "1000")
            .build();
        ResponseBody body = ResponseBody.create(new byte[0], MediaType.get("application/octet-stream"));
        long total = DownloadExpectedLength.resolveTotalBytes(response, body, "X-Uncompressed-Length");
        assertEquals(1000L, total);
    }

    @Test
    public void resolveTotalBytesIgnoresLengthHeaderWhenContentEncodingPresent() {
        Response response = new Response.Builder()
            .request(new Request.Builder().url("http://127.0.0.1/").build())
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .header("Content-Encoding", "gzip")
            .header("Content-Length", "132")
            .header("X-Uncompressed-Length", "100000")
            .build();
        ResponseBody body = ResponseBody.create(new byte[132], MediaType.get("application/octet-stream"));
        long total = DownloadExpectedLength.resolveTotalBytes(response, body, "X-Uncompressed-Length");
        assertEquals(132L, total);
    }

    @Test
    public void resolveTotalBytesFallsBackWhenLengthHeaderMissing() {
        Response response = new Response.Builder()
            .request(new Request.Builder().url("http://127.0.0.1/").build())
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .header("Content-Length", "256")
            .build();
        ResponseBody body = ResponseBody.create(new byte[256], MediaType.get("application/octet-stream"));
        long total = DownloadExpectedLength.resolveTotalBytes(response, body, "X-Uncompressed-Length");
        assertEquals(256L, total);
    }

    @Test
    public void parsePositiveHeaderValueRejectsOverflow() {
        assertEquals(-1L, DownloadExpectedLength.parsePositiveHeaderValue("9223372036854775808"));
    }
}
