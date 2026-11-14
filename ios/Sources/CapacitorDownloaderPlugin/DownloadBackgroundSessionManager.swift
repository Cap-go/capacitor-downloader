import Foundation

/// Owns background URL sessions created at process launch so iOS can reconnect after relaunch.
final class DownloadBackgroundSessionManager: NSObject {
    static let shared = DownloadBackgroundSessionManager()

    private weak var downloadDelegate: URLSessionDownloadDelegate?
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "CapacitorDownloader.URLSession"
        return queue
    }()

    private var completionHandlers: [String: () -> Void] = [:]
    private let handlerLock = NSLock()

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

  func register(downloadDelegate: URLSessionDownloadDelegate) {
    self.downloadDelegate = downloadDelegate
  }

  func session(allowsCellularAccess: Bool, preferForegroundCapable: Bool) -> URLSession {
    if preferForegroundCapable, foregroundCapableSession != nil {
      return foregroundCapableSession
    }
    return allowsCellularAccess ? mainSession : wifiOnlySession
  }

  func storeBackgroundEventsCompletionHandler(_ handler: @escaping () -> Void, for identifier: String) {
    handlerLock.lock()
    completionHandlers[identifier] = handler
    handlerLock.unlock()
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
    downloadDelegate?.urlSession?(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    downloadDelegate?.urlSession?(session, task: task, didCompleteWithError: error)
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
    handlerLock.lock()
    let handler = completionHandlers.removeValue(forKey: identifier)
    handlerLock.unlock()
    DispatchQueue.main.async {
      handler?()
    }
  }
}