import Foundation

final class DownloadTaskGenerationStore {
    static let shared = DownloadTaskGenerationStore()

    static let userDefaultsKey = "CapacitorDownloaderTaskGenerations"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setGeneration(_ generation: UInt64, forTaskIdentifier taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        var map = generationsMapUnlocked()
        map[String(taskIdentifier)] = NSNumber(value: generation)
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func removeGeneration(forTaskIdentifier taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        var map = generationsMapUnlocked()
        map.removeValue(forKey: String(taskIdentifier))
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func allGenerations() -> [Int: UInt64] {
        lock.lock()
        defer { lock.unlock() }
        var result: [Int: UInt64] = [:]
        for (key, value) in generationsMapUnlocked() {
            guard let taskIdentifier = Int(key), let number = value as? NSNumber else {
                continue
            }
            result[taskIdentifier] = number.uint64Value
        }
        return result
    }

    private func generationsMapUnlocked() -> [String: Any] {
        defaults.dictionary(forKey: Self.userDefaultsKey) ?? [:]
    }
}
