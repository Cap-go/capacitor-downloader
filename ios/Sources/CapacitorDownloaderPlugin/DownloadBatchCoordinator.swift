import Foundation

final class DownloadBatchCoordinator {
    private struct ActiveBatch {
        let batchId: String
        let generation: UInt64
        let fileCount: Int
        var fileProgress: [Float]
        var fileCompleted: [Bool]
        var completedCount: Int
        var failed: Bool
        var cancelled: Bool
        var paused: Bool
        var childTaskIds: Set<String>
        var savedDestinations: [Int: String]
    }

    private var batches: [String: ActiveBatch] = [:]
    private var batchGenerations: [String: UInt64] = [:]
    private var registeredChildren: [String: String] = [:]
    /// Batch child ids unregistered while still finishing on the URLSession delegate queue.
    private var inactiveBatchChildTaskIds: Set<String> = []
    /// Batch generations that finished before the download() promise resolved startup.
    private var startupCompletedBeforeResolve: [String: UInt64] = [:]
    private var startupPendingGenerations: [String: UInt64] = [:]
    private let batchesLock = NSLock()
    private let store: DownloadBatchStore
    private let persistQueue = DispatchQueue(label: "CapacitorDownloader.DownloadBatchCoordinator.persist")
    private var persistDebounceWorkItem: DispatchWorkItem?

    init(store: DownloadBatchStore = .shared) {
        self.store = store
        restorePersistedBatches()
    }

    func fileTaskId(batchId: String, generation: UInt64, fileIndex: Int) -> String {
        "\(batchId)#\(generation):\(fileIndex)"
    }

