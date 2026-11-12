package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import com.getcapacitor.JSObject;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mockito;

public class OkHttpDownloadExecutorTest {

    private MockWebServer server;
    private OkHttpDownloadExecutor executor;
    private File tempDir;

    @Before
    public void setUp() throws Exception {
        server = new MockWebServer();
        server.start();
        Context context = Mockito.mock(Context.class);
        Mockito.when(context.getApplicationContext()).thenReturn(context);
        executor = new OkHttpDownloadExecutor(context);
        tempDir = new File(System.getProperty("java.io.tmpdir"), "okhttp-download-test");
        tempDir.mkdirs();
    }

    @After
    public void tearDown() throws Exception {
        server.shutdown();
    }

    @Test
    public void downloadsBytesToDestination() throws Exception {
        byte[] payload = "offline-package".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("Content-Length", String.valueOf(payload.length))
        );

        File destination = new File(tempDir, "pkg.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);
        AtomicReference<String> error = new AtomicReference<>();

        executor.start(
            "task-1",
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                error.set(errorMessage);
                finished.countDown();
            }
        );

        assertTrue(finished.await(10, TimeUnit.SECONDS));
        assertTrue(success.get());
        assertEquals(payload.length, destination.length());
        byte[] onDisk = java.nio.file.Files.readAllBytes(destination.toPath());
        assertEquals(new String(payload, StandardCharsets.UTF_8), new String(onDisk, StandardCharsets.UTF_8));
    }

    @Test
    public void downloadsShortDestinationFileName() throws Exception {
        byte[] payload = "x".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("Content-Length", String.valueOf(payload.length))
        );

        File destination = new File(tempDir, "a");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);

        executor.start(
            "task-short",
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(10, TimeUnit.SECONDS));
        assertTrue(success.get());
        assertEquals(1, destination.length());
    }

    @Test
    public void preservesExistingDestinationWhenConnectionFails() throws Exception {
        server.enqueue(new MockResponse().setResponseCode(503));

        File destination = new File(tempDir, "existing-pack.bin");
        byte[] existing = "keep-me".getBytes(StandardCharsets.UTF_8);
        try (java.io.FileOutputStream fos = new java.io.FileOutputStream(destination)) {
            fos.write(existing);
        }

        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(true);

        executor.start(
            "task-2",
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(10, TimeUnit.SECONDS));
        assertEquals(false, success.get());
        assertEquals(existing.length, destination.length());
        try (java.io.FileInputStream fis = new java.io.FileInputStream(destination)) {
            byte[] restored = fis.readAllBytes();
            assertEquals(new String(existing, StandardCharsets.UTF_8), new String(restored, StandardCharsets.UTF_8));
        }
    }
}
