package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.content.Intent;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

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
        OkHttpDownloadForegroundService.resetLifecycleStateForTests();
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
        service.onDestroy();
    }

    @Test
    public void abandonDownloadReleasesForegroundSlot() {
        assertTrue(notifier.started("leak", "Title", null, "progress"));
        notifier.abandonDownload("leak");
        OkHttpDownloadForegroundService service = Robolectric.buildService(OkHttpDownloadForegroundService.class).create().get();
        service.onStartCommand(new Intent(), 0, 1);
        service.onDestroy();
    }
}
