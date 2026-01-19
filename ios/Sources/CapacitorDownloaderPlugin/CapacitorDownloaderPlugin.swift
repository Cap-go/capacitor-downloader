import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */

@objc(CapacitorDownloaderPlugin)
public class CapacitorDownloaderPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.1.2"
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
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "CapacitorDownloader")
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    @objc func download(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let urlString = call.getString("url"),
              let destination = call.getString("destination"),
              let url = URL(string: urlString) else {
            call.reject("Invalid parameters")
            return
        }

        var request = URLRequest(url: url)
        if let headers = call.getObject("headers") as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let task = session.downloadTask(with: request)
        tasks[id] = task
        task.resume()

        call.resolve([
            "id": id,
            "state": "RUNNING",
            "progress": 0
        ])
    }

    @objc func pause(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = tasks[id] else {
            call.reject("Task not found")
            return
        }

        task.suspend()
        call.resolve()
    }

    @objc func resume(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = tasks[id] else {
            call.reject("Task not found")
            return
        }

        task.resume()
        call.resolve()
    }

    @objc func stop(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = tasks[id] else {
            call.reject("Task not found")
            return
        }

        task.cancel()
        tasks.removeValue(forKey: id)
        call.resolve()
    }

    @objc func checkStatus(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let task = tasks[id] else {
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
}

extension CapacitorDownloaderPlugin: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = tasks.first(where: { $0.value == downloadTask })?.key,
              let destinationURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(id) else {
            return
        }

        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            notifyListeners("downloadCompleted", data: ["id": id])
        } catch {
            notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let id = tasks.first(where: { $0.value == downloadTask })?.key else {
            return
        }

        tasks.removeValue(forKey: id)

        if let error = error {
            notifyListeners("downloadFailed", data: ["id": id, "error": error.localizedDescription])
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = tasks.first(where: { $0.value == downloadTask })?.key else {
            return
        }

        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        notifyListeners("downloadProgress", data: ["id": id, "progress": progress])
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }

}
