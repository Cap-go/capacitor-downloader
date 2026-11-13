package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class AndroidHttpEngineSelectorTest {

    @Test
    public void omittedOptionUsesDownloadManagerLikeMain() {
        assertEquals(AndroidHttpEngineSelector.Engine.DOWNLOAD_MANAGER, AndroidHttpEngineSelector.resolve(null, true));
        assertEquals(AndroidHttpEngineSelector.Engine.DOWNLOAD_MANAGER, AndroidHttpEngineSelector.resolve("", true));
    }

    @Test
    public void autoSelectsOkHttpForPrivateDestinations() {
        assertEquals(AndroidHttpEngineSelector.Engine.OKHTTP, AndroidHttpEngineSelector.resolve("auto", true));
    }

    @Test
    public void autoKeepsDownloadManagerForPublicDestinations() {
        assertEquals(AndroidHttpEngineSelector.Engine.DOWNLOAD_MANAGER, AndroidHttpEngineSelector.resolve("auto", false));
    }

    @Test
    public void explicitFlagsOverrideAuto() {
        assertEquals(AndroidHttpEngineSelector.Engine.OKHTTP, AndroidHttpEngineSelector.resolve("okhttp", false));
        assertEquals(AndroidHttpEngineSelector.Engine.DOWNLOAD_MANAGER, AndroidHttpEngineSelector.resolve("downloadManager", true));
    }
}
