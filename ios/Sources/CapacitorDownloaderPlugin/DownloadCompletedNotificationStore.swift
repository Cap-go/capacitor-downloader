import Foundation

final class DownloadCompletedNotificationStore {
    static let shared = DownloadCompletedNotificationStore()

    static let userDefaultsKey = "CapacitorDownloaderCompletedNotificationTexts"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setText(_ text: String?, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = textsMapUnlocked()
        if let normalized = DownloadCompletedNotificationText.normalize(text) {
            map[id] = normalized
        } else {
            map.removeValue(forKey: id)
        }
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func takeText(for id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var map = textsMapUnlocked()
        let text = map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
        return text
    }

    func removeText(for id: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = textsMapUnlocked()
        map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    private func textsMapUnlocked() -> [String: String] {
        defaults.dictionary(forKey: Self.userDefaultsKey) as? [String: String] ?? [:]
    }
}
