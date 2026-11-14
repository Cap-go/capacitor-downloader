import Foundation

enum DownloadBatchProgress {
    static func overallProgress(fileProgress: [Float], fileCount: Int) -> Float {
        guard fileCount > 0, !fileProgress.isEmpty else {
            return 0
        }

        let counted = min(fileCount, fileProgress.count)
        let sum = fileProgress.prefix(counted).reduce(0) { partial, value in
            partial + min(1, max(0, value))
        }
        return sum / Float(fileCount)
    }

    static func toPercent(_ ratio: Float) -> Float {
        min(100, max(0, ratio * 100))
    }
}
