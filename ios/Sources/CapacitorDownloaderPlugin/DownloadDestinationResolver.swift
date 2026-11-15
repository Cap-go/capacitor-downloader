import Foundation

enum DownloadDestinationResolver {
    static func resolveDestinationURL(
        destination: String?,
        id: String,
        documentsDirectory: URL
    ) -> URL {
        let trimmedDestination = destination?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let destination = trimmedDestination, !destination.isEmpty else {
            return documentsDirectory.appendingPathComponent(id)
        }

        if destination.hasPrefix("file://"), let url = URL(string: destination) {
            return url
        }

        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination)
        }

        if let privateURL = resolvePrivateRelativeDestination(destination, fallbackId: id) {
            return privateURL
        }

        return documentsDirectory.appendingPathComponent(destination)
    }

    /// Maps optional roots to app-private directories (not user-visible Documents).
    static func resolvePrivateRelativeDestination(_ destination: String, fallbackId: String) -> URL? {
        let fileManager = FileManager.default

        if destination.hasPrefix("files/") {
            let relative = String(destination.dropFirst("files/".count))
            guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            let path = relative.isEmpty ? fallbackId : relative
            guard !path.isEmpty else {
                return nil
            }
            return base.appendingPathComponent(path)
        }

        if destination.hasPrefix("cache/") {
            let relative = String(destination.dropFirst("cache/".count))
            guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return nil
            }
            let path = relative.isEmpty ? fallbackId : relative
            guard !path.isEmpty else {
                return nil
            }
            return base.appendingPathComponent(path)
        }

        if destination.hasPrefix("private/") {
            let relative = String(destination.dropFirst("private/".count))
            guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            let privateRoot = base.appendingPathComponent("CapacitorDownloader", isDirectory: true)
            let path = relative.isEmpty ? fallbackId : relative
            guard !path.isEmpty else {
                return nil
            }
            return privateRoot.appendingPathComponent(path)
        }

        return nil
    }
}
