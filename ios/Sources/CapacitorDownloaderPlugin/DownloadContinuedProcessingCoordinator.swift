import BackgroundTasks
import Foundation

/// Optional iOS 26+ BGContinuedProcessingTask wrapper so progress stays visible while the device is locked.
final class DownloadContinuedProcessingCoordinator {
    static var permittedIdentifierPattern: String {
        DownloadSessionIdentifiers.continuedProcessingPermittedIdentifierPattern()
    }

  private static let registrationLock = NSLock()
  private static var continuedProcessingHandlerRegistered = false
  /// Routes launch callbacks to the plugin-owned coordinator instance.
  weak static var handlingInstance: DownloadContinuedProcessingCoordinator?

    private let lock = NSLock()
  private var pendingContinuedLaunch: ((_ useForegroundCapableSession: Bool) -> Void)?
  private var pendingContinuedDownloadId: String?
  private var continuedLaunchFallback: DispatchWorkItem?
    private var activeTasks: [String: Any] = [:]
    private var totalUnitCounts: [String: Int64] = [:]

    var onDownloadExpired: ((String) -> Void)?

    struct Request {
        let title: String
        let subtitle: String?
    }

  static func prepareContinuedProcessingRegistration() {
    DownloadContinuedProcessingCoordinator().registerContinuedProcessingTaskHandler()
  }

  func registerContinuedProcessingTaskHandler() {
    guard #available(iOS 26.0, *) else {
      return
    }
    Self.registrationLock.lock()
    defer { Self.registrationLock.unlock() }
    guard !Self.continuedProcessingHandlerRegistered else {
      return
    }
    let identifier = DownloadSessionIdentifiers.continuedProcessingDefaultTaskIdentifier()
    Self.continuedProcessingHandlerRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let coordinator = Self.handlingInstance else {
        task.setTaskCompleted(success: false)
        return
      }
      coordinator.handleContinuedProcessingTaskLaunch(task)
    }
  }

  @available(iOS 26.0, *)
  private func handleContinuedProcessingTaskLaunch(_ task: BGTask) {
    lock.lock()
    continuedLaunchFallback?.cancel()
    continuedLaunchFallback = nil
    let downloadId = pendingContinuedDownloadId
    lock.unlock()
    guard let continued = task as? BGContinuedProcessingTask else {
      task.setTaskCompleted(success: false)
      completePendingContinuedLaunch(useForeground: false)
      return
    }
    guard let downloadId else {
      task.setTaskCompleted(success: false)
      completePendingContinuedLaunch(useForeground: false)
      return
    }
    activate(task: continued, downloadId: downloadId)
    completePendingContinuedLaunch(useForeground: true)
  }

  private func completePendingContinuedLaunch(useForeground: Bool) {
    lock.lock()
    let onReady = pendingContinuedLaunch
    pendingContinuedLaunch = nil
    pendingContinuedDownloadId = nil
    lock.unlock()
    onReady?(useForeground)
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
        reportContinuedProgress(downloadId: downloadId, fraction: fraction)
    }

    func finish(downloadId: String, success: Bool) {
        lock.lock()
        let taskAny = activeTasks.removeValue(forKey: downloadId)
        totalUnitCounts.removeValue(forKey: downloadId)
        lock.unlock()
        if #available(iOS 26.0, *) {
            finishContinuedTask(taskAny, success: success)
        }
    }

    @available(iOS 26.0, *)
    private func reportContinuedProgress(downloadId: String, fraction: Double) {
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

    @available(iOS 26.0, *)
    private func finishContinuedTask(_ taskAny: Any?, success: Bool) {
        guard let task = taskAny as? BGContinuedProcessingTask else {
            return
        }
        task.setTaskCompleted(success: success)
    }

    @available(iOS 26.0, *)
    private func submitContinuedTask(
        downloadId: String,
        request: Request,
        onReady: @escaping (_ useForegroundCapableSession: Bool) -> Void
    ) {
        registerContinuedProcessingTaskHandler()
        guard Self.continuedProcessingHandlerRegistered else {
            onReady(false)
            return
        }
        lock.lock()
        let superseded = pendingContinuedLaunch
        pendingContinuedLaunch = onReady
        pendingContinuedDownloadId = downloadId
        continuedLaunchFallback?.cancel()
        lock.unlock()
        superseded?(false)

        var fallback = DispatchWorkItem { [weak self] in
            self?.completePendingContinuedLaunch(useForeground: false)
        }
        lock.lock()
        continuedLaunchFallback = fallback
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: fallback)

        let identifier = DownloadSessionIdentifiers.continuedProcessingDefaultTaskIdentifier()
        let processingRequest = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: request.title,
            subtitle: request.subtitle ?? ""
        )
        processingRequest.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(processingRequest)
        } catch {
            lock.lock()
            continuedLaunchFallback?.cancel()
            continuedLaunchFallback = nil
            lock.unlock()
            completePendingContinuedLaunch(useForeground: false)
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