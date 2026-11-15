import Foundation

/// Owns background URL sessions created at process launch so iOS can reconnect after relaunch.
final class DownloadBackgroundSessionManager: NSObject {
    static let shared = DownloadBackgroundSessionManager()

    /// When true, `register` always enqueues on `delegateQueue` (production path) even under XCTest.
    internal static var forceProductionRegistrationQueueForTests = false

    internal static var deferredHandlerFallbackIntervalForTests: TimeInterval = 20

    private weak var downloadDelegate: URLSessionDownloadDelegate?

    internal var hasRegisteredDownloadDelegateForTests: Bool {
        downloadDelegate != nil
    }

    internal var delegateQueueForTests: OperationQueue {
        delegateQueue
    }

    internal var pendingFinishCountForTests: Int {
        sessionLock.lock()
        let count = pendingFinishes.count
        sessionLock.unlock()
        return count
    }

    /// Resets delegate and pending queues (unit tests only).
    internal func resetSessionManagerStateForTests() {
        downloadDelegate = nil
        sessionLock.lock()
        pendingFinishes = []
        pendingCompletions = []
        sessionLock.unlock()
        flushHandlerLock.lock()
        for entry in pendingFlushCompletionHandlers {
            entry.fallbackWorkItem?.cancel()
        }
        pendingFlushCompletionHandlers = []
        flushHandlerLock.unlock()
    }

    private struct DeferredBackgroundHandler {
        let id: UUID
        let handler: () -> Void
        var fallbackWorkItem: DispatchWorkItem?
    }
    private struct PendingFinish {
        let session: URLSession
        let downloadTask: URLSessionDownloadTask
        let location: URL
        let removeStagedFile: Bool
    }

    private struct PendingCompletion {
        let session: URLSession
        let task: URLSessionTask
        let error: Error?
    }

