package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Notification;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import com.getcapacitor.JSObject;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowNotificationManager;
import org.robolectric.shadows.ShadowService;
import org.robolectric.shadows.ShadowSystemClock;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class OkHttpDownloadProgressNotifierRobolectricTest {

    private Context context;
    private OkHttpDownloadProgressNotifier notifier;

    @Before
    public void setUp() {
        OkHttpDownloadForegroundService.resetLifecycleStateForTests();
        context = RuntimeEnvironment.getApplication();
        notifier = new OkHttpDownloadProgressNotifier(context);
    }

    @After
    public void tearDown() {
        notifier.shutdown();
        OkHttpDownloadForegroundService.setThrowStartNotAllowedForTests(false);
        OkHttpDownloadForegroundService.setThrowOnStartForegroundForTests(false);
        OkHttpDownloadProgressNotifier.setSimulateNotificationPostSecurityExceptionForTests(false);
        OkHttpDownloadForegroundService.resetLifecycleStateForTests();
    }

    @Test
    public void progressModePostsSingleSharedNotificationForOneDownload() {
        assertTrue(notifier.started("single", "Area", "Maps", "progress"));

        Notification pinned = OkHttpDownloadProgressNotifier.foregroundServiceNotification(context);
        assertNotNull(pinned.extras.getCharSequence(Notification.EXTRA_TITLE));
        assertEquals("Area", pinned.extras.getCharSequence(Notification.EXTRA_TITLE).toString());

        NotificationManager notificationManager = context.getSystemService(NotificationManager.class);
        ShadowNotificationManager shadowNotificationManager = shadowOf(notificationManager);
        assertEquals(1, shadowNotificationManager.size());
        assertNotNull(shadowNotificationManager.getNotification(null, OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID));

        notifier.finished("single", true);
        assertNull(shadowNotificationManager.getNotification(null, OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID));
    }

    @Test
    public void parallelProgressDownloadsUseOneCombinedNotification() {
        assertTrue(notifier.started("a", "Pack A", null, "progress"));
        assertTrue(notifier.started("b", "Pack B", null, "progress"));

        NotificationManager notificationManager = context.getSystemService(NotificationManager.class);
        ShadowNotificationManager shadowNotificationManager = shadowOf(notificationManager);
        assertEquals(1, shadowNotificationManager.size());

        Notification notification = shadowNotificationManager.getNotification(
            null,
            OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID
        );
        assertNotNull(notification);
        String title = notification.extras.getCharSequence(Notification.EXTRA_TITLE).toString();
        assertTrue(title.contains("Pack A"));
        assertTrue(title.contains("Pack B"));

        ShadowSystemClock.advanceBy(Duration.ofMillis(2_000L));
        notifier.update("a", 0.5f);
        notifier.update("b", 0.5f);
        notification = shadowNotificationManager.getNotification(null, OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID);
        assertNotNull(notification);
        assertEquals(50, notification.extras.getInt(Notification.EXTRA_PROGRESS, -1));

        notifier.finished("a", true);
        assertEquals(1, shadowNotificationManager.size());
        notification = shadowNotificationManager.getNotification(null, OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID);
        assertNotNull(notification);
        assertEquals("Pack B", notification.extras.getCharSequence(Notification.EXTRA_TITLE).toString());

        notifier.finished("b", true);
        assertNull(shadowNotificationManager.getNotification(null, OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID));
    }

    @Test
    public void completedModeDoesNotOptIntoProgressUi() {
        assertFalse(OkHttpDownloadProgressNotifier.shouldShowProgressForMode(null));
        assertFalse(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("completed"));
        assertTrue(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("progress"));
        assertFalse(OkHttpDownloadProgressNotifier.shouldShowProgressForMode("hidden"));
    }

    @Test
    public void startedReturnsTrueForCompletedModeWithoutForegroundService() {
        assertTrue(notifier.started("id-1", "Title", null, "completed"));
        notifier.finished("id-1", true);
    }

    @Test
    public void immediateFinishBeforeServiceForegroundDoesNotCrash() {
        assertTrue(notifier.started("fast", "Title", null, "progress"));
        notifier.finished("fast", true);

        OkHttpDownloadForegroundService service = Robolectric.buildService(OkHttpDownloadForegroundService.class).create().get();
        int startId = service.onStartCommand(new Intent(), 0, 1);
        assertEquals(android.app.Service.START_NOT_STICKY, startId);
        assertEquals(0, OkHttpDownloadForegroundService.peekLastKnownActiveDownloadsForTests());
        assertEquals(1, OkHttpDownloadForegroundService.peekForegroundPromotionCountForTests());
        service.onDestroy();
    }

    @Test
    public void foregroundPromotionShowsCurrentAggregateAfterDownloadFinishes() {
        assertTrue(notifier.started("a", "Pack A", null, "progress"));
        assertTrue(notifier.started("b", "Pack B", null, "progress"));
        notifier.finished("a", true);

        NotificationManager notificationManager = context.getSystemService(NotificationManager.class);
        ShadowNotificationManager shadowNotificationManager = shadowOf(notificationManager);
        Notification beforePromotion = shadowNotificationManager.getNotification(
            null,
            OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID
        );
        assertNotNull(beforePromotion);
        String titleBefore = beforePromotion.extras.getCharSequence(Notification.EXTRA_TITLE).toString();
        assertEquals("Pack B", titleBefore);

        OkHttpDownloadForegroundService service = Robolectric.buildService(OkHttpDownloadForegroundService.class).create().get();
        service.onStartCommand(new Intent(), 0, 1);

        Notification afterPromotion = shadowNotificationManager.getNotification(
            null,
            OkHttpDownloadForegroundService.SERVICE_NOTIFICATION_ID
        );
        assertNotNull(afterPromotion);
        String titleAfter = afterPromotion.extras.getCharSequence(Notification.EXTRA_TITLE).toString();
        assertEquals("Pack B", titleAfter);
        assertFalse(titleAfter.contains("Pack A"));
        service.onDestroy();
    }

    @Test
    public void abandonDownloadReleasesForegroundSlot() {
        assertTrue(notifier.started("leak", "Title", null, "progress"));
        notifier.abandonDownload("leak");
        assertEquals(0, OkHttpDownloadForegroundService.peekLastKnownActiveDownloadsForTests());
        OkHttpDownloadForegroundService service = Robolectric.buildService(OkHttpDownloadForegroundService.class).create().get();
        service.onStartCommand(new Intent(), 0, 1);
        service.onDestroy();
    }

    @Test
    public void shutdownReleasesForegroundSlot() {
        assertTrue(notifier.started("busy", "Title", null, "progress"));
        notifier.shutdown();
        assertEquals(0, OkHttpDownloadForegroundService.peekLastKnownActiveDownloadsForTests());
    }

    @Test
    public void progressNotificationSecurityExceptionReleasesForegroundSlot() {
        OkHttpDownloadProgressNotifier.setSimulateNotificationPostSecurityExceptionForTests(true);
        assertTrue(notifier.started("no-post", "Title", null, "progress"));
        assertEquals(0, OkHttpDownloadForegroundService.peekLastKnownActiveDownloadsForTests());
    }

    @Test
    public void onStartCommandSurvivesStartForegroundFailure() {
        OkHttpDownloadForegroundService.setThrowOnStartForegroundForTests(true);
        OkHttpDownloadForegroundService service = Robolectric.buildService(OkHttpDownloadForegroundService.class).create().get();
        int startId = service.onStartCommand(new Intent(), 0, 1);
        assertEquals(android.app.Service.START_NOT_STICKY, startId);
        assertEquals(0, OkHttpDownloadForegroundService.peekForegroundPromotionCountForTests());
        ShadowService shadowService = shadowOf(service);
        assertTrue(shadowService.isStoppedBySelf());
        service.onDestroy();
    }

    @Test(timeout = 10_000)
    public void downloadCompletesWhenForegroundServiceStartNotAllowed() throws Exception {
        OkHttpDownloadForegroundService.setThrowStartNotAllowedForTests(true);

        MockWebServer server = new MockWebServer();
        server.start();
        byte[] payload = "foreground-blocked".getBytes(StandardCharsets.UTF_8);
        server.enqueue(
            new MockResponse().setBody(new okio.Buffer().write(payload)).addHeader("Content-Length", String.valueOf(payload.length))
        );

        File destination = new File(context.getCacheDir(), "fg-blocked.bin");
        CountDownLatch finished = new CountDownLatch(1);
        AtomicBoolean success = new AtomicBoolean(false);

        OkHttpDownloadExecutor executor = new OkHttpDownloadExecutor(context);
        OkHttpDownloadExecutor.ActiveDownload reservation = executor.beginTransfer("fg-blocked");
        assertTrue(notifier.started("fg-blocked", "Title", null, "progress"));

        executor.start(
            reservation,
            server.url("/file").toString(),
            destination,
            new JSObject(),
            "cellular",
            (downloadId, progress) -> notifier.update(downloadId, progress),
            (downloadId, ok, cancelled, errorMessage) -> {
                success.set(ok);
                notifier.finished(downloadId, ok);
                finished.countDown();
            }
        );

        assertTrue(finished.await(5, TimeUnit.SECONDS));
        assertTrue("download should succeed when FGS start is blocked", success.get());
        assertTrue(destination.exists());
        assertEquals(payload.length, destination.length());

        server.shutdown();
    }
}
