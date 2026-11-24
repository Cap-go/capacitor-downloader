package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atMost;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.timeout;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import android.app.DownloadManager;
import android.content.Context;
import android.database.MatrixCursor;
import android.os.Looper;
import com.getcapacitor.JSArray;
import com.getcapacitor.PluginCall;
import java.lang.reflect.Field;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mockito;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class CapacitorDownloaderPluginBatchEntryTest {

    private CapacitorDownloaderPlugin plugin;
    private DownloadManager downloadManager;
    private ExecutorService downloadManagerExecutor;
    private Context context;

    @Before
    public void setUp() throws Exception {
        context = RuntimeEnvironment.getApplication();
        plugin = spy(new CapacitorDownloaderPlugin());
        downloadManager = Mockito.mock(DownloadManager.class);
        downloadManagerExecutor = Executors.newSingleThreadExecutor((runnable) -> new Thread(runnable, "download-manager-worker"));
        doReturn(context).when(plugin).getContext();

        setField(plugin, "downloadManager", downloadManager);
        setField(plugin, "downloadManagerExecutor", downloadManagerExecutor);
        setField(plugin, "okHttpTransferExecutor", Executors.newFixedThreadPool(4));
        setField(plugin, "okHttpDownloadExecutor", new OkHttpDownloadExecutor(context));
        setField(plugin, "completedNotificationStore", new DownloadCompletedNotificationStore(context));
        setField(plugin, "failedNotificationStore", new DownloadFailedNotificationStore(context));
        setField(plugin, "handler", new android.os.Handler(Looper.getMainLooper()));
    }

    @After
    public void tearDown() throws Exception {
        if (downloadManagerExecutor != null) {
            downloadManagerExecutor.shutdown();
            downloadManagerExecutor.awaitTermination(5, TimeUnit.SECONDS);
        }
    }

    @Test
    public void downloadBatchEnqueuesThirtyThreeFilesFromPluginEntry() throws Exception {
        AtomicLong nextSystemId = new AtomicLong(2000L);
        when(downloadManager.enqueue(any(DownloadManager.Request.class))).thenAnswer((invocation) -> nextSystemId.getAndIncrement());

        PluginCall call = buildBatchCall("thirty-three-batch", 33);
        plugin.download(call);
        Shadows.shadowOf(Looper.getMainLooper()).idle();

        verify(call, timeout(5000)).resolve(any());
        verify(downloadManager, times(33)).enqueue(any(DownloadManager.Request.class));
    }

    @Test
    public void downloadBatchStartsSingleProgressPollerForHundredFiles() throws Exception {
        AtomicLong nextSystemId = new AtomicLong(3000L);
        when(downloadManager.enqueue(any(DownloadManager.Request.class))).thenAnswer((invocation) -> nextSystemId.getAndIncrement());

        when(downloadManager.query(any())).thenAnswer((invocation) -> {
            MatrixCursor cursor = new MatrixCursor(new String[] {
                DownloadManager.COLUMN_ID,
                DownloadManager.COLUMN_STATUS,
                DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
                DownloadManager.COLUMN_TOTAL_SIZE_BYTES
            });
            for (long id = 3000L; id < 3100L; id++) {
                cursor.addRow(new Object[] { id, DownloadManager.STATUS_RUNNING, 10L, 100L });
            }
            return cursor;
        });

        PluginCall call = buildBatchCall("hundred-batch", 100);
        plugin.download(call);
        Shadows.shadowOf(Looper.getMainLooper()).idle();

        verify(call, timeout(5000)).resolve(any());
        verify(downloadManager, times(100)).enqueue(any(DownloadManager.Request.class));

        Shadows.shadowOf(Looper.getMainLooper()).idleFor(1100, TimeUnit.MILLISECONDS);
        Shadows.shadowOf(Looper.getMainLooper()).idle();

        verify(downloadManager, timeout(5000).atLeastOnce()).query(any());
        // One poll can tick twice inside the advanced second; a poller per file would query a hundred times.
        verify(downloadManager, atMost(2)).query(any());
    }

    @Test
    public void downloadBatchFailsWhenItsDownloadManagerRowDisappears() throws Exception {
        AtomicLong nextSystemId = new AtomicLong(4000L);
        when(downloadManager.enqueue(any(DownloadManager.Request.class))).thenAnswer((invocation) -> nextSystemId.getAndIncrement());
        AtomicInteger queries = new AtomicInteger();
        // Only the first, unfiltered poll query returns rows; the single-id query that confirms 4002 finds nothing.
        when(downloadManager.query(any())).thenAnswer((invocation) ->
            queries.getAndIncrement() == 0 ? runningRows(4000L, 4001L) : runningRows()
        );

        PluginCall call = buildBatchCall("missing-row-batch", 3);
        plugin.download(call);
        Shadows.shadowOf(Looper.getMainLooper()).idle();
        verify(call, timeout(5000)).resolve(any());

        @SuppressWarnings("unchecked")
        Map<String, DownloadBatchState> batches = (Map<String, DownloadBatchState>) getField(plugin, "batches").get(plugin);
        DownloadBatchState batch = batches.get("missing-row-batch");
        assertNotNull(batch);

        Shadows.shadowOf(Looper.getMainLooper()).idleFor(1100, TimeUnit.MILLISECONDS);
        verify(downloadManager, timeout(5000).atLeastOnce()).query(any());
        for (int attempt = 0; attempt < 50 && !batch.failed.get(); attempt++) {
            Thread.sleep(100);
            Shadows.shadowOf(Looper.getMainLooper()).idle();
        }

        assertTrue(batch.failed.get());
    }

    @Test
    public void downloadBatchKeepsRunningWhenTheConfirmationQueryFindsTheSkippedRow() throws Exception {
        AtomicLong nextSystemId = new AtomicLong(5000L);
        when(downloadManager.enqueue(any(DownloadManager.Request.class))).thenAnswer((invocation) -> nextSystemId.getAndIncrement());
        AtomicInteger queries = new AtomicInteger();
        // The unfiltered poll query skips 5002, as a cursor read in windows can; the single-id query finds it running.
        when(downloadManager.query(any())).thenAnswer((invocation) ->
            queries.getAndIncrement() == 0 ? runningRows(5000L, 5001L) : runningRows(5002L)
        );

        PluginCall call = buildBatchCall("skipped-row-batch", 3);
        plugin.download(call);
        Shadows.shadowOf(Looper.getMainLooper()).idle();
        verify(call, timeout(5000)).resolve(any());

        @SuppressWarnings("unchecked")
        Map<String, DownloadBatchState> batches = (Map<String, DownloadBatchState>) getField(plugin, "batches").get(plugin);
        DownloadBatchState batch = batches.get("skipped-row-batch");
        assertNotNull(batch);

        Shadows.shadowOf(Looper.getMainLooper()).idleFor(1100, TimeUnit.MILLISECONDS);
        verify(downloadManager, timeout(5000).atLeast(2)).query(any());
        for (int attempt = 0; attempt < 5; attempt++) {
            Thread.sleep(100);
            Shadows.shadowOf(Looper.getMainLooper()).idle();
        }

        assertFalse(batch.failed.get());
        assertSame(batch, batches.get("skipped-row-batch"));
    }

    @Test
    public void downloadBatchEnqueuesFortyFilesFromPluginEntry() throws Exception {
        AtomicLong nextSystemId = new AtomicLong(1000L);
        when(downloadManager.enqueue(any(DownloadManager.Request.class))).thenAnswer((invocation) -> nextSystemId.getAndIncrement());

        PluginCall call = buildBatchCall("large-batch", 40);
        plugin.download(call);
        Shadows.shadowOf(Looper.getMainLooper()).idle();

        verify(call, timeout(5000)).resolve(any());
        verify(downloadManager, times(40)).enqueue(any(DownloadManager.Request.class));

        @SuppressWarnings("unchecked")
        Map<String, DownloadBatchState> batches = (Map<String, DownloadBatchState>) getField(plugin, "batches").get(plugin);
        DownloadBatchState batch = batches.get("large-batch");
        assertNotNull(batch);
        assertEquals(40, batch.fileCount);
        assertEquals(40, batch.ownedChildIds.size());
    }

    private static MatrixCursor runningRows(long... systemDownloadIds) {
        MatrixCursor cursor = new MatrixCursor(new String[] {
            DownloadManager.COLUMN_ID,
            DownloadManager.COLUMN_STATUS,
            DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
            DownloadManager.COLUMN_TOTAL_SIZE_BYTES
        });
        for (long systemDownloadId : systemDownloadIds) {
            cursor.addRow(new Object[] { systemDownloadId, DownloadManager.STATUS_RUNNING, 10L, 100L });
        }
        return cursor;
    }

    private static PluginCall buildBatchCall(String batchId, int fileCount) throws Exception {
        JSArray filesArray = Mockito.mock(JSArray.class);
        when(filesArray.length()).thenReturn(fileCount);
        when(filesArray.getJSONObject(Mockito.anyInt())).thenAnswer((invocation) -> {
            int index = invocation.getArgument(0);
            JSONObject file = new JSONObject();
            file.put("url", "https://example.com/" + index + ".bin");
            file.put("destination", "large-" + index + ".bin");
            return file;
        });
        PluginCall call = Mockito.mock(PluginCall.class);
        when(call.getString("id")).thenReturn(batchId);
        when(call.getArray("files")).thenReturn(filesArray);
        when(call.getString("url")).thenReturn(null);
        when(call.getString("androidHttpEngine")).thenReturn("downloadManager");
        return call;
    }

    private static Field getField(Object target, String fieldName) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        return field;
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        getField(target, fieldName).set(target, value);
    }
}
