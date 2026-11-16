package ee.forgr.capacitor.plugin.downloader;

final class DownloadHttpStatusRules {

    private DownloadHttpStatusRules() {}

    static boolean isSuccessfulHttpCode(int code) {
        return code >= 200 && code < 300;
    }

    static String formatHttpErrorMessage(int code) {
        return "HTTP " + code;
    }
}
