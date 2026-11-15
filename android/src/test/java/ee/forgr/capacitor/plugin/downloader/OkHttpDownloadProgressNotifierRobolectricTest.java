package ee.forgr.capacitor.plugin.downloader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.app.Application;
import android.content.Context;
import androidx.test.core.app.ApplicationProvider;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ServiceController;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowApplication;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class OkHttpDownloadProgressNotifierRobolectricTest {

    private Context context;
    private OkHttpDownloadProgressNotifier notifier;

    @Before
    public void setUp() {
        OkHttpDownloadForegroundService.resetLifecycleStateForTests();
        context = ApplicationProvider.getApplicationContext();
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
    public void startedReturnsTrueWhenForegroundServiceCannotStart() {
        ShadowApplication shadow = shadowOf((Application) context);
        shadow.setComponentEnabledAndUpdateFlags(
            OkHttpDownloadForegroundService.class.getName(),
            android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            android.content.pm.PackageManager.DONT_KILL_APP
        );
        assertTrue(notifier.started("id-1", "Title", null, "progress"));
        notifier.finished("id-1", true);
    }

    @Test
    public void immediateFinishBeforeServiceForegroundDoesNotCrash() {
        assertTrue(notifier.started("fast", "Title", null, "progress"));
        notifier.finished("fast", true);

        ServiceController<OkHttpDownloadForegroundService> controller = Robolectric.buildService(OkHttpDownloadForegroundService.class);
        controller.create();
        int startId = controller.get().onStartCommand(null, 0, 1);
        assertEquals(android.app.Service.START_NOT_STICKY, startId);
        controller.destroy();
    }

    @Test
    public void abandonDownloadReleasesForegroundSlot() {
        assertTrue(notifier.started("leak", "Title", null, "progress"));
        notifier.abandonDownload("leak");
        ServiceController<OkHttpDownloadForegroundService> controller = Robolectric.buildService(OkHttpDownloadForegroundService.class);
        controller.create();
        controller.get().onStartCommand(null, 0, 1);
        controller.destroy();
    }
}
