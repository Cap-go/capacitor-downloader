import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */

@objc(CapacitorDownloaderPlugin)
public class CapacitorDownloaderPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.5.1"
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
    private var taskGenerations: [Int: UInt64] = [:]
    private let tasksLock = NSLock()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "CapacitorDownloader")
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public override func load() {
        tasksLock.lock()
        downloadGenerations = DownloadIdGenerationStore.shared.allGenerations()
        taskGenerations = DownloadTaskGenerationStore.shared.allGenerations()
        tasksLock.unlock()
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

    private func removeTask(for id: String, completing task: URLSessionDownloadTask) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        if tasks[id] === task {
            tasks.removeValue(forKey: id)
        }
        taskGenerations.removeValue(forKey: task.taskIdentifier)
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

    private func setTaskGeneration(_ generation: UInt64, for task: URLSessionDownloadTask) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        taskGenerations[task.taskIdentifier] = generation
        DownloadTaskGenerationStore.shared.setGeneration(generation, forTaskIdentifier: task.taskIdentifier)
    }

    private func generation(for task: URLSessionTask) -> UInt64? {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        return taskGenerations[task.taskIdentifier]
    }

    private func clearTaskGeneration(for task: URLSessionTask) {
        tasksLock.lock()
        defer { tasksLock.unlock() }
        taskGenerations.removeValue(forKey: task.taskIdentifier)
        DownloadTaskGenerationStore.shared.removeGeneration(forTaskIdentifier: task.taskIdentifier)
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

    @objc func download(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let urlString = call.getString("url"),
              let url = URL(string: urlString) else {
            call.reject("Invalid parameters")
            return
        }

        let destination = call.getString("destination") ?? ""
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

        let task = session.downloadTask(with: request)
        task.taskDescription = id
        setTask(task, for: id)
        setTaskGeneration(generation, for: task)
        task.resume()

        call.resolve([
            "id": id,
            "state": "RUNNING",
            "progress": 0
        ])
    }

    @objc func pause(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        task.suspend()
        call.resolve()
    }

    @objc func resume(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        task.resume()
        call.resolve()
    }

    @objc func stop(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = getTask(for: id) else {
            call.reject("Task not found")
            return
        }

        let generation = generation(for: id)
        task.cancel()
        removeTask(for: id, completing: task)
        DownloadDestinationStore.shared.removeDestination(for: id)
        if let generation {
            DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
        }
        call.resolve()
    }

    @objc func checkStatus(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = getTask(for: id) else {
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

        let storedDestination = DownloadDestinationStore.shared.takeDestination(for: id)
        let generation = generation(for: downloadTask)

        guard let destinationURL = destinationURL(for: id, storedDestination: storedDestination) else {
            if let generation {
                DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
            }
            notifyListeners("downloadFailed", data: ["id": id, "error": "Unable to resolve destination"])
            return
        }

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !DownloadHTTPValidator.isSuccessfulStatusCode(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: location)
            if let generation {
                DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
            }
            notifyListeners(
                "downloadFailed",
                data: ["id": id, "error": "HTTP \(httpResponse.statusCode)"]
            )
            return
        }

        do {
            try prepareDestinationDirectory(for: destinationURL)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            notifyListeners("downloadCompleted", data: ["id": id])
            if let completionText = DownloadCompletedNotificationStore.shared.takeText(for: id, generation: generation) {
                DownloadCompletedNotificationPresenter.presentIfAllowed(downloadId: id, body: completionText)
            }
        } catch {
            if let generation {
                DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
            }
            notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
        }

        clearTaskGeneration(for: downloadTask)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let id = idForTask(downloadTask) else {
            return
        }

        let generation = generation(for: downloadTask)
        removeTask(for: id, completing: downloadTask)

        if error != nil {
            _ = DownloadDestinationStore.shared.takeDestination(for: id)
        }

        if let error {
            if let generation {
                DownloadCompletedNotificationStore.shared.removeText(for: id, generation: generation)
            }
            notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
        }

        clearTaskGeneration(for: downloadTask)
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
