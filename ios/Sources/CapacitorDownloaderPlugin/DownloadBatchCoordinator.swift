import Foundation

final class DownloadBatchCoordinator {
    private struct ActiveBatch {
        let batchId: String
        let fileCount: Int
        var fileProgress: [Float]
        var completedCount: Int
        var failed: Bool
        var cancelled: Bool
    }

    private var batches: [String: ActiveBatch] = [:]
    private let batchesLock = NSLock()

    func fileTaskId(batchId: String, fileIndex: Int) -> String {
        "\(batchId)#\(fileIndex)"
    }

    func parseBatchId(from taskId: String) -> (batchId: String, fileIndex: Int)? {
        guard let hashIndex = taskId.lastIndex(of: "#") else {
            return nil
        }
        let batchId = String(taskId[..<hashIndex])
        let indexPart = String(taskId[taskId.index(after: hashIndex)...])
        guard let fileIndex = Int(indexPart) else {
            return nil
        }
        return (batchId, fileIndex)
    }

    func startBatch(batchId: String, fileCount: Int) -> Bool {
        guard fileCount > 0 else {
            return false
        }
        batchesLock.lock()
        defer { batchesLock.unlock() }
        if batches[batchId] != nil {
            return false
        }
        batches[batchId] = ActiveBatch(
            batchId: batchId,
            fileCount: fileCount,
            fileProgress: Array(repeating: 0, count: fileCount),
            completedCount: 0,
            failed: false,
            cancelled: false
        )
        return true
    }

    func isBatch(batchId: String) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return batches[batchId] != nil
    }

    func fileCount(batchId: String) -> Int? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return batches[batchId]?.fileCount
    }

    func overallProgress(batchId: String) -> Float? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard let batch = batches[batchId] else {
            return nil
        }
        return DownloadBatchProgress.overallProgress(fileProgress: batch.fileProgress, fileCount: batch.fileCount)
    }

    func markCancelled(batchId: String) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        batches[batchId]?.cancelled = true
    }

    func removeBatch(batchId: String) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        batches.removeValue(forKey: batchId)
    }

    func updateFileProgress(batchId: String, fileIndex: Int, progress: Float) -> (overall: Float, file: Float)? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId], !batch.failed, !batch.cancelled else {
            return nil
        }
        guard fileIndex >= 0, fileIndex < batch.fileProgress.count else {
            return nil
        }
        batch.fileProgress[fileIndex] = progress
        batches[batchId] = batch
        let overall = DownloadBatchProgress.overallProgress(fileProgress: batch.fileProgress, fileCount: batch.fileCount)
        return (overall, progress)
    }

    func markFileCompleted(batchId: String, fileIndex: Int) -> BatchCompletionState? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId], !batch.failed, !batch.cancelled else {
            return nil
        }
        guard fileIndex >= 0, fileIndex < batch.fileProgress.count else {
            return nil
        }
        batch.fileProgress[fileIndex] = 1
        batch.completedCount += 1
        batches[batchId] = batch
        if batch.completedCount >= batch.fileCount {
            batches.removeValue(forKey: batchId)
            return .allSucceeded(batchId: batchId)
        }
        return .inProgress(
            overall: DownloadBatchProgress.overallProgress(fileProgress: batch.fileProgress, fileCount: batch.fileCount)
        )
    }

    enum BatchCompletionState {
        case inProgress(overall: Float)
        case allSucceeded(batchId: String)
    }
}
