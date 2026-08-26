import Foundation

enum DownloadHTTPValidator {
    static func isSuccessfulStatusCode(_ statusCode: Int) -> Bool {
        statusCode >= 200 && statusCode < 300
    }
}
