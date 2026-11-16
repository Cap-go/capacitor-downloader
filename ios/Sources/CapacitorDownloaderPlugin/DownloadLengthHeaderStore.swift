import Foundation

/// Per-task `lengthHeader` option and resolved expected totals from HTTP responses.
final class DownloadLengthHeaderStore {
    static let shared = DownloadLengthHeaderStore()

    static let headerNamesDefaultsKey = "CapacitorDownloaderLengthHeaderNames"
    static let expectedTotalsDefaultsKey = "CapacitorDownloaderLengthHeaderTotals"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setHeaderName(_ name: String?, for taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        var names = headerNamesMap()
        var totals = expectedTotalsMap()
        if let name, !name.isEmpty {
            names[taskId] = name
        } else {
            names.removeValue(forKey: taskId)
        }
        totals.removeValue(forKey: taskId)
        persistHeaderNames(names)
        persistExpectedTotals(totals)
    }

    func headerName(for taskId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return headerNamesMap()[taskId]
    }

    func setExpectedTotal(_ total: Int64, for taskId: String) {
        guard total > 0 else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        var totals = expectedTotalsMap()
        totals[taskId] = total
        persistExpectedTotals(totals)
    }

    func expectedTotal(for taskId: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return expectedTotalsMap()[taskId]
    }

    func clear(for taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        var names = headerNamesMap()
        var totals = expectedTotalsMap()
        names.removeValue(forKey: taskId)
        totals.removeValue(forKey: taskId)
        persistHeaderNames(names)
        persistExpectedTotals(totals)
    }

    private func headerNamesMap() -> [String: String] {
        defaults.dictionary(forKey: Self.headerNamesDefaultsKey) as? [String: String] ?? [:]
    }

    private func expectedTotalsMap() -> [String: Int64] {
        guard let raw = defaults.dictionary(forKey: Self.expectedTotalsDefaultsKey) as? [String: NSNumber] else {
            return [:]
        }
        var totals: [String: Int64] = [:]
        for (key, value) in raw {
            totals[key] = value.int64Value
        }
        return totals
    }

    private func persistHeaderNames(_ map: [String: String]) {
        defaults.set(map, forKey: Self.headerNamesDefaultsKey)
    }

    private func persistExpectedTotals(_ map: [String: Int64]) {
        let encoded = map.mapValues { NSNumber(value: $0) }
        defaults.set(encoded, forKey: Self.expectedTotalsDefaultsKey)
    }
}