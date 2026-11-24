import Foundation

enum DownloadConnectionRetry {
    static let maxRetryDelaySeconds: TimeInterval = 600

    struct Budget {
        var remainingRetries: Int
        var connectionFailureCount: Int
    }

    static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed
    ]

    static func isRetryableConnectionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }
        let code = URLError.Code(rawValue: nsError.code)
        return retryableURLErrorCodes.contains(code)
    }

    static func delaySeconds(afterConnectionFailureCount failureCount: Int) -> TimeInterval {
        let delay = TimeInterval(5 * failureCount)
        return min(delay, maxRetryDelaySeconds)
    }

    static func normalizeRetries(_ raw: Int?) -> Int {
        max(0, raw ?? 0)
    }
}