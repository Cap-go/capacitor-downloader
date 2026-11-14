import Foundation

/// Host `AppDelegate` hooks for background URL session completion. Optional if bootstrap runs at launch.
@objc(CapacitorDownloaderLifecycle)
public class CapacitorDownloaderLifecycle: NSObject {
  @objc public static func warmUpBackgroundSessions() {
    DownloadBackgroundSessionManager.shared.warmUp()
  }

  @objc(handleEventsForBackgroundURLSession:completionHandler:)
  public static func handleEventsForBackgroundURLSession(
    identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard DownloadSessionIdentifiers.isPluginSession(identifier) else {
      completionHandler()
      return
    }
    DownloadBackgroundSessionManager.shared.warmUp()
    DownloadBackgroundSessionManager.shared.storeBackgroundEventsCompletionHandler(completionHandler, for: identifier)
  }
}