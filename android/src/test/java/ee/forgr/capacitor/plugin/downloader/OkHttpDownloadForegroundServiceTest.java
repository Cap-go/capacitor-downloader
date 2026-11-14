package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.content.Intent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class OkHttpDownloadForegroundServiceTest {

    @Test
    public void serviceStartsStickyAndExposesNoBinder() {
        OkHttpDownloadForegroundService service = Robolectric.buildService(OkHttpDownloadForegroundService.class).create().get();
        int startId = service.onStartCommand(new Intent(), 0, 1);
        assertEquals(android.app.Service.START_NOT_STICKY, startId);
        assertNull(service.onBind(new Intent()));
    }

    @Test
    public void androidManifestDeclaresDataSyncForegroundService() throws Exception {
        Path manifest = Path.of("src/main/AndroidManifest.xml");
        String xml = new String(Files.readAllBytes(manifest), StandardCharsets.UTF_8);
        assertTrue(xml.contains("android:foregroundServiceType=\"dataSync\""));
        assertTrue(xml.contains("android.permission.FOREGROUND_SERVICE_DATA_SYNC"));
        assertTrue(xml.contains(OkHttpDownloadForegroundService.class.getName()));
        assertTrue(xml.contains("android.permission.POST_NOTIFICATIONS"));
    }
}
