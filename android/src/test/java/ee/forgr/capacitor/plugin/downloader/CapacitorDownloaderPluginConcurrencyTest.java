package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import android.app.DownloadManager;
import com.getcapacitor.PluginCall;
import java.lang.reflect.Field;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;

public class CapacitorDownloaderPluginConcurrencyTest {

    private CapacitorDownloaderPlugin plugin;
    private DownloadManager downloadManager;
    private ExecutorService downloadManagerExecutor;
    private Map<String, Long> downloads;

    @Before
    public void setUp() throws Exception {
        plugin = new CapacitorDownloaderPlugin();
        downloadManager = mock(DownloadManager.class);
        downloadManagerExecutor = Executors.newSingleThreadExecutor((runnable) -> new Thread(runnable, "download-manager-worker"));

        setField(plugin, "downloadManager", downloadManager);
        setField(plugin, "downloadManagerExecutor", downloadManagerExecutor);
        downloads = getDownloadsMap(plugin);
    }

    @After
    public void tearDown() throws Exception {
        if (downloadManagerExecutor != null) {
            downloadManagerExecutor.shutdown();
            downloadManagerExecutor.awaitTermination(5, TimeUnit.SECONDS);
        }
    }

    @Test
    public void downloadsMapIsConcurrentHashMap() throws Exception {
        assertTrue(downloads instanceof ConcurrentHashMap);
    }

    @Test
    public void stopRemovesFromMapBeforeDownloadManagerRemove() throws Exception {
        downloads.put("test-id", 42L);

        CountDownLatch removeStarted = new CountDownLatch(1);
        when(downloadManager.remove(42L)).thenAnswer((invocation) -> {
            assertFalse("download id must be removed before DownloadManager.remove()", downloads.containsKey("test-id"));
            removeStarted.countDown();
            return 1;
        });

        PluginCall call = mockPluginCall("test-id");
        plugin.stop(call);

        assertTrue("stop() should remove the id before scheduling remove()", removeStarted.await(5, TimeUnit.SECONDS));
        assertFalse(downloads.containsKey("test-id"));
        verify(call, timeout(5000)).resolve(any());
    }

    @Test
    public void stopRunsRemoveOffCallingThread() throws Exception {
        downloads.put("test-id", 42L);

        AtomicReference<String> removeThreadName = new AtomicReference<>();
        String callingThreadName = Thread.currentThread().getName();
        CountDownLatch removeFinished = new CountDownLatch(1);

        when(downloadManager.remove(42L)).thenAnswer((invocation) -> {
            removeThreadName.set(Thread.currentThread().getName());
            removeFinished.countDown();
            return 1;
        });

        PluginCall call = mockPluginCall("test-id");
        plugin.stop(call);

        assertTrue(removeFinished.await(5, TimeUnit.SECONDS));
        assertEquals("download-manager-worker", removeThreadName.get());
        assertNotEquals(callingThreadName, removeThreadName.get());
        verify(call, timeout(5000)).resolve(any());
    }

    @Test
    public void checkStatusRejectsUnknownDownloadWithoutQuerying() {
        PluginCall call = mockPluginCall("missing-id");
        plugin.checkStatus(call);

        verify(call).reject("Download not found");
        verify(downloadManager, org.mockito.Mockito.never()).query(any(DownloadManager.Query.class));
    }

    @Test
    public void stopCancelsPendingDownloadWithoutCallingDownloadManager() throws Exception {
        downloads.put("test-id", -42L);

        PluginCall call = mockPluginCall("test-id");
        plugin.stop(call);

        assertFalse(downloads.containsKey("test-id"));
        verify(downloadManager, org.mockito.Mockito.never()).remove(anyLong());
        verify(call, timeout(5000)).resolve(any());
    }

    @Test
    public void stopRestoresMappingWhenRemoveFails() throws Exception {
        downloads.put("test-id", 42L);
        when(downloadManager.remove(42L)).thenThrow(new RuntimeException("binder failure"));

        PluginCall call = mockPluginCall("test-id");
        plugin.stop(call);

        verify(call, timeout(5000)).reject(eq("Download could not be removed"), any(RuntimeException.class));
        assertEquals(42L, downloads.get("test-id").longValue());
    }

    @Test
    public void checkStatusRejectsPendingDownloadWithoutQuerying() {
        downloads.put("test-id", -99L);

        PluginCall call = mockPluginCall("test-id");
        plugin.checkStatus(call);

        verify(call).reject("Download not found");
        verify(downloadManager, org.mockito.Mockito.never()).query(any(DownloadManager.Query.class));
    }

    @Test
    public void stopRejectsUnknownDownloadWithoutCallingDownloadManager() throws Exception {
        PluginCall call = mockPluginCall("missing-id");
        plugin.stop(call);

        verify(call).reject("Download not found");
        verify(downloadManager, org.mockito.Mockito.never()).remove(anyLong());
    }

    @Test
    public void checkStatusRejectsWhenQueryReturnsNullCursor() {
        downloads.put("test-id", 42L);
        when(downloadManager.query(any(DownloadManager.Query.class))).thenReturn(null);

        PluginCall call = mockPluginCall("test-id");
        plugin.checkStatus(call);

        verify(call, timeout(5000)).reject("Download not found");
    }

    @Test
    public void checkStatusRejectsWhenQueryThrows() throws Exception {
        downloads.put("test-id", 42L);
        DownloadManager throwingManager = mock(
            DownloadManager.class,
            invocation -> {
                if ("query".equals(invocation.getMethod().getName())) {
                    throw new RuntimeException("binder failure");
                }
                return org.mockito.Answers.RETURNS_DEFAULTS.answer(invocation);
            }
        );
        setField(plugin, "downloadManager", throwingManager);

        PluginCall call = mockPluginCall("test-id");
        plugin.checkStatus(call);

        verify(call, timeout(5000)).reject(eq("Download status could not be read"), any(Exception.class));
    }

    private static PluginCall mockPluginCall(String id) {
        PluginCall call = mock(PluginCall.class);
        when(call.getString("id")).thenReturn(id);
        return call;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Long> getDownloadsMap(CapacitorDownloaderPlugin plugin) throws Exception {
        Field downloadsField = CapacitorDownloaderPlugin.class.getDeclaredField("downloads");
        downloadsField.setAccessible(true);
        return (Map<String, Long>) downloadsField.get(plugin);
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }
}
