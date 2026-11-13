import Foundation
import UserNotifications

enum DownloadCompletedNotificationPresenter {
    static func presentIfAllowed(downloadId: String, body: String) {
        guard let bodyText = DownloadCompletedNotificationText.normalize(body) else {
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                allowed = true
            case .denied, .notDetermined:
                allowed = false
            @unknown default:
                allowed = false
            }

            guard allowed else {
                return
            }

            let content = UNMutableNotificationContent()
            content.body = bodyText
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "capacitor-downloader-completed-\(downloadId)",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }
}
