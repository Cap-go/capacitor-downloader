package ee.forgr.capacitor.plugin.downloader;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import android.app.DownloadManager;
import org.junit.Test;
import org.mockito.ArgumentMatchers;

public class DownloadManagerNotificationLabelsTest {

    @Test
    public void appliesTitleAndDescriptionWhenNonEmpty() {
        DownloadManager.Request request = mock(DownloadManager.Request.class);

        DownloadManagerNotificationLabels.apply(request, "Episode 12", "Downloading for offline playback");

        verify(request).setTitle("Episode 12");
        verify(request).setDescription("Downloading for offline playback");
    }

    @Test
    public void trimsWhitespaceBeforeApply() {
        DownloadManager.Request request = mock(DownloadManager.Request.class);

        DownloadManagerNotificationLabels.apply(request, "  My title  ", "  My description  ");

        verify(request).setTitle("My title");
        verify(request).setDescription("My description");
    }

    @Test
    public void skipsEmptyOrBlankStrings() {
        DownloadManager.Request request = mock(DownloadManager.Request.class);

        DownloadManagerNotificationLabels.apply(request, null, "");
        DownloadManagerNotificationLabels.apply(request, "   ", null);

        verify(request, never()).setTitle(ArgumentMatchers.any());
        verify(request, never()).setDescription(ArgumentMatchers.any());
    }
}
