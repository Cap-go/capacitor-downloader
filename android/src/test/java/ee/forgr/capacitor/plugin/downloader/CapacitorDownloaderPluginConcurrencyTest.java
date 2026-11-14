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
import com.getcapacitor.JSArray;
import com.getcapacitor.PluginCall;
import java.io.File;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.List;
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
        setField(plugin, "completedNotificationStore", new DownloadCompletedNotificationStore());
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
    public void stopPreservesNotificationTextWhenRemoveFails() throws Exception {
        downloads.put("test-id", 42L);

        getDownloadGenerationsMap(plugin).put("test-id", 1L);

        DownloadCompletedNotificationStore notificationStore = getNotificationStore(plugin);
        notificationStore.setText("test-id", "Keep me", 1L);
        when(downloadManager.remove(42L)).thenThrow(new RuntimeException("binder failure"));

        PluginCall call = mockPluginCall("test-id");
        plugin.stop(call);

        verify(call, timeout(5000)).reject(eq("Download could not be removed"), any(RuntimeException.class));
        assertEquals("Keep me", notificationStore.takeText("test-id", 1L));
        assertEquals(Long.valueOf(42L), downloads.get("test-id"));
    }

    @Test
    public void duplicateDownloadRejectsWithoutChangingNotificationText() throws Exception {
        downloads.put("dup-id", 99L);

        DownloadCompletedNotificationStore notificationStore = getNotificationStore(plugin);
        notificationStore.setText("dup-id", "Original", 1L);

        PluginCall call = mock(PluginCall.class);
        when(call.getString("id")).thenReturn("dup-id");
        when(call.getString("url")).thenReturn("https://example.com/file");
        when(call.getString("destination")).thenReturn("file.bin");
        when(call.getString("downloadCompletedNotificationText")).thenReturn("Replacement");

        plugin.download(call);

        verify(call).reject("Download already exists");
        assertEquals("Original", notificationStore.takeText("dup-id", 1L));
        assertEquals(Long.valueOf(99L), downloads.get("dup-id"));
    }

    @Test(timeout = 5_000)
    public void okHttpStartFailureDoesNotEvictReusedIdWithNewGeneration() throws Exception {
        String id = "reuse-id";
        File newDestination = new File(System.getProperty("java.io.tmpdir"), "okhttp-new-dest.bin");
        downloads.put(id, OkHttpDownloadExecutor.TRACKED_DOWNLOAD_ID);
        getDownloadGenerationsMap(plugin).put(id, 2L);

        @SuppressWarnings("unchecked")
        Map<String, File> destinationFiles = (Map<String, File>) getField(plugin, "okHttpDestinationFiles").get(plugin);
        destinationFiles.put(id, newDestination);

        File staleDestination = new File(System.getProperty("java.io.tmpdir"), "okhttp-old-dest.bin");
        Method method = CapacitorDownloaderPlugin.class.getDeclaredMethod(
            "applyOkHttpStartFailureIfCurrent",
            String.class,
            long.class,
            File.class,
            String.class
        );
        method.setAccessible(true);
        method.invoke(plugin, id, 1L, staleDestination, "stale transfer error");

        assertEquals(Long.valueOf(OkHttpDownloadExecutor.TRACKED_DOWNLOAD_ID), downloads.get(id));
        assertEquals(newDestination, destinationFiles.get(id));
        assertEquals(Long.valueOf(2L), getDownloadGenerationsMap(plugin).get(id));
    }

    @Test
    public void okHttpGenerationHelperRejectsStaleGeneration() throws Exception {
        getDownloadGenerationsMap(plugin).put("reuse-id", 2L);

        Method method = CapacitorDownloaderPlugin.class.getDeclaredMethod("isCurrentOkHttpGeneration", String.class, long.class);
        method.setAccessible(true);

        assertFalse((boolean) method.invoke(plugin, "reuse-id", 1L));
        assertTrue((boolean) method.invoke(plugin, "reuse-id", 2L));
    }

    @Test
    public void stopBatchSucceedsWhenChildrenNoLongerInDownloadManager() throws Exception {
        Map<String, DownloadBatchState> batches = getBatchesMap(plugin);
        Map<String, String> batchChildOwners = getBatchChildOwnersMap(plugin);

        DownloadBatchState batch = new DownloadBatchState("batch-1", 2, 1L, "completed");
        batch.trackChildId("batch-1#0");
        batch.trackChildId("batch-1#1");
        batches.put("batch-1", batch);
        downloads.put("batch-1#0", 101L);
        downloads.put("batch-1#1", 102L);
        batchChildOwners.put("batch-1#0", "batch-1");
        batchChildOwners.put("batch-1#1", "batch-1");

        when(downloadManager.remove(any(long[].class))).thenReturn(1);
        when(downloadManager.query(any(DownloadManager.Query.class))).thenReturn(null);

        PluginCall call = mockPluginCall("batch-1");
        plugin.stop(call);

        verify(call, timeout(5000)).resolve(any());
        assertFalse(batches.containsKey("batch-1"));
        assertFalse(downloads.containsKey("batch-1#0"));
        assertFalse(downloads.containsKey("batch-1#1"));
    }

    @Test
    public void stopBatchDoesNotRemoveCompletedChildFromDownloadManager() throws Exception {
        Map<String, DownloadBatchState> batches = getBatchesMap(plugin);
        Map<String, String> batchChildOwners = getBatchChildOwnersMap(plugin);
        DownloadBatchState batch = new DownloadBatchState("batch-1", 2, 1L, "completed");
        batch.markFileCompleted(0);
        batch.trackChildId("batch-1#0");
        batch.trackChildId("batch-1#1");
        batches.put("batch-1", batch);
        batchChildOwners.put("batch-1#0", "batch-1");
        batchChildOwners.put("batch-1#1", "batch-1");
        downloads.put("batch-1#0", 101L);
        downloads.put("batch-1#1", 102L);

        when(downloadManager.remove(any(long[].class))).thenReturn(1);
        when(downloadManager.query(any(DownloadManager.Query.class))).thenReturn(null);

        PluginCall call = mockPluginCall("batch-1");
        plugin.stop(call);

        verify(downloadManager, org.mockito.Mockito.never()).remove(101L);
        verify(call, timeout(5000)).resolve(any());
        assertFalse(batches.containsKey("batch-1"));
    }

    @Test
    public void failBatchPreservesChildWithFullProgressBeforeCompletionFlag() throws Exception {
        Map<String, DownloadBatchState> batches = getBatchesMap(plugin);
        Map<String, String> batchChildOwners = getBatchChildOwnersMap(plugin);
        DownloadBatchState batch = new DownloadBatchState("batch-1", 2, 1L, "completed");
        batch.updateFileProgress(0, 1f);
        batch.trackChildId("batch-1#0");
        batch.trackChildId("batch-1#1");
        batches.put("batch-1", batch);
        batchChildOwners.put("batch-1#0", "batch-1");
        batchChildOwners.put("batch-1#1", "batch-1");
        downloads.put("batch-1#0", 101L);
        downloads.put("batch-1#1", 102L);

        Method failBatch = plugin.getClass().getDeclaredMethod("failBatch", String.class, String.class, Integer.class);
        failBatch.setAccessible(true);
        failBatch.invoke(plugin, "batch-1", "failed", 1);

        verify(downloadManager, org.mockito.Mockito.never()).remove(101L);
        verify(downloadManager).remove(102L);
    }

    @Test
    public void downloadRejectsUrlAndFilesTogether() {
        PluginCall call = mock(PluginCall.class);
        JSArray filesArray = mock(JSArray.class);
        when(call.getString("id")).thenReturn("mixed");
        when(call.getString("url")).thenReturn("https://example.com/file");
        when(call.getArray("files")).thenReturn(filesArray);
        when(filesArray.length()).thenReturn(1);

        plugin.download(call);

        verify(call).reject("Provide either url and destination or files, not both");
    }

    @Test
    public void rollbackBatchDoesNotRemoveReusedChildId() throws Exception {
        Map<String, DownloadBatchState> batches = getBatchesMap(plugin);
        Map<String, String> batchChildOwners = getBatchChildOwnersMap(plugin);
        DownloadBatchState batch = new DownloadBatchState("batch-1", 1, 1L, "completed");
        batch.trackChildId("batch-1#0");
        batches.put("batch-1", batch);
        batchChildOwners.put("batch-1#0", "batch-1");
        downloads.put("batch-1#0", 101L);

        batchChildOwners.remove("batch-1#0", "batch-1");
        downloads.remove("batch-1#0", 101L);
        downloads.put("batch-1#0", 909L);

        Method rollback = CapacitorDownloaderPlugin.class.getDeclaredMethod("rollbackBatch", DownloadBatchState.class);
        rollback.setAccessible(true);
        rollback.invoke(plugin, batch);

        assertEquals(Long.valueOf(909L), downloads.get("batch-1#0"));
        assertFalse(batches.containsKey("batch-1"));
    }

    @Test
    public void failBatchDoesNotRemoveCompletedChildFromDownloadManager() throws Exception {
        Map<String, DownloadBatchState> batches = getBatchesMap(plugin);
        Map<String, String> batchChildOwners = getBatchChildOwnersMap(plugin);
        DownloadBatchState batch = new DownloadBatchState("batch-1", 2, 1L, "completed");
        batch.markFileCompleted(0);
        batch.trackChildId("batch-1#0");
        batch.trackChildId("batch-1#1");
        batches.put("batch-1", batch);
        batchChildOwners.put("batch-1#0", "batch-1");
        batchChildOwners.put("batch-1#1", "batch-1");
        downloads.put("batch-1#0", 101L);
        downloads.put("batch-1#1", 102L);

        Method failBatch = plugin.getClass().getDeclaredMethod("failBatch", String.class, String.class, Integer.class);
        failBatch.setAccessible(true);
        failBatch.invoke(plugin, "batch-1", "failed", 1);

        verify(downloadManager, org.mockito.Mockito.never()).remove(101L);
        verify(downloadManager).remove(102L);
        assertFalse(downloads.containsKey("batch-1#0"));
        assertFalse(downloads.containsKey("batch-1#1"));
    }

    @Test
    public void restoreStoppedBatchChildrenDoesNotResurrectRolledBackBatch() throws Exception {
        Map<String, DownloadBatchState> batches = getBatchesMap(plugin);
        DownloadBatchState batch = new DownloadBatchState("batch-1", 1, 1L, "completed");
        batch.committed.set(true);
        batch.rolledBack.set(true);
        batch.trackChildId("batch-1#0");

        Class<?> stoppedChildClass = Class.forName("ee.forgr.capacitor.plugin.downloader.CapacitorDownloaderPlugin$StoppedBatchChild");
        Constructor<?> constructor = stoppedChildClass.getDeclaredConstructor(String.class, long.class);
        constructor.setAccessible(true);
        Object stoppedChild = constructor.newInstance("batch-1#0", 101L);
        downloads.put("batch-1#0", 101L);

        Method restore = CapacitorDownloaderPlugin.class.getDeclaredMethod(
            "restoreStoppedBatchChildren",
            DownloadBatchState.class,
            String.class,
            List.class
        );
        restore.setAccessible(true);
        restore.invoke(plugin, batch, "batch-1", List.of(stoppedChild));

        assertFalse(batches.containsKey("batch-1"));
    }

    @Test
    public void restoreStoppedBatchChildrenSkipsReusedChildId() throws Exception {
        Map<String, String> batchChildOwners = getBatchChildOwnersMap(plugin);
        downloads.put("batch-1#0", 999L);

        DownloadBatchState batch = new DownloadBatchState("batch-1", 1, 1L, "completed");
        Class<?> stoppedChildClass = Class.forName("ee.forgr.capacitor.plugin.downloader.CapacitorDownloaderPlugin$StoppedBatchChild");
        Constructor<?> constructor = stoppedChildClass.getDeclaredConstructor(String.class, long.class);
        constructor.setAccessible(true);
        Object stoppedChild = constructor.newInstance("batch-1#0", 101L);

        Method method = CapacitorDownloaderPlugin.class.getDeclaredMethod(
            "restoreStoppedBatchChildren",
            DownloadBatchState.class,
            String.class,
            List.class
        );
        method.setAccessible(true);
        method.invoke(plugin, batch, "batch-1", List.of(stoppedChild));

        assertEquals(Long.valueOf(999L), downloads.get("batch-1#0"));
        assertFalse(batchChildOwners.containsKey("batch-1#0"));
        assertTrue(batch.ownedChildIds.isEmpty());
    }

    @Test
    public void checkStatusRejectsWhenQueryThrows() throws Exception {
        downloads.put("test-id", 42L);
        DownloadManager throwingManager = mock(DownloadManager.class, (invocation) -> {
            if ("query".equals(invocation.getMethod().getName())) {
                throw new RuntimeException("binder failure");
            }
            return org.mockito.Answers.RETURNS_DEFAULTS.answer(invocation);
        });
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
    private static Map<String, Long> getDownloadGenerationsMap(CapacitorDownloaderPlugin plugin) throws Exception {
        Field field = CapacitorDownloaderPlugin.class.getDeclaredField("downloadGenerations");
        field.setAccessible(true);
        return (Map<String, Long>) field.get(plugin);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Long> getDownloadsMap(CapacitorDownloaderPlugin plugin) throws Exception {
        Field downloadsField = CapacitorDownloaderPlugin.class.getDeclaredField("downloads");
        downloadsField.setAccessible(true);
        return (Map<String, Long>) downloadsField.get(plugin);
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        getField(target, fieldName).set(target, value);
    }

    private static Field getField(Object target, String fieldName) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        return field;
    }

    private static DownloadCompletedNotificationStore getNotificationStore(CapacitorDownloaderPlugin plugin) throws Exception {
        Field field = CapacitorDownloaderPlugin.class.getDeclaredField("completedNotificationStore");
        field.setAccessible(true);
        return (DownloadCompletedNotificationStore) field.get(plugin);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, DownloadBatchState> getBatchesMap(CapacitorDownloaderPlugin plugin) throws Exception {
        Field field = CapacitorDownloaderPlugin.class.getDeclaredField("batches");
        field.setAccessible(true);
        return (Map<String, DownloadBatchState>) field.get(plugin);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, String> getBatchChildOwnersMap(CapacitorDownloaderPlugin plugin) throws Exception {
        Field field = CapacitorDownloaderPlugin.class.getDeclaredField("batchChildOwners");
        field.setAccessible(true);
        return (Map<String, String>) field.get(plugin);
    }
}
