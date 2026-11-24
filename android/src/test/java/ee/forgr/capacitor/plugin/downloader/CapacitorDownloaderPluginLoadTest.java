package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.spy;

import java.lang.reflect.Field;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.ThreadPoolExecutor;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class CapacitorDownloaderPluginLoadTest {

    @Test
    public void loadInitializesFourThreadOkHttpTransferPool() throws Exception {
        CapacitorDownloaderPlugin plugin = spy(new CapacitorDownloaderPlugin());
        doReturn(RuntimeEnvironment.getApplication()).when(plugin).getContext();
        plugin.load();

        Field field = CapacitorDownloaderPlugin.class.getDeclaredField("okHttpTransferExecutor");
        field.setAccessible(true);
        ExecutorService executor = (ExecutorService) field.get(plugin);
        assertTrue(executor instanceof ThreadPoolExecutor);
        assertEquals(4, ((ThreadPoolExecutor) executor).getMaximumPoolSize());

        plugin.handleOnDestroy();
    }
}
