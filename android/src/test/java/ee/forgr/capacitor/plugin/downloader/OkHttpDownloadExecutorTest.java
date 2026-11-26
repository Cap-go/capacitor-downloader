package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import com.getcapacitor.JSObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.lang.reflect.Field;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.zip.GZIPOutputStream;
import javax.net.SocketFactory;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.mockwebserver.Dispatcher;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import okhttp3.mockwebserver.SocketPolicy;
import okhttp3.tls.HandshakeCertificates;
import okhttp3.tls.HeldCertificate;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.mockito.Mockito;

public class OkHttpDownloadExecutorTest {

    private MockWebServer server;
    private OkHttpDownloadExecutor executor;
    private File tempDir;

    /** Released when the server receives the slow request a test cancels, so it is cancelled while in flight. */
    private final CountDownLatch slowRequestReceived = new CountDownLatch(1);

    @Before
    public void setUp() throws Exception {
        server = new MockWebServer();
        server.start(InetAddress.getByName("127.0.0.1"), 0);
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

    @Test(timeout = 10_000)
    public void usesLengthHeaderWhenContentLengthMissing() throws Exception {
        byte[] payload = "gzip-style-payload".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse()
                .setChunkedBody(new okio.Buffer().write(payload), 8)
                .addHeader("X-Uncompressed-Length", String.valueOf(payload.length))
        );

        File destination = new File(tempDir, "length-header.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);
        java.util.List<Float> progressSamples = new java.util.ArrayList<>();
        AtomicReference<Long> lastBytesTotal = new AtomicReference<>(0L);

        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer("length-header");
        assertNotNull(reservation);
        executor.start(
            reservation,
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            0,
            "X-Uncompressed-Length",
            (id, progress) -> {
                progressSamples.add(progress);
                OkHttpDownloadExecutor.ActiveDownload active = executor.getActive(id);
                if (active != null) {
                    lastBytesTotal.set(active.bytesTotal);
                }
            },
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertTrue(success.get());
        assertEquals(payload.length, destination.length());
        assertFalse(progressSamples.isEmpty());
        for (Float sample : progressSamples) {
            assertTrue("progress must stay <= 1 (sample=" + sample + ")", sample <= 1f);
        }
        assertEquals(Long.valueOf(payload.length), lastBytesTotal.get());
    }

    @Test(timeout = 10_000)
    public void clampsProgressWhenLengthHeaderSmallerThanDecodedBody() throws Exception {
        byte[] payload = new byte[4096];
        for (int i = 0; i < payload.length; i++) {
            payload[i] = (byte) (i % 251);
        }
        server.enqueue(new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("X-Uncompressed-Length", "100"));

        File destination = new File(tempDir, "length-header-clamp.bin");
        CountDownLatch finished = new CountDownLatch(1);
        java.util.List<Float> progressSamples = new java.util.ArrayList<>();

        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer("length-header-clamp");
        assertNotNull(reservation);
        executor.start(
            reservation,
            server.url("/clamp").toString(),
            destination,
            new JSObject(),
            "cellular",
            0,
            "X-Uncompressed-Length",
            (id, progress) -> progressSamples.add(progress),
            (id, ok, cancelled, errorMessage) -> finished.countDown()
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertEquals(payload.length, destination.length());
        assertFalse(progressSamples.isEmpty());
        for (Float sample : progressSamples) {
            assertTrue("progress must stay <= 1 (sample=" + sample + ")", sample <= 1f);
        }
    }

    @Test(timeout = 10_000)
    public void downloadsBytesToDestination() throws Exception {
        byte[] payload = "offline-package".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("Content-Length", String.valueOf(payload.length))
        );

        File destination = new File(tempDir, "pkg.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);
        AtomicReference<String> error = new AtomicReference<>();

        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer("task-1");
        assertNotNull(reservation);
        executor.start(
            reservation,
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            0,
            null,
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                error.set(errorMessage);
                finished.countDown();
            }
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertTrue(success.get());
        assertEquals(payload.length, destination.length());
        byte[] onDisk = java.nio.file.Files.readAllBytes(destination.toPath());
        assertEquals(new String(payload, StandardCharsets.UTF_8), new String(onDisk, StandardCharsets.UTF_8));
    }

    @Test(timeout = 10_000)
    public void downloadsShortDestinationFileName() throws Exception {
        byte[] payload = "x".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("Content-Length", String.valueOf(payload.length))
        );

        File destination = new File(tempDir, "a");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);

        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer("task-short");
        assertNotNull(reservation);
        executor.start(
            reservation,
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            0,
            null,
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertTrue(success.get());
        assertEquals(1, destination.length());
    }

    @Test(timeout = 10_000)
    public void rejectsHttpsToHttpRedirectBeforeFollowing() throws Exception {
        HeldCertificate heldCertificate = new HeldCertificate.Builder().addSubjectAlternativeName("127.0.0.1").build();
        HandshakeCertificates certificates = new HandshakeCertificates.Builder()
            .heldCertificate(heldCertificate)
            .addTrustedCertificate(heldCertificate.certificate())
            .build();
        server.shutdown();
        server = new MockWebServer();
        server.useHttps(certificates.sslSocketFactory(), false);
        server.start(InetAddress.getByName("127.0.0.1"), 0);

        HttpUrl httpsStart = server.url("/start").newBuilder().host("127.0.0.1").build();
        String httpLocation = server.url("/insecure").newBuilder().host("127.0.0.1").scheme("http").build().toString();
        server.enqueue(
            new MockResponse()
                .setResponseCode(302)
                .addHeader("Location", httpLocation)
                .addHeader("Connection", "close")
                .setBody(new okio.Buffer())
        );

        OkHttpClient client = new OkHttpClient.Builder()
            .sslSocketFactory(certificates.sslSocketFactory(), certificates.trustManager())
            .hostnameVerifier((hostname, session) -> true)
            .followRedirects(true)
            .followSslRedirects(false)
            .callTimeout(5, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .build();

        Request request = new Request.Builder().url(httpsStart).build();
        try (Response response = client.newCall(request).execute()) {
            assertEquals(302, response.code());
            assertTrue(response.request().url().isHttps());
        }

        assertEquals(1, server.getRequestCount());
    }

    @Test(timeout = 5_000)
    public void executorDefaultClientDisallowsSslDowngradeRedirects() throws Exception {
        Field field = OkHttpDownloadExecutor.class.getDeclaredField("defaultClient");
        field.setAccessible(true);
        OkHttpClient productionClient = (OkHttpClient) field.get(executor);

        HeldCertificate heldCertificate = new HeldCertificate.Builder().addSubjectAlternativeName("127.0.0.1").build();
        HandshakeCertificates certificates = new HandshakeCertificates.Builder()
            .heldCertificate(heldCertificate)
            .addTrustedCertificate(heldCertificate.certificate())
            .build();
        server.shutdown();
        server = new MockWebServer();
        server.useHttps(certificates.sslSocketFactory(), false);
        server.start(InetAddress.getByName("127.0.0.1"), 0);

        HttpUrl httpsStart = server.url("/start").newBuilder().host("127.0.0.1").build();
        String httpLocation = server.url("/insecure").newBuilder().host("127.0.0.1").scheme("http").build().toString();
        server.enqueue(
            new MockResponse()
                .setResponseCode(302)
                .addHeader("Location", httpLocation)
                .addHeader("Connection", "close")
                .setBody(new okio.Buffer())
        );

        OkHttpClient client = productionClient
            .newBuilder()
            .sslSocketFactory(certificates.sslSocketFactory(), certificates.trustManager())
            .hostnameVerifier((hostname, session) -> true)
            .callTimeout(5, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .build();

        Request request = new Request.Builder().url(httpsStart).build();
        try (Response response = client.newCall(request).execute()) {
            assertEquals(302, response.code());
            assertTrue(response.request().url().isHttps());
        }
        assertEquals(1, server.getRequestCount());
    }

    @Test(timeout = 10_000)
    public void wifiOnlyLookupResolvesWifiNetworkOncePerTransfer() throws Exception {
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write("wifi".getBytes(StandardCharsets.UTF_8))).addHeader("Content-Length", "4")
        );

        Context context = Mockito.mock(Context.class);
        ConnectivityManager connectivityManager = Mockito.mock(ConnectivityManager.class);
        Network wifi = Mockito.mock(Network.class);
        NetworkCapabilities capabilities = Mockito.mock(NetworkCapabilities.class);
        when(context.getApplicationContext()).thenReturn(context);
        when(context.getSystemService(Context.CONNECTIVITY_SERVICE)).thenReturn(connectivityManager);
        when(connectivityManager.getAllNetworks()).thenReturn(new Network[] { wifi });
        when(connectivityManager.getNetworkCapabilities(wifi)).thenReturn(capabilities);
        when(capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)).thenReturn(true);
        when(capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)).thenReturn(true);
        when(wifi.getSocketFactory()).thenReturn(SocketFactory.getDefault());

        OkHttpDownloadExecutor wifiExecutor = new OkHttpDownloadExecutor(context);
        File destination = new File(tempDir, "wifi.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);

        OkHttpDownloadExecutor.ActiveDownload reservation = wifiExecutor.beginTransfer("wifi-1");
        assertNotNull(reservation);
        wifiExecutor.start(
            reservation,
            server.url("/wifi").toString(),
            destination,
            new JSObject(),
            "wifi-only",
            0,
            null,
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertTrue(success.get());
        verify(connectivityManager, times(1)).getAllNetworks();
    }

    @Test(timeout = 10_000)
    public void preservesExistingDestinationWhenConnectionFails() throws Exception {
        server.enqueue(new MockResponse().setResponseCode(503));

        File destination = new File(tempDir, "existing-pack.bin");
        byte[] existing = "keep-me".getBytes(StandardCharsets.UTF_8);
        try (java.io.FileOutputStream fos = new java.io.FileOutputStream(destination)) {
            fos.write(existing);
        }

        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(true);

        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer("task-2");
        assertNotNull(reservation);
        executor.start(
            reservation,
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            0,
            null,
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertEquals(false, success.get());
        assertEquals(existing.length, destination.length());
        try (java.io.FileInputStream fis = new java.io.FileInputStream(destination)) {
            byte[] restored = fis.readAllBytes();
            assertEquals(new String(existing, StandardCharsets.UTF_8), new String(restored, StandardCharsets.UTF_8));
        }
    }

    @Test(timeout = 5_000)
    public void ensureDestinationParentAcceptsExistingDirectory() throws Exception {
        File parent = new File(tempDir, "mkdir-race");
        assertTrue(parent.mkdirs() || parent.isDirectory());
        File destination = new File(parent, "out.bin");
        OkHttpDownloadExecutor.ensureDestinationParentDirectory(destination);
        assertTrue(parent.isDirectory());

        File nested = new File(tempDir, "nested/deep/file.bin");
        OkHttpDownloadExecutor.ensureDestinationParentDirectory(nested);
        assertTrue(nested.getParentFile().isDirectory());
    }

    @Test(timeout = 10_000)
    public void startRejectsStaleReservationWithoutHittingNetwork() throws Exception {
        server.enqueue(
            new MockResponse()
                .setBody(new okio.Buffer().write("must-not-fetch".getBytes(StandardCharsets.UTF_8)))
                .addHeader("Content-Length", "14")
        );
        OkHttpDownloadExecutor.ActiveDownload stale = executor.beginTransfer("reuse-id");
        assertNotNull(stale);
        executor.abandonTransfer(stale);
        OkHttpDownloadExecutor.ActiveDownload current = executor.beginTransfer("reuse-id");
        assertNotNull(current);

        File destination = new File(tempDir, "stale.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(true);
        AtomicBoolean cancelled = new AtomicBoolean(false);

        executor.start(
            stale,
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            0,
            null,
            (id, progress) -> {},
            (id, ok, cancelledFlag, errorMessage) -> {
                success.set(ok);
                cancelled.set(cancelledFlag);
                finished.countDown();
            }
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertFalse(success.get());
        assertTrue(cancelled.get());
        assertEquals(0, server.getRequestCount());
        assertNotNull(executor.getActive("reuse-id"));
        assertEquals(current, executor.getActive("reuse-id"));
    }

    @Test(timeout = 20_000)
    public void retriesOnceAfterConnectionDrop() throws Exception {
        byte[] payload = "retried".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse()
                .setBody(new okio.Buffer().write(payload))
                .addHeader("Content-Length", String.valueOf(payload.length))
                .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
        );
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("Content-Length", String.valueOf(payload.length))
        );

        File destination = new File(tempDir, "retry.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);

        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer("retry-task");
        assertNotNull(reservation);
        executor.start(
            reservation,
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            1,
            null,
            (id, progress) -> {},
            (id, ok, cancelled, errorMessage) -> {
                success.set(ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(15, TimeUnit.SECONDS));
        assertTrue(success.get());
        assertEquals(2, server.getRequestCount());
        assertEquals(payload.length, destination.length());
    }

    @Test(timeout = 5_000)
    public void abandonTransferOnlyRemovesMatchingReservation() {
        OkHttpDownloadExecutor.ActiveDownload current = executor.beginTransfer("shared-id");
        assertNotNull(current);

        OkHttpDownloadExecutor.ActiveDownload staleHandle = new OkHttpDownloadExecutor.ActiveDownload("shared-id");
        executor.abandonTransfer(staleHandle);
        assertSame(current, executor.getActive("shared-id"));
        assertFalse(current.cancelled.get());

        executor.abandonTransfer(current);
        assertNull(executor.getActive("shared-id"));
        assertTrue(current.cancelled.get());

        OkHttpDownloadExecutor.ActiveDownload next = executor.beginTransfer("shared-id");
        assertNotNull(next);
        assertNotSame(current, next);
    }

    @Test
    public void transferSlotsUseFairSemaphoreAndFourConcurrentCap() throws Exception {
        Field field = OkHttpDownloadExecutor.class.getDeclaredField("transferSlots");
        field.setAccessible(true);
        Semaphore semaphore = (Semaphore) field.get(executor);
        assertTrue(semaphore.isFair());
        assertEquals(4, semaphore.availablePermits());
    }

    @Test(timeout = 30_000)
    public void transferSlotsReturnAfterConcurrentSuccesses() throws Exception {
        assertTransferSlotsReturnAfterOutcomes(2, 0, 0);
    }

    @Test(timeout = 30_000)
    public void transferSlotsReturnAfterConcurrentHttp500() throws Exception {
        assertTransferSlotsReturnAfterOutcomes(0, 2, 0);
    }

    @Test(timeout = 30_000)
    public void transferSlotsReturnAfterCancelDuringTransfer() throws Exception {
        assertTransferSlotsReturnAfterOutcomes(0, 0, 1);
    }

    private void assertTransferSlotsReturnAfterOutcomes(int successCount, int http500Count, int cancelCount) throws Exception {
        byte[] payload = "slot-test".getBytes(StandardCharsets.UTF_8);
        int total = successCount + http500Count + cancelCount;
        CountDownLatch finished = new CountDownLatch(total);
        List<TransferOutcome> outcomes = Collections.synchronizedList(new ArrayList<>());
        java.util.concurrent.ExecutorService workers = java.util.concurrent.Executors.newFixedThreadPool(Math.max(1, total));

        installOutcomeDispatcher(payload, successCount, http500Count);

        String cancelTaskId = "cancel-path-0";
        for (int index = 0; index < total; index++) {
            final int taskIndex = index;
            final String taskId = cancelCount > 0 && index == total - 1 ? cancelTaskId : "outcome-" + taskIndex;
            workers.submit(() -> {
                File destination = new File(tempDir, taskId + ".bin");
                OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer(taskId);
                assertNotNull(reservation);
                String path = cancelCount > 0 && taskIndex == total - 1 ? "/cancel-path-0" : "/outcome-" + taskIndex;
                executor.start(
                    reservation,
                    server.url(path).toString(),
                    destination,
                    new JSObject(),
                    "cellular",
                    0,
                    null,
                    (id, progress) -> {},
                    (id, ok, cancelled, errorMessage) -> {
                        outcomes.add(new TransferOutcome(taskId, ok, cancelled, errorMessage));
                        finished.countDown();
                    }
                );
            });
        }

        if (cancelCount > 0) {
            assertTrue(slowRequestReceived.await(20, TimeUnit.SECONDS));
            executor.cancel(cancelTaskId, new File(tempDir, cancelTaskId + ".bin"));
        }

        assertTrue(finished.await(25, TimeUnit.SECONDS));
        workers.shutdown();
        assertTrue(workers.awaitTermination(10, TimeUnit.SECONDS));
        for (int index = 0; index < successCount; index++) {
            assertOutcomePresent(outcomes, "outcome-" + index, true, false);
        }
        for (int index = 0; index < http500Count; index++) {
            assertOutcomePresent(outcomes, "outcome-" + (successCount + index), false, false);
        }
        if (cancelCount > 0) {
            assertOutcomePresent(outcomes, cancelTaskId, false, true);
        }
        assertEquals(4, executor.availableTransferSlots());
    }

    private static void assertOutcomePresent(List<TransferOutcome> outcomes, String taskId, boolean success, boolean cancelled) {
        TransferOutcome match = null;
        for (TransferOutcome outcome : outcomes) {
            if (taskId.equals(outcome.taskId)) {
                match = outcome;
                break;
            }
        }
        assertNotNull("missing outcome for " + taskId, match);
        assertEquals(success, match.success);
        assertEquals(cancelled, match.cancelled);
    }

    private static final class TransferOutcome {

        final String taskId;
        final boolean success;
        final boolean cancelled;

        TransferOutcome(String taskId, boolean success, boolean cancelled, String errorMessage) {
            this.taskId = taskId;
            this.success = success;
            this.cancelled = cancelled;
        }
    }

    @Test(timeout = 60_000)
    public void transferSlotsReturnToFourAfterMixedOutcomes() throws Exception {
        byte[] payload = "slot-test".getBytes(StandardCharsets.UTF_8);
        CountDownLatch finished = new CountDownLatch(5);
        List<TransferOutcome> outcomes = Collections.synchronizedList(new ArrayList<>());
        java.util.concurrent.ExecutorService workers = java.util.concurrent.Executors.newFixedThreadPool(5);

        installMixedDispatcher(payload);

        for (int index = 0; index < 5; index++) {
            final int taskIndex = index;
            workers.submit(() -> {
                String taskId = "mixed-" + taskIndex;
                File destination = new File(tempDir, taskId + ".bin");
                OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer(taskId);
                assertNotNull(reservation);
                executor.start(
                    reservation,
                    server.url("/mixed-" + taskIndex).toString(),
                    destination,
                    new JSObject(),
                    "cellular",
                    0,
                    null,
                    (id, progress) -> {},
                    (id, ok, cancelled, errorMessage) -> {
                        outcomes.add(new TransferOutcome(taskId, ok, cancelled, errorMessage));
                        finished.countDown();
                    }
                );
            });
        }

        assertTrue(slowRequestReceived.await(20, TimeUnit.SECONDS));
        executor.cancel("mixed-4", new File(tempDir, "mixed-4.bin"));

        assertTrue(finished.await(30, TimeUnit.SECONDS));
        workers.shutdown();
        assertTrue(workers.awaitTermination(10, TimeUnit.SECONDS));
        assertOutcomePresent(outcomes, "mixed-0", true, false);
        assertOutcomePresent(outcomes, "mixed-1", true, false);
        assertOutcomePresent(outcomes, "mixed-2", false, false);
        assertOutcomePresent(outcomes, "mixed-3", false, false);
        assertOutcomePresent(outcomes, "mixed-4", false, true);
        assertEquals(4, executor.availableTransferSlots());
    }

    @Test(timeout = 60_000)
    public void fifthTransferWaitsUntilSlotOpensUnderSaturation() throws Exception {
        byte[] payload = "saturation".getBytes(StandardCharsets.UTF_8);
        CountDownLatch slowTransfersHoldingSlots = new CountDownLatch(4);
        installSaturationDispatcher(payload, slowTransfersHoldingSlots);

        java.util.concurrent.ExecutorService workers = java.util.concurrent.Executors.newFixedThreadPool(5);
        CountDownLatch finished = new CountDownLatch(5);

        for (int index = 0; index < 5; index++) {
            final int taskIndex = index;
            workers.submit(() -> {
                String taskId = "sat-" + taskIndex;
                File destination = new File(tempDir, taskId + ".bin");
                OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer(taskId);
                assertNotNull(reservation);
                executor.start(
                    reservation,
                    server.url("/sat-" + taskIndex).toString(),
                    destination,
                    new JSObject(),
                    "cellular",
                    0,
                    null,
                    (id, progress) -> {},
                    (id, ok, cancelled, errorMessage) -> finished.countDown()
                );
            });
        }

        assertTrue(slowTransfersHoldingSlots.await(20, TimeUnit.SECONDS));
        assertEquals(0, executor.availableTransferSlots());

        executor.cancel("sat-0", new File(tempDir, "sat-0.bin"));

        assertTrue(finished.await(30, TimeUnit.SECONDS));
        workers.shutdown();
        assertTrue(workers.awaitTermination(10, TimeUnit.SECONDS));
        assertEquals(4, executor.availableTransferSlots());
    }

    @Test(timeout = 30_000)
    public void cancelUnlessCommittedPreservesPreexistingDestination() throws Exception {
        byte[] payload = new byte[512 * 1024];
        byte[] preexisting = "keep-me".getBytes(StandardCharsets.UTF_8);
        CountDownLatch requestStarted = new CountDownLatch(1);
        CountDownLatch downloadInProgress = new CountDownLatch(1);
        server.setDispatcher(
            new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    if ("/preserve-dest".equals(request.getPath())) {
                        requestStarted.countDown();
                        return new MockResponse()
                            .setBody(new okio.Buffer().write(payload))
                            .addHeader("Content-Length", String.valueOf(payload.length))
                            .throttleBody(1024, 500, TimeUnit.MILLISECONDS);
                    }
                    return new MockResponse().setResponseCode(404);
                }
            }
        );

        String taskId = "preserve-cancel";
        File destination = new File(tempDir, taskId + ".bin");
        java.nio.file.Files.write(destination.toPath(), preexisting);

        CountDownLatch finished = new CountDownLatch(1);
        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer(taskId);
        assertNotNull(reservation);
        Thread transfer = new Thread(() ->
            executor.start(
                reservation,
                server.url("/preserve-dest").toString(),
                destination,
                new JSObject(),
                "cellular",
                0,
                null,
                (id, progress) -> {
                    if (progress > 0f) {
                        downloadInProgress.countDown();
                    }
                },
                (id, ok, cancelled, errorMessage) -> finished.countDown()
            )
        );
        transfer.start();

        assertTrue(requestStarted.await(20, TimeUnit.SECONDS));
        assertTrue(downloadInProgress.await(20, TimeUnit.SECONDS));
        assertTrue(executor.cancelUnlessCommitted(taskId, destination));
        assertTrue(finished.await(20, TimeUnit.SECONDS));
        assertTrue(destination.exists());
        assertArrayEquals(preexisting, java.nio.file.Files.readAllBytes(destination.toPath()));
    }

    private void installOutcomeDispatcher(byte[] payload, int successCount, int http500Count) {
        server.setDispatcher(
            new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    String path = request.getPath();
                    if (path == null) {
                        return new MockResponse().setResponseCode(404);
                    }
                    if ("/cancel-path-0".equals(path)) {
                        slowRequestReceived.countDown();
                        return new MockResponse()
                            .setBody(new okio.Buffer().write(payload))
                            .addHeader("Content-Length", String.valueOf(payload.length))
                            .setBodyDelay(3, TimeUnit.SECONDS);
                    }
                    if (path.startsWith("/outcome-")) {
                        int index = Integer.parseInt(path.substring("/outcome-".length()));
                        if (index < successCount) {
                            return new MockResponse()
                                .setBody(new okio.Buffer().write(payload))
                                .addHeader("Content-Length", String.valueOf(payload.length));
                        }
                        if (index < successCount + http500Count) {
                            return new MockResponse().setResponseCode(500);
                        }
                    }
                    return new MockResponse().setResponseCode(404);
                }
            }
        );
    }

    private void installMixedDispatcher(byte[] payload) {
        server.setDispatcher(
            new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    String path = request.getPath();
                    if (path == null) {
                        return new MockResponse().setResponseCode(404);
                    }
                    switch (path) {
                        case "/mixed-0":
                        case "/mixed-1":
                            return new MockResponse()
                                .setBody(new okio.Buffer().write(payload))
                                .addHeader("Content-Length", String.valueOf(payload.length));
                        case "/mixed-2":
                        case "/mixed-3":
                            return new MockResponse().setResponseCode(500);
                        case "/mixed-4":
                            slowRequestReceived.countDown();
                            return new MockResponse()
                                .setBody(new okio.Buffer().write(payload))
                                .addHeader("Content-Length", String.valueOf(payload.length))
                                .setBodyDelay(3, TimeUnit.SECONDS);
                        default:
                            return new MockResponse().setResponseCode(404);
                    }
                }
            }
        );
    }

    private void installSaturationDispatcher(byte[] payload, CountDownLatch slowTransfersHoldingSlots) {
        server.setDispatcher(
            new Dispatcher() {
                @Override
                public MockResponse dispatch(RecordedRequest request) {
                    String path = request.getPath();
                    if (path == null) {
                        return new MockResponse().setResponseCode(404);
                    }
                    if (path.matches("/sat-[0-3]")) {
                        slowTransfersHoldingSlots.countDown();
                        return new MockResponse()
                            .setBody(new okio.Buffer().write(payload))
                            .addHeader("Content-Length", String.valueOf(payload.length))
                            .setBodyDelay(8, TimeUnit.SECONDS);
                    }
                    if ("/sat-4".equals(path)) {
                        return new MockResponse()
                            .setBody(new okio.Buffer().write(payload))
                            .addHeader("Content-Length", String.valueOf(payload.length));
                    }
                    return new MockResponse().setResponseCode(404);
                }
            }
        );
    }
}
