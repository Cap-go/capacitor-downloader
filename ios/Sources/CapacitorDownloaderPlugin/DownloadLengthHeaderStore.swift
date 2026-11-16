import Foundation

/// Per-task `lengthHeader` option and resolved expected totals from HTTP responses.
final class DownloadLengthHeaderStore {
    static let shared = DownloadLengthHeaderStore()

    private let lock = NSLock()
    private var headerNames: [String: String] = [:]
    private var expectedTotals: [String: Int64] = [:]

    func setHeaderName(_ name: String?, for taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        if let name, !name.isEmpty {
            headerNames[taskId] = name
        } else {
            headerNames.removeValue(forKey: taskId)
        }
        expectedTotals.removeValue(forKey: taskId)
    }

    func headerName(for taskId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return headerNames[taskId]
    }

    func setExpectedTotal(_ total: Int64, for taskId: String) {
        guard total > 0 else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        expectedTotals[taskId] = total
    }

    func expectedTotal(for taskId: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return expectedTotals[taskId]
    }

    func clear(for taskId: String) {
        lock.lock()
        defer { lock.unlock() }
        headerNames.removeValue(forKey: taskId)
        expectedTotals.removeValue(forKey: taskId)
    }
}