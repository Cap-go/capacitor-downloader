package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import java.io.File;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mockito;

public class AndroidDownloadDestinationTest {

    private Context context;
    private File cacheDir;
    private File filesDir;
    private File dataDir;
    private File externalFilesDir;

    @Before
    public void setUp() {
        context = Mockito.mock(Context.class);
        cacheDir = new File("/data/user/0/app/cache");
        filesDir = new File("/data/user/0/app/files");
        dataDir = new File("/data/user/0/app");
        externalFilesDir = new File("/storage/emulated/0/Android/data/app/files");

        Mockito.when(context.getCacheDir()).thenReturn(cacheDir);
        Mockito.when(context.getFilesDir()).thenReturn(filesDir);
        Mockito.when(context.getDataDir()).thenReturn(dataDir);
        Mockito.when(context.getExternalFilesDir(null)).thenReturn(externalFilesDir);
    }

    @Test
    public void cachePrefixPrefersOkHttpInAutoMode() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, "cache/offline/pkg.zip");
        assertTrue(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(cacheDir, "offline/pkg.zip").getPath(), resolved.file.getPath());
    }

    @Test
    public void filesPrefixPrefersOkHttpInAutoMode() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, "files/secure/data.bin");
        assertTrue(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(filesDir, "secure/data.bin").getPath(), resolved.file.getPath());
    }

    @Test
    public void legacyRelativePathUsesExternalFilesAndDownloadManagerInAuto() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, "downloads/sample.zip");
        assertFalse(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(externalFilesDir, "downloads/sample.zip").getPath(), resolved.file.getPath());
    }

    @Test
    public void preferOkHttpForAbsolutePathUnderFilesDir() {
        File target = new File(filesDir, "nested/item.bin");
        assertTrue(AndroidDownloadDestination.preferOkHttpInAutoMode(context, target));
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsPathTraversalUnderFilesPrefix() {
        AndroidDownloadDestination.resolve(context, "files/../cache/escape.bin");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDestinationAtStorageRoot() {
        AndroidDownloadDestination.resolve(context, "files/");
    }

    @Test
    public void prefersOkHttpWhenExternalFilesDirUnavailable() {
        Mockito.when(context.getExternalFilesDir(null)).thenReturn(null);
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, "offline/pack.zip");
        assertTrue(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(filesDir, "offline/pack.zip").getPath(), resolved.file.getPath());
    }
}
