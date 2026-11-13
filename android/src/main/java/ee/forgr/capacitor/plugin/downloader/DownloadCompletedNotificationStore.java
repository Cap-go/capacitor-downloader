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
    private final ConcurrentHashMap<String, Entry> inMemoryEntries;
    private final Object lock = new Object();

    DownloadCompletedNotificationStore(Context context) {
        prefs = context.getApplicationContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        inMemoryEntries = null;
        clearPersistedTexts();
    }

    DownloadCompletedNotificationStore() {
        prefs = null;
        inMemoryEntries = new ConcurrentHashMap<>();
    }

    void setText(String downloadId, String text, long generation) {
        if (downloadId == null) {
            return;
        }
        String normalized = DownloadCompletedNotificationText.normalize(text);
        synchronized (lock) {
            Map<String, Entry> entries = loadEntriesLocked();
            if (normalized == null) {
                entries.remove(downloadId);
            } else {
                entries.put(downloadId, new Entry(normalized, generation));
            }
            saveEntriesLocked(entries);
        }
    }

    String takeText(String downloadId, long generation) {
        if (downloadId == null) {
            return null;
        }
        synchronized (lock) {
            Map<String, Entry> entries = loadEntriesLocked();
            Entry entry = entries.get(downloadId);
            if (entry == null || entry.generation != generation) {
                return null;
            }
            entries.remove(downloadId);
            saveEntriesLocked(entries);
            return entry.text;
        }
    }

    void clearPersistedTexts() {
        if (prefs == null) {
            return;
        }
        synchronized (lock) {
            prefs.edit().remove(MAP_KEY).apply();
        }
    }

    void remove(String downloadId, long generation) {
        if (downloadId == null) {
            return;
        }
        synchronized (lock) {
            Map<String, Entry> entries = loadEntriesLocked();
            Entry entry = entries.get(downloadId);
            if (entry == null || entry.generation != generation) {
                return;
            }
            entries.remove(downloadId);
            saveEntriesLocked(entries);
        }
    }

    private Map<String, Entry> loadEntriesLocked() {
        if (inMemoryEntries != null) {
            return new HashMap<>(inMemoryEntries);
        }
        String json = prefs.getString(MAP_KEY, "{}");
        Map<String, Entry> entries = new HashMap<>();
        try {
            JSONObject object = new JSONObject(json);
            Iterator<String> keys = object.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                JSONObject entryObject = object.getJSONObject(key);
                entries.put(key, new Entry(entryObject.getString("text"), entryObject.getLong("generation")));
            }
        } catch (JSONException ignored) {
            return new HashMap<>();
        }
        return entries;
    }

    private void saveEntriesLocked(Map<String, Entry> entries) {
        if (inMemoryEntries != null) {
            inMemoryEntries.clear();
            inMemoryEntries.putAll(entries);
            return;
        }
        JSONObject object = new JSONObject();
        for (Map.Entry<String, Entry> entry : entries.entrySet()) {
            try {
                JSONObject entryObject = new JSONObject();
                entryObject.put("text", entry.getValue().text);
                entryObject.put("generation", entry.getValue().generation);
                object.put(entry.getKey(), entryObject);
            } catch (JSONException ignored) {
                // Skip malformed serialization for a single key.
            }
        }
        prefs.edit().putString(MAP_KEY, object.toString()).apply();
    }

    private static final class Entry {

        private final String text;
        private final long generation;

        private Entry(String text, long generation) {
            this.text = text;
            this.generation = generation;
        }
    }
}
