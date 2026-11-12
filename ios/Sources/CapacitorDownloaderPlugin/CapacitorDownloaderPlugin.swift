import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */

@objc(CapacitorDownloaderPlugin)
public class CapacitorDownloaderPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.3.20"
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
    private let tasksLock = NSLock()
    private let batchCoordinator = DownloadBatchCoordinator()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "CapacitorDownloader")
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

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

    private func removeTask(for id: String) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        tasks.removeValue(forKey: id)
    }

    private func singleDownloadIds() -> Set<String> {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return Set(tasks.keys.filter { batchCoordinator.childParts(for: $0) == nil })
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
          guard let documentsDirectory = documentsDirectoryURL(),
                let destinationURL = destinationURL(for: "cleanup", storedDestination: destination),
                FileManager.default.fileExists(atPath: destinationURL.path) else {
              continue
          }
          try? FileManager.default.removeItem(at: destinationURL)
      }
  }

    @objc func download(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
            call.reject("Invalid parameters")
            return
        }

        if call.getArray("files") != nil {
            guard let files = call.getArray("files") as? [[String: Any]] else {
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

        DownloadDestinationStore.shared.setDestination(destination, for: id)

        var request = URLRequest(url: url)
        if let headers = call.getObject("headers") as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = id
        setTask(task, for: id)
        task.resume()

        call.resolve([
            "id": id,
            "state": "RUNNING",
            "progress": 0
        ])
    }

    private func downloadBatch(_ call: CAPPluginCall, batchId: String, files: [[String: Any]]) {
        var parsed: [(url: URL, destination: String)] = []
        let headers = call.getObject("headers") as? [String: String] ?? [:]

        for fileObject in files {
            guard let urlString = fileObject["url"] as? String,
                  let url = URL(string: urlString),
                  let destination = fileObject["destination"] as? String,
                  !destination.isEmpty else {
                call.reject("Each file entry requires url and destination")
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

        var stagedTasks: [(taskId: String, task: URLSessionDownloadTask)] = []

        for (index, entry) in parsed.enumerated() {
            let taskId = batchCoordinator.fileTaskId(batchId: batchId, generation: generation, fileIndex: index)
            DownloadDestinationStore.shared.setDestination(entry.destination, for: taskId)
            batchCoordinator.registerChildTask(batchId: batchId, taskId: taskId, fileIndex: index, destination: entry.destination)

            var request = URLRequest(url: entry.url)
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let task = session.downloadTask(with: request)
            task.taskDescription = taskId
            stagedTasks.append((taskId, task))
        }

        for staged in stagedTasks {
            setTask(staged.task, for: staged.taskId)
            staged.task.resume()
        }

        call.resolve([
            "id": batchId,
            "state": "RUNNING",
            "progress": 0
        ])
    }

    private func cancelBatchTasks(batchId: String) {
        let taskIds = batchCoordinator.childTaskIds(batchId: batchId)
        for taskId in taskIds {
            if let task = getTask(for: taskId) {
                task.cancel()
            }
            removeTask(for: taskId)
            DownloadDestinationStore.shared.removeDestination(for: taskId)
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
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
        guard let id = call.getString("id") else {
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

    private func failBatch(batchId: String, fileIndex: Int, error: String) {
        guard batchCoordinator.beginFailure(batchId: batchId) else {
            return
        }
        cancelBatchTasks(batchId: batchId)
        batchCoordinator.removeBatch(batchId: batchId)
        notifyListeners(
            "downloadFailed",
            data: ["id": batchId, "fileIndex": fileIndex, "error": error]
        )
    }

    @objc func stop(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
            call.reject("Task not found")
            return
        }

        if batchCoordinator.isBatch(batchId: id) {
            let destinations = batchCoordinator.destinationsForCancellation(batchId: id)
            batchCoordinator.markCancelled(batchId: id)
            cancelBatchTasks(batchId: id)
            deleteDownloadedFiles(destinations: destinations)
            batchCoordinator.removeBatch(batchId: id)
            call.resolve()
            return
        }

        guard let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        task.cancel()
        removeTask(for: id)
        DownloadDestinationStore.shared.removeDestination(for: id)
        call.resolve()
    }


    @objc func checkStatus(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
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
            removeTask(for: id)
            _ = DownloadDestinationStore.shared.takeDestination(for: id)
            return
        }

        let storedDestination = DownloadDestinationStore.shared.takeDestination(for: id)
        guard let destinationURL = destinationURL(for: id, storedDestination: storedDestination) else {
            notifyListeners("downloadFailed", data: ["id": id, "error": "Unable to resolve destination"])
            return
        }

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !DownloadHTTPValidator.isSuccessfulStatusCode(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: location)
            if let batchParts = batchCoordinator.childParts(for: id) {
                failBatch(batchId: batchParts.batchId, fileIndex: batchParts.fileIndex, error: "HTTP \(httpResponse.statusCode)")
            } else {
                notifyListeners(
                    "downloadFailed",
                    data: ["id": id, "error": "HTTP \(httpResponse.statusCode)"]
                )
            }
            return
        }

        do {
            try prepareDestinationDirectory(for: destinationURL)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            if let batchParts = batchCoordinator.childParts(for: id) {
                guard batchCoordinator.isBatch(batchId: batchParts.batchId) else {
                    try? FileManager.default.removeItem(at: location)
                    removeTask(for: id)
                    return
                }
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)

            if let batchParts = batchCoordinator.childParts(for: id) {
                removeTask(for: id)
                if let storedDestination {
                    batchCoordinator.recordMovedDestination(
                        batchId: batchParts.batchId,
                        fileIndex: batchParts.fileIndex,
                        destination: storedDestination
                    )
                }
                switch batchCoordinator.markFileCompleted(batchId: batchParts.batchId, fileIndex: batchParts.fileIndex) {
                case .allSucceeded(let batchId):
                    notifyListeners("downloadCompleted", data: ["id": batchId])
                case .inProgress(let overall):
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
            } else {
                notifyListeners("downloadCompleted", data: ["id": id])
            }
        } catch {
            if let batchParts = batchCoordinator.childParts(for: id) {
                failBatch(batchId: batchParts.batchId, fileIndex: batchParts.fileIndex, error: error.localizedDescription)
            } else {
                notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let id = idForTask(downloadTask) else {
            return
        }

        removeTask(for: id)

        if error != nil {
            _ = DownloadDestinationStore.shared.takeDestination(for: id)
        }

        if let error = error {
            if let batchParts = batchCoordinator.childParts(for: id) {
                failBatch(batchId: batchParts.batchId, fileIndex: batchParts.fileIndex, error: error.localizedDescription)
            } else {
                notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
            }
        }
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

        if let batchParts = batchCoordinator.childParts(for: id) {
            guard let batchProgress = batchCoordinator.updateFileProgress(
                batchId: batchParts.batchId,
                fileIndex: batchParts.fileIndex,
                progress: progress
            ) else {
                return
            }
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
