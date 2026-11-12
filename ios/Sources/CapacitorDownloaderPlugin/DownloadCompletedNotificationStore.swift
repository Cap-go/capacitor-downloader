import Foundation

final class DownloadCompletedNotificationStore {
    static let shared = DownloadCompletedNotificationStore()

    static let userDefaultsKey = "CapacitorDownloaderCompletedNotificationTexts"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setText(_ text: String?, for id: String) {
        var map = textsMap()
        if let normalized = DownloadCompletedNotificationText.normalize(text) {
            map[id] = normalized
        } else {
            map.removeValue(forKey: id)
        }
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func takeText(for id: String) -> String? {
        var map = textsMap()
        let text = map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
        return text
    }

    func removeText(for id: String) {
        var map = textsMap()
        map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    private func textsMap() -> [String: String] {
        defaults.dictionary(forKey: Self.userDefaultsKey) as? [String: String] ?? [:]
    }
}
