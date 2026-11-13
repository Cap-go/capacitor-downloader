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
    public void legacyCachePathMatchesMainUnderExternalFiles() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(
            context,
            "cache/offline/pkg.zip",
            false
        );
        assertFalse(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(externalFilesDir, "cache/offline/pkg.zip").getPath(), resolved.file.getPath());
    }

    @Test
    public void legacyAbsolutePathMatchesMainFileParentResolution() {
        String absolute = externalFilesDir.getAbsolutePath() + "/absolute-pack.zip";
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, absolute, false);
        assertFalse(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(externalFilesDir, absolute).getPath(), resolved.file.getPath());
    }

    @Test
    public void legacyFileUriMatchesMainFileParentResolution() {
        String absolute = externalFilesDir.getAbsolutePath() + "/uri-pack.zip";
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, "file://" + absolute, false);
        assertFalse(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(externalFilesDir, absolute).getPath(), resolved.file.getPath());
    }

    @Test
    public void legacyFilesPathMatchesMainUnderExternalFiles() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(
            context,
            "files/secure/data.bin",
            false
        );
        assertFalse(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(externalFilesDir, "files/secure/data.bin").getPath(), resolved.file.getPath());
    }

    @Test
    public void extendedCachePrefixUsesInternalCacheAndOkHttpAuto() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(
            context,
            "cache/offline/pkg.zip",
            true
        );
        assertTrue(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(cacheDir, "offline/pkg.zip").getPath(), resolved.file.getPath());
    }

    @Test
    public void extendedFilesPrefixUsesInternalFilesAndOkHttpAuto() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(
            context,
            "files/secure/data.bin",
            true
        );
        assertTrue(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(filesDir, "secure/data.bin").getPath(), resolved.file.getPath());
    }

    @Test
    public void legacyRelativePathUsesExternalFilesAndDownloadManagerInAuto() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(
            context,
            "downloads/sample.zip",
            false
        );
        assertFalse(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(externalFilesDir, "downloads/sample.zip").getPath(), resolved.file.getPath());
    }

    @Test
    public void extendedLegacyRelativePathUsesExternalFilesAndDownloadManagerInAuto() {
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, "downloads/sample.zip", true);
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
        AndroidDownloadDestination.resolve(context, "files/../cache/escape.bin", true);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDestinationAtStorageRoot() {
        AndroidDownloadDestination.resolve(context, "files/", true);
    }

    @Test
    public void prefersOkHttpWhenExternalFilesDirUnavailable() {
        Mockito.when(context.getExternalFilesDir(null)).thenReturn(null);
        AndroidDownloadDestination.ResolvedDestination resolved = AndroidDownloadDestination.resolve(context, "offline/pack.zip", true);
        assertTrue(resolved.preferOkHttpInAutoMode);
        assertEquals(new File(filesDir, "offline/pack.zip").getPath(), resolved.file.getPath());
    }
}
