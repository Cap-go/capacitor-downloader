package ee.forgr.capacitor.plugin.downloader;

import android.content.Context;
import android.content.SharedPreferences;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.json.JSONException;
import org.json.JSONObject;

final class DownloadCompletedNotificationStore {

    private static final String PREFS_NAME = "CapacitorDownloaderCompletedNotificationTexts";
    private static final String MAP_KEY = "texts";

    private final SharedPreferences prefs;
    private final ConcurrentHashMap<String, String> inMemoryTexts;
    private final Object lock = new Object();

    DownloadCompletedNotificationStore(Context context) {
        prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        inMemoryTexts = null;
    }

    DownloadCompletedNotificationStore() {
        prefs = null;
        inMemoryTexts = new ConcurrentHashMap<>();
    }

    void setText(String downloadId, String text) {
        if (downloadId == null) {
            return;
        }
        String normalized = DownloadCompletedNotificationText.normalize(text);
        synchronized (lock) {
            Map<String, String> texts = loadTextsLocked();
            if (normalized == null) {
                texts.remove(downloadId);
            } else {
                texts.put(downloadId, normalized);
            }
            saveTextsLocked(texts);
        }
    }

    String takeText(String downloadId) {
        if (downloadId == null) {
            return null;
        }
        synchronized (lock) {
            Map<String, String> texts = loadTextsLocked();
            String value = texts.remove(downloadId);
            saveTextsLocked(texts);
            return value;
        }
    }

    void remove(String downloadId) {
        if (downloadId == null) {
            return;
        }
        synchronized (lock) {
            Map<String, String> texts = loadTextsLocked();
            texts.remove(downloadId);
            saveTextsLocked(texts);
        }
    }

    private Map<String, String> loadTextsLocked() {
        if (inMemoryTexts != null) {
            return new HashMap<>(inMemoryTexts);
        }
        String json = prefs.getString(MAP_KEY, "{}");
        Map<String, String> texts = new HashMap<>();
        try {
            JSONObject object = new JSONObject(json);
            Iterator<String> keys = object.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                texts.put(key, object.getString(key));
            }
        } catch (JSONException ignored) {
            return new HashMap<>();
        }
        return texts;
    }

    private void saveTextsLocked(Map<String, String> texts) {
        if (inMemoryTexts != null) {
            inMemoryTexts.clear();
            inMemoryTexts.putAll(texts);
            return;
        }
        prefs.edit().putString(MAP_KEY, new JSONObject(texts).toString()).apply();
    }
}