    func childParts(for taskId: String) -> (batchId: String, generation: UInt64, fileIndex: Int)? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return childPartsUnlocked(for: taskId)
    }

    func activeChildParts(for taskId: String) -> (batchId: String, generation: UInt64, fileIndex: Int)? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return activeChildPartsUnlocked(for: taskId)
    }

    private func activeChildPartsUnlocked(for taskId: String) -> (batchId: String, generation: UInt64, fileIndex: Int)? {
        guard let parts = childPartsUnlocked(for: taskId) ?? inactiveOwnedChildPartsUnlocked(for: taskId),
              let batch = batches[parts.batchId],
              batch.generation == parts.generation,
              !batch.cancelled, !batch.failed else {
            return nil
        }
        return parts
    }

    private func inactiveOwnedChildPartsUnlocked(for taskId: String) -> (batchId: String, generation: UInt64, fileIndex: Int)? {
        guard inactiveBatchChildTaskIds.contains(taskId) else {
            return nil
        }
        return parsedBatchChildTaskId(taskId)
    }

    func isBatchFormattedTaskId(_ taskId: String) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return parsedBatchChildTaskId(taskId) != nil
    }

    func isOwnedBatchChild(taskId: String) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return registeredChildren[taskId] != nil || inactiveBatchChildTaskIds.contains(taskId)
    }

    /// Verifies a batch child is still active, then removes an existing destination file under the batch lock.
    func prepareDestinationReplacement(taskId: String, destinationURL: URL) throws -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        let ownedBatchChild = registeredChildren[taskId] != nil || inactiveBatchChildTaskIds.contains(taskId)
        if ownedBatchChild {
            guard activeChildPartsUnlocked(for: taskId) != nil else {
                return false
            }
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        return true
    }

    private func childPartsUnlocked(for taskId: String) -> (batchId: String, generation: UInt64, fileIndex: Int)? {
        guard registeredChildren[taskId] != nil else {
            return nil
        }
        return parsedBatchChildTaskId(taskId)
    }

    private func parsedBatchChildTaskId(_ taskId: String) -> (batchId: String, generation: UInt64, fileIndex: Int)? {
        guard let hashIndex = taskId.lastIndex(of: "#"),
              let colonIndex = taskId.lastIndex(of: ":"),
              colonIndex > hashIndex else {
            return nil
        }
        let batchId = String(taskId[..<hashIndex])
        let generationPart = String(taskId[taskId.index(after: hashIndex)..<colonIndex])
        guard let generation = UInt64(generationPart) else {
            return nil
        }
        let indexPart = String(taskId[taskId.index(after: colonIndex)...])
        guard let fileIndex = Int(indexPart) else {
            return nil
        }
        return (batchId, generation, fileIndex)
    }

    func startBatch(batchId: String, fileCount: Int, singleDownloadIds: Set<String>) -> UInt64? {
        guard fileCount > 0 else {
            return nil
        }
        batchesLock.lock()
        defer { batchesLock.unlock() }
        if batches[batchId] != nil || singleDownloadIds.contains(batchId) {
            return nil
        }

        let generation = (batchGenerations[batchId] ?? 0) + 1
        batchGenerations[batchId] = generation

        for index in 0..<fileCount {
            let childId = fileTaskId(batchId: batchId, generation: generation, fileIndex: index)
            if singleDownloadIds.contains(childId) {
                batchGenerations[batchId] = generation - 1
                if batchGenerations[batchId] == 0 {
                    batchGenerations.removeValue(forKey: batchId)
                }
                return nil
            }
        }

        batches[batchId] = ActiveBatch(
            batchId: batchId,
            generation: generation,
            fileCount: fileCount,
            fileProgress: Array(repeating: 0, count: fileCount),
            fileCompleted: Array(repeating: false, count: fileCount),
            completedCount: 0,
            failed: false,
            cancelled: false,
            paused: false,
            childTaskIds: [],
            savedDestinations: [:]
        )
        persistBatchesImmediatelyLocked()
        return generation
    }

    func registerChildTask(batchId: String, taskId: String, fileIndex: Int) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId] else {
            return
        }
        batch.childTaskIds.insert(taskId)
        registeredChildren[taskId] = batchId
        batches[batchId] = batch
    }

    func persistBatchChildRegistrations(batchId: String) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard batches[batchId] != nil else {
            return
        }
        persistBatchesImmediatelyLocked()
    }

    func unregisterChildTask(_ taskId: String) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        if registeredChildren.removeValue(forKey: taskId) != nil, parsedBatchChildTaskId(taskId) != nil {
            inactiveBatchChildTaskIds.insert(taskId)
        }
    }

    func clearInactiveBatchChildTask(_ taskId: String) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        inactiveBatchChildTaskIds.remove(taskId)
    }

    func isBatch(batchId: String) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return batches[batchId] != nil
    }

    func generation(for batchId: String) -> UInt64? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return batches[batchId]?.generation
    }

    func childTaskIds(batchId: String) -> [String] {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard let batch = batches[batchId] else {
            return []
        }
        return Array(batch.childTaskIds)
    }

    func fileCount(batchId: String) -> Int? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return batches[batchId]?.fileCount
    }

    func isPaused(batchId: String) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        return batches[batchId]?.paused ?? false
    }

    func setPaused(batchId: String, paused: Bool) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId] else {
            return
        }
        batch.paused = paused
        batches[batchId] = batch
        persistBatchesImmediatelyLocked()
    }

    /// Call only while the plugin holds `tasksLock` so pause and retry registration stay coordinated.
    func setPausedReturningChildTaskIds(batchId: String, paused: Bool) -> [String] {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId] else {
            return []
        }
        batch.paused = paused
        batches[batchId] = batch
        persistBatchesImmediatelyLocked()
        return Array(batch.childTaskIds)
    }

    /// Call only while the plugin holds `tasksLock`.
    func isActiveChildPaused(taskId: String) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard let parts = childPartsUnlocked(for: taskId),
              let batch = batches[parts.batchId],
              batch.generation == parts.generation else {
            return false
        }
        return batch.paused
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
        guard var batch = batches[batchId] else {
            return
        }
        batch.cancelled = true
        batches[batchId] = batch
        for taskId in batch.childTaskIds {
            inactiveBatchChildTaskIds.remove(taskId)
        }
        startupPendingGenerations.removeValue(forKey: batchId)
        persistBatchesImmediatelyLocked()
    }

    struct BatchStartupSnapshot {
        let allowed: Bool
        let paused: Bool
    }

    func batchStartupSnapshot(batchId: String, generation: UInt64) -> BatchStartupSnapshot {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard let batch = batches[batchId], batch.generation == generation, !batch.cancelled, !batch.failed else {
            return BatchStartupSnapshot(allowed: false, paused: false)
        }
        return BatchStartupSnapshot(allowed: true, paused: batch.paused)
    }

    enum BatchStartupResumeOutcome {
        case proceed(paused: Bool)
        case abort
    }

    /// Decides whether download() may resolve after child tasks were resumed.
    func batchStartupResumeOutcome(batchId: String, generation: UInt64) -> BatchStartupResumeOutcome {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        let pendingGeneration = startupPendingGenerations.removeValue(forKey: batchId)
        if let batch = batches[batchId], batch.generation == generation {
            if batch.cancelled || batch.failed {
                return .abort
            }
            return .proceed(paused: batch.paused)
        }
        if pendingGeneration == generation, startupCompletedBeforeResolve.removeValue(forKey: batchId) == generation {
            return .proceed(paused: false)
        }
        return .abort
    }

    /// Registers child task ids for a batch under the same lock used by cancellation.
    func registerStartupChildren(
        batchId: String,
        generation: UInt64,
        children: [(taskId: String, fileIndex: Int)]
    ) -> BatchStartupSnapshot {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId], batch.generation == generation, !batch.cancelled, !batch.failed else {
            return BatchStartupSnapshot(allowed: false, paused: false)
        }
        for child in children {
            batch.childTaskIds.insert(child.taskId)
            registeredChildren[child.taskId] = batchId
        }
        batches[batchId] = batch
        startupPendingGenerations[batchId] = generation
        persistBatchesLocked()
        return BatchStartupSnapshot(allowed: true, paused: batch.paused)
    }

    struct BatchStopSnapshot {
        let generation: UInt64
        let childTaskIds: [String]
        let destinations: [String]
    }

    /// Removes the batch under the batch lock and returns child ids for task cancellation.
    func takeBatchForStop(batchId: String) -> BatchStopSnapshot? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard let batch = batches[batchId] else {
            return nil
        }
        let snapshot = BatchStopSnapshot(
            generation: batch.generation,
            childTaskIds: Array(batch.childTaskIds),
            destinations: batch.savedDestinations.values.sorted()
        )
        removeBatchLocked(batchId: batchId, unregisterChildren: false)
        return snapshot
    }

    func removeBatch(batchId: String, unregisterChildren: Bool = true) {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        removeBatchLocked(batchId: batchId, unregisterChildren: unregisterChildren)
    }

    func destinationsForCancellation(batchId: String) -> [String] {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard let batch = batches[batchId] else {
            return []
        }
        return batch.savedDestinations.values.sorted()
    }

    @discardableResult
    func recordMovedDestination(batchId: String, generation: UInt64, fileIndex: Int, destination: String) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId], batch.generation == generation, !batch.cancelled, !batch.failed else {
            return false
        }
        batch.savedDestinations[fileIndex] = destination
        batches[batchId] = batch
        schedulePersistBatchesLocked()
        return true
    }

    func updateFileProgress(batchId: String, generation: UInt64, fileIndex: Int, progress: Float) -> (overall: Float, file: Float)? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId], batch.generation == generation, !batch.failed, !batch.cancelled else {
            return nil
        }
        guard fileIndex >= 0, fileIndex < batch.fileProgress.count else {
            return nil
        }
        if batch.fileCompleted[fileIndex] {
            let overall = DownloadBatchProgress.overallProgress(fileProgress: batch.fileProgress, fileCount: batch.fileCount)
            return (overall, 1)
        }
        let clamped = min(1, max(0, progress))
        batch.fileProgress[fileIndex] = clamped
        batches[batchId] = batch
        let overall = DownloadBatchProgress.overallProgress(fileProgress: batch.fileProgress, fileCount: batch.fileCount)
        return (overall, clamped)
    }

    func markFileCompleted(
        batchId: String,
        generation: UInt64,
        fileIndex: Int,
        movedDestination: String? = nil
    ) -> BatchCompletionState? {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId], batch.generation == generation, !batch.failed, !batch.cancelled else {
            return nil
        }
        guard fileIndex >= 0, fileIndex < batch.fileProgress.count else {
            return nil
        }
        if let movedDestination {
            batch.savedDestinations[fileIndex] = movedDestination
        }
        if batch.fileCompleted[fileIndex] {
            if batch.completedCount >= batch.fileCount {
                return .allSucceeded(batchId: batchId, generation: batch.generation)
            }
            return .inProgress(
                overall: DownloadBatchProgress.overallProgress(fileProgress: batch.fileProgress, fileCount: batch.fileCount)
            )
        }
        batch.fileCompleted[fileIndex] = true
        batch.fileProgress[fileIndex] = 1
        batch.completedCount += 1
        batches[batchId] = batch
        if batch.completedCount >= batch.fileCount {
            let generation = batch.generation
            if startupPendingGenerations[batchId] == generation {
                startupCompletedBeforeResolve[batchId] = generation
            }
            startupPendingGenerations.removeValue(forKey: batchId)
            removeBatchLocked(batchId: batchId, unregisterChildren: true)
            return .allSucceeded(batchId: batchId, generation: generation)
        }
        persistBatchesImmediatelyLocked()
        return .inProgress(
            overall: DownloadBatchProgress.overallProgress(fileProgress: batch.fileProgress, fileCount: batch.fileCount)
        )
    }

    func beginFailure(batchId: String, generation: UInt64) -> Bool {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        guard var batch = batches[batchId], batch.generation == generation, !batch.failed, !batch.cancelled else {
            return false
        }
        batch.failed = true
        batches[batchId] = batch
        persistBatchesImmediatelyLocked()
        return true
    }

    enum BatchCompletionState {
        case inProgress(overall: Float)
        case allSucceeded(batchId: String, generation: UInt64)
    }

    private func removeBatchLocked(batchId: String, unregisterChildren: Bool) {
        guard let batch = batches.removeValue(forKey: batchId) else {
            return
        }
        for taskId in batch.childTaskIds {
            inactiveBatchChildTaskIds.remove(taskId)
        }
        startupPendingGenerations.removeValue(forKey: batchId)
        startupCompletedBeforeResolve.removeValue(forKey: batchId)
        if unregisterChildren {
            for taskId in batch.childTaskIds {
                registeredChildren.removeValue(forKey: taskId)
            }
        }
        persistBatchesImmediatelyLocked()
    }

    private func schedulePersistBatchesLocked() {
        persistDebounceWorkItem?.cancel()
        let snapshot = batches.mapValues { batch in
            DownloadBatchStore.Record(
                batchId: batch.batchId,
                generation: batch.generation,
                fileCount: batch.fileCount,
                fileProgress: batch.fileProgress,
                fileCompleted: batch.fileCompleted,
                completedCount: batch.completedCount,
                failed: batch.failed,
                cancelled: batch.cancelled,
                paused: batch.paused,
                childTaskIds: Array(batch.childTaskIds),
                savedDestinations: batch.savedDestinations
            )
        }
        let work = DispatchWorkItem { [store] in
            store.save(snapshot)
        }
        persistDebounceWorkItem = work
        persistQueue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func persistBatchesImmediatelyLocked() {
        persistDebounceWorkItem?.cancel()
        persistDebounceWorkItem = nil
        let snapshot = batches.mapValues { batch in
            DownloadBatchStore.Record(
                batchId: batch.batchId,
                generation: batch.generation,
                fileCount: batch.fileCount,
                fileProgress: batch.fileProgress,
                fileCompleted: batch.fileCompleted,
                completedCount: batch.completedCount,
                failed: batch.failed,
                cancelled: batch.cancelled,
                paused: batch.paused,
                childTaskIds: Array(batch.childTaskIds),
                savedDestinations: batch.savedDestinations
            )
        }
        persistQueue.sync {
            store.save(snapshot)
        }
    }

    internal func flushPersistenceForTests() {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        persistDebounceWorkItem?.cancel()
        persistDebounceWorkItem = nil
        persistBatchesImmediatelyLocked()
    }

    private func restorePersistedBatches() {
        batchesLock.lock()
        defer { batchesLock.unlock() }
        let records = store.load()
        var skippedOrphan = false
        for record in records.values {
            if record.childTaskIds.isEmpty && !record.failed && !record.cancelled && record.completedCount < record.fileCount {
                skippedOrphan = true
                continue
            }
            var childSet = Set(record.childTaskIds)
            batches[record.batchId] = ActiveBatch(
                batchId: record.batchId,
                generation: record.generation,
                fileCount: record.fileCount,
                fileProgress: record.fileProgress,
                fileCompleted: record.fileCompleted,
                completedCount: record.completedCount,
                failed: record.failed,
                cancelled: record.cancelled,
                paused: record.paused,
                childTaskIds: childSet,
                savedDestinations: record.savedDestinations
            )
            batchGenerations[record.batchId] = max(batchGenerations[record.batchId] ?? 0, record.generation)
            for taskId in childSet {
                registeredChildren[taskId] = record.batchId
            }
        }
        if skippedOrphan {
            persistBatchesImmediatelyLocked()
        }
    }
}
