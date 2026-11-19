import Foundation

/// Per-task `lengthHeader` option and resolved expected totals from HTTP responses.
final class DownloadLengthHeaderStore {
    static let shared = DownloadLengthHeaderStore()

    static let headerNamesDefaultsKey = "CapacitorDownloaderLengthHeaderNames"
    static let expectedTotalsDefaultsKey = "CapacitorDownloaderLengthHeaderTotals"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var headerNames: [String: String] = [:]
    private var expectedTotals: [String: Int64] = [:]
    private var loadedFromDisk = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setHeaderName(_ name: String?, for taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedUnlocked()
        if let name, !name.isEmpty {
            headerNames[taskId] = name
        } else {
            headerNames.removeValue(forKey: taskId)
        }
        expectedTotals.removeValue(forKey: taskId)
        persistUnlocked()
    }

    func headerName(for taskId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedUnlocked()
        return headerNames[taskId]
    }

    func setExpectedTotal(_ total: Int64, for taskId: String) {
        guard total > 0 else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedUnlocked()
        expectedTotals[taskId] = total
        persistUnlocked()
    }

    func expectedTotal(for taskId: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedUnlocked()
        return expectedTotals[taskId]
    }

    func clear(for taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedUnlocked()
        headerNames.removeValue(forKey: taskId)
        expectedTotals.removeValue(forKey: taskId)
        persistUnlocked()
    }

    func sweepStaleEntries(keeping taskIds: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedUnlocked()
        let staleNameKeys = headerNames.keys.filter { !taskIds.contains($0) }
        let staleTotalKeys = expectedTotals.keys.filter { !taskIds.contains($0) }
        guard !staleNameKeys.isEmpty || !staleTotalKeys.isEmpty else {
            return
        }
        for key in staleNameKeys {
            headerNames.removeValue(forKey: key)
        }
        for key in staleTotalKeys {
            expectedTotals.removeValue(forKey: key)
        }
        persistUnlocked()
    }

    private func ensureLoadedUnlocked() {
        guard !loadedFromDisk else {
            return
        }
        loadedFromDisk = true
        headerNames = defaults.dictionary(forKey: Self.headerNamesDefaultsKey) as? [String: String] ?? [:]
        if let raw = defaults.dictionary(forKey: Self.expectedTotalsDefaultsKey) as? [String: NSNumber] {
            var totals: [String: Int64] = [:]
            for (key, value) in raw {
                totals[key] = value.int64Value
            }
            expectedTotals = totals
        } else {
            expectedTotals = [:]
        }
    }

    private func persistUnlocked() {
        defaults.set(headerNames, forKey: Self.headerNamesDefaultsKey)
        let encoded = expectedTotals.mapValues { NSNumber(value: $0) }
        defaults.set(encoded, forKey: Self.expectedTotalsDefaultsKey)
    }
}