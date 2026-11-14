import Foundation

enum DownloadSessionIdentifiers {
    static let main = "CapacitorDownloader"
    static let wifiOnly = "CapacitorDownloader.wifiOnly"
    static let continuedProcessingPrefix = "CapacitorDownloader.continuedProcessing."

    static func isPluginSession(_ identifier: String) -> Bool {
        identifier == main || identifier == wifiOnly
    }
}