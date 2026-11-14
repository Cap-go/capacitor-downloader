import BackgroundTasks
import Foundation

/// Optional iOS 26+ BGContinuedProcessingTask wrapper so progress stays visible while the device is locked.
final class DownloadContinuedProcessingCoordinator {
    static var permittedIdentifierPattern: String {
        DownloadSessionIdentifiers.continuedProcessingPermittedIdentifierPattern()
    }

    private let lock = NSLock()
    private var activeTasks: [String: Any] = [:]
    private var totalUnitCounts: [String: Int64] = [:]

    var onDownloadExpired: ((String) -> Void)?

    struct Request {
        let title: String
        let subtitle: String?
    }

    func beginIfPossible(
        downloadId: String,
        request: Request?,
        onReady: @escaping (_ useForegroundCapableSession: Bool) -> Void
    ) {
        guard let request else {
            onReady(false)
            return
        }

        if #available(iOS 26.0, *) {
            submitContinuedTask(downloadId: downloadId, request: request, onReady: onReady)
        } else {
            onReady(false)
        }
    }

    func reportProgress(downloadId: String, fraction: Double) {
        guard #available(iOS 26.0, *) else {
            return
        }
        lock.lock()
        let task = activeTasks[downloadId] as? BGContinuedProcessingTask
        let totalUnitCount = totalUnitCounts[downloadId] ?? 1
        lock.unlock()
        guard let task else {
            return
        }
        let clamped = min(max(fraction, 0), 1)
        task.progress.completedUnitCount = Int64(Double(totalUnitCount) * clamped)
    }

    func finish(downloadId: String, success: Bool) {
        lock.lock()
        let taskBox = activeTasks.removeValue(forKey: downloadId)
        totalUnitCounts.removeValue(forKey: downloadId)
        lock.unlock()
        if #available(iOS 26.0, *), let task = taskBox as? BGContinuedProcessingTask {
            task.setTaskCompleted(success: success)
        }
    }

    @available(iOS 26.0, *)
    private func submitContinuedTask(
        downloadId: String,
        request: Request,
        onReady: @escaping (_ useForegroundCapableSession: Bool) -> Void
    ) {
        let identifier = DownloadSessionIdentifiers.continuedProcessingTaskIdentifier()
        let launchLock = NSLock()
        var completed = false
        let completeOnce: (_ useForegroundCapableSession: Bool) -> Void = { useForeground in
            launchLock.lock()
            defer { launchLock.unlock() }
            if completed {
                return
            }
            completed = true
            onReady(useForeground)
        }
        var fallback: DispatchWorkItem!
        fallback = DispatchWorkItem {
            completeOnce(false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: fallback)

        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            fallback.cancel()
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                completeOnce(false)
                return
            }
            self?.activate(task: continued, downloadId: downloadId)
            completeOnce(true)
        }
        guard registered else {
            fallback.cancel()
            completeOnce(false)
            return
        }

        let processingRequest = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: request.title,
            subtitle: request.subtitle ?? ""
        )
        processingRequest.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(processingRequest)
        } catch {
            fallback.cancel()
            completeOnce(false)
        }
    }

    @available(iOS 26.0, *)
    private func activate(task: BGContinuedProcessingTask, downloadId: String) {
        lock.lock()
        activeTasks[downloadId] = task
        totalUnitCounts[downloadId] = 1_000
        task.progress.totalUnitCount = 1_000
        task.progress.completedUnitCount = 0
        let onExpired = onDownloadExpired
        task.expirationHandler = { [weak self] in
            onExpired?(downloadId)
            self?.finish(downloadId: downloadId, success: false)
        }
        lock.unlock()
    }
}