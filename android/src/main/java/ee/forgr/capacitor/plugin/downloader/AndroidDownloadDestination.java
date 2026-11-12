package ee.forgr.capacitor.plugin.downloader;

import android.content.Context;
import java.io.File;

/**
 * Resolves download destinations under app storage roots.
 *
 * <p>Relative prefixes:
 * <ul>
 *   <li>{@code cache/...} -> {@link Context#getCacheDir()}</li>
 *   <li>{@code files/...} -> {@link Context#getFilesDir()} (app-private data)</li>
 *   <li>{@code external/...} or default relative path -> {@link Context#getExternalFilesDir(String)}</li>
 *   <li>{@code public-downloads/...} -> public Downloads directory (DownloadManager only)</li>
 * </ul>
 */
public final class AndroidDownloadDestination {

    private AndroidDownloadDestination() {}

    public static ResolvedDestination resolve(Context context, String destination) {
        if (destination == null || destination.trim().isEmpty()) {
            throw new IllegalArgumentException("Missing destination");
        }

        String trimmed = destination.trim();
        if (trimmed.startsWith("file://")) {
            File file = new File(android.net.Uri.parse(trimmed).getPath());
            return new ResolvedDestination(file, preferOkHttpInAutoMode(context, file));
        }

        if (trimmed.startsWith("/")) {
            File file = new File(trimmed);
            return new ResolvedDestination(file, preferOkHttpInAutoMode(context, file));
        }

        if (trimmed.startsWith("cache/")) {
            File base = context.getCacheDir();
            File file = new File(base, trimmed.substring("cache/".length()));
            return new ResolvedDestination(file, true);
        }

        if (trimmed.startsWith("files/")) {
            File base = context.getFilesDir();
            File file = new File(base, trimmed.substring("files/".length()));
            return new ResolvedDestination(file, true);
        }

        if (trimmed.startsWith("public-downloads/")) {
            File base = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS);
            File file = new File(base, trimmed.substring("public-downloads/".length()));
            return new ResolvedDestination(file, false);
        }

        File base = context.getExternalFilesDir(null);
        if (base == null) {
            base = context.getFilesDir();
        }
        File file = new File(base, trimmed);
        return new ResolvedDestination(file, false);
    }

    /**
     * Whether {@link AndroidHttpEngineSelector} should pick OkHttp when {@code androidHttpEngine} is auto.
     */
    public static boolean preferOkHttpInAutoMode(Context context, File file) {
        try {
            String canonical = file.getCanonicalPath();
            return (
                isUnder(canonical, context.getCacheDir()) ||
                isUnder(canonical, context.getFilesDir()) ||
                isUnder(canonical, context.getDataDir())
            );
        } catch (java.io.IOException e) {
            return false;
        }
    }

    private static boolean isUnder(String path, File root) {
        if (root == null) {
            return false;
        }
        try {
            String rootCanonical = root.getCanonicalPath();
            return path.equals(rootCanonical) || path.startsWith(rootCanonical + File.separator);
        } catch (java.io.IOException e) {
            return false;
        }
    }

    public static final class ResolvedDestination {

        public final File file;
        /** When true, {@code androidHttpEngine: 'auto'} selects OkHttp. */
        public final boolean preferOkHttpInAutoMode;

        ResolvedDestination(File file, boolean preferOkHttpInAutoMode) {
            this.file = file;
            this.preferOkHttpInAutoMode = preferOkHttpInAutoMode;
        }
    }
}
