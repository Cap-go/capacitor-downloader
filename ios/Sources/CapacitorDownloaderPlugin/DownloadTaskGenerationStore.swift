import Foundation

enum DownloadTaskGenerationKey {
    static let separator = "|"

    static func storageKey(sessionIdentifier: String, taskIdentifier: Int) -> String {
        "\(sessionIdentifier)\(separator)\(taskIdentifier)"
    }

    static func storageKey(for task: URLSessionTask) -> String {
        let sessionIdentifier = task.session.configuration.identifier ?? DownloadSessionIdentifiers.foregroundCapable
        return storageKey(sessionIdentifier: sessionIdentifier, taskIdentifier: task.taskIdentifier)
    }

    static func isLegacyBareKey(_ key: String) -> Bool {
        !key.contains(separator) && Int(key) != nil
    }
}

final class DownloadTaskGenerationStore {
    static let shared = DownloadTaskGenerationStore()

    static let userDefaultsKey = "CapacitorDownloaderTaskGenerations"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setGeneration(_ generation: UInt64, forSessionIdentifier sessionIdentifier: String, taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        var map = generationsMapUnlocked()
        let key = DownloadTaskGenerationKey.storageKey(sessionIdentifier: sessionIdentifier, taskIdentifier: taskIdentifier)
        map[key] = NSNumber(value: generation)
        map.removeValue(forKey: String(taskIdentifier))
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func setGeneration(_ generation: UInt64, forTask task: URLSessionTask) {
        let sessionIdentifier = task.session.configuration.identifier ?? DownloadSessionIdentifiers.foregroundCapable
        setGeneration(generation, forSessionIdentifier: sessionIdentifier, taskIdentifier: task.taskIdentifier)
    }

    func removeGeneration(forSessionIdentifier sessionIdentifier: String, taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        var map = generationsMapUnlocked()
        let key = DownloadTaskGenerationKey.storageKey(sessionIdentifier: sessionIdentifier, taskIdentifier: taskIdentifier)
        map.removeValue(forKey: key)
        map.removeValue(forKey: String(taskIdentifier))
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func removeGeneration(forTask task: URLSessionTask) {
        let sessionIdentifier = task.session.configuration.identifier ?? DownloadSessionIdentifiers.foregroundCapable
        removeGeneration(forSessionIdentifier: sessionIdentifier, taskIdentifier: task.taskIdentifier)
    }

    /// Restores session qualified keys and migrates bare 8.7.0 integer keys to the main background session.
    func allGenerations() -> [String: UInt64] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: UInt64] = [:]
        for (key, value) in generationsMapUnlocked() {
            guard let number = value as? NSNumber else {
                continue
            }
            if DownloadTaskGenerationKey.isLegacyBareKey(key), let taskIdentifier = Int(key) {
                let qualified = DownloadTaskGenerationKey.storageKey(
                    sessionIdentifier: DownloadSessionIdentifiers.main,
                    taskIdentifier: taskIdentifier
                )
                if result[qualified] == nil {
                    result[qualified] = number.uint64Value
                }
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