import Foundation

enum DownloadLengthHeaderProgress {
    static func bytesTotalAndProgress(
        downloadId: String,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) -> (bytesTotal: Int64, progress: Float) {
        var bytesTotal: Int64 = 0
        if let override = DownloadLengthHeaderStore.shared.expectedTotal(for: downloadId), override > 0 {
            bytesTotal = override
        } else if totalBytesExpectedToWrite > 0 {
            bytesTotal = totalBytesExpectedToWrite
        }
        let progress: Float
        if bytesTotal > 0 {
            progress = min(1, max(0, Float(totalBytesWritten) / Float(bytesTotal)))
        } else {
            progress = 0
        }
        return (bytesTotal, progress)
    }
}