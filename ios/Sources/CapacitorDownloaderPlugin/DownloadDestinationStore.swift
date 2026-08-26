import Foundation

final class DownloadDestinationStore {
    static let shared = DownloadDestinationStore()

    static let userDefaultsKey = "CapacitorDownloaderDestinations"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setDestination(_ destination: String, for id: String) {
        var map = destinationsMap()
        map[id] = destination
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func takeDestination(for id: String) -> String? {
        var map = destinationsMap()
        let destination = map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
        return destination
    }

    func removeDestination(for id: String) {
        var map = destinationsMap()
        map.removeValue(forKey: id)
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    private func destinationsMap() -> [String: String] {
        defaults.dictionary(forKey: Self.userDefaultsKey) as? [String: String] ?? [:]
    }
}
