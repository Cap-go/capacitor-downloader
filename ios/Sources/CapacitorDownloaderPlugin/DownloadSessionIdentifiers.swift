import Foundation

enum DownloadSessionIdentifiers {
    static let main = "CapacitorDownloader"
    static let wifiOnly = "CapacitorDownloader.wifiOnly"
    static let foregroundCapable = "CapacitorDownloader.foreground"
    static let continuedProcessingSuffix = ".CapacitorDownloader.continuedProcessing."

    static func continuedProcessingTaskIdentifier() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "CapacitorDownloader"
        return bundleId + continuedProcessingSuffix + UUID().uuidString
    }

    static func continuedProcessingPermittedIdentifierPattern() -> String {
        let bundleId = Bundle.main.bundleIdentifier ?? "CapacitorDownloader"
        return bundleId + continuedProcessingSuffix + "*"
    }

    static func isPluginSession(_ identifier: String) -> Bool {
        identifier == main || identifier == wifiOnly
    }
}