package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import com.getcapacitor.JSObject;
import java.io.File;
import java.lang.reflect.Field;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import javax.net.SocketFactory;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
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
    public void downloadsBytesToDestination() throws Exception {
        byte[] payload = "offline-package".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("Content-Length", String.valueOf(payload.length))
        );

        File destination = new File(tempDir, "pkg.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);
        AtomicReference<String> error = new AtomicReference<>();

        assertTrue(executor.beginTransfer("task-1"));
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

        assertTrue(executor.beginTransfer("task-short"));
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

        assertTrue(wifiExecutor.beginTransfer("wifi-1"));
        wifiExecutor.start(
            "wifi-1",
            server.url("/wifi").toString(),
            destination,
            new JSObject(),
            "wifi-only",
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

        assertTrue(executor.beginTransfer("task-2"));
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

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertEquals(false, success.get());
        assertEquals(existing.length, destination.length());
        try (java.io.FileInputStream fis = new java.io.FileInputStream(destination)) {
            byte[] restored = fis.readAllBytes();
            assertEquals(new String(existing, StandardCharsets.UTF_8), new String(restored, StandardCharsets.UTF_8));
        }
    }
}
