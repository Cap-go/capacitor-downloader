package ee.forgr.capacitor.plugin.downloader;

import android.content.Context;
import java.io.File;
import java.io.IOException;

/**
 * Resolves download destinations under app storage roots.
 *
 * <p>Relative prefixes:
 * <ul>
 *   <li>{@code cache/...} -> {@link Context#getCacheDir()}</li>
 *   <li>{@code files/...} -> {@link Context#getFilesDir()} (app-private data)</li>
 *   <li>{@code external/...} or default relative path -> {@link Context#getFilesDir()} or app external files</li>
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
            File file = childUnder(base, trimmed.substring("cache/".length()));
            return new ResolvedDestination(file, true);
        }

        if (trimmed.startsWith("files/")) {
            File base = context.getFilesDir();
            File file = childUnder(base, trimmed.substring("files/".length()));
            return new ResolvedDestination(file, true);
        }

        if (trimmed.startsWith("public-downloads/")) {
            File base = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS);
            File file = childUnder(base, trimmed.substring("public-downloads/".length()));
            return new ResolvedDestination(file, false);
        }

        File base = context.getExternalFilesDir(null);
        boolean usedInternalFallback = base == null;
        if (usedInternalFallback) {
            base = context.getFilesDir();
        }
        File file = childUnder(base, trimmed);
        boolean preferOkHttp = usedInternalFallback || preferOkHttpInAutoMode(context, file);
        return new ResolvedDestination(file, preferOkHttp);
    }

    static File childUnder(File base, String relative) {
        if (base == null) {
            throw new IllegalArgumentException("Storage root is unavailable");
        }
        File file = new File(base, relative);
        try {
            String canonical = file.getCanonicalPath();
            String baseCanonical = base.getCanonicalPath();
            if (!canonical.equals(baseCanonical) && !canonical.startsWith(baseCanonical + File.separator)) {
                throw new IllegalArgumentException("Destination escapes app storage: " + relative);
            }
        } catch (IOException e) {
            throw new IllegalArgumentException("Invalid destination path", e);
        }
        return file;
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
        } catch (IOException e) {
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
        } catch (IOException e) {
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
