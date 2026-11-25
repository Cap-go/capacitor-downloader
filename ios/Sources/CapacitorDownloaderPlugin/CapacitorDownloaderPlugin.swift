import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */

@objc(CapacitorDownloaderPlugin)
public class CapacitorDownloaderPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.11.0"
    public let identifier = "CapacitorDownloaderPlugin"
    public let jsName = "CapacitorDownloader"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "download", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getFileInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var downloadGenerations: [String: UInt64] = [:]
    private var taskGenerations: [String: UInt64] = [:]
    private let tasksLock = NSLock()
    private let batchCoordinator: DownloadBatchCoordinator
    private let continuedProcessing = DownloadContinuedProcessingCoordinator()
    private var foregroundSessionDownloadIds = Set<String>()
    private var pendingDownloadStarts = Set<String>()
    private var downloadRetryBudgets: [String: DownloadConnectionRetry.Budget] = [:]
    private var pendingRetryWorkItems: [String: DispatchWorkItem] = [:]
    private var foregroundRetryPausedDownloadIds = Set<String>()
    private let foregroundSessionLock = NSLock()
    private let continuedProcessingGenerationsLock = NSLock()
    private var continuedProcessingGenerations: [String: UInt64] = [:]
    internal private(set) var restoredBackgroundSessionIdentifiers: [String] = []
    internal private(set) var didRestoreGenerationsBeforeDelegateRegistration = false

    public override init() {
        batchCoordinator = DownloadBatchCoordinator()
        super.init()
    }

    internal init(batchStore: DownloadBatchStore) {
        batchCoordinator = DownloadBatchCoordinator(store: batchStore)
        super.init()
    }

    private func registerDownloadDelegateIfGenerationsRestored() {
        tasksLock.lock()
        let generationsRestored = !downloadGenerations.isEmpty
        tasksLock.unlock()
        DownloadBackgroundSessionManager.shared.register(downloadDelegate: self)
        didRestoreGenerationsBeforeDelegateRegistration = generationsRestored
    }

    private func downloadSession(allowsCellularAccess: Bool, preferForegroundCapable: Bool) -> URLSession {
        DownloadBackgroundSessionManager.shared.session(
            allowsCellularAccess: allowsCellularAccess,
            preferForegroundCapable: preferForegroundCapable
        )
    }

    private func sessionAssumedForStoredTask(downloadId: String) -> URLSession {
        foregroundSessionLock.lock()
        let useForeground = foregroundSessionDownloadIds.contains(downloadId)
        foregroundSessionLock.unlock()
        return downloadSession(allowsCellularAccess: true, preferForegroundCapable: useForeground)
    }

    public override func load() {
        DownloadBackgroundSessionManager.shared.warmUp()
        tasksLock.lock()
        downloadGenerations = DownloadIdGenerationStore.shared.allGenerations()
        taskGenerations = DownloadTaskGenerationStore.shared.allGenerations()
        downloadRetryBudgets = DownloadRetryBudgetStore.shared.allBudgets()
        tasksLock.unlock()
        restoredBackgroundSessionIdentifiers = [
            DownloadSessionIdentifiers.main,
            DownloadSessionIdentifiers.wifiOnly
        ]
        DownloadContinuedProcessingCoordinator.handlingInstance = continuedProcessing
        continuedProcessing.registerContinuedProcessingTaskHandler()
        continuedProcessing.onDownloadExpired = { [weak self] downloadId in
            self?.cancelDownloadFromContinuedProcessingExpiry(downloadId)
        }
        let finishLoad: ([URLSessionTask]) -> Void = { [weak self] tasks in
            guard let self else {
                return
            }
            self.rehydrateBackgroundDownloadTasks(tasks)
            let activeIds = self.singleDownloadIds()
                .union(Set(tasks.compactMap { ($0 as? URLSessionDownloadTask)?.taskDescription }))
            DownloadLengthHeaderStore.shared.sweepStaleEntries(keeping: activeIds)
            self.registerDownloadDelegateIfGenerationsRestored()
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let semaphore = DispatchSemaphore(value: 0)
            DownloadBackgroundSessionManager.shared.rehydrateTasks { tasks in
                finishLoad(tasks)
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 5)
            if !didRestoreGenerationsBeforeDelegateRegistration {
                registerDownloadDelegateIfGenerationsRestored()
            }
        } else {
            DownloadBackgroundSessionManager.shared.rehydrateTasks(completion: finishLoad)
        }
    }

    private func cancelDownloadFromContinuedProcessingExpiry(_ downloadId: String) {
        if batchCoordinator.isBatch(batchId: downloadId),
           let generation = continuedProcessingGeneration(for: downloadId) ?? batchCoordinator.generation(for: downloadId) {
            failBatch(batchId: downloadId, generation: generation, fileIndex: nil, error: "Continued processing task expired")
            return
        }
        tasksLock.lock()
        let hasPendingForegroundRetry = pendingRetryWorkItems[downloadId] != nil
        tasksLock.unlock()
        guard let task = getTask(for: downloadId) else {
            if hasPendingForegroundRetry {
                clearRetryBudget(for: downloadId)
                foregroundSessionLock.lock()
                foregroundSessionDownloadIds.remove(downloadId)
                foregroundSessionLock.unlock()
                DownloadDestinationStore.shared.removeDestination(for: downloadId)
                if let generation = generation(for: downloadId) {
                    DownloadCompletedNotificationStore.shared.removeText(for: downloadId, generation: generation)
                    presentFailedDownloadNotificationIfStored(downloadId: downloadId, generation: generation)
                }
                notifyListeners("downloadFailed", data: ["id": downloadId, "error": "Continued processing task expired"])
            }
            return
        }
        task.cancel()
        removeTask(for: downloadId, completing: task, in: sessionAssumedForStoredTask(downloadId: downloadId))
        DownloadDestinationStore.shared.removeDestination(for: downloadId)
        if let generation = generation(for: downloadId) {
            DownloadCompletedNotificationStore.shared.removeText(for: downloadId, generation: generation)
            presentFailedDownloadNotificationIfStored(downloadId: downloadId, generation: generation)
        }
        clearRetryBudget(for: downloadId)
        foregroundSessionLock.lock()
        foregroundSessionDownloadIds.remove(downloadId)
        foregroundSessionLock.unlock()
        notifyListeners("downloadFailed", data: ["id": downloadId, "error": "Continued processing task expired"])
    }

    internal func rehydrateBackgroundDownloadTasks(_ tasks: [URLSessionTask]) {
        for task in tasks {
            guard let downloadTask = task as? URLSessionDownloadTask,
                  let id = downloadTask.taskDescription,
                  !id.isEmpty else {
                continue
            }
            setTask(downloadTask, for: id)
        }
    }

    internal func hasRegisteredTask(id: String) -> Bool {
        getTask(for: id) != nil
    }

    private func setTask(_ task: URLSessionDownloadTask, for id: String) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        tasks[id] = task
    }

    private func getTask(for id: String) -> URLSessionDownloadTask? {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return tasks[id]
    }

    private func removeTask(for id: String, completing task: URLSessionDownloadTask, in session: URLSession) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        if tasks[id] === task {
            tasks.removeValue(forKey: id)
        }
        taskGenerations.removeValue(forKey: DownloadTaskGenerationKey.storageKey(session: session, task: task))
        DownloadLengthHeaderStore.shared.clear(for: id)
    }

    private func normalizedLengthHeader(from call: CAPPluginCall) -> String? {
        guard let raw = call.getString("lengthHeader")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private func registerLengthHeaderOption(_ headerName: String?, for taskId: String) {
        DownloadLengthHeaderStore.shared.setHeaderName(headerName, for: taskId)
    }

    private func captureExpectedTotalFromResponseIfNeeded(
        downloadId: String,
        downloadTask: URLSessionDownloadTask
    ) {
        guard DownloadLengthHeaderStore.shared.expectedTotal(for: downloadId) == nil,
              let headerName = DownloadLengthHeaderStore.shared.headerName(for: downloadId),
              let httpResponse = downloadTask.response as? HTTPURLResponse,
              let expected = DownloadExpectedLength.parse(from: httpResponse, headerName: headerName) else {
            return
        }
        DownloadLengthHeaderStore.shared.setExpectedTotal(expected, for: downloadId)
    }

    private func nextGeneration(for id: String) -> UInt64 {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        let generation = (downloadGenerations[id] ?? 0) &+ 1
        downloadGenerations[id] = generation
        DownloadIdGenerationStore.shared.setGeneration(generation, forDownloadId: id)
        return generation
    }

    private func generation(for id: String) -> UInt64? {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return downloadGenerations[id]
    }

    private func setTaskGeneration(_ generation: UInt64, for task: URLSessionDownloadTask, in session: URLSession) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        let key = DownloadTaskGenerationKey.storageKey(session: session, task: task)
        taskGenerations[key] = generation
        DownloadTaskGenerationStore.shared.setGeneration(generation, forTask: task, in: session)
    }

    private func generation(for task: URLSessionTask, in session: URLSession) -> UInt64? {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return taskGenerations[DownloadTaskGenerationKey.storageKey(session: session, task: task)]
    }

    private func clearTaskGeneration(for task: URLSessionTask, in session: URLSession) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        let key = DownloadTaskGenerationKey.storageKey(session: session, task: task)
        taskGenerations.removeValue(forKey: key)
        DownloadTaskGenerationStore.shared.removeGeneration(forTask: task, in: session)
    }

    private func setRetryBudget(for downloadId: String, retries: Int) {
        tasksLock.lock()
        cancelPendingRetryWorkLocked(for: downloadId)
        if retries <= 0 {
            downloadRetryBudgets.removeValue(forKey: downloadId)
            tasksLock.unlock()
            DownloadRetryBudgetStore.shared.removeBudget(for: downloadId)
            return
        }
        let budget = DownloadConnectionRetry.Budget(remainingRetries: retries, connectionFailureCount: 0)
        downloadRetryBudgets[downloadId] = budget
        tasksLock.unlock()
        DownloadRetryBudgetStore.shared.setBudget(budget, for: downloadId)
    }

    private func clearRetryBudget(for downloadId: String) {
        tasksLock.lock()
        cancelPendingRetryWorkLocked(for: downloadId)
        downloadRetryBudgets.removeValue(forKey: downloadId)
        tasksLock.unlock()
        DownloadRetryBudgetStore.shared.removeBudget(for: downloadId)
    }

    private func cancelPendingRetryWorkLocked(for downloadId: String) {
        pendingRetryWorkItems.removeValue(forKey: downloadId)?.cancel()
        foregroundRetryPausedDownloadIds.remove(downloadId)
    }

    private func sessionUsesEarliestBeginDateForRetries(_ session: URLSession) -> Bool {
        guard let identifier = session.configuration.identifier else {
            return false
        }
        return DownloadSessionIdentifiers.isPluginSession(identifier)
    }

    private func emitRetryProgressReset(for downloadId: String) {
        if let batchParts = batchCoordinator.activeChildParts(for: downloadId),
           let batchProgress = batchCoordinator.updateFileProgress(
               batchId: batchParts.batchId,
               generation: batchParts.generation,
               fileIndex: batchParts.fileIndex,
               progress: 0
           ) {
            notifyListeners(
                "downloadProgress",
                data: [
                    "id": batchParts.batchId,
                    "progress": batchProgress.overall,
                    "fileIndex": batchParts.fileIndex,
                    "fileProgress": batchProgress.file,
                    "bytesWritten": 0,
                    "bytesTotal": 0
                ]
            )
        } else if batchCoordinator.activeChildParts(for: downloadId) == nil {
            notifyListeners("downloadProgress", data: ["id": downloadId, "progress": 0])
        }
    }

    private func registerAndResumeRetryTaskIfCurrent(
        downloadId: String,
        retryTask: URLSessionDownloadTask,
        session: URLSession,
        generation: UInt64?
    ) -> Bool {
        tasksLock.lock()
        guard downloadRetryBudgets[downloadId] != nil, tasks[downloadId] == nil else {
            tasksLock.unlock()
            retryTask.cancel()
            return false
        }
        tasks[downloadId] = retryTask
        if let generation {
            let key = DownloadTaskGenerationKey.storageKey(session: session, task: retryTask)
            taskGenerations[key] = generation
            DownloadTaskGenerationStore.shared.setGeneration(generation, forTask: retryTask, in: session)
        }
        let pausedChild = batchCoordinator.isActiveChildPaused(taskId: downloadId)
        let standalonePaused = foregroundRetryPausedDownloadIds.contains(downloadId)
        tasksLock.unlock()
        if !pausedChild && !standalonePaused {
            retryTask.resume()
        }
        emitRetryProgressReset(for: downloadId)
        return true
    }

    private func resumePendingForegroundRetryIfCurrent(
        downloadId: String,
        retryTask: URLSessionDownloadTask
    ) {
        tasksLock.lock()
        guard downloadRetryBudgets[downloadId] != nil, tasks[downloadId] === retryTask else {
            pendingRetryWorkItems.removeValue(forKey: downloadId)
            tasksLock.unlock()
            retryTask.cancel()
            return
        }
        pendingRetryWorkItems.removeValue(forKey: downloadId)
        let pausedChild = batchCoordinator.isActiveChildPaused(taskId: downloadId)
        let standalonePaused = foregroundRetryPausedDownloadIds.contains(downloadId)
        tasksLock.unlock()
        if !pausedChild && !standalonePaused {
            retryTask.resume()
        }
    }

    private func isPendingForegroundRetry(_ downloadId: String) -> Bool {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return pendingRetryWorkItems[downloadId] != nil
    }

    private func scheduleConnectionRetryIfPossible(
        downloadId: String,
        failedTask: URLSessionDownloadTask,
        session: URLSession,
        error: Error,
        generation: UInt64?
    ) -> Bool {
        guard DownloadConnectionRetry.isRetryableConnectionError(error) else {
            return false
        }
        tasksLock.lock()
        guard var budget = downloadRetryBudgets[downloadId], budget.remainingRetries > 0,
              let request = failedTask.originalRequest else {
            tasksLock.unlock()
            return false
        }
        budget.remainingRetries -= 1
        budget.connectionFailureCount += 1
        let failureCount = budget.connectionFailureCount
        downloadRetryBudgets[downloadId] = budget
        tasksLock.unlock()
        DownloadRetryBudgetStore.shared.setBudget(budget, for: downloadId)

        removeTask(for: downloadId, completing: failedTask, in: session)
        clearTaskGeneration(for: failedTask, in: session)

        let retryTask = session.downloadTask(with: request)
        retryTask.taskDescription = downloadId
        let delay = DownloadConnectionRetry.delaySeconds(afterConnectionFailureCount: failureCount)

        if sessionUsesEarliestBeginDateForRetries(session) {
            if #available(iOS 11.0, *) {
                retryTask.earliestBeginDate = Date().addingTimeInterval(delay)
            }
            return registerAndResumeRetryTaskIfCurrent(
                downloadId: downloadId,
                retryTask: retryTask,
                session: session,
                generation: generation
            )
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.resumePendingForegroundRetryIfCurrent(downloadId: downloadId, retryTask: retryTask)
        }
        tasksLock.lock()
        guard downloadRetryBudgets[downloadId] != nil else {
            tasksLock.unlock()
            retryTask.cancel()
            return false
        }
        tasks[downloadId] = retryTask
        if let generation {
            let key = DownloadTaskGenerationKey.storageKey(session: session, task: retryTask)
            taskGenerations[key] = generation
            DownloadTaskGenerationStore.shared.setGeneration(generation, forTask: retryTask, in: session)
        }
        cancelPendingRetryWorkLocked(for: downloadId)
        pendingRetryWorkItems[downloadId] = workItem
        tasksLock.unlock()
        emitRetryProgressReset(for: downloadId)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    private func singleDownloadIds() -> Set<String> {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return Set(tasks.keys.filter { batchCoordinator.childParts(for: $0) == nil })
    }

    private func pluginString(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSString {
            return value as String
        }
        return nil
    }

    private func parsedBatchFiles(from filesValue: JSArray) -> [[String: Any]]? {
        var files: [[String: Any]] = []
        files.reserveCapacity(filesValue.count)
        for entry in filesValue {
            if let object = entry as? [String: Any] {
                files.append(object)
                continue
            }
            if let object = entry as? JSObject {
                var normalized: [String: Any] = [:]
                for (key, value) in object {
                    normalized[key] = value
                }
                files.append(normalized)
                continue
            }
            if let object = entry as? NSDictionary {
                var normalized: [String: Any] = [:]
                for (key, value) in object {
                    guard let stringKey = key as? String else {
                        return nil
                    }
                    normalized[stringKey] = value
                }
                files.append(normalized)
                continue
            }
            return nil
        }
        return files
    }

    private func normalizedTaskId(from call: CAPPluginCall) -> String? {
        guard let rawId = call.getString("id") else {
            return nil
        }
        let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private func idForTask(_ task: URLSessionDownloadTask) -> String? {
        if let id = task.taskDescription, !id.isEmpty {
            return id
        }
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return tasks.first(where: { $0.value == task })?.key
    }

    private func documentsDirectoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func destinationURL(for id: String, storedDestination: String?) -> URL? {
        guard let documentsDirectory = documentsDirectoryURL() else {
            return nil
        }

        return DownloadDestinationResolver.resolveDestinationURL(
            destination: storedDestination,
            id: id,
            documentsDirectory: documentsDirectory
        )
    }

    private func prepareDestinationDirectory(for destinationURL: URL) throws {
        let directoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func deleteDownloadedFiles(destinations: [String]) {
        for destination in destinations {
            let destinationURL = URL(fileURLWithPath: destination)
            guard
                  FileManager.default.fileExists(atPath: destinationURL.path) else {
                continue
            }
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    @objc func download(_ call: CAPPluginCall) {
        guard let rawId = call.getString("id") else {
            call.reject("Invalid parameters")
            return
        }
        let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            call.reject("Invalid parameters")
            return
        }

        if let filesValue = call.getArray("files") {
            if let urlString = call.getString("url"), !urlString.isEmpty {
                call.reject("Provide either url and destination or files, not both")
                return
            }
            guard let files = parsedBatchFiles(from: filesValue) else {
                call.reject("Invalid file entry")
                return
            }
            if files.isEmpty {
                call.reject("Invalid file entry")
                return
            }
            downloadBatch(call, batchId: id, files: files)
            return
        }

        guard let urlString = call.getString("url"),
              let url = URL(string: urlString) else {
            call.reject("Invalid parameters")
            return
        }

        let destination = call.getString("destination") ?? ""
        if destination.isEmpty {
            call.reject("Invalid parameters")
            return
        }

        if batchCoordinator.isBatch(batchId: id) {
            call.reject("Download already exists")
            return
        }

        if getTask(for: id) != nil {
            call.reject("Download already exists")
            return
        }

        tasksLock.lock()
        let reserved = pendingDownloadStarts.insert(id).inserted
        tasksLock.unlock()
        guard reserved else {
            call.reject("Download already exists")
            return
        }

        let generation = nextGeneration(for: id)
        DownloadDestinationStore.shared.setDestination(destination, for: id)
        DownloadCompletedNotificationStore.shared.setText(
            call.getString("downloadCompletedNotificationText"),
            for: id,
            generation: generation
        )
        DownloadFailedNotificationStore.shared.setText(
            call.getString("downloadFailedNotificationText"),
            for: id,
            generation: generation
        )

        var request = URLRequest(url: url)
        if let headers = call.getObject("headers") as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        registerLengthHeaderOption(normalizedLengthHeader(from: call), for: id)

        let wifiOnly = call.getString("network") == "wifi-only"
        let retries = DownloadConnectionRetry.normalizeRetries(call.getInt("retries"))
        let continuedRequest = parseContinuedProcessingRequest(call)

        continuedProcessing.beginIfPossible(downloadId: id, request: continuedRequest) { [weak self] useForeground in
            guard let self else {
                call.reject("Download plugin was deallocated before the download could start")
                return
            }
            self.tasksLock.lock()
            self.pendingDownloadStarts.remove(id)
            self.tasksLock.unlock()
            self.foregroundSessionLock.lock()
            if useForeground {
                self.foregroundSessionDownloadIds.insert(id)
            }
            self.foregroundSessionLock.unlock()

            let activeSession = self.downloadSession(allowsCellularAccess: !wifiOnly, preferForegroundCapable: useForeground)
            let task = activeSession.downloadTask(with: request)
            task.taskDescription = id
            self.setRetryBudget(for: id, retries: retries)
            self.setTask(task, for: id)
            self.setTaskGeneration(generation, for: task, in: activeSession)
            task.resume()

            call.resolve([
                "id": id,
                "state": "RUNNING",
                "progress": 0
            ])
        }
    }

    /// The continued processing task to run the download in: `title` and `description` with `iosContinuedProcessing`,
    /// or the deprecated `iosContinuedProcessingTitle` and `iosContinuedProcessingSubtitle` of 8.8.0.
    private func parseContinuedProcessingRequest(_ call: CAPPluginCall) -> DownloadContinuedProcessingCoordinator.Request? {
        let useShared = call.getBool("iosContinuedProcessing") == true
        let title = Self.nonEmpty(useShared ? call.getString("title") : call.getString("iosContinuedProcessingTitle"))
        guard let title else {
            return nil
        }
        let subtitle = Self.nonEmpty(useShared ? call.getString("description") : call.getString("iosContinuedProcessingSubtitle"))
        return DownloadContinuedProcessingCoordinator.Request(title: title, subtitle: subtitle)
    }

    private func parseBatchContinuedProcessingRequest(_ call: CAPPluginCall) -> DownloadContinuedProcessingCoordinator.Request? {
        guard call.getBool("iosContinuedProcessing") == true else {
            return nil
        }
        guard let title = Self.nonEmpty(call.getString("title")) else {
            return nil
        }
        let subtitle = Self.nonEmpty(call.getString("description"))
        return DownloadContinuedProcessingCoordinator.Request(title: title, subtitle: subtitle)
    }

    private func setContinuedProcessingGeneration(downloadId: String, generation: UInt64) {
        continuedProcessingGenerationsLock.lock()
        continuedProcessingGenerations[downloadId] = generation
        continuedProcessingGenerationsLock.unlock()
    }

    private func continuedProcessingGeneration(for downloadId: String) -> UInt64? {
        continuedProcessingGenerationsLock.lock()
        defer { continuedProcessingGenerationsLock.unlock() }
        return continuedProcessingGenerations[downloadId]
    }

    private func clearContinuedProcessingGeneration(downloadId: String) {
        continuedProcessingGenerationsLock.lock()
        continuedProcessingGenerations.removeValue(forKey: downloadId)
        continuedProcessingGenerationsLock.unlock()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func markContinuedProcessingFinished(downloadId: String, success: Bool) {
        continuedProcessing.finish(downloadId: downloadId, success: success)
        clearContinuedProcessingGeneration(downloadId: downloadId)
        foregroundSessionLock.lock()
        foregroundSessionDownloadIds.remove(downloadId)
        foregroundSessionLock.unlock()
    }

    private func downloadBatch(_ call: CAPPluginCall, batchId: String, files: [[String: Any]]) {
        var parsed: [(url: URL, destination: String)] = []
        let headers = call.getObject("headers") as? [String: String] ?? [:]
        let lengthHeader = normalizedLengthHeader(from: call)
        let wifiOnly = call.getString("network") == "wifi-only"
        let retries = DownloadConnectionRetry.normalizeRetries(call.getInt("retries"))

        for fileObject in files {
            guard let urlString = pluginString(fileObject["url"]),
                  let url = URL(string: urlString),
                  let destination = pluginString(fileObject["destination"]),
                  !destination.isEmpty else {
                call.reject("Each file entry requires url and destination")
                return
            }
            let probeId = "\(batchId)#\(parsed.count)"
            guard destinationURL(for: probeId, storedDestination: destination) != nil else {
                call.reject("Invalid destination for batch file")
                return
            }
            parsed.append((url, destination))
        }

        guard let generation = batchCoordinator.startBatch(
            batchId: batchId,
            fileCount: parsed.count,
            singleDownloadIds: singleDownloadIds()
        ) else {
            call.reject("Download already exists. Call stop() with the same id first.")
            return
        }

        if call.getBool("iosContinuedProcessing") == true {
            guard parseBatchContinuedProcessingRequest(call) != nil else {
                _ = batchCoordinator.removeBatch(batchId: batchId, generation: generation, unregisterChildren: true)
                call.reject("title is required when iosContinuedProcessing is true")
                return
            }
        }

        DownloadCompletedNotificationStore.shared.setText(
            call.getString("downloadCompletedNotificationText"),
            for: batchId,
            generation: generation
        )
        DownloadFailedNotificationStore.shared.setText(
            call.getString("downloadFailedNotificationText"),
            for: batchId,
            generation: generation
        )

        let continuedRequest = parseBatchContinuedProcessingRequest(call)
        continuedProcessing.beginIfPossible(downloadId: batchId, request: continuedRequest) { [weak self] useForeground in
            guard let self else {
                call.reject("Download plugin was deallocated before the batch could start")
                return
            }
            if continuedRequest != nil, useForeground {
                self.setContinuedProcessingGeneration(downloadId: batchId, generation: generation)
            }
            guard self.batchCoordinator.batchStartupSnapshot(batchId: batchId, generation: generation).allowed else {
                self.markContinuedProcessingFinished(downloadId: batchId, success: false)
                call.reject("Download was cancelled")
                return
            }
            let batchSession = self.downloadSession(allowsCellularAccess: !wifiOnly, preferForegroundCapable: useForeground)
            var stagedTasks: [(taskId: String, task: URLSessionDownloadTask)] = []
            var childRegistrations: [(taskId: String, fileIndex: Int)] = []

            for (index, entry) in parsed.enumerated() {
                let taskId = self.batchCoordinator.fileTaskId(batchId: batchId, generation: generation, fileIndex: index)
                DownloadDestinationStore.shared.setDestination(entry.destination, for: taskId)
                registerLengthHeaderOption(lengthHeader, for: taskId)

                var request = URLRequest(url: entry.url)
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                let task = batchSession.downloadTask(with: request)
                task.taskDescription = taskId
                stagedTasks.append((taskId, task))
                childRegistrations.append((taskId, index))
            }

            if useForeground {
                self.foregroundSessionLock.lock()
                stagedTasks.forEach { self.foregroundSessionDownloadIds.insert($0.taskId) }
                self.foregroundSessionLock.unlock()
            }

            for staged in stagedTasks {
                self.setRetryBudget(for: staged.taskId, retries: retries)
                self.setTask(staged.task, for: staged.taskId)
            }
            let startup = self.batchCoordinator.registerStartupChildren(
                batchId: batchId,
                generation: generation,
                children: childRegistrations
            )
            guard startup.allowed else {
                self.discardStagedBatchTasks(stagedTasks, session: batchSession)
                self.markBatchContinuedProcessingFinished(batchId: batchId, generation: generation, success: false)
                call.reject("Download was cancelled")
                return
            }
            if !self.skipBatchTaskResumeForTests, !startup.paused {
                stagedTasks.forEach { $0.task.resume() }
            }
            switch self.batchCoordinator.batchStartupResumeOutcome(batchId: batchId, generation: generation) {
            case .abort:
                self.discardStagedBatchTasks(stagedTasks, session: batchSession)
                self.markBatchContinuedProcessingFinished(batchId: batchId, generation: generation, success: false)
                call.reject("Download was cancelled")
                return
            case .proceed(let paused):
                call.resolve([
                    "id": batchId,
                    "state": paused ? "PAUSED" : "RUNNING",
                    "progress": 0
                ])
            }
        }
    }

    /// Cancels the transfers of a batch that was stopped while they were being created. They are published before the
    /// batch is checked again, so a `stop` that comes after that check cancels them itself through `cancelBatchTasks`.
    private func discardStagedBatchTasks(_ stagedTasks: [(taskId: String, task: URLSessionDownloadTask)], session: URLSession) {
        for staged in stagedTasks {
            staged.task.cancel()
            removeTask(for: staged.taskId, completing: staged.task, in: session)
            DownloadDestinationStore.shared.removeDestination(for: staged.taskId)
            clearRetryBudget(for: staged.taskId)
            batchCoordinator.unregisterChildTask(staged.taskId)
        }
    }

    /// Ends the continued processing task of a batch and forgets which of its transfers ran in the in-process session,
    /// by their id prefix since a batch that succeeded has already unregistered them.
    private func markBatchContinuedProcessingFinished(batchId: String, generation: UInt64, success: Bool) {
        markContinuedProcessingFinished(downloadId: batchId, success: success)
        let childIdPrefix = batchCoordinator.fileTaskId(batchId: batchId, generation: generation, fileIndex: 0).dropLast()
        foregroundSessionLock.lock()
        foregroundSessionDownloadIds = foregroundSessionDownloadIds.filter { !$0.hasPrefix(childIdPrefix) }
        foregroundSessionLock.unlock()
    }

    private func cancelBatchTasks(batchId: String) {
        cancelBatchTasks(taskIds: batchCoordinator.childTaskIds(batchId: batchId))
    }

    private func cancelBatchTasks(taskIds: [String]) {
        for taskId in taskIds {
            if let task = getTask(for: taskId) {
                task.cancel()
                removeTask(for: taskId, completing: task, in: sessionAssumedForStoredTask(downloadId: taskId))
            }
            DownloadDestinationStore.shared.removeDestination(for: taskId)
            clearRetryBudget(for: taskId)
            batchCoordinator.unregisterChildTask(taskId)
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        guard let id = normalizedTaskId(from: call) else {
            call.reject("Task not found")
            return
        }

        if batchCoordinator.isBatch(batchId: id) {
            pauseBatch(batchId: id)
            call.resolve()
            return
        }

        if isPendingForegroundRetry(id) {
            tasksLock.lock()
            foregroundRetryPausedDownloadIds.insert(id)
            tasksLock.unlock()
            call.resolve()
            return
        }

        guard let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        task.suspend()
        call.resolve()
    }

    @objc func resume(_ call: CAPPluginCall) {
        guard let id = normalizedTaskId(from: call) else {
            call.reject("Task not found")
            return
        }

        if batchCoordinator.isBatch(batchId: id) {
            resumeBatch(batchId: id)
            call.resolve()
            return
        }

        if isPendingForegroundRetry(id) {
            tasksLock.lock()
            foregroundRetryPausedDownloadIds.remove(id)
            tasksLock.unlock()
            call.resolve()
            return
        }

        guard let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        task.resume()
        call.resolve()
    }

    private func pauseBatch(batchId: String) {
        tasksLock.lock()
        let childTaskIds = batchCoordinator.setPausedReturningChildTaskIds(batchId: batchId, paused: true)
        for taskId in childTaskIds {
            tasks[taskId]?.suspend()
        }
        tasksLock.unlock()
    }

    private func resumeBatch(batchId: String) {
        tasksLock.lock()
        let childTaskIds = batchCoordinator.setPausedReturningChildTaskIds(batchId: batchId, paused: false)
        tasksLock.unlock()
        for taskId in childTaskIds {
            if isPendingForegroundRetry(taskId) {
                continue
            }
            getTask(for: taskId)?.resume()
        }
    }

    internal func trackedBatchFileCountForTests(batchId: String) -> Int? {
        batchCoordinator.fileCount(batchId: batchId)
    }

    internal var batchCoordinatorForTests: DownloadBatchCoordinator {
        batchCoordinator
    }

    internal var skipBatchTaskResumeForTests = false

    internal func tearDownBatchForTests(batchId: String) {
        cancelBatchTasks(batchId: batchId)
        batchCoordinator.removeBatch(batchId: batchId)
        DownloadBatchStore.shared.clear()
    }

    internal var mainBackgroundSessionForTests: URLSession {
        DownloadBackgroundSessionManager.shared.mainSession
    }

    internal func registerSingleDownloadForTests(
        downloadId: String,
        task: URLSessionDownloadTask,
        session: URLSession,
        generation: UInt64,
        destination: String
    ) {
        DownloadDestinationStore.shared.setDestination(destination, for: downloadId)
        setTask(task, for: downloadId)
        setTaskGeneration(generation, for: task, in: session)
    }

    internal func registeredTaskGenerationKeysForTests() -> Set<String> {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return Set(taskGenerations.keys)
    }

    private func failBatch(batchId: String, generation: UInt64, fileIndex: Int?, error: String) {
        guard let childTaskIds = batchCoordinator.beginFailure(batchId: batchId, generation: generation) else {
            return
        }
        cancelBatchTasks(taskIds: childTaskIds)
        markBatchContinuedProcessingFinished(batchId: batchId, generation: generation, success: false)
        _ = batchCoordinator.removeBatch(batchId: batchId, generation: generation, unregisterChildren: false)
        DownloadCompletedNotificationStore.shared.removeText(for: batchId, generation: generation)
        presentFailedDownloadNotificationIfStored(downloadId: batchId, generation: generation)
        var data: [String: Any] = ["id": batchId, "error": error]
        if let fileIndex {
            data["fileIndex"] = fileIndex
        }
        notifyListeners("downloadFailed", data: data)
    }

    private func presentFailedDownloadNotificationIfStored(downloadId: String, generation: UInt64?) {
        if let failedText = DownloadFailedNotificationStore.shared.takeText(for: downloadId, generation: generation) {
            DownloadCompletedNotificationPresenter.presentIfAllowed(downloadId: downloadId, body: failedText)
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        guard let id = normalizedTaskId(from: call) else {
            call.reject("Task not found")
            return
        }

        if batchCoordinator.isBatch(batchId: id) {
            guard let stopSnapshot = batchCoordinator.takeBatchForStop(batchId: id) else {
                call.reject("Task not found")
                return
            }
            cancelBatchTasks(taskIds: stopSnapshot.childTaskIds)
            markBatchContinuedProcessingFinished(batchId: id, generation: stopSnapshot.generation, success: false)
            deleteDownloadedFiles(destinations: stopSnapshot.destinations)
            DownloadCompletedNotificationStore.shared.removeText(for: id, generation: stopSnapshot.generation)
            DownloadFailedNotificationStore.shared.removeText(for: id, generation: stopSnapshot.generation)
            call.resolve()
            return
        }

        guard let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        let generation = generation(for: id)
        markContinuedProcessingFinished(downloadId: id, success: false)
        task.cancel()
        removeTask(for: id, completing: task, in: sessionAssumedForStoredTask(downloadId: id))
        DownloadDestinationStore.shared.removeDestination(for: id)
        clearRetryBudget(for: id)
        if let generation {
            DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
            DownloadFailedNotificationStore.shared.removeText(for: id, generation: generation)
        }
        call.resolve()
    }


    @objc func checkStatus(_ call: CAPPluginCall) {
        guard let id = normalizedTaskId(from: call) else {
            call.reject("Task not found")
            return
        }

        if batchCoordinator.isBatch(batchId: id) {
            let progress = batchCoordinator.overallProgress(batchId: id) ?? 0
            let state = batchCoordinator.isPaused(batchId: id) ? "PAUSED" : "RUNNING"
            call.resolve([
                "id": id,
                "state": state,
                "progress": progress
            ])
            return
        }

        guard let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        let state: String
        switch task.state {
        case .running:
            state = "RUNNING"
        case .suspended:
            state = "PAUSED"
        case .canceling:
            state = "ERROR"
        case .completed:
            state = "DONE"
        @unknown default:
            state = "PENDING"
        }

        call.resolve([
            "id": id,
            "state": state,
            "progress": task.progress.fractionCompleted
        ])
    }

    @objc func getFileInfo(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else {
            call.reject("Invalid path")
            return
        }

        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            call.reject("File not found")
            return
        }

        let size = attributes[.size] as? Int64 ?? 0
        let type = (try? attributes[.type] as? String) ?? "unknown"

        call.resolve([
            "size": size,
            "type": type
        ])
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }

    internal func testing_setRetryBudget(downloadId: String, retries: Int) {
        setRetryBudget(for: downloadId, retries: retries)
    }

    internal func testing_preparePausedBatchChild(
        batchId: String,
        fileCount: Int,
        fileIndex: Int
    ) -> String? {
        guard let generation = batchCoordinator.startBatch(batchId: batchId, fileCount: fileCount, singleDownloadIds: []) else {
            return nil
        }
        let childTaskId = batchCoordinator.fileTaskId(batchId: batchId, generation: generation, fileIndex: fileIndex)
        batchCoordinator.registerChildTask(batchId: batchId, taskId: childTaskId, fileIndex: fileIndex)
        _ = batchCoordinator.setPausedReturningChildTaskIds(batchId: batchId, paused: true)
        return childTaskId
    }

    internal func testing_registerAndResumeRetryTask(
        downloadId: String,
        retryTask: URLSessionDownloadTask,
        session: URLSession,
        generation: UInt64?
    ) -> Bool {
        registerAndResumeRetryTaskIfCurrent(
            downloadId: downloadId,
            retryTask: retryTask,
            session: session,
            generation: generation
        )
    }

    internal func testing_registerPendingForegroundRetry(
        downloadId: String,
        retryTask: URLSessionDownloadTask,
        session: URLSession,
        generation: UInt64?,
        delay: TimeInterval
    ) -> Bool {
        tasksLock.lock()
        guard downloadRetryBudgets[downloadId] != nil else {
            tasksLock.unlock()
            return false
        }
        tasks[downloadId] = retryTask
        if let generation {
            let key = DownloadTaskGenerationKey.storageKey(session: session, task: retryTask)
            taskGenerations[key] = generation
            DownloadTaskGenerationStore.shared.setGeneration(generation, forTask: retryTask, in: session)
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.resumePendingForegroundRetryIfCurrent(downloadId: downloadId, retryTask: retryTask)
        }
        cancelPendingRetryWorkLocked(for: downloadId)
        pendingRetryWorkItems[downloadId] = workItem
        tasksLock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    internal func testing_hasPendingForegroundRetry(downloadId: String) -> Bool {
        isPendingForegroundRetry(downloadId)
    }

    internal func testing_setForegroundRetryPaused(downloadId: String) {
        tasksLock.lock()
        foregroundRetryPausedDownloadIds.insert(downloadId)
        tasksLock.unlock()
    }

    internal func testing_resumePendingForegroundRetryIfCurrent(
        downloadId: String,
        retryTask: URLSessionDownloadTask
    ) {
        resumePendingForegroundRetryIfCurrent(downloadId: downloadId, retryTask: retryTask)
    }

    internal func testing_cancelDownloadFromContinuedProcessingExpiry(downloadId: String) {
        cancelDownloadFromContinuedProcessingExpiry(downloadId)
    }
}

extension CapacitorDownloaderPlugin: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = idForTask(downloadTask) else {
            return
        }

        if let batchParts = batchCoordinator.childParts(for: id), batchCoordinator.isBatch(batchId: batchParts.batchId) == false {
            try? FileManager.default.removeItem(at: location)
            removeTask(for: id, completing: downloadTask, in: session)
            _ = DownloadDestinationStore.shared.takeDestination(for: id)
            batchCoordinator.unregisterChildTask(id)
            return
        }

        let storedDestination = DownloadDestinationStore.shared.takeDestination(for: id)
        let generation = generation(for: downloadTask, in: session)

        guard let destinationURL = destinationURL(for: id, storedDestination: storedDestination) else {
            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                failBatch(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    error: "Unable to resolve destination"
                )
            } else if !batchCoordinator.isOwnedBatchChild(taskId: id) {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                    presentFailedDownloadNotificationIfStored(downloadId: id, generation: generation)
                }
                notifyListeners("downloadFailed", data: ["id": id, "error": "Unable to resolve destination"])
                clearRetryBudget(for: id)
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
            removeTask(for: id, completing: downloadTask, in: session)
            batchCoordinator.unregisterChildTask(id)
            batchCoordinator.clearInactiveBatchChildTask(id)
            clearTaskGeneration(for: downloadTask, in: session)
            return
        }

        if let httpResponse = DownloadSessionDelegateTestSupport.httpResponse(for: downloadTask),
           !DownloadHTTPValidator.isSuccessfulStatusCode(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: location)
            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                failBatch(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    error: "HTTP \(httpResponse.statusCode)"
                )
            } else if !batchCoordinator.isOwnedBatchChild(taskId: id) {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                    presentFailedDownloadNotificationIfStored(downloadId: id, generation: generation)
                }
                notifyListeners(
                    "downloadFailed",
                    data: ["id": id, "error": "HTTP \(httpResponse.statusCode)"]
                )
                clearRetryBudget(for: id)
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
            return
        }

        do {
            try prepareDestinationDirectory(for: destinationURL)
            guard try batchCoordinator.prepareDestinationReplacement(taskId: id, destinationURL: destinationURL) else {
                try? FileManager.default.removeItem(at: location)
                removeTask(for: id, completing: downloadTask, in: session)
                batchCoordinator.unregisterChildTask(id)
                batchCoordinator.clearInactiveBatchChildTask(id)
                return
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)

            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                removeTask(for: id, completing: downloadTask, in: session)
                switch batchCoordinator.markFileCompleted(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    movedDestination: destinationURL.path
                ) {
                case .allSucceeded(let batchId, let generation):
                    notifyListeners(
                        "downloadProgress",
                        data: [
                            "id": batchParts.batchId,
                            "progress": 1,
                            "fileIndex": batchParts.fileIndex,
                            "fileProgress": 1
                        ]
                    )
                    notifyListeners("downloadCompleted", data: ["id": batchId])
                    if let completionText = DownloadCompletedNotificationStore.shared.takeText(for: batchId, generation: generation) {
                        DownloadCompletedNotificationPresenter.presentIfAllowed(downloadId: batchId, body: completionText)
                    }
                    DownloadFailedNotificationStore.shared.removeText(for: batchId, generation: generation)
                    markBatchContinuedProcessingFinished(batchId: batchId, generation: generation, success: true)
                case .inProgress(let overall):
                    continuedProcessing.reportProgress(downloadId: batchParts.batchId, fraction: Double(overall))
                    notifyListeners(
                        "downloadProgress",
                        data: [
                            "id": batchParts.batchId,
                            "progress": overall,
                            "fileIndex": batchParts.fileIndex,
                            "fileProgress": 1
                        ]
                    )
                case .none:
                    try? FileManager.default.removeItem(at: destinationURL)
                }
                batchCoordinator.unregisterChildTask(id)
                batchCoordinator.clearInactiveBatchChildTask(id)
            } else if batchCoordinator.isOwnedBatchChild(taskId: id) {
                try? FileManager.default.removeItem(at: destinationURL)
                removeTask(for: id, completing: downloadTask, in: session)
                batchCoordinator.unregisterChildTask(id)
                batchCoordinator.clearInactiveBatchChildTask(id)
            } else {
                notifyListeners("downloadCompleted", data: ["id": id])
                if let completionText = DownloadCompletedNotificationStore.shared.takeText(for: id, generation: generation) {
                    DownloadCompletedNotificationPresenter.presentIfAllowed(downloadId: id, body: completionText)
                }
                DownloadFailedNotificationStore.shared.removeText(for: id, generation: generation)
                markContinuedProcessingFinished(downloadId: id, success: true)
            }
            clearRetryBudget(for: id)
        } catch {
            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                failBatch(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    error: error.localizedDescription
                )
            } else if !batchCoordinator.isOwnedBatchChild(taskId: id) {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                    presentFailedDownloadNotificationIfStored(downloadId: id, generation: generation)
                }
                notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
                clearRetryBudget(for: id)
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
        }

        if batchCoordinator.childParts(for: id) != nil {
            batchCoordinator.unregisterChildTask(id)
            batchCoordinator.clearInactiveBatchChildTask(id)
        }
        clearTaskGeneration(for: downloadTask, in: session)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let id = idForTask(downloadTask) else {
            return
        }

        tasksLock.lock()
        let stillCurrent = tasks[id] === downloadTask
        tasksLock.unlock()
        guard stillCurrent else {
            if batchCoordinator.childParts(for: id) != nil || batchCoordinator.isOwnedBatchChild(taskId: id) {
                batchCoordinator.clearInactiveBatchChildTask(id)
            }
            return
        }

        let generation = generation(for: downloadTask, in: session)

        if let error {
            if scheduleConnectionRetryIfPossible(
                downloadId: id,
                failedTask: downloadTask,
                session: session,
                error: error,
                generation: generation
            ) {
                return
            }
            removeTask(for: id, completing: downloadTask, in: session)
            _ = DownloadDestinationStore.shared.takeDestination(for: id)
            clearRetryBudget(for: id)
            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                failBatch(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    error: error.localizedDescription
                )
            } else if !batchCoordinator.isOwnedBatchChild(taskId: id) {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                    presentFailedDownloadNotificationIfStored(downloadId: id, generation: generation)
                }
                notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
        } else {
            removeTask(for: id, completing: downloadTask, in: session)
        }

        if batchCoordinator.childParts(for: id) != nil {
            batchCoordinator.unregisterChildTask(id)
            batchCoordinator.clearInactiveBatchChildTask(id)
        }
        clearTaskGeneration(for: downloadTask, in: session)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = idForTask(downloadTask) else {
            return
        }
        tasksLock.lock()
        let isCurrentTask = tasks[id] === downloadTask
        tasksLock.unlock()
        if isCurrentTask {
            captureExpectedTotalFromResponseIfNeeded(downloadId: id, downloadTask: downloadTask)
        }

        let progressSnapshot = DownloadLengthHeaderProgress.bytesTotalAndProgress(
            downloadId: id,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite
        )
        let bytesTotal = progressSnapshot.bytesTotal
        let progress = progressSnapshot.progress

        if let batchParts = batchCoordinator.activeChildParts(for: id) {
            guard let batchProgress = batchCoordinator.updateFileProgress(
                batchId: batchParts.batchId,
                generation: batchParts.generation,
                fileIndex: batchParts.fileIndex,
                progress: progress
            ) else {
                return
            }
            continuedProcessing.reportProgress(downloadId: batchParts.batchId, fraction: Double(batchProgress.overall))
            notifyListeners(
                "downloadProgress",
                data: [
                    "id": batchParts.batchId,
                    "progress": batchProgress.overall,
                    "fileIndex": batchParts.fileIndex,
                    "fileProgress": batchProgress.file,
                    "bytesWritten": totalBytesWritten,
                    "bytesTotal": bytesTotal
                ]
            )
            return
        }

        continuedProcessing.reportProgress(downloadId: id, fraction: Double(progress))
        notifyListeners(
            "downloadProgress",
            data: [
                "id": id,
                "progress": progress,
                "bytesWritten": totalBytesWritten,
                "bytesTotal": bytesTotal
            ]
        )
    }
}
