import Foundation

/// Test-only HTTP response overrides keyed by `URLSessionTask.taskIdentifier`.
enum DownloadSessionDelegateTestSupport {
    static var httpResponseOverrides: [Int: HTTPURLResponse] = [:]

    static func httpResponse(for task: URLSessionDownloadTask) -> HTTPURLResponse? {
        if let override = httpResponseOverrides[task.taskIdentifier] {
            return override
        }
        return task.response as? HTTPURLResponse
    }

    static func reset() {
        httpResponseOverrides = [:]
    }
}