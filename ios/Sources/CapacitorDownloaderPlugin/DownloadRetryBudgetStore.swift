import Foundation

final class DownloadRetryBudgetStore {
    static let shared = DownloadRetryBudgetStore()

    static let userDefaultsKey = "CapacitorDownloaderRetryBudgets"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setBudget(_ budget: DownloadConnectionRetry.Budget, for downloadId: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = budgetsMapUnlocked()
        map[downloadId] = [
            "remainingRetries": budget.remainingRetries,
            "connectionFailureCount": budget.connectionFailureCount
        ]
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func removeBudget(for downloadId: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = budgetsMapUnlocked()
        map.removeValue(forKey: downloadId)
        defaults.set(map, forKey: Self.userDefaultsKey)
    }

    func allBudgets() -> [String: DownloadConnectionRetry.Budget] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: DownloadConnectionRetry.Budget] = [:]
        for (downloadId, entry) in budgetsMapUnlocked() {
            guard let remaining = entry["remainingRetries"] as? Int,
                  let failures = entry["connectionFailureCount"] as? Int else {
                continue
            }
            result[downloadId] = DownloadConnectionRetry.Budget(
                remainingRetries: remaining,
                connectionFailureCount: failures
            )
        }
        return result
    }

    private func budgetsMapUnlocked() -> [String: [String: Any]] {
        defaults.dictionary(forKey: Self.userDefaultsKey) as? [String: [String: Any]] ?? [:]
    }
}