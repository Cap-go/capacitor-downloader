package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class DownloadHttpStatusRulesTest {

    @Test
    public void treatsOnly2xxAsSuccessful() {
        assertTrue(DownloadHttpStatusRules.isSuccessfulHttpCode(200));
        assertTrue(DownloadHttpStatusRules.isSuccessfulHttpCode(204));
        assertTrue(DownloadHttpStatusRules.isSuccessfulHttpCode(299));
        assertFalse(DownloadHttpStatusRules.isSuccessfulHttpCode(199));
        assertFalse(DownloadHttpStatusRules.isSuccessfulHttpCode(404));
        assertFalse(DownloadHttpStatusRules.isSuccessfulHttpCode(500));
        assertFalse(DownloadHttpStatusRules.isSuccessfulHttpCode(503));
    }

    @Test
    public void formatsHttpErrorMessage() {
        assertEquals("HTTP 500", DownloadHttpStatusRules.formatHttpErrorMessage(500));
    }
}