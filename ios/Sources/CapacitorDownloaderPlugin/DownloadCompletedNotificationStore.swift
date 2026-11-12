import Foundation

final class DownloadCompletedNotificationStore {
    static let shared = DownloadCompletedNotificationStore()

    static let userDefaultsKey = "CapacitorDownloaderCompletedNotificationTexts"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setText(_ text: String?, for id: String, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        var map = entriesMapUnlocked()
        if let normalized = DownloadCompletedNotificationText.normalize(text) {
            map[id] = Self.encodeEntry(text: normalized, generation: generation)
        } else {
            map.removeValue(forKey: id)
        }
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func takeText(for id: String, generation: UInt64) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var map = entriesMapUnlocked()
        guard let entry = map[id], Self.generation(from: entry) == generation else {
            return nil
        }
        map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
        return Self.text(from: entry)
    }

    func removeText(for id: String, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        var map = entriesMapUnlocked()
        guard let entry = map[id], Self.generation(from: entry) == generation else {
            return
        }
        map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    private func entriesMapUnlocked() -> [String: [String: Any]] {
        defaults.dictionary(forKey: Self.userDefaultsKey) as? [String: [String: Any]] ?? [:]
    }

    private static func encodeEntry(text: String, generation: UInt64) -> [String: Any] {
        ["text": text, "generation": NSNumber(value: generation)]
    }

    private static func text(from entry: [String: Any]) -> String? {
        entry["text"] as? String
    }

    private static func generation(from entry: [String: Any]) -> UInt64? {
        if let number = entry["generation"] as? NSNumber {
            return number.uint64Value
        }
        return entry["generation"] as? UInt64
    }
}
