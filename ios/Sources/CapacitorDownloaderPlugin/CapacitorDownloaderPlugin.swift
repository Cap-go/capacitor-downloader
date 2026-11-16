import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */

@objc(CapacitorDownloaderPlugin)
public class CapacitorDownloaderPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.8.0"
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
    private let batchCoordinator = DownloadBatchCoordinator()
    private let continuedProcessing = DownloadContinuedProcessingCoordinator()
    private var foregroundSessionDownloadIds = Set<String>()
    private var pendingDownloadStarts = Set<String>()
    private let foregroundSessionLock = NSLock()
    internal private(set) var restoredBackgroundSessionIdentifiers: [String] = []
    internal private(set) var didRestoreGenerationsBeforeDelegateRegistration = false
    static let batchMaxFiles = 32

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
        tasksLock.unlock()
        restoredBackgroundSessionIdentifiers = [
            DownloadSessionIdentifiers.main,
            DownloadSessionIdentifiers.wifiOnly
        ]
        continuedProcessing.onDownloadExpired = { [weak self] downloadId in
            self?.cancelDownloadFromContinuedProcessingExpiry(downloadId)
        }
        let finishLoad: ([URLSessionTask]) -> Void = { [weak self] tasks in
            guard let self else {
                return
            }
            self.rehydrateBackgroundDownloadTasks(tasks)
            self.registerDownloadDelegateIfGenerationsRestored()
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let semaphore = DispatchSemaphore(value: 0)
            DownloadBackgroundSessionManager.shared.rehydrateTasks { tasks in
                finishLoad(tasks)
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 5)
        } else {
            DownloadBackgroundSessionManager.shared.rehydrateTasks(completion: finishLoad)
        }
    }

    private func cancelDownloadFromContinuedProcessingExpiry(_ downloadId: String) {
        if batchCoordinator.isBatch(batchId: downloadId), let generation = batchCoordinator.generation(for: downloadId) {
            failBatch(batchId: downloadId, generation: generation, fileIndex: nil, error: "Continued processing task expired")
            return
        }
        guard let task = getTask(for: downloadId) else {
            return
        }
        task.cancel()
        removeTask(for: downloadId, completing: task, in: sessionAssumedForStoredTask(downloadId: downloadId))
        DownloadDestinationStore.shared.removeDestination(for: downloadId)
        if let generation = generation(for: downloadId) {
            DownloadCompletedNotificationStore.shared.removeText(for: downloadId, generation: generation)
        }
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

    private func singleDownloadIds() -> Set<String> {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return Set(tasks.keys.filter { batchCoordinator.childParts(for: $0) == nil })
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
            guard let files = filesValue as? [[String: Any]] else {
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

        var request = URLRequest(url: url)
        if let headers = call.getObject("headers") as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let wifiOnly = call.getString("network") == "wifi-only"
        let continuedRequest = parseContinuedProcessingRequest(call)

        continuedProcessing.beginIfPossible(downloadId: id, request: continuedRequest) { [weak self] useForeground in
            guard let self else {
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

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func markContinuedProcessingFinished(downloadId: String, success: Bool) {
        continuedProcessing.finish(downloadId: downloadId, success: success)
        foregroundSessionLock.lock()
        foregroundSessionDownloadIds.remove(downloadId)
        foregroundSessionLock.unlock()
    }

    private func downloadBatch(_ call: CAPPluginCall, batchId: String, files: [[String: Any]]) {
        if files.count > Self.batchMaxFiles {
            call.reject("Batch exceeds maximum of \(Self.batchMaxFiles) files")
            return
        }

        var parsed: [(url: URL, destination: String)] = []
        let headers = call.getObject("headers") as? [String: String] ?? [:]
        let wifiOnly = call.getString("network") == "wifi-only"

        for fileObject in files {
            guard let urlString = fileObject["url"] as? String,
                  let url = URL(string: urlString),
                  let destination = fileObject["destination"] as? String,
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
            call.reject("Download already exists")
            return
        }

        DownloadCompletedNotificationStore.shared.setText(
            call.getString("downloadCompletedNotificationText"),
            for: batchId,
            generation: generation
        )

        let continuedRequest = parseContinuedProcessingRequest(call)
        continuedProcessing.beginIfPossible(downloadId: batchId, request: continuedRequest) { [weak self] useForeground in
            guard let self else {
                return
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

            stagedTasks.forEach { self.setTask($0.task, for: $0.taskId) }
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
            if !startup.paused {
                stagedTasks.forEach { $0.task.resume() }
            }
            guard self.batchCoordinator.batchStartupSnapshot(batchId: batchId, generation: generation).allowed else {
                self.discardStagedBatchTasks(stagedTasks, session: batchSession)
                self.markBatchContinuedProcessingFinished(batchId: batchId, generation: generation, success: false)
                call.reject("Download was cancelled")
                return
            }

            call.resolve([
                "id": batchId,
                "state": startup.paused ? "PAUSED" : "RUNNING",
                "progress": 0
            ])
        }
    }

    /// Cancels the transfers of a batch that was stopped while they were being created. They are published before the
    /// batch is checked again, so a `stop` that comes after that check cancels them itself through `cancelBatchTasks`.
    private func discardStagedBatchTasks(_ stagedTasks: [(taskId: String, task: URLSessionDownloadTask)], session: URLSession) {
        for staged in stagedTasks {
            staged.task.cancel()
            removeTask(for: staged.taskId, completing: staged.task, in: session)
            DownloadDestinationStore.shared.removeDestination(for: staged.taskId)
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

        guard let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        task.resume()
        call.resolve()
    }

    private func pauseBatch(batchId: String) {
        batchCoordinator.setPaused(batchId: batchId, paused: true)
        for taskId in batchCoordinator.childTaskIds(batchId: batchId) {
            getTask(for: taskId)?.suspend()
        }
    }

    private func resumeBatch(batchId: String) {
        batchCoordinator.setPaused(batchId: batchId, paused: false)
        for taskId in batchCoordinator.childTaskIds(batchId: batchId) {
            getTask(for: taskId)?.resume()
        }
    }

    internal var mainBackgroundSessionForTests: URLSession {
        DownloadBackgroundSessionManager.shared.mainSession
    }

    private func failBatch(batchId: String, generation: UInt64, fileIndex: Int?, error: String) {
        guard batchCoordinator.beginFailure(batchId: batchId, generation: generation) else {
            return
        }
        cancelBatchTasks(batchId: batchId)
        markBatchContinuedProcessingFinished(batchId: batchId, generation: generation, success: false)
        batchCoordinator.removeBatch(batchId: batchId, unregisterChildren: false)
        var data: [String: Any] = ["id": batchId, "error": error]
        if let fileIndex {
            data["fileIndex"] = fileIndex
        }
        notifyListeners("downloadFailed", data: data)
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
        if let generation {
            DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
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
            } else {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                }
                notifyListeners("downloadFailed", data: ["id": id, "error": "Unable to resolve destination"])
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
            removeTask(for: id, completing: downloadTask, in: session)
            batchCoordinator.unregisterChildTask(id)
            clearTaskGeneration(for: downloadTask, in: session)
            return
        }

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !DownloadHTTPValidator.isSuccessfulStatusCode(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: location)
            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                failBatch(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    error: "HTTP \(httpResponse.statusCode)"
                )
            } else {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                }
                notifyListeners(
                    "downloadFailed",
                    data: ["id": id, "error": "HTTP \(httpResponse.statusCode)"]
                )
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
            return
        }

        do {
            try prepareDestinationDirectory(for: destinationURL)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            if let batchParts = batchCoordinator.childParts(for: id) {
                guard batchCoordinator.activeChildParts(for: id) != nil else {
                    try? FileManager.default.removeItem(at: location)
                    removeTask(for: id, completing: downloadTask, in: session)
                    batchCoordinator.unregisterChildTask(id)
                    return
                }
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)

            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                removeTask(for: id, completing: downloadTask, in: session)
                batchCoordinator.recordMovedDestination(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    destination: destinationURL.path
                )
                switch batchCoordinator.markFileCompleted(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex
                ) {
                case .allSucceeded(let batchId, let generation):
                    notifyListeners("downloadCompleted", data: ["id": batchId])
                    if let completionText = DownloadCompletedNotificationStore.shared.takeText(for: batchId, generation: generation) {
                        DownloadCompletedNotificationPresenter.presentIfAllowed(downloadId: batchId, body: completionText)
                    }
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
                    break
                }
                batchCoordinator.unregisterChildTask(id)
            } else {
                notifyListeners("downloadCompleted", data: ["id": id])
                if let completionText = DownloadCompletedNotificationStore.shared.takeText(for: id, generation: generation) {
                    DownloadCompletedNotificationPresenter.presentIfAllowed(downloadId: id, body: completionText)
                }
                markContinuedProcessingFinished(downloadId: id, success: true)
            }
        } catch {
            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                failBatch(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    error: error.localizedDescription
                )
            } else {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                }
                notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
        }

        if batchCoordinator.childParts(for: id) != nil {
            batchCoordinator.unregisterChildTask(id)
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
            return
        }

        let generation = generation(for: downloadTask, in: session)
        removeTask(for: id, completing: downloadTask, in: session)

        if error != nil {
            _ = DownloadDestinationStore.shared.takeDestination(for: id)
        }

        if let error {
            if let batchParts = batchCoordinator.activeChildParts(for: id) {
                failBatch(
                    batchId: batchParts.batchId,
                    generation: batchParts.generation,
                    fileIndex: batchParts.fileIndex,
                    error: error.localizedDescription
                )
            } else {
                if let generation {
                    DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
                }
                notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
                markContinuedProcessingFinished(downloadId: id, success: false)
            }
        }

        if batchCoordinator.childParts(for: id) != nil {
            batchCoordinator.unregisterChildTask(id)
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

        let bytesTotal = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        let progress = bytesTotal > 0 ? Float(totalBytesWritten) / Float(bytesTotal) : 0

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
