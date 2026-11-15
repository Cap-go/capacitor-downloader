import Foundation

/// Host `AppDelegate` must forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` here.
/// Bootstrap warmup alone does not deliver background URL session completion events.
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