    private var pendingFinishes: [PendingFinish] = []
    private var pendingCompletions: [PendingCompletion] = []
    private let sessionLock = NSLock()
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "CapacitorDownloader.URLSession"
        return queue
    }()

    private var completionHandlers: [String: () -> Void] = [:]
    private var pendingBackgroundRelaunchHandlers: Set<String> = []
    private let handlerLock = NSLock()
    /// AppDelegate completion handlers deferred until a plugin delegate is registered and staged events flush.
    private var pendingFlushCompletionHandlers: [DeferredBackgroundHandler] = []
    private let flushHandlerLock = NSLock()

    private(set) var mainSession: URLSession!
    private(set) var wifiOnlySession: URLSession!
    private(set) var foregroundCapableSession: URLSession!

    private override init() {
        super.init()
    }

    func warmUp() {
        if mainSession != nil {
            return
        }
        removeStaleStagedDownloadsIfNeeded()
        let mainConfig = URLSessionConfiguration.background(withIdentifier: DownloadSessionIdentifiers.main)
        mainConfig.sessionSendsLaunchEvents = true
        mainConfig.allowsCellularAccess = true
        mainConfig.isDiscretionary = false

        let wifiConfig = URLSessionConfiguration.background(withIdentifier: DownloadSessionIdentifiers.wifiOnly)
        wifiConfig.sessionSendsLaunchEvents = true
        wifiConfig.allowsCellularAccess = false
        wifiConfig.isDiscretionary = false

        mainSession = URLSession(configuration: mainConfig, delegate: self, delegateQueue: delegateQueue)
        wifiOnlySession = URLSession(configuration: wifiConfig, delegate: self, delegateQueue: delegateQueue)

        let foregroundConfig = URLSessionConfiguration.default
        foregroundConfig.allowsCellularAccess = true
        foregroundCapableSession = URLSession(configuration: foregroundConfig, delegate: self, delegateQueue: delegateQueue)
    }

    private func removeStaleStagedDownloadsIfNeeded() {
        sessionLock.lock()
        let hasPending = !pendingFinishes.isEmpty
        sessionLock.unlock()
        guard !hasPending else {
            return
        }
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorDownloaderPending", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func register(downloadDelegate: URLSessionDownloadDelegate) {
        let registerOnQueue = {
            self.downloadDelegate = downloadDelegate
            self.flushPendingEvents()
            self.runPendingBackgroundCompletionHandlers()
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           !Self.forceProductionRegistrationQueueForTests {
            registerOnQueue()
            return
        }
        delegateQueue.addOperation(registerOnQueue)
    }

    private func flushPendingEvents() {
        guard downloadDelegate != nil else {
            return
        }
        sessionLock.lock()
        let finishes = pendingFinishes
        let completions = pendingCompletions
        pendingFinishes = []
        pendingCompletions = []
        sessionLock.unlock()

        for finish in finishes {
            downloadDelegate?.urlSession(
                finish.session,
                downloadTask: finish.downloadTask,
                didFinishDownloadingTo: finish.location
            )
            if finish.removeStagedFile {
                try? FileManager.default.removeItem(at: finish.location)
            }
        }
        for completion in completions {
            downloadDelegate?.urlSession?(completion.session, task: completion.task, didCompleteWithError: completion.error)
        }
    }

    private func enqueueBackgroundCompletionHandlerUntilFlush(_ handler: @escaping () -> Void) {
        let id = UUID()
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem { [weak self] in
            self?.takeAndRunDeferredBackgroundHandler(id: id)
        }
        let deferred = DeferredBackgroundHandler(id: id, handler: handler, fallbackWorkItem: workItem)
        flushHandlerLock.lock()
        pendingFlushCompletionHandlers.append(deferred)
        flushHandlerLock.unlock()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.deferredHandlerFallbackIntervalForTests,
            execute: workItem
        )
    }

    private func takeAndRunDeferredBackgroundHandler(id: UUID) -> Bool {
        flushHandlerLock.lock()
        guard let index = pendingFlushCompletionHandlers.firstIndex(where: { $0.id == id }) else {
            flushHandlerLock.unlock()
            return false
        }
        let entry = pendingFlushCompletionHandlers.remove(at: index)
        flushHandlerLock.unlock()
        entry.fallbackWorkItem?.cancel()
        DispatchQueue.main.async(execute: entry.handler)
        return true
    }

    private func runPendingBackgroundCompletionHandlers() {
        flushHandlerLock.lock()
        let handlers = pendingFlushCompletionHandlers
        pendingFlushCompletionHandlers = []
        flushHandlerLock.unlock()
        for entry in handlers {
            entry.fallbackWorkItem?.cancel()
            DispatchQueue.main.async(execute: entry.handler)
        }
    }

    private func stageDownloadIfNeeded(
        session: URLSession,
        downloadTask: URLSessionDownloadTask,
        location: URL
    ) -> PendingFinish? {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapacitorDownloaderPending", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let stagedURL = stagingDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: stagedURL)
            return PendingFinish(
                session: session,
                downloadTask: downloadTask,
                location: stagedURL,
                removeStagedFile: true
            )
        } catch {
            return nil
        }
    }

    func session(allowsCellularAccess: Bool, preferForegroundCapable: Bool) -> URLSession {
        if preferForegroundCapable, allowsCellularAccess, foregroundCapableSession != nil {
            return foregroundCapableSession
        }
        return allowsCellularAccess ? mainSession : wifiOnlySession
    }

    func storeBackgroundEventsCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
        var shouldRun = false
        handlerLock.lock()
        if pendingBackgroundRelaunchHandlers.remove(identifier) != nil {
            shouldRun = true
        }
        if !shouldRun {
            completionHandlers[identifier] = handler
        }
        handlerLock.unlock()
        if shouldRun {
            runBackgroundCompletionHandlerAfterFlushingPending(handler)
        }
    }

    private func hasStagedSessionEvents() -> Bool {
        sessionLock.lock()
        let hasPending = !pendingFinishes.isEmpty || !pendingCompletions.isEmpty
        sessionLock.unlock()
        return hasPending
    }

    private func runBackgroundCompletionHandlerAfterFlushingPending(_ handler: @escaping () -> Void) {
        delegateQueue.addOperation {
            self.flushPendingEvents()
            if self.downloadDelegate == nil, self.hasStagedSessionEvents() {
                self.enqueueBackgroundCompletionHandlerUntilFlush(handler)
                return
            }
            DispatchQueue.main.async(execute: handler)
        }
    }

    func rehydrateTasks(completion: @escaping ([URLSessionTask]) -> Void) {
        guard mainSession != nil, wifiOnlySession != nil else {
            completion([])
            return
        }
        let group = DispatchGroup()
        var collected: [URLSessionTask] = []
        let collectLock = NSLock()
        let collect: ([URLSessionTask]) -> Void = { tasks in
            collectLock.lock()
            collected.append(contentsOf: tasks)
            collectLock.unlock()
        }
        group.enter()
        mainSession.getAllTasks { tasks in
            collect(tasks)
            group.leave()
        }
        group.enter()
        wifiOnlySession.getAllTasks { tasks in
            collect(tasks)
            group.leave()
        }
        group.notify(queue: .global(qos: .utility)) {
            completion(collected)
        }
    }
}

extension DownloadBackgroundSessionManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let downloadDelegate {
            downloadDelegate.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
            return
        }
        guard let staged = stageDownloadIfNeeded(session: session, downloadTask: downloadTask, location: location) else {
            let copyError = NSError(
                domain: "CapacitorDownloader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to stage background download"]
            )
            sessionLock.lock()
            pendingCompletions.append(
                PendingCompletion(session: session, task: downloadTask, error: copyError)
            )
            sessionLock.unlock()
            return
        }
        sessionLock.lock()
        pendingFinishes.append(staged)
        sessionLock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let downloadDelegate {
            downloadDelegate.urlSession?(session, task: task, didCompleteWithError: error)
            return
        }
        sessionLock.lock()
        pendingCompletions.append(PendingCompletion(session: session, task: task, error: error))
        sessionLock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        downloadDelegate?.urlSession?(
            session,
            downloadTask: downloadTask,
            didWriteData: bytesWritten,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite
        )
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else {
            return
        }
        var handler: (() -> Void)?
        handlerLock.lock()
        handler = completionHandlers.removeValue(forKey: identifier)
        if handler == nil {
            pendingBackgroundRelaunchHandlers.insert(identifier)
        }
        handlerLock.unlock()
        if let handler {
            runBackgroundCompletionHandlerAfterFlushingPending(handler)
        }
    }
}