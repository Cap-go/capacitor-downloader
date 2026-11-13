import Foundation

final class DownloadIdGenerationStore {
    static let shared = DownloadIdGenerationStore()

    static let userDefaultsKey = "CapacitorDownloaderDownloadGenerations"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setGeneration(_ generation: UInt64, forDownloadId id: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = generationsMapUnlocked()
        map[id] = NSNumber(value: generation)
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func allGenerations() -> [String: UInt64] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: UInt64] = [:]
        for (key, value) in generationsMapUnlocked() {
            guard let number = value as? NSNumber else {
                continue
            }
            result[key] = number.uint64Value
        }
        return result
    }

    private func generationsMapUnlocked() -> [String: Any] {
        defaults.dictionary(forKey: Self.userDefaultsKey) ?? [:]
    }
}
