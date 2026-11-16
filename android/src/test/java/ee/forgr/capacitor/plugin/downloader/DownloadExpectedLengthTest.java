package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;

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
}
