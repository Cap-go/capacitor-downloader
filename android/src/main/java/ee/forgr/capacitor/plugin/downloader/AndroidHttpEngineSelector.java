package ee.forgr.capacitor.plugin.downloader;

/**
 * Chooses between DownloadManager and OkHttp for Android downloads.
 */
public final class AndroidHttpEngineSelector {

    public enum Engine {
        DOWNLOAD_MANAGER,
        OKHTTP
    }

    private AndroidHttpEngineSelector() {}

    /**
     * @param option explicit value from {@code androidHttpEngine}: auto, okhttp, or downloadManager (null => DownloadManager, same as main)
     */
    public static Engine resolve(String option, boolean preferOkHttpInAutoMode) {
        if (option == null || option.isEmpty()) {
            return Engine.DOWNLOAD_MANAGER;
        }
        if ("auto".equalsIgnoreCase(option)) {
            return preferOkHttpInAutoMode ? Engine.OKHTTP : Engine.DOWNLOAD_MANAGER;
        }
        if ("okhttp".equalsIgnoreCase(option) || "native".equalsIgnoreCase(option)) {
            return Engine.OKHTTP;
        }
        if ("downloadManager".equalsIgnoreCase(option) || "download_manager".equalsIgnoreCase(option)) {
            return Engine.DOWNLOAD_MANAGER;
        }
        throw new IllegalArgumentException("Invalid androidHttpEngine: " + option);
    }
}